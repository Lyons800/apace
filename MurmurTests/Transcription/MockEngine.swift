import Foundation
@testable import Murmur

final class MockEngine: TranscriptionEngineProtocol {
    let identifier: EngineID
    private(set) var isModelLoaded = false
    var loadShouldThrow: Error?
    var transcribeShouldThrow: Error?
    var stubbedResult: TranscriptionResult
    private(set) var transcribeCallCount = 0
    private(set) var lastLanguage: String?

    init(identifier: EngineID = .whisperKit, stubbedText: String = "hello world") {
        self.identifier = identifier
        self.stubbedResult = TranscriptionResult(text: stubbedText, duration: 0.1, language: "en", segments: [])
    }

    func loadModel(progress: ((Double) -> Void)?) async throws {
        if let loadShouldThrow { throw loadShouldThrow }
        progress?(1.0)
        isModelLoaded = true
    }

    func transcribe(audioSamples: [Float], language: String, promptText: String?) async throws -> TranscriptionResult {
        transcribeCallCount += 1
        lastLanguage = language
        if let transcribeShouldThrow { throw transcribeShouldThrow }
        return stubbedResult
    }

    func unload() { isModelLoaded = false }
}
