import XCTest
@testable import LaunchDashboard

final class AuthTests: XCTestCase {
    func testAcceptsValidBearer() {
        let req = HTTPRequest(method: "GET", path: "/x",
                              headers: ["Authorization": "Bearer abc123"], body: Data())
        XCTAssertTrue(Auth.allows(req, expected: "abc123"))
    }
    func testRejectsMissingHeader() {
        let req = HTTPRequest(method: "GET", path: "/x", headers: [:], body: Data())
        XCTAssertFalse(Auth.allows(req, expected: "abc123"))
    }
    func testRejectsWrongToken() {
        let req = HTTPRequest(method: "GET", path: "/x",
                              headers: ["Authorization": "Bearer wrong"], body: Data())
        XCTAssertFalse(Auth.allows(req, expected: "abc123"))
    }
}
