import SwiftUI
import Speech

extension Notification.Name {
    static let apaceEngineConfigChanged = Notification.Name("apaceEngineConfigChanged")
}

@main
struct ApaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appDelegate: appDelegate)
        } label: {
            Image(systemName: appDelegate.menuBarIcon)
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("History", id: "history") {
            HistoryView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Transcribe File", id: "file-transcription") {
            FileTranscriptionView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var config = ApaceConfig.load()

    var body: some View {
        Text(appDelegate.appState.state.statusText)
            .font(.caption)

        if let last = appDelegate.appState.lastTranscription, !last.isEmpty {
            Divider()
            let preview = String(last.prefix(60)) + (last.count > 60 ? "..." : "")
            Text("Last: \(preview)")
                .font(.caption)
        }

        Divider()

        let hotkeyName = KeyCodes.displayName(keyCode: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
        Text("Hotkey: \(hotkeyName)")
            .font(.caption)
        Text("Model: \(config.modelName)")
            .font(.caption)

        Divider()

        Button("History...") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "history")
        }
        .keyboardShortcut("h")

        Button("Transcribe File...") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "file-transcription")
        }
        .keyboardShortcut("t")

        Button("Settings...") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")

        Button("Check for Updates...") {
            appDelegate.updateManager.checkForUpdates()
        }
        .disabled(!appDelegate.updateManager.canCheckForUpdates)

        Button("Quit Apace") {
            appDelegate.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, Observable {
    let appState = AppState()
    let audioRecorder = AudioRecorder()
    let textInserter = TextInserter()
    let hotkeyManager: HotkeyManager
    var transcriptionEngine: TranscriptionEngineProtocol
    let overlay = TranscriptionOverlay()
    let llmProcessor = LLMProcessor()
    let updateManager = UpdateManager()
    let mediaController = MediaController()

    // Apace Pro: Command Mode agent + the Dynamic Island surface.
    let island = IslandController()
    lazy var voiceEditService = VoiceEditService(selection: textInserter, rewriter: llmProcessor)
    private var isCommandHold = false
    private var pendingScreenshot: Task<Data?, Never>?
    private var pendingFrontApp: String?
    private var pendingSelection: String?

    var menuBarIcon: String = "waveform"
    private var streamingTask: Task<Void, Error>?
    /// Live Apple SpeechAnalyzer streaming session (macOS 26). Stored as `Any?`
    /// because `StreamingSpeechSession` is gated to macOS 26; cast at use sites.
    private var streamingSession: Any?
    private var onboardingWindow: NSWindow?

    /// Tracks the in-flight model load triggered by a reload, so a rapid second
    /// reload can cancel the previous load before starting a new one.
    private var engineLoadTask: Task<Void, Never>?
    /// Set when a reload is requested while a dictation is active. Applied once
    /// the app returns to idle (`.ready`).
    private var pendingEngineReload = false

    override init() {
        let config = ApaceConfig.load()
        self.transcriptionEngine = Self.buildEngine(for: config)
        self.hotkeyManager = HotkeyManager(
            keyCode: config.hotkeyKeyCode,
            modifiers: config.hotkeyModifiers,
            mode: config.recordingMode
        )
        super.init()

        // Apply Settings engine/model changes live, without an app restart.
        NotificationCenter.default.addObserver(forName: .apaceEngineConfigChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadEngineFromConfig()
            }
        }
    }

    // MARK: - Engine Selection

    /// Apple DictationTranscriber base languages (approximate; ~10 base langs).
    /// Static to avoid async locale enumeration during init. AppleSpeechEngine
    /// still guards unsupported locales at load time, and the factory falls back.
    static let appleSupportedBaseLanguages: Set<String> = [
        "en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "yue"
    ]

    static func localeID(for language: String) -> String {
        (language == "auto" || language == "en") ? "en-US" : language
    }

    static func buildEngine(for config: ApaceConfig) -> TranscriptionEngineProtocol {
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let id = EngineSelector.resolve(preference: config.enginePreference,
                                        osMajor: osMajor,
                                        language: config.language,
                                        appleSupported: appleSupportedBaseLanguages)
        return EngineSelector.makeEngine(id: id, modelName: config.modelName, localeID: localeID(for: config.language))
    }

    /// Rebuild the engine from the current persisted config and reload its model.
    /// Called when Settings posts `.apaceEngineConfigChanged`.
    func reloadEngineFromConfig() {
        // Never swap the engine out from under an active dictation — the
        // streaming/final transcription paths read `transcriptionEngine` per
        // call, so unloading it mid-flight breaks an in-progress transcription.
        // Defer the reload until the app returns to idle.
        switch appState.state {
        case .recording, .transcribing, .inserting:
            pendingEngineReload = true
            NSLog("[Apace] Engine reload deferred (state: \(appState.state.statusText))")
            return
        default:
            break
        }

        pendingEngineReload = false
        let config = ApaceConfig.load()
        let newEngine = Self.buildEngine(for: config)
        let old = transcriptionEngine

        // Cancel any previous in-flight load before swapping.
        engineLoadTask?.cancel()
        old.unload()
        transcriptionEngine = newEngine
        NSLog("[Apace] Engine reloaded: \(newEngine.identifier.rawValue)")
        engineLoadTask = Task { try? await newEngine.loadModel(progress: nil) }
    }

    /// Set the app back to `.ready` and, if a reload was deferred while a
    /// dictation was active, apply it now.
    private func setReadyAndApplyPendingReload() {
        appState.state = .ready
        if pendingEngineReload {
            NSLog("[Apace] Applying deferred engine reload")
            reloadEngineFromConfig()
        }
    }

    private static let onboardingCompleteKey = "apace_onboarding_complete"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check current permission state without prompting
        appState.hasMicrophonePermission = Permissions.checkMicrophone()
        appState.hasAccessibilityPermission = Permissions.checkAccessibility()

        let onboardingDone = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)

        if !onboardingDone || !appState.hasMicrophonePermission {
            // Show onboarding — permissions are requested there by user action
            NSLog("[Apace] Showing onboarding...")
            showOnboardingWindow()
        } else {
            // Already onboarded with mic permission — go straight to loading
            Task { await loadModelAndStart() }
        }
    }

    // MARK: - Onboarding Window

    private func showOnboardingWindow() {
        let onboardingView = OnboardingView { [weak self] in
            self?.completeOnboarding()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Apace"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        self.onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Called from OnboardingView when the user taps "Get Started"
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        appState.hasMicrophonePermission = Permissions.checkMicrophone()
        appState.hasAccessibilityPermission = Permissions.checkAccessibility()

        onboardingWindow?.close()
        onboardingWindow = nil

        Task { await loadModelAndStart() }
    }

    func shutdown() {
        hotkeyManager.stop()
        streamingTask?.cancel()
        audioRecorder.shutdown()
    }

    // MARK: - Initialization

    private func loadModelAndStart() async {
        NSLog("[Apace] Initializing...")

        // Load Whisper model (no permission prompts here)
        NSLog("[Apace] Loading model via engine: \(transcriptionEngine.identifier.rawValue)...")
        appState.state = .loading(progress: 0)

        do {
            try await transcriptionEngine.loadModel { progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // applyingLoadingProgress ignores late callbacks once we've left
                    // .loading — a final progress(1.0) delivered after we set .ready
                    // below must not clobber it back to "Downloading model (100%)".
                    self.appState.state = self.appState.state.applyingLoadingProgress(progress)
                    NSLog("[Apace] Model download: \(Int(progress * 100))%")
                }
            }
            appState.state = .ready
            NSLog("[Apace] Model loaded. Ready!")
        } catch {
            appState.state = .error(error.localizedDescription)
            NSLog("[Apace] Model load failed: \(error.localizedDescription)")
            return
        }

        // Load LLM model if enabled (background, non-blocking)
        let config = ApaceConfig.load()
        if config.llmEnabled && llmProcessor.isAvailable {
            Task {
                do {
                    try await llmProcessor.loadModel { progress in
                        NSLog("[Apace] LLM download: \(Int(progress * 100))%")
                    }
                } catch {
                    NSLog("[Apace] LLM load failed (non-fatal): \(error.localizedDescription)")
                }
            }
        }

        // Warm up audio engine so first recording starts instantly
        do {
            try audioRecorder.warmUp()
        } catch {
            NSLog("[Apace] Audio warm-up failed (non-fatal): \(error.localizedDescription)")
        }

        // Set up hotkey
        setupHotkey()
        NSLog("[Apace] Hotkey active. Hold Right Option to record.")
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onRecordingStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }

        hotkeyManager.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        // Command Mode (Apace Pro): ⇧ + the dictation key.
        hotkeyManager.onCommandStart = { [weak self] in
            Task { @MainActor in self?.startCommand() }
        }
        hotkeyManager.onCommandStop = { [weak self] in
            Task { @MainActor in await self?.stopCommandAndRun() }
        }
        island.onCancel = { [weak self] in self?.island.dismiss() }

        hotkeyManager.start()
    }

    // MARK: - Command Mode (Apace Pro)

    private func startCommand() {
        guard ProEntitlement.shared.isActive else {
            island.message("Command Mode is a Apace Pro feature.")
            return
        }
        guard appState.state == .ready else { return }
        guard Permissions.checkMicrophone() else {
            island.message("Microphone access required.")
            return
        }
        // Freeze the screen context at the moment of invocation.
        pendingFrontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        pendingSelection = textInserter.readSelectedText()
        pendingScreenshot = Task { await ScreenCapture.capturePNG() }
        do {
            try audioRecorder.startRecording { [weak self] level in
                Task { @MainActor in self?.island.updateLevel(level) }
            }
            appState.state = .recording
            isCommandHold = true
            island.listening()
        } catch {
            NSLog("[Apace] Command start failed: \(error.localizedDescription)")
            appState.state = .ready
        }
    }

    private func stopCommandAndRun() async {
        guard isCommandHold else { return }
        isCommandHold = false

        let samples = audioRecorder.stopRecording()
        appState.state = .transcribing
        island.thinking()

        guard samples.count > 8000 else {
            island.dismiss()
            setReadyAndApplyPendingReload()
            return
        }

        // Transcribe the spoken command (e.g. "add this to my calendar").
        let config = ApaceConfig.load()
        let trimmed = Self.trimTrailingSilence(samples, threshold: 0.005, minTrailingSamples: 8000)
        let command: String
        do {
            let result = try await transcriptionEngine.transcribe(
                audioSamples: trimmed, language: config.language, promptText: nil
            )
            command = Self.stripSpecialTokens(result.text).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            island.message("Didn't catch that.")
            setReadyAndApplyPendingReload()
            return
        }
        guard !command.isEmpty, !isHallucination(command) else {
            island.dismiss()
            setReadyAndApplyPendingReload()
            return
        }

        // Hand the command + screenshot + context to the agent brain.
        let png = await pendingScreenshot?.value
        let context = AgentContext(command: command, screenshotPNG: png,
                                   frontmostApp: pendingFrontApp, selection: pendingSelection)
        let brain = AgentBrainFactory.make(provider: config.commandBrainProvider)
        do {
            let decision = try await brain.decide(context)
            await handleResolved(CommandModeService.resolve(decision))
        } catch let e as AgentError {
            island.message(e.errorDescription ?? "Command failed.")
        } catch {
            island.message("Command failed: \(error.localizedDescription)")
        }
        setReadyAndApplyPendingReload()
    }

    private func handleResolved(_ resolved: ResolvedCommand) async {
        switch resolved {
        case .answer(let text):
            island.answer(text)
        case .nothing:
            island.message("I couldn't do that one.")
        case .run(let action):
            await execute(action)
        case .confirm(let action):
            island.onRun = { [weak self] in
                Task { @MainActor in await self?.execute(action) }
            }
            island.confirm(summary: action.summary)
        }
    }

    private func execute(_ action: CommandAction) async {
        island.running(action.summary)          // show a spinner + what's happening
        let result = await AppleScriptRunner.run(action.appleScript)
        if result.succeeded {
            island.done(action.summary)
        } else {
            NSLog("[Apace] Command failed: \(result.error ?? "")")
            island.message("That didn't work: \(result.error ?? "unknown error")")
        }
    }

    // MARK: - Recording

    private func startRecording() async {
        guard appState.state == .ready else {
            NSLog("[Apace] Cannot record — state is \(appState.state.statusText)")
            return
        }

        // Check microphone permission at point of use
        if !Permissions.checkMicrophone() {
            NSLog("[Apace] Microphone permission not granted, requesting...")
            let granted = await Permissions.requestMicrophone()
            appState.hasMicrophonePermission = granted
            if !granted {
                NSLog("[Apace] Microphone permission denied")
                appState.state = .error("Microphone access required")
                SoundEffects.playError()
                try? await Task.sleep(for: .seconds(2))
                appState.state = .ready
                return
            }
        }

        let config = ApaceConfig.load()
        if config.playSounds { SoundEffects.playStart() }

        // Mute system audio if enabled
        if config.muteMediaDuringRecording {
            mediaController.muteSystemAudio()
        }

        // Try streaming mode first
        if config.useStreaming {
            do {
                try startStreamingRecording(config: config)
                return
            } catch {
                NSLog("[Apace] Streaming init failed, falling back to batch: \(error)")
            }
        }

        // Batch mode fallback
        do {
            try audioRecorder.startRecording { level in
                Task { @MainActor [weak self] in
                    self?.appState.audioLevel = level
                }
            }
            appState.state = .recording
            menuBarIcon = "waveform.circle.fill"
            NSLog("[Apace] Recording started (batch mode)")
        } catch {
            appState.state = .error(error.localizedDescription)
            NSLog("[Apace] Recording failed: \(error)")
        }
    }

    private func startStreamingRecording(config: ApaceConfig) throws {
        // Real-time path (macOS 26 + Apple SpeechAnalyzer): ONE persistent analyzer,
        // fed live mic audio, surfacing volatile partials to the notch word-by-word.
        // This is what actually keeps up with speech; the batch loop below can't.
        if #available(macOS 26.0, *), transcriptionEngine.identifier == .appleSpeech,
           let session = StreamingSpeechSession(localeID: Self.localeID(for: config.language)) {
            self.streamingSession = session
            appState.state = .recording
            appState.isStreaming = true
            menuBarIcon = "waveform.circle.fill"
            island.transcribing("")

            Task { @MainActor [weak self] in
                do {
                    try await session.start { text in
                        self?.appState.streamingConfirmedText = text
                        self?.island.transcribing(text)
                    }
                } catch {
                    NSLog("[Apace] Apple streaming start failed: \(error.localizedDescription)")
                }
            }

            // Feed each freshly-captured chunk straight to the analyzer (chunks
            // arrive on the main queue in order, so feeding stays ordered).
            try audioRecorder.startRecording(levelCallback: { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.appState.audioLevel = level
                    self?.island.updateLevel(level)
                }
            }, sampleCallback: { [weak self] samples in
                (self?.streamingSession as? StreamingSpeechSession)?.feed(samples)
            })
            NSLog("[Apace] Recording started (Apple live streaming)")
            return
        }

        // Fallback (WhisperKit / Parakeet): batch re-transcription loop.
        try audioRecorder.startRecording { [weak self] level in
            Task { @MainActor [weak self] in
                self?.appState.audioLevel = level
                self?.island.updateLevel(level)
            }
        }

        appState.state = .recording
        appState.isStreaming = true
        menuBarIcon = "waveform.circle.fill"

        // Show the live transcript in the notch; it follows the current word.
        island.transcribing("")

        // Track last transcription to debounce (skip re-transcription if no new audio)
        var lastSampleCount = 0

        // Periodic transcription: re-transcribe recent audio every ~300ms and push to the notch.
        streamingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { break }

                let samples = self.audioRecorder.getAudioSamples()
                // Need at least 0.5s of audio
                guard samples.count > 8000 else { continue }

                // Debounce: skip if no significant new audio since last tick
                let newSamples = samples.count - lastSampleCount
                guard newSamples > 1600 else { continue } // at least 0.1s of new audio
                lastSampleCount = samples.count

                // Check audio energy before transcribing — skip if silence/noise
                let rms = samples.reduce(0.0) { $0 + $1 * $1 } / Float(samples.count)
                let rmsDb = 10 * log10(max(rms, 1e-10))
                if rmsDb < -45 {
                    NSLog("[Apace] Streaming tick: audio too quiet (\(String(format: "%.1f", rmsDb)) dB), skipping")
                    continue
                }

                do {
                    let promptHint = CustomDictionary.promptHint(from: config.dictionaryEntries)
                    // Cap the live-preview audio to the most recent ~12s so per-tick
                    // latency stays bounded on long utterances; the final pass on
                    // release (stopStreamingAndInsert) still uses the full recording.
                    let liveSamples = samples.count > 192_000 ? Array(samples.suffix(192_000)) : samples
                    let result = try await self.transcriptionEngine.transcribe(
                        audioSamples: liveSamples,
                        language: config.language,
                        promptText: promptHint
                    )
                    let text = Self.stripSpecialTokens(result.text)
                    if !text.isEmpty && !self.isHallucination(text) {
                        self.appState.streamingConfirmedText = text
                        self.appState.streamingUnconfirmedText = ""
                        self.island.transcribing(text)
                    }
                } catch {
                    NSLog("[Apace] Streaming transcription tick failed: \(error.localizedDescription)")
                }
            }
        }

        NSLog("[Apace] Recording started (streaming mode)")
    }

    private func stopRecordingAndTranscribe() async {
        guard appState.state == .recording else { return }

        // Brief delay to capture the tail end of speech (user may still be finishing a word
        // when they lift their finger off the hotkey). Use try to allow cancellation on shutdown.
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return // Cancelled (e.g., app quitting)
        }

        let config = ApaceConfig.load()
        menuBarIcon = "waveform"

        // Restore system audio if it was muted
        mediaController.restoreSystemAudio()

        // Detect context before processing
        let context = ContextDetector.detectContext()
        NSLog("[Apace] Detected context: \(context.rawValue)")

        if appState.isStreaming {
            await stopStreamingAndInsert(config: config, context: context)
        } else {
            await stopBatchAndInsert(config: config, context: context)
        }
    }

    // MARK: - Streaming Stop

    private func stopStreamingAndInsert(config: ApaceConfig, context: AppContext) async {
        // Apple live-streaming path: finish the persistent analyzer and use its
        // already-accurate final transcript — no second batch pass needed.
        if #available(macOS 26.0, *), let session = streamingSession as? StreamingSpeechSession {
            streamingSession = nil
            _ = audioRecorder.stopRecording()
            appState.isStreaming = false
            appState.state = .transcribing
            let finalText = await session.finish()
            island.dismiss()
            let raw = Self.stripSpecialTokens(finalText)
            if !raw.isEmpty, !isHallucination(raw) {
                await processAndInsert(rawText: raw, config: config, context: context)
            } else {
                NSLog("[Apace] Streaming produced no usable text")
                if config.playSounds { SoundEffects.playError() }
                setReadyAndApplyPendingReload()
            }
            return
        }

        // Capture last streaming result before cancelling (used as fallback)
        let lastStreamingText = appState.streamingConfirmedText

        // Stop periodic transcription
        streamingTask?.cancel()
        streamingTask = nil
        island.dismiss()

        // Stop recording and get ALL audio for final accurate transcription
        let allSamples = audioRecorder.stopRecording()
        appState.isStreaming = false

        guard allSamples.count > 8000 else {
            NSLog("[Apace] Streaming: too short (\(allSamples.count) samples)")
            if config.playSounds { SoundEffects.playError() }
            setReadyAndApplyPendingReload()
            return
        }

        // Trim trailing silence for cleaner final transcription
        let samples = Self.trimTrailingSilence(allSamples, threshold: 0.005, minTrailingSamples: 8000)
        NSLog("[Apace] Trimmed audio: \(allSamples.count) → \(samples.count) samples")

        // Do one final full transcription on trimmed audio (most accurate)
        appState.state = .transcribing
        do {
            let promptHint = CustomDictionary.promptHint(from: config.dictionaryEntries)
            let result = try await transcriptionEngine.transcribe(
                audioSamples: samples,
                language: config.language,
                promptText: promptHint
            )
            let rawText = Self.stripSpecialTokens(result.text)

            if !rawText.isEmpty, !isHallucination(rawText) {
                NSLog("[Apace] Final transcription (\(String(format: "%.1f", result.duration))s): \(rawText)")
                await processAndInsert(rawText: rawText, config: config, context: context)
                return
            }

            // Final transcription was empty — fall back to last streaming result
            if !lastStreamingText.isEmpty, !isHallucination(lastStreamingText) {
                NSLog("[Apace] Final transcription empty, using last streaming result: '\(lastStreamingText)'")
                await processAndInsert(rawText: lastStreamingText, config: config, context: context)
                return
            }

            NSLog("[Apace] Filtered hallucination or empty: '\(rawText)'")
            setReadyAndApplyPendingReload()
        } catch {
            // On error, try streaming fallback
            if !lastStreamingText.isEmpty, !isHallucination(lastStreamingText) {
                NSLog("[Apace] Final transcription error, using last streaming result: '\(lastStreamingText)'")
                await processAndInsert(rawText: lastStreamingText, config: config, context: context)
                return
            }
            NSLog("[Apace] Final transcription error: \(error)")
            if config.playSounds { SoundEffects.playError() }
            setReadyAndApplyPendingReload()
        }
    }

    // MARK: - Batch Stop

    private func stopBatchAndInsert(config: ApaceConfig, context: AppContext) async {
        let samples = audioRecorder.stopRecording()

        // Need at least 0.5s of audio (8000 samples at 16kHz)
        guard samples.count > 8000 else {
            NSLog("[Apace] Too short (\(samples.count) samples), ignoring")
            if config.playSounds { SoundEffects.playError() }
            setReadyAndApplyPendingReload()
            return
        }

        // Check audio energy
        let rms = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        let rmsDb = 10 * log10(max(rms, 1e-10))
        NSLog("[Apace] Audio RMS: \(String(format: "%.1f", rmsDb)) dB (\(samples.count) samples)")

        if rmsDb < -50 {
            NSLog("[Apace] Audio too quiet (silence), ignoring")
            setReadyAndApplyPendingReload()
            return
        }

        appState.state = .transcribing
        NSLog("[Apace] Transcribing \(samples.count) samples...")

        do {
            let promptHint = CustomDictionary.promptHint(from: config.dictionaryEntries)
            let result = try await transcriptionEngine.transcribe(
                audioSamples: samples,
                language: config.language,
                promptText: promptHint
            )

            let trimmed = Self.stripSpecialTokens(result.text)
            guard !trimmed.isEmpty, !isHallucination(trimmed) else {
                NSLog("[Apace] Filtered hallucination or empty: '\(trimmed)'")
                setReadyAndApplyPendingReload()
                return
            }

            NSLog("[Apace] Batch result (\(String(format: "%.1f", result.duration))s): \(trimmed)")
            await processAndInsert(rawText: trimmed, config: config, context: context)

        } catch {
            NSLog("[Apace] Transcription error: \(error)")
            if config.playSounds { SoundEffects.playError() }
            // Error recovery: return to .ready immediately instead of hanging
            setReadyAndApplyPendingReload()
        }
    }

    // MARK: - Process & Insert

    private func processAndInsert(rawText: String, config: ApaceConfig, context: AppContext) async {
        // Check for voice commands
        if config.llmEnabled, llmProcessor.isReady, let parsed = VoiceCommandParser.parse(rawText, smartModes: config.smartModes) {
            NSLog("[Apace] Voice command detected: \(parsed.command)")
            await handleVoiceCommand(parsed.command, config: config)
            return
        }

        // Partition dictionary entries: safe (regex) vs contextual (LLM)
        let (safeEntries, contextualEntries) = CustomDictionary.partition(config.dictionaryEntries)

        // Apply safe dictionary replacements via regex
        var text = CustomDictionary.apply(entries: safeEntries, to: rawText)

        // Post-process text with context
        let processor = TextPostProcessor(
            autoCapitalize: config.autoCapitalize,
            convertPunctuation: config.convertPunctuation,
            removeFiller: config.removeFiller
        )
        var processed = processor.process(text, context: context)

        // Optional LLM cleanup
        if config.llmEnabled && llmProcessor.isReady {
            appState.state = .transcribing
            // Pass safe dictionary terms for guaranteed replacement
            llmProcessor.dictionaryTerms = safeEntries
            // Pre-filter contextual entries: only include those whose spoken form appears in the text
            let relevant = CustomDictionary.relevantContextualEntries(from: contextualEntries, in: processed)
            llmProcessor.contextualDictionaryEntries = relevant
            if !relevant.isEmpty {
                NSLog("[Apace] \(relevant.count) contextual dictionary entries injected into LLM prompt")
            }
            let llmStart = CFAbsoluteTimeGetCurrent()
            processed = await llmProcessor.process(text: processed, context: context)
            let llmElapsed = (CFAbsoluteTimeGetCurrent() - llmStart) * 1000
            NSLog("[Apace] LLM processing took %.0fms", llmElapsed)
            // Write timing to file for debugging
            let logLine = "\(Date()): LLM took \(Int(llmElapsed))ms for \(processed.count) chars\n"
            if let data = logLine.data(using: .utf8) {
                let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Apace/llm_timing.log")
                if FileManager.default.fileExists(atPath: logPath.path) {
                    if let handle = try? FileHandle(forWritingTo: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logPath)
                }
            }
        } else if !contextualEntries.isEmpty {
            // LLM disabled — fall back to regex for all entries (preserves current behavior)
            processed = CustomDictionary.apply(entries: contextualEntries, to: processed)
        }

        NSLog("[Apace] Final text: \(processed)")

        // Save to history
        if config.historyEnabled {
            TranscriptionHistory.shared.add(rawText: rawText, processedText: processed, appContext: context)
        }

        // Check accessibility before inserting — request only at point of use
        if !Permissions.checkAccessibility() {
            appState.hasAccessibilityPermission = false
            NSLog("[Apace] Accessibility not granted — copying to clipboard only")
            // Graceful degradation: copy to clipboard, user can paste manually
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(processed, forType: .string)
            appState.lastTranscription = processed
            if config.playSounds { SoundEffects.playStop() }
            setReadyAndApplyPendingReload()

            // Prompt for accessibility once (not every time)
            if !UserDefaults.standard.bool(forKey: "apace_accessibility_prompted") {
                UserDefaults.standard.set(true, forKey: "apace_accessibility_prompted")
                _ = Permissions.requestAccessibility()
            }
            return
        }

        appState.hasAccessibilityPermission = true

        // Insert text via paste
        appState.state = .inserting
        await textInserter.insert(processed)

        appState.lastTranscription = processed
        if config.playSounds { SoundEffects.playStop() }
        setReadyAndApplyPendingReload()
    }

    // MARK: - Voice Commands

    private func handleVoiceCommand(_ command: VoiceCommand, config: ApaceConfig) async {
        NSLog("[Apace] Executing voice command...")

        // Capture selected text from the active app
        guard let selectedText = await VoiceCommandParser.captureSelectedText(), !selectedText.isEmpty else {
            NSLog("[Apace] No text selected for voice command")
            if config.playSounds { SoundEffects.playError() }
            setReadyAndApplyPendingReload()
            return
        }

        // Process with LLM
        let result = await llmProcessor.executeCommand(command, on: selectedText)

        // Replace selection with result
        appState.state = .inserting
        await textInserter.insert(result)

        appState.lastTranscription = result
        if config.playSounds { SoundEffects.playStop() }
        setReadyAndApplyPendingReload()
    }

    // MARK: - Hallucination Filter

    private func isHallucination(_ text: String) -> Bool {
        let exactHallucinations: Set<String> = [
            "you", "Thank you.", "Thanks for watching!",
            "Bye.", "Goodbye.", "...",
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return exactHallucinations.contains(trimmed)
    }

    /// Strip WhisperKit special tokens AND hallucination markers like [BLANK_AUDIO], [MUSIC], etc.
    private static func stripSpecialTokens(_ text: String) -> String {
        var result = text
        // Strip <|...|> special tokens
        result = result.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        // Strip hallucination markers that WhisperKit may embed in or append to real text
        let hallucinationMarkers = [
            "\\[BLANK_AUDIO\\]", "\\[BLANK AUDIO\\]", "\\(blank audio\\)",
            "\\[MUSIC\\]", "\\[SILENCE\\]", "\\[NOISE\\]",
            "\\[APPLAUSE\\]", "\\[LAUGHTER\\]",
        ]
        for marker in hallucinationMarkers {
            result = result.replacingOccurrences(
                of: marker,
                with: "",
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trim trailing silence from audio samples to improve transcription accuracy.
    /// WhisperKit struggles when short speech is followed by long silence.
    /// - Parameters:
    ///   - samples: Raw PCM audio samples
    ///   - threshold: RMS amplitude below which audio is considered silence
    ///   - minTrailingSamples: Minimum trailing silent samples before trimming (0.5s = 8000 at 16kHz)
    private static func trimTrailingSilence(_ samples: [Float], threshold: Float = 0.005, minTrailingSamples: Int = 8000) -> [Float] {
        guard samples.count > minTrailingSamples else { return samples }

        // Scan backwards to find where audio rises above silence threshold
        // Use a sliding window of 1600 samples (0.1s) for smoothing
        let windowSize = 1600
        var lastLoudIndex = samples.count

        var i = samples.count - windowSize
        while i >= 0 {
            let window = samples[i..<min(i + windowSize, samples.count)]
            let rms = sqrt(window.reduce(0) { $0 + $1 * $1 } / Float(window.count))
            if rms > threshold {
                lastLoudIndex = min(i + windowSize + minTrailingSamples / 2, samples.count) // keep 0.25s padding after last sound
                break
            }
            i -= windowSize
        }

        // Don't trim if silence portion is too small to matter
        let trimmedCount = samples.count - lastLoudIndex
        if trimmedCount < minTrailingSamples {
            return samples
        }

        return Array(samples.prefix(lastLoudIndex))
    }
}
