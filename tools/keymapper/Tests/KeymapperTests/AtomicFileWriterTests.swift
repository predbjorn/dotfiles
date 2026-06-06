import XCTest
@testable import Keymapper

final class AtomicFileWriterTests: XCTestCase {
    private var dir: URL!
    private var backups: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-\(UUID())")
        backups = dir.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testWriteCreatesFileWithContent() throws {
        let target = dir.appendingPathComponent("a.txt")
        let writer = AtomicFileWriter(backupDir: backups)
        try writer.write("hello\n", to: target, backupStem: "a")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "hello\n")
    }

    func testBackupCapturesPreviousContentWith0600() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "old".write(to: target, atomically: true, encoding: .utf8)
        let writer = AtomicFileWriter(backupDir: backups, timestamp: "20260606-120000")
        try writer.write("new", to: target, backupStem: "a")
        let backup = backups.appendingPathComponent("a.20260606-120000.bak")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "old")
        let perms = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testRetentionKeepsLastN() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "seed".write(to: target, atomically: true, encoding: .utf8)
        for i in 0..<25 {
            let ts = String(format: "20260606-1200%02d", i)
            let writer = AtomicFileWriter(backupDir: backups, timestamp: ts, retain: 20)
            try writer.write("v\(i)", to: target, backupStem: "a")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: self.backups.path)
            .filter { $0.hasPrefix("a.") && $0.hasSuffix(".bak") }
        XCTAssertEqual(names.count, 20)
        XCTAssertFalse(names.contains("a.20260606-120000.bak")) // oldest pruned
        XCTAssertTrue(names.contains("a.20260606-120024.bak"))  // newest kept
    }

    func testRestoreReturnsBackupContentToTarget() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "good".write(to: target, atomically: true, encoding: .utf8)
        let writer = AtomicFileWriter(backupDir: backups, timestamp: "20260606-120000")
        let backup = try writer.makeBackup(of: target, stem: "a")
        try "corrupt".write(to: target, atomically: true, encoding: .utf8)
        try writer.restore(backup, to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "good")
    }
}
