import Foundation
import Speech
import AVFoundation
import CoreMedia

/// `TranscriptionEngineProtocol` implementation backed by Apple's on-device
/// `SpeechAnalyzer` + `DictationTranscriber` (macOS 26+). Free-form dictation
/// with automatic punctuation, fully on-device.
///
/// Availability: the whole type is `@available(macOS 26.0, *)`. The app's
/// deployment target is macOS 14.0, so this file compiles against the 26 SDK
/// but the type is only reachable at runtime on macOS 26+ (callers gate with
/// `if #available(macOS 26.0, *)`).
@available(macOS 26.0, *)
final class AppleSpeechEngine: TranscriptionEngineProtocol {
    let identifier: EngineID = .appleSpeech
    private(set) var isModelLoaded = false
    private let localeID: String

    init(localeID: String = "en-US") { self.localeID = localeID }

    func loadModel(progress: ((Double) -> Void)?) async throws {
        let locale = Locale(identifier: localeID)
        let transcriber = Self.makeTranscriber(locale: locale)

        // `installedLocales` / `supportedLocales` are async statics on the SDK.
        let installed = await DictationTranscriber.installedLocales
        let supported = await DictationTranscriber.supportedLocales

        let normalizedTarget = Self.normalize(locale.identifier)
        let isInstalled = installed.contains { Self.normalize($0.identifier) == normalizedTarget }
        let isSupported = supported.contains { Self.normalize($0.identifier) == normalizedTarget }

        guard isInstalled || isSupported else {
            throw TranscriptionEngineError.unsupportedLanguage(localeID)
        }

        if !isInstalled {
            // Asset not on disk yet — download & install (may take minutes on first run).
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
        progress?(0.9)

        // Reserve the locale so the analyzer can use it. Best-effort: a `false`
        // return (or reservation cap reached) is non-fatal — transcription can
        // still proceed if the asset is installed.
        _ = try? await AssetInventory.reserve(locale: locale)

        progress?(1.0)
        isModelLoaded = true
    }

    func transcribe(audioSamples: [Float], language: String, promptText: String?) async throws -> TranscriptionResult {
        guard isModelLoaded else { throw TranscriptionEngineError.modelNotLoaded }
        guard !audioSamples.isEmpty else {
            return TranscriptionResult(text: "", language: language)
        }

        let locale = Locale(identifier: localeID)
        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionEngineError.transcriptionFailed
        }

        let buffer = try Self.makeBuffer(samples: audioSamples,
                                         sourceSampleRate: 16_000,
                                         targetFormat: analyzerFormat)
        let start = Date()

        // Start collecting final results BEFORE feeding input — `results` is a
        // live AsyncSequence that emits as analysis proceeds.
        let collector = Task { () -> String in
            var acc = AttributedString()
            for try await result in transcriber.results where result.isFinal {
                acc.append(result.text)
            }
            return String(acc.characters)
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputSequence)
        inputBuilder.yield(AnalyzerInput(buffer: buffer))
        inputBuilder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text,
                                   duration: Date().timeIntervalSince(start),
                                   language: language,
                                   segments: [])
    }

    func unload() { isModelLoaded = false }

    // MARK: - Helpers

    private static func makeTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale,
                             contentHints: [],
                             transcriptionOptions: [.punctuation],
                             reportingOptions: [],
                             attributeOptions: [])
    }

    /// Locale identifiers can come back as either `en-US` or `en_US`; normalize
    /// for matching against the SDK's installed/supported lists.
    private static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// Convert raw 16 kHz mono float PCM into an `AVAudioPCMBuffer` in the
    /// analyzer's required format (resampling/reformatting if necessary).
    private static func makeBuffer(samples: [Float],
                                   sourceSampleRate: Double,
                                   targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sourceSampleRate,
                                            channels: 1,
                                            interleaved: false),
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                               frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriptionEngineError.transcriptionFailed
        }
        srcBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                srcBuffer.floatChannelData!.pointee.update(from: base, count: samples.count)
            }
        }

        // Same format already — feed source buffer directly.
        guard srcFormat != targetFormat else { return srcBuffer }

        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            throw TranscriptionEngineError.transcriptionFailed
        }
        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw TranscriptionEngineError.transcriptionFailed
        }

        var fed = false
        var err: NSError?
        converter.convert(to: outBuffer, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return srcBuffer
        }
        if let err { throw err }
        return outBuffer
    }
}
