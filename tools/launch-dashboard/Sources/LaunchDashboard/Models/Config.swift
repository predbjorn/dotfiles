import Foundation
import Security

struct InspectTarget: Codable, Equatable {
    var `public`: String?
    var local: String?

    var publicURL: URL? { `public`.flatMap { URL(string: $0) } }
    var localURL: URL? { local.flatMap { URL(string: $0) } }
    /// Prefer the public (tunnel) URL; fall back to local.
    var preferredURL: URL? { publicURL ?? localURL }
}

struct Config: Codable {
    var bearerToken: String
    var httpPort: UInt16
    var pollIntervalSeconds: Int
    var autoRestartEnabled: Bool
    /// Priority labels: shown at the top of the popover and the ONLY ones that drive the
    /// menu-bar badge and crash notifications. The rest appear under "Show more". `nil`/empty
    /// = treat everything as priority (no split). Optional so existing config.json still decodes.
    var priorityLabels: [String]?
    /// Per-service inspect URLs (label → {public, local}). Optional so existing config.json decodes.
    var inspectTargets: [String: InspectTarget]?
    /// Path to the cloudflared config.yml. nil → ~/.cloudflared/config.yml.
    var cloudflaredConfigPath: String?
    /// LaunchAgent label for the tunnel, used for reload. nil → com.prebenhafnor.cloudflared.
    var cloudflaredLabel: String?

    static func loadOrCreate(at url: URL) throws -> Config {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)              // throws on unreadable
            return try JSONDecoder().decode(Config.self, from: data)  // throws on corrupt — no rotation
        }
        let fresh = Config(
            bearerToken: Self.makeToken(),
            httpPort: 8765,
            pollIntervalSeconds: 5,
            autoRestartEnabled: true,
            priorityLabels: nil,
            inspectTargets: nil,
            cloudflaredConfigPath: nil,
            cloudflaredLabel: nil
        )
        let data = try JSONEncoder().encode(fresh)
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return fresh
    }

    /// Internal (not private) so AppDelegate can mint an ephemeral token if config is unreadable.
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("CSPRNG unavailable; refusing to mint a predictable token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support.appendingPathComponent("LaunchDashboard/config.json")
    }
}
