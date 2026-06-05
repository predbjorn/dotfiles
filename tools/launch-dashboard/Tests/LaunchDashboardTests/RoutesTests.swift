import XCTest
@testable import LaunchDashboard

final class RoutesTests: XCTestCase {
    func testListServicesReturnsSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body: [String: Any] = ["Label": "com.example.foo",
                                   "ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: body,
                                                      format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("com.example.foo.plist"))

        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok", priorityLabels: [])

        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let obj = try JSONSerialization.jsonObject(with: resp.body) as? [[String: Any]]
        XCTAssertEqual(obj?.first?["label"] as? String, "com.example.foo")
    }

    func testRestartTriggersKickstartK() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok", priorityLabels: [])

        let req = HTTPRequest(method: "POST",
                              path: "/services/com.example.foo/restart",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(fake.calls.last?.1,
                       ["kickstart", "-k", "gui/501/com.example.foo"])
    }

    func testStartBootstrapsWhenNotLoaded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body: [String: Any] = ["Label": "com.example.foo", "ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        let plistURL = dir.appendingPathComponent("com.example.foo.plist")
        try data.write(to: plistURL)

        let fake = FakeRunner()   // empty `launchctl list` → service not loaded
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client, token: "tok", priorityLabels: [])

        let req = HTTPRequest(method: "POST", path: "/services/com.example.foo/start",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let cmds = fake.calls.map(\.1)
        XCTAssertTrue(cmds.contains(["bootstrap", "gui/501", plistURL.path]))
        XCTAssertTrue(cmds.contains(["kickstart", "gui/501/com.example.foo"]))
    }

    func testLogsRejectsPathOutsideAllowlist() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let secret = dir.appendingPathComponent("id_ed25519")
        try "PRIVATE KEY".write(to: secret, atomically: true, encoding: .utf8)
        let body: [String: Any] = ["Label": "com.evil.foo",
                                   "ProgramArguments": ["/bin/true"],
                                   "StandardErrorPath": secret.path]   // not under allowlist
        let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("com.evil.foo.plist"))

        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: FakeRunner(), uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client, token: "tok", priorityLabels: [])

        let req = HTTPRequest(method: "GET", path: "/services/com.evil.foo/logs",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        XCTAssertEqual(router.handle(req).status, 403)
    }

    func testUnauthorizedReturns401() {
        let dir = FileManager.default.temporaryDirectory
        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok", priorityLabels: [])
        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: [:], body: Data())
        XCTAssertEqual(router.handle(req).status, 401)
    }
}
