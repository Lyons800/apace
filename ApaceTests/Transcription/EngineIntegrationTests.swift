import XCTest
import FluidAudio
@testable import Apace

final class EngineIntegrationTests: XCTestCase {
    private var shouldRun: Bool { ProcessInfo.processInfo.environment["APACE_RUN_ENGINE_INTEGRATION"] == "1" }

    private func loadSamples() throws -> [Float] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hello", withExtension: "wav"))
        return try AudioTestUtil.float16kMono(from: url)
    }

    func test_parakeet_transcribesKnownPhrase() async throws {
        try XCTSkipUnless(shouldRun, "Set TEST_RUNNER_APACE_RUN_ENGINE_INTEGRATION=1 when invoking xcodebuild (the test runner exposes it as APACE_RUN_ENGINE_INTEGRATION) to run engine integration tests")
        let engine = ParakeetEngine(version: .v2)
        try await engine.loadModel(progress: nil)
        let result = try await engine.transcribe(audioSamples: try loadSamples(), language: "en", promptText: nil)
        XCTAssertTrue(result.text.lowercased().contains("hello"), "got: \(result.text)")
    }

    func test_appleSpeech_transcribesKnownPhrase() async throws {
        try XCTSkipUnless(shouldRun, "Set TEST_RUNNER_APACE_RUN_ENGINE_INTEGRATION=1 when invoking xcodebuild (the test runner exposes it as APACE_RUN_ENGINE_INTEGRATION) to run engine integration tests")
        guard #available(macOS 26.0, *) else { throw XCTSkip("Requires macOS 26+") }
        let engine = AppleSpeechEngine(localeID: "en-US")
        try await engine.loadModel(progress: nil)
        let result = try await engine.transcribe(audioSamples: try loadSamples(), language: "en", promptText: nil)
        XCTAssertTrue(result.text.lowercased().contains("hello"), "got: \(result.text)")
    }
}
