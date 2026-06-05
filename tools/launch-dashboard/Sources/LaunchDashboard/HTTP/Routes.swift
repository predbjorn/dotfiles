import Foundation

enum Routes {
    static func register(router: Router,
                         monitor: ServiceMonitor,
                         client: LaunchctlClient,
                         token: String,
                         priorityLabels: [String]) {
        let guarded: (@escaping (HTTPRequest, [String: String]) -> HTTPResponse)
                  -> (HTTPRequest, [String: String]) -> HTTPResponse = { handler in
            return { req, params in
                guard Auth.allows(req, expected: token) else {
                    return .text(401, "unauthorized")
                }
                return handler(req, params)
            }
        }

        router.add("GET", "/services", guarded { _, _ in
            do {
                let snap = try monitor.snapshot()
                let arr = try JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(snap)) as? [Any] ?? []
                return .json(200, arr)
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        // [FIX 8] Ensure the job is in the domain before kickstart; bootstrap from plist if not.
        router.add("POST", "/services/:label/start", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let loaded = try client.listLoaded()
                if loaded[label] == nil {
                    guard let entry = try monitor.scanner.scan().first(where: { $0.label == label })
                    else { return .text(404, "no plist for label") }
                    try client.bootstrap(plistPath: entry.plistPath)
                }
                try client.kickstart(label: label, restart: false)
                return .text(200, "ok")
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/stop", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do { try client.bootout(label: label); return .text(200, "ok") }
            catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/restart", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do { try client.kickstart(label: label, restart: true); return .text(200, "ok") }
            catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("GET", "/services/:label/logs", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let entries = try monitor.scanner.scan()
                guard let entry = entries.first(where: { $0.label == label }),
                      let path = entry.stderrPath
                else { return .text(404, "no log") }
                // [FIX 11] confine to standard log locations.
                guard let resolved = resolvedAllowedLogPath(path) else { return .text(403, "log path not allowed") }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved))
                else { return .text(404, "no log") }
                let tail = String(data: data.suffix(16_384), encoding: .utf8) ?? ""
                return .text(200, tail)
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/load", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let entries = try monitor.scanner.scan()
                guard let entry = entries.first(where: { $0.label == label })
                else { return .text(404, "no plist") }
                try client.bootstrap(plistPath: entry.plistPath)
                return .text(200, "ok")
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })
    }

    /// [FIX 11] Returns the resolved real path IF it is under a known log directory, else nil.
    /// The caller reads the RESOLVED path (not the original), closing the check-then-read
    /// TOCTOU on a symlinked StandardErrorPath.
    static func resolvedAllowedLogPath(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefixes = ["\(home)/Library/Logs/", "/tmp/", "/private/tmp/", "/var/log/"]
        return prefixes.contains { resolved.hasPrefix($0) } ? resolved : nil
    }
}
