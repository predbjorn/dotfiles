import Foundation

final class Router {
    typealias Handler = (HTTPRequest, [String: String]) -> HTTPResponse
    private struct Route {
        let method: String
        let segments: [String]
        let handler: Handler
    }
    private var routes: [Route] = []

    func add(_ method: String, _ pattern: String, _ handler: @escaping Handler) {
        let segs = pattern.split(separator: "/").map(String.init)
        routes.append(Route(method: method, segments: segs, handler: handler))
    }

    func handle(_ req: HTTPRequest) -> HTTPResponse {
        let reqSegs = req.path.split(separator: "/").map(String.init)
        for r in routes where r.method == req.method && r.segments.count == reqSegs.count {
            var params: [String: String] = [:]
            var ok = true
            for (a, b) in zip(r.segments, reqSegs) {
                if a.hasPrefix(":") {
                    params[String(a.dropFirst())] = b
                } else if a != b {
                    ok = false; break
                }
            }
            if ok { return r.handler(req, params) }
        }
        return .text(404, "not found")
    }
}
