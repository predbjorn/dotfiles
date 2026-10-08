import Foundation

struct PlistEntry: Equatable {
    let label: String
    let plistPath: String
    let stderrPath: String?
    let stdoutPath: String?
    /// Human description for interval/calendar agents without KeepAlive ("every 10 min");
    /// nil for long-running services.
    var schedule: String? = nil
}

struct PlistScanner {
    let directory: URL

    static var userLaunchAgents: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    func scan() throws -> [PlistEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        var out: [PlistEntry] = []
        for name in names where name.hasSuffix(".plist") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any],
                  let label = obj["Label"] as? String
            else { continue }
            out.append(PlistEntry(
                label: label,
                plistPath: url.path,
                stderrPath: obj["StandardErrorPath"] as? String,
                stdoutPath: obj["StandardOutPath"] as? String,
                schedule: Self.schedule(of: obj)
            ))
        }
        return out.sorted { $0.label < $1.label }
    }

    static func schedule(of plist: [String: Any]) -> String? {
        if let keepAlive = plist["KeepAlive"], (keepAlive as? Bool) != false { return nil }
        if let seconds = plist["StartInterval"] as? Int, seconds > 0 {
            if seconds % 3600 == 0 { return "every \(seconds / 3600) h" }
            if seconds % 60 == 0 { return "every \(seconds / 60) min" }
            return "every \(seconds) s"
        }
        if plist["StartCalendarInterval"] != nil { return "on a calendar schedule" }
        return nil
    }
}
