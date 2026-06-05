import Foundation

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return HTTPResponse(status: status,
                            headers: ["Content-Type": "application/json"],
                            body: data)
    }

    static func text(_ status: Int, _ string: String) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "text/plain; charset=utf-8"],
                     body: Data(string.utf8))
    }
}
