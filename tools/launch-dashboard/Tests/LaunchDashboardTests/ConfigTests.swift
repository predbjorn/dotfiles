import XCTest
@testable import LaunchDashboard

final class ConfigTests: XCTestCase {
    func testLoadMissingFileCreatesDefaultsWithToken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        let cfg = try Config.loadOrCreate(at: url)
        XCTAssertEqual(cfg.httpPort, 8765)
        XCTAssertEqual(cfg.pollIntervalSeconds, 5)
        XCTAssertTrue(cfg.autoRestartEnabled)
        XCTAssertEqual(cfg.bearerToken.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testLoadExistingFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        let original = try Config.loadOrCreate(at: url)
        let again = try Config.loadOrCreate(at: url)
        XCTAssertEqual(original.bearerToken, again.bearerToken)
    }

    func testCorruptFileThrowsAndDoesNotRotateToken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        try "}{ not json".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try Config.loadOrCreate(at: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "}{ not json")
    }

    func testDecodesInspectTargets() throws {
        let json = """
        {"bearerToken":"x","httpPort":8765,"pollIntervalSeconds":5,"autoRestartEnabled":true,
         "inspectTargets":{"com.nors.ai-daemon":{"public":"https://daemon.prebenhafnor.com","local":"http://localhost:8787"}}}
        """
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let t = cfg.inspectTargets?["com.nors.ai-daemon"]
        XCTAssertEqual(t?.publicURL, URL(string: "https://daemon.prebenhafnor.com"))
        XCTAssertEqual(t?.localURL, URL(string: "http://localhost:8787"))
        XCTAssertEqual(t?.preferredURL, URL(string: "https://daemon.prebenhafnor.com"))
    }

    func testConfigWithoutInspectTargetsStillDecodes() throws {
        let json = """
        {"bearerToken":"x","httpPort":8765,"pollIntervalSeconds":5,"autoRestartEnabled":true}
        """
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertNil(cfg.inspectTargets)
        XCTAssertNil(cfg.cloudflaredConfigPath)
        XCTAssertNil(cfg.cloudflaredLabel)
    }

    func testPreferredURLFallsBackToLocal() {
        let t = InspectTarget(public: nil, local: "http://localhost:9000")
        XCTAssertEqual(t.preferredURL, URL(string: "http://localhost:9000"))
    }
}
