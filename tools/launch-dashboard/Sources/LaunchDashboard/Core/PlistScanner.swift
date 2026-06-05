import Foundation

struct PlistEntry: Equatable {
    let label: String
    let plistPath: String
    let stderrPath: String?
    let stdoutPath: String?
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
                stdoutPath: obj["StandardOutPath"] as? String
            ))
        }
        return out.sorted { $0.label < $1.label }
    }
}
