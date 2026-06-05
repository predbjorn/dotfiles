import Foundation
import Network

final class HTTPServer {
    enum ParseOutcome {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    private let router: Router
    private let port: UInt16
    private let workQueue: DispatchQueue
    private let maxRequestBytes = 256 * 1024
    private static let requestTimeoutSeconds: TimeInterval = 10
    private var listener: NWListener?

    init(router: Router, port: UInt16, workQueue: DispatchQueue) {
        self.router = router
        self.port = port
        self.workQueue = workQueue
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // [FIX 2] bind to loopback only (IPv4); cloudflared reaches us at 127.0.0.1.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                  port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global())
            // Drop a connection that fails to deliver a full request in time (slowloris/idle guard).
            let timeout = DispatchWorkItem { conn.cancel() }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.requestTimeoutSeconds, execute: timeout)
            self?.receiveLoop(conn, accumulated: Data(), timeout: timeout)
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    // [FIX 9] keep reading until a full request is buffered (or limits are hit).
    private func receiveLoop(_ conn: NWConnection, accumulated: Data, timeout: DispatchWorkItem) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { timeout.cancel(); conn.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.count > self.maxRequestBytes {
                timeout.cancel()
                self.send(conn, .text(413, "request too large")); return
            }
            switch HTTPServer.parse(buffer) {
            case .complete(let req):
                timeout.cancel()
                self.workQueue.async {
                    let resp = self.router.handle(req)
                    self.send(conn, resp)
                }
            case .invalid:
                timeout.cancel()
                self.send(conn, .text(400, "bad request"))
            case .incomplete:
                if isComplete || error != nil { timeout.cancel(); conn.cancel() }
                else { self.receiveLoop(conn, accumulated: buffer, timeout: timeout) }
            }
        }
    }

    /// Pure, testable HTTP/1.1 request parser. Returns .incomplete until the header
    /// terminator AND the full Content-Length body are buffered. Strips any query
    /// string / fragment from the target before building `path`.
    static func parse(_ data: Data) -> ParseOutcome {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let headData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let bits = requestLine.split(separator: " ")
        guard bits.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        let bodyStart = range.upperBound
        let available = data.subdata(in: bodyStart..<data.endIndex)
        let expected: Int
        if let cl = headers.first(where: { $0.key.lowercased() == "content-length" })?.value {
            guard let n = Int(cl), n >= 0 else { return .invalid }
            expected = n
        } else {
            expected = 0
        }
        if available.count < expected { return .incomplete }
        let body = expected > 0 ? available.prefix(expected) : Data()

        // Strip query string / fragment from the target.
        let rawTarget = String(bits[1])
        let path = String(rawTarget.prefix { $0 != "?" && $0 != "#" })

        return .complete(HTTPRequest(method: String(bits[0]), path: path,
                                     headers: headers, body: Data(body)))
    }

    private func send(_ conn: NWConnection, _ resp: HTTPResponse) {
        conn.send(content: serialize(resp),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func serialize(_ resp: HTTPResponse) -> Data {
        var head = "HTTP/1.1 \(resp.status) \(reason(resp.status))\r\n"
        var headers = resp.headers
        headers["Content-Length"] = String(resp.body.count)
        headers["Connection"] = "close"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + resp.body
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
