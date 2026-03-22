# Murmur — Project Conventions

## What is this?
macOS menu bar dictation app. Hold a hotkey, speak, release — text appears in any app. Powered by WhisperKit (on-device, CoreML + Neural Engine). Previously named "Whispr", renamed to "Murmur" for launch.

## Stack
- Swift 5.10+, macOS 14.0+ (Sonoma)
- SwiftUI (settings, onboarding) + AppKit (menu bar, status item)
- WhisperKit 0.9+ (speech-to-text via CoreML)
- mlx-swift-lm (optional on-device LLM cleanup via MLXLLM)
- Sparkle 2.6+ (auto-updates)
- AVAudioEngine (audio capture)
- CGEvent + NSPasteboard (text insertion)
- NSEvent globalMonitor (global hotkeys)

## Architecture
- Menu bar app (LSUIElement = true, no dock icon)
- Bundle ID: `dev.murmur.app`
- Observable AppState drives all UI updates
- Core modules: AudioRecorder, TranscriptionEngine, HotkeyManager, TextInserter, TextPostProcessor, ContextDetector, LLMProcessor, VoiceCommandParser, CustomDictionary, FileTranscriber, MediaController, UpdateManager
- UI: StatusBarController (menu bar), TranscriptionOverlay (floating preview), SettingsView (SwiftUI), FileTranscriptionView
- Two transcription modes: **streaming** (real-time with floating overlay) and **batch** (fallback)
- Context-aware formatting: ContextDetector reads frontmost app bundle ID → AppContext enum → TextPostProcessor adjusts capitalization/punctuation per context
- Optional LLM post-processing: LLMProcessor wraps mlx-swift-lm (MLXLLM) for local inference, guarded by `#if canImport(MLXLLM)`
- Voice commands + Smart Modes: VoiceCommandParser detects trigger phrases and custom user-defined modes, routes to LLMProcessor

## Conventions
- Use async/await everywhere (no completion handlers)
- @Observable macro for state (not ObservableObject)
- Errors: throw, don't return optionals for failable operations
- Prefer value types (structs/enums) over classes except where reference semantics needed
- All audio processing on background queues, UI updates on @MainActor
- SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — all types default to @MainActor unless explicitly opted out
- Config struct: `MurmurConfig` (stored as `murmur_config` in UserDefaults)
- NSLog prefix: `[Murmur]`
- App Support path: `~/Library/Application Support/Murmur/`

## File Layout
- `Murmur/Core/` — business logic (audio, transcription, hotkeys, text insertion)
- `Murmur/UI/` — SwiftUI views and AppKit controllers
- `Murmur/Models/` — state, config, result types
- `Murmur/Utilities/` — permissions, key codes, sounds
- `Murmur/Resources/` — sound effects

## Key Decisions
- WhisperKit (CoreML) over whisper.cpp — 2-5x faster, 75% less power
- Accessibility API text insertion first, clipboard paste as fallback
- Default model: base.en (142MB, ~500ms for 5s audio)
- Default hotkey: Right Option key
- Streaming mode on by default; batch mode as automatic fallback
- LLM post-processing off by default (requires adding mlx-swift-lm SPM package)
- Context detection via bundle ID map + fuzzy matching — no accessibility API needed
- Sparkle for auto-updates (EdDSA signed appcast)
- $29 one-time purchase via Paddle (free tier available)

## Enabling LLM Post-Processing
1. In Xcode: File → Add Package Dependencies → `https://github.com/ml-explore/mlx-swift-lm.git`
2. Add the `MLXLLM` and `MLXLMCommon` products to the Murmur target
3. Build — the `#if canImport(MLXLLM)` guards will activate the LLM code
4. Enable in Settings → Features tab → toggle "Enable LLM cleanup"

## Migration
- Data migrated automatically from `~/Library/Application Support/Whispr/` on first launch
- UserDefaults keys migrated from `whispr_*` to `murmur_*`
- Config migrated from `whispr_config` to `murmur_config`
