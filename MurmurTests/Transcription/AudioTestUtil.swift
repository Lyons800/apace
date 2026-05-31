import Foundation
import AVFoundation

enum AudioTestUtil {
    /// Load a WAV as 16 kHz mono Float PCM samples.
    static func float16kMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let conv = AVAudioConverter(from: file.processingFormat, to: target)!
        let cap = AVAudioFrameCount(file.length)
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap)!
        try file.read(into: inBuf)
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(cap) * ratio) + 1024)!
        var fed = false; var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { throw err }
        let ptr = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }
}
