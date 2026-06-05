import XCTest
@testable import LaunchDashboard

final class PlistScannerTests: XCTestCase {
    func testScansLabelsFromDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-scan-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("com.example.foo.plist")
        let body: [String: Any] = [
            "Label": "com.example.foo",
            "ProgramArguments": ["/bin/echo", "hi"],
            "StandardErrorPath": "/tmp/foo.err"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: body,
                                                      format: .xml, options: 0)
        try data.write(to: plist)

        let scanner = PlistScanner(directory: dir)
        let entries = try scanner.scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].label, "com.example.foo")
        XCTAssertEqual(entries[0].plistPath, plist.path)
        XCTAssertEqual(entries[0].stderrPath, "/tmp/foo.err")
    }

    func testIgnoresNonPlistFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-scan-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "junk".write(to: dir.appendingPathComponent("README.txt"),
                         atomically: true, encoding: .utf8)
        let entries = try PlistScanner(directory: dir).scan()
        XCTAssertEqual(entries.count, 0)
    }
}
