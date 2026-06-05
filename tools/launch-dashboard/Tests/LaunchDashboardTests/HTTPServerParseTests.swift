import XCTest
@testable import LaunchDashboard

final class HTTPServerParseTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testParsesSimpleGet() {
        let raw = data("GET /services HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer tok\r\n\r\n")
        guard case .complete(let req) = HTTPServer.parse(raw) else { return XCTFail("expected complete") }
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/services")
        XCTAssertEqual(req.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(req.body.count, 0)
    }

    func testStripsQueryStringAndFragment() {
        let raw = data("GET /services?verbose=1#frag HTTP/1.1\r\nHost: x\r\n\r\n")
        guard case .complete(let req) = HTTPServer.parse(raw) else { return XCTFail("expected complete") }
        XCTAssertEqual(req.path, "/services")
    }

    func testIncompleteUntilHeaderTerminator() {
        let raw = data("GET /services HTTP/1.1\r\nHost: x\r\n")   // no blank line yet
        if case .incomplete = HTTPServer.parse(raw) {} else { XCTFail("expected incomplete") }
    }

    func testWaitsForFullBodyPerContentLength() {
        let partial = data("POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nab")   // 2 of 5 body bytes
        if case .incomplete = HTTPServer.parse(partial) {} else { XCTFail("expected incomplete (partial body)") }
        let full = data("POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nabcde")
        guard case .complete(let req) = HTTPServer.parse(full) else { return XCTFail("expected complete") }
        XCTAssertEqual(String(data: req.body, encoding: .utf8), "abcde")
    }

    func testTrimsHeaderValueWhitespace() {
        let raw = data("GET /x HTTP/1.1\r\nAuthorization:   Bearer tok  \r\n\r\n")
        guard case .complete(let req) = HTTPServer.parse(raw) else { return XCTFail("expected complete") }
        XCTAssertEqual(req.headers["Authorization"], "Bearer tok")
    }
}
