import Foundation
import SwiftUI

/// Read-only view of simq (~/Hacking/simq): the shared simulator/emulator pool and version pins
/// in `$SIMQ_HOME` (default `~/.simq`). We only read `policy.json` and `state.json`; simq writes
/// them atomically (temp file + rename), so no lock is needed. A missing or unparsable policy
/// means simq isn't set up: `load` returns nil and nothing simq-related is shown.
struct Simq {
    struct Lease {
        let device: String
        let kind: String
        let sessionID: String
        let project: String?
        let since: Date?
        let lastActivity: Date?

        var projectName: String { project.map { ($0 as NSString).lastPathComponent } ?? "unknown project" }
    }

    /// A pending approval request from a Claude session (only `pending` ones are decoded).
    struct Request {
        let id: Int
        let type: String
        let project: String?
        let command: String
        let detail: String?
        let reason: String?
        let cwd: String?
        let created: Date?

        var projectName: String { project.map { ($0 as NSString).lastPathComponent } ?? "unknown project" }
    }

    /// A session waiting in a device queue.
    struct Waiter {
        let sessionID: String
        let project: String?
        let device: String?
        let since: Date?
    }

    /// Where a pool device stands right now.
    enum DeviceState: Equatable {
        case held(project: String, idleMinutes: Int?)
        case reserved
        case free

        var text: String {
            switch self {
            case .held(let p, let idle): "held by \(p)" + (idle.map { " (idle \(Simq.minutes($0)))" } ?? "")
            case .reserved: "reserved"
            case .free: "free"
            }
        }
    }

    var iosRuntime: String?            // com.apple.CoreSimulator.SimRuntime.iOS-26-5
    var androidImage: String?          // system-images/android-35/google_apis_playstore/arm64-v8a
    var iosPool: [String: String] = [:] // pool name → UDID
    var androidPool: [String] = []      // AVD names
    var gradleVersions: Set<String> = []

    var leases: [Lease] = []
    var queues: [String: [Waiter]] = [:]     // kind → sessions waiting
    var reservations: [String: Date] = [:]   // device → reserved until
    var requests: [Request] = []             // pending only, newest first
    var idleMinutesLimit = 45

    var queued: [String: Int] { queues.mapValues(\.count) }
    var pendingRequests: Int { requests.count }

    static var home: String { ProcessInfo.processInfo.environment["SIMQ_HOME"] ?? "\(Paths.home)/.simq" }

    static func load(home: String = home) -> Simq? {
        guard let policy = FileManager.default.contents(atPath: "\(home)/policy.json") else { return nil }
        return parse(policy: policy, state: FileManager.default.contents(atPath: "\(home)/state.json"))
    }

    /// Never throws: a bad policy gives nil, a bad or missing state gives an empty one.
    static func parse(policy: Data, state: Data?) -> Simq? {
        guard let p = (try? JSONSerialization.jsonObject(with: policy)) as? [String: Any] else { return nil }
        var s = Simq()
        s.iosRuntime = p["ios_runtime"] as? String
        s.androidImage = (p["android_image"] as? String)?.replacingOccurrences(of: ";", with: "/")
        s.iosPool = (p["ios_pool"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        s.androidPool = (p["android_pool"] as? [Any] ?? []).compactMap { $0 as? String }
        s.gradleVersions = Set((p["gradle_versions"] as? [Any] ?? []).compactMap { $0 as? String })

        s.idleMinutesLimit = (p["idle_minutes"] as? NSNumber)?.intValue ?? 45

        guard let state, let st = (try? JSONSerialization.jsonObject(with: state)) as? [String: Any] else { return s }
        let date: (Any?) -> Date? = { ($0 as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        s.leases = (st["leases"] as? [Any] ?? []).compactMap { any in
            guard let l = any as? [String: Any], let device = l["device"] as? String else { return nil }
            return Lease(device: device, kind: l["kind"] as? String ?? "", sessionID: l["session_id"] as? String ?? "",
                         project: l["project"] as? String, since: date(l["since"]), lastActivity: date(l["last_activity"]))
        }
        s.queues = (st["queues"] as? [String: Any] ?? [:]).mapValues { any in
            (any as? [Any] ?? []).compactMap { w in
                guard let w = w as? [String: Any], let sid = w["session_id"] as? String else { return nil }
                return Waiter(sessionID: sid, project: w["project"] as? String, device: w["device"] as? String, since: date(w["since"]))
            }
        }
        s.reservations = (st["reservations"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? [String: Any]).flatMap { date($0["until"]) } }
        s.requests = (st["requests"] as? [Any] ?? []).compactMap { any -> Request? in
            guard let r = any as? [String: Any], r["status"] as? String == "pending",
                  let id = (r["id"] as? NSNumber).flatMap({ $0 === kCFBooleanTrue || $0 === kCFBooleanFalse ? nil : $0.intValue })
            else { return nil }
            return Request(id: id, type: r["type"] as? String ?? "", project: r["project"] as? String,
                           command: r["command"] as? String ?? "", detail: r["detail"] as? String,
                           reason: r["reason"] as? String, cwd: r["cwd"] as? String, created: date(r["created"]))
        }.sorted { ($0.created ?? .distantPast, $0.id) > ($1.created ?? .distantPast, $1.id) }
        return s
    }

    // MARK: lookups

    /// Pool name for a simulator UDID or AVD name.
    func poolName(udid: String) -> String? { iosPool.first { $0.value == udid }?.key }
    func poolName(avd: String) -> String? { androidPool.contains(avd) ? avd : nil }

    func state(of device: String, now: Date = Date()) -> DeviceState {
        if let l = leases.first(where: { $0.device == device }) {
            return .held(project: l.projectName,
                         idleMinutes: l.lastActivity.map { max(0, Int(now.timeIntervalSince($0)) / 60) })
        }
        if let until = reservations[device], until > now { return .reserved }
        return .free
    }

    /// Held by a Claude session that has been inactive for `idleMinutesLimit` or more (never the human).
    func isIdle(_ l: Lease, now: Date = Date()) -> Bool {
        guard l.sessionID != "human", let last = l.lastActivity else { return false }
        return now.timeIntervalSince(last) >= Double(idleMinutesLimit) * 60
    }

    /// "simq: 1/2 sims held · 0/1 emulators held · 1 queued · 1 pending request"
    func summary(now: Date = Date()) -> String {
        let held: (String, [String]) -> String = { noun, devices in
            "\(devices.filter { if case .held = state(of: $0, now: now) { true } else { false } }.count)/\(devices.count) \(noun) held"
        }
        var parts = [held("sims", Array(iosPool.keys)), held("emulators", androidPool)]
        let q = queued.values.reduce(0, +)
        if q > 0 { parts.append("\(q) queued") }
        if pendingRequests > 0 { parts.append("\(pendingRequests) pending request\(pendingRequests == 1 ? "" : "s")") }
        return "simq: " + parts.joined(separator: " · ")
    }

    static func minutes(_ m: Int) -> String { m < 60 ? "\(m)m" : "\(m / 60)h\(m % 60 == 0 ? "" : " \(m % 60)m")" }

    /// Badge for a device: pool status, or a warning for a running device outside the pool.
    func badge(pool: String?, running: Bool) -> (String, Color)? {
        guard let pool else { return running ? ("Running · outside simq pool", .orange) : nil }
        return switch state(of: pool) {
        case .held: ("simq \(pool) · held", .green)
        case .reserved: ("simq \(pool) · reserved", .blue)
        case .free: ("simq \(pool) · free", .blue)
        }
    }

    static let poolDeleteWarning = "This device is in the simq pool. Removing it breaks the pool for every Claude session. "
        + "Remove it from ~/.simq/policy.json first (simq has no command for that)."
}
