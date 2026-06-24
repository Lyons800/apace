import XCTest
@testable import Apace

private final class MockSelection: SelectionReading {
    var text: String?
    init(_ t: String?) { text = t }
    func currentSelectedText() -> String? { text }
}

private final class MockRewriter: TextRewriting {
    let transform: (String, String) -> String
    private(set) var lastInstruction: String?
    init(_ t: @escaping (String, String) -> String) { transform = t }
    func rewrite(_ text: String, instruction: String) async -> String {
        lastInstruction = instruction
        return transform(text, instruction)
    }
}

final class VoiceEditServiceTests: XCTestCase {
    func test_appliesInstructionToSelection() async throws {
        let rewriter = MockRewriter { text, _ in text.uppercased() }
        let svc = VoiceEditService(selection: MockSelection("hello world"),
                                   rewriter: rewriter,
                                   isProActive: { true })
        let edit = try await svc.prepareEdit(instruction: "shout it")
        XCTAssertEqual(edit, VoiceEdit(before: "hello world", after: "HELLO WORLD"))
        XCTAssertEqual(rewriter.lastInstruction, "shout it")
    }

    func test_trimsWhitespaceFromSelectionAndResult() async throws {
        let svc = VoiceEditService(selection: MockSelection("  hi  "),
                                   rewriter: MockRewriter { _, _ in "  bye  " },
                                   isProActive: { true })
        let edit = try await svc.prepareEdit(instruction: "x")
        XCTAssertEqual(edit, VoiceEdit(before: "hi", after: "bye"))
    }

    func test_blockedWhenNotPro() async {
        let svc = VoiceEditService(selection: MockSelection("x"),
                                   rewriter: MockRewriter { t, _ in t },
                                   isProActive: { false })
        do {
            _ = try await svc.prepareEdit(instruction: "y")
            XCTFail("expected proRequired")
        } catch {
            XCTAssertEqual(error as? VoiceEditError, .proRequired)
        }
    }

    func test_noSelectionThrows() async {
        for selection in [MockSelection(nil), MockSelection("   ")] {
            let svc = VoiceEditService(selection: selection,
                                       rewriter: MockRewriter { t, _ in t },
                                       isProActive: { true })
            do {
                _ = try await svc.prepareEdit(instruction: "y")
                XCTFail("expected noSelection")
            } catch {
                XCTAssertEqual(error as? VoiceEditError, .noSelection)
            }
        }
    }

    func test_emptyResultThrows() async {
        let svc = VoiceEditService(selection: MockSelection("hi"),
                                   rewriter: MockRewriter { _, _ in "   " },
                                   isProActive: { true })
        do {
            _ = try await svc.prepareEdit(instruction: "blank it")
            XCTFail("expected emptyResult")
        } catch {
            XCTAssertEqual(error as? VoiceEditError, .emptyResult)
        }
    }
}
