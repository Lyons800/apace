import XCTest
@testable import Murmur

@MainActor
final class MurmurConfigEngineTests: XCTestCase {

    func test_defaultEnginePreference_isAutomatic() {
        XCTAssertEqual(MurmurConfig().enginePreference, .automatic)
    }

    func test_decodingConfigWithoutEngineField_defaultsToAutomatic() throws {
        // Encode a real config, strip the enginePreference key, decode → must default.
        let data = try JSONEncoder().encode(MurmurConfig())
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "enginePreference")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(MurmurConfig.self, from: stripped)
        XCTAssertEqual(decoded.enginePreference, .automatic)
        // Verify another field also survived intact
        XCTAssertEqual(decoded.modelName, MurmurConfig().modelName)
    }
}
