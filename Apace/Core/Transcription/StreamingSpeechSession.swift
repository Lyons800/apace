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

    // Diagnostics (written to /tmp/apace-debug.log) to distinguish: no audio fed
    // (wiring) vs. silence (mic) vs. audio-but-no-results (engine).
    private var fedSamples = 0
    private var peakAmp: Float = 0
    private var resultCount = 0

    init?(localeID: String) {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16_000, channels: 1, interleaved: false) else { return nil }
        self.localeID = localeID
        self.srcFormat = src
    }

    /// Start the analyzer. `onPartial` is called with the running transcript
    /// (finalized text + the current volatile tail) as it evolves.
    func start(onPartial: @escaping (String) -> Void) async throws {
        Self.dbg("start: locale=\(localeID)")
        let locale = Locale(identifier: localeID)
        let transcriber = DictationTranscriber(locale: locale,
                                               contentHints: [],
                                               transcriptionOptions: [.punctuation],
                                               reportingOptions: [.volatileResults],
                                               attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            Self.dbg("start FAILED: no bestAvailableAudioFormat")
            throw TranscriptionEngineError.transcriptionFailed
        }
        self.analyzerFormat = fmt
        self.converter = (fmt == srcFormat) ? nil : AVAudioConverter(from: srcFormat, to: fmt)
        self.analyzer = analyzer
        Self.dbg("start: analyzerFmt=\(fmt.sampleRate)Hz ch=\(fmt.channelCount) needsConvert=\(converter != nil)")

        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder

        // Drain results: volatile = live partials (not appended to finalized), final
        // = committed (appended). Either way we push the best running transcript.
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    self.resultCount += 1
                    let t = String(result.text.characters)
                    Self.dbg("result #\(self.resultCount) isFinal=\(result.isFinal) text='\(t.prefix(60))'")
                    if result.isFinal {
                        self.finalizedText.append(result.text)
                        onPartial(String(self.finalizedText.characters))
                    } else {
                        var running = self.finalizedText
                        running.append(result.text)
                        onPartial(String(running.characters))
                    }
                }
                Self.dbg("results stream ended cleanly (count=\(self.resultCount))")
            } catch {
                Self.dbg("results stream ERROR: \(error.localizedDescription)")
            }
        }

        do {
            try await analyzer.start(inputSequence: inputSequence)
            Self.dbg("analyzer.start ok")
        } catch {
            Self.dbg("analyzer.start ERROR: \(error.localizedDescription)")
            throw error
        }
    }

    /// Feed a chunk of 16 kHz mono float PCM captured from the recorder tap.
    func feed(_ samples: [Float]) {
        guard let builder = inputBuilder, !samples.isEmpty,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                               frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        fedSamples += samples.count
        for s in samples { let a = abs(s); if a > peakAmp { peakAmp = a } }

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
            if err != nil { Self.dbg("feed convert ERROR: \(err!.localizedDescription)"); return }
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
        let text = String(finalizedText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        Self.dbg("finish: fedSamples=\(fedSamples) peakAmp=\(String(format: "%.4f", peakAmp)) results=\(resultCount) finalLen=\(text.count) final='\(text.prefix(80))'")
        return text
    }

    /// Append a line to /tmp/apace-debug.log (NSLog isn't surfacing for release-style runs).
    static func dbg(_ s: String) {
        let line = "\(Date().description) [stream] \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/apace-debug.log")
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); try? h.write(contentsOf: data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
