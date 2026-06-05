import Foundation

enum Auth {
    static func allows(_ req: HTTPRequest, expected: String) -> Bool {
        guard let header = req.headers["Authorization"] ?? req.headers["authorization"]
        else { return false }
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(String(parts[1]), expected)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        if ab.count != bb.count { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}
