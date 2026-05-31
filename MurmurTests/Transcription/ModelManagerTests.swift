import XCTest
@testable import Murmur

final class ModelManagerTests: XCTestCase {
    func test_engineAvailability_appleUnavailableBelowMacOS26() {
        let avail = ModelManager.availability(osMajor: 15)
        XCTAssertFalse(avail[.appleSpeech] ?? true)
        XCTAssertTrue(avail[.whisperKit] ?? false)
        XCTAssertTrue(avail[.parakeet] ?? false)
    }
    func test_engineAvailability_appleAvailableOnMacOS26() {
        let avail = ModelManager.availability(osMajor: 26)
        XCTAssertTrue(avail[.appleSpeech] ?? false)
    }
}
