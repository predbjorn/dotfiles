import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}
