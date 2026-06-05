import XCTest
@testable import LaunchDashboard

final class RouterTests: XCTestCase {
    func testMatchesExactPath() {
        let router = Router()
        router.add("GET", "/services") { _, _ in .text(200, "list") }
        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: [:], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(String(data: resp.body, encoding: .utf8), "list")
    }

    func testCapturesPathParam() {
        let router = Router()
        router.add("POST", "/services/:label/start") { _, params in
            .text(200, params["label"] ?? "")
        }
        let req = HTTPRequest(method: "POST", path: "/services/com.example.foo/start",
                              headers: [:], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(String(data: resp.body, encoding: .utf8), "com.example.foo")
    }

    func testReturns404OnMiss() {
        let router = Router()
        let req = HTTPRequest(method: "GET", path: "/nope", headers: [:], body: Data())
        XCTAssertEqual(router.handle(req).status, 404)
    }
}
