import Foundation

/// One cloudflared ingress route parsed from config.yml.
struct IngressRule: Identifiable, Equatable {
    let hostname: String?          // nil for the catch-all (service-only) rule
    let service: String
    let enabled: Bool              // false = commented out in config.yml
    let isCatchAll: Bool
    let lineRange: ClosedRange<Int>  // 0-based line indices this rule occupies

    var id: String { hostname ?? "__catchall_\(lineRange.lowerBound)" }
}
