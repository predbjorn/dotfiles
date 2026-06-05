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
}
