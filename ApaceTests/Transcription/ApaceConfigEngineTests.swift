import XCTest
@testable import Apace

@MainActor
final class ApaceConfigEngineTests: XCTestCase {

    func test_defaultEnginePreference_isAutomatic() {
        XCTAssertEqual(ApaceConfig().enginePreference, .automatic)
    }

    func test_decodingConfigWithoutEngineField_defaultsToAutomatic() throws {
        // Encode a real config, strip the enginePreference key, decode → must default.
        let data = try JSONEncoder().encode(ApaceConfig())
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "enginePreference")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(ApaceConfig.self, from: stripped)
        XCTAssertEqual(decoded.enginePreference, .automatic)
        // Verify another field also survived intact
        XCTAssertEqual(decoded.modelName, ApaceConfig().modelName)
    }
}
