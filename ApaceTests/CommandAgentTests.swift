import XCTest
@testable import Apace

final class ClaudeBrainParsingTests: XCTestCase {
    func test_parsesToolUseIntoAction() {
        let content: [[String: Any]] = [[
            "type": "tool_use",
            "name": "run_applescript",
            "input": [
                "script": "set volume output volume 30",
                "summary": "Set the volume to 30%",
                "risk": "safe",
            ],
        ]]
        guard case let .act(action) = ClaudeBrain.parse(content: content) else {
            return XCTFail("expected .act")
        }
        XCTAssertEqual(action.appleScript, "set volume output volume 30")
        XCTAssertEqual(action.summary, "Set the volume to 30%")
        XCTAssertEqual(action.risk, .safe)
    }

    func test_unknownRiskDefaultsToRisky() {
        let content: [[String: Any]] = [[
            "type": "tool_use", "name": "run_applescript",
            "input": ["script": "x", "summary": "y"],  // no risk field
        ]]
        guard case let .act(action) = ClaudeBrain.parse(content: content) else {
            return XCTFail("expected .act")
        }
        XCTAssertEqual(action.risk, .risky)
    }

    func test_parsesTextIntoAnswer() {
        let content: [[String: Any]] = [["type": "text", "text": "That's a 404 error."]]
        XCTAssertEqual(ClaudeBrain.parse(content: content), .answer("That's a 404 error."))
    }

    func test_emptyContentIsNothing() {
        XCTAssertEqual(ClaudeBrain.parse(content: []), .nothing)
    }
}

final class CommandRiskTests: XCTestCase {
    func test_modelRiskyAlwaysRisky() {
        XCTAssertEqual(CommandRisk.resolve(modelRisk: .risky, script: "set volume output volume 30"), .risky)
    }

    func test_safeScriptStaysSafe() {
        XCTAssertEqual(CommandRisk.resolve(modelRisk: .safe, script: "set volume output volume 30"), .safe)
    }

    func test_destructiveScriptEscalatedToRisky() {
        XCTAssertEqual(CommandRisk.resolve(modelRisk: .safe, script: "tell application \"Mail\" to send theMessage"), .risky)
        XCTAssertEqual(CommandRisk.resolve(modelRisk: .safe, script: "tell application \"Finder\" to delete every item"), .risky)
        XCTAssertEqual(CommandRisk.resolve(modelRisk: .safe, script: "do shell script \"rm -rf /tmp/x\""), .risky)
    }
}

final class AppleScriptRunnerTests: XCTestCase {
    func test_runsSafeScriptAndReturnsOutput() async {
        let result = await AppleScriptRunner.run("return 6 * 7")
        XCTAssertTrue(result.succeeded, "error: \(result.error ?? "")")
        XCTAssertEqual(result.output, "42")
    }

    func test_reportsScriptError() async {
        let result = await AppleScriptRunner.run("this is not valid applescript {{{")
        XCTAssertFalse(result.succeeded)
        XCTAssertNotNil(result.error)
    }
}
