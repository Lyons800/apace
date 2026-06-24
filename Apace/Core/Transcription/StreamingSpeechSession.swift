import Foundation
import Speech
import AVFoundation

/// A persistent, real-time dictation session backed by Apple's `SpeechAnalyzer` +
/// `DictationTranscriber` (macOS 26+).
///
/// Unlike the batch `TranscriptionEngineProtocol` path — which spins up a fresh
/// analyzer and re-transcribes the whole accumulated clip every tick (and so
/// falls permanently behind real speech) — this keeps ONE analyzer alive for the
/// whole hold, feeds mic audio as it arrives, and surfaces **volatile (partial)
/// results** immediately. That's what makes the live transcript keep up word-by-word.
@available(macOS 26.0, *)
final class StreamingSpeechSession {
    private let localeID: String
    private let srcFormat: AVAudioFormat

    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    /// Text that has been finalized so far (committed segments).
    private var finalizedText = AttributedString()

    init?(localeID: String) {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16_000, channels: 1, interleaved: false) else { return nil }
        self.localeID = localeID
        self.srcFormat = src
    }

    /// Start the analyzer. `onPartial` is called with the running transcript
    /// (finalized text + the current volatile tail) as it evolves.
    func start(onPartial: @escaping (String) -> Void) async throws {
        let locale = Locale(identifier: localeID)
        let transcriber = DictationTranscriber(locale: locale,
                                               contentHints: [],
                                               transcriptionOptions: [.punctuation],
                                               reportingOptions: [.volatileResults],
                                               attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionEngineError.transcriptionFailed
        }
        self.analyzerFormat = fmt
        self.converter = (fmt == srcFormat) ? nil : AVAudioConverter(from: srcFormat, to: fmt)
        self.analyzer = analyzer

        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder

        // Drain results: volatile = live partials (not appended to finalized), final
        // = committed (appended). Either way we push the best running transcript.
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        self.finalizedText.append(result.text)
                        onPartial(String(self.finalizedText.characters))
                    } else {
                        var running = self.finalizedText
                        running.append(result.text)
                        onPartial(String(running.characters))
                    }
                }
            } catch {
                NSLog("[Apace] Streaming results ended: \(error.localizedDescription)")
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Feed a chunk of 16 kHz mono float PCM captured from the recorder tap.
    func feed(_ samples: [Float]) {
        guard let builder = inputBuilder, !samples.isEmpty,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                               frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        srcBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                srcBuffer.floatChannelData!.pointee.update(from: base, count: samples.count)
            }
        }

        let outBuffer: AVAudioPCMBuffer
        if let converter, let analyzerFormat {
            let ratio = analyzerFormat.sampleRate / srcFormat.sampleRate
            let cap = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true; status.pointee = .haveData; return srcBuffer
            }
            if err != nil { return }
            outBuffer = out
        } else {
            outBuffer = srcBuffer   // analyzer accepts 16 kHz directly
        }

        builder.yield(AnalyzerInput(buffer: outBuffer))
    }

    /// Finish input, flush the final results, and return the full transcript.
    func finish() async -> String {
        inputBuilder?.finish()
        if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        await resultsTask?.value          // wait for the results loop to drain
        analyzer = nil
        return String(finalizedText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
