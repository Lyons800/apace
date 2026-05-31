import XCTest
@testable import Murmur

final class FileTranscriberTests: XCTestCase {
    /// Regression test for engines (Parakeet / AppleSpeech) that return only
    /// `.text` and leave `.segments` empty. Before the fix, FileTranscriber built
    /// its output solely from `result.segments`, so the file transcript came back
    /// empty for these engines. The MockEngine mirrors that behaviour: empty
    /// segments + stubbed text.
    func test_fileTranscribe_withEmptySegmentsEngine_producesNonEmptyText() async throws {
        let stubbed = "this is the stubbed transcript"
        let engine = MockEngine(identifier: .parakeet, stubbedText: stubbed)
        try await engine.loadModel(progress: nil)

        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hello", withExtension: "wav"))

        let transcriber = FileTranscriber(transcriptionEngine: engine)
        let result = try await transcriber.transcribe(fileURL: url, language: "en") { _ in }

        XCTAssertFalse(
            result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "fullText should not be empty for an engine that returns only .text"
        )
        XCTAssertTrue(
            result.fullText.contains(stubbed),
            "fullText should contain the stubbed transcript, got: '\(result.fullText)'"
        )
        XCTAssertFalse(result.segments.isEmpty, "a synthetic segment should be produced")
    }
}
