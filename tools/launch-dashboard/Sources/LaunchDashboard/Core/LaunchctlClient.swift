import Foundation

struct LoadedEntry {
    let pid: Int?
    let lastExitCode: Int?
}

struct LaunchctlClient {
    let runner: ProcessRunner
    let uid: uid_t

    static func makeReal() -> LaunchctlClient {
        LaunchctlClient(runner: RealProcessRunner(), uid: getuid())
    }

    func listLoaded() throws -> [String: LoadedEntry] {
        let result = try runner.run("/bin/launchctl", ["list"])
        var out: [String: LoadedEntry] = [:]
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t", maxSplits: 2,
                                   omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let pid = Int(parts[0]) // "-" → nil
            let exit = Int(parts[1])
            let label = String(parts[2])
            out[label] = LoadedEntry(pid: pid, lastExitCode: exit)
        }
        return out
    }

    func kickstart(label: String, restart: Bool) throws {
        var args = ["kickstart"]
        if restart { args.append("-k") }
        args.append("gui/\(uid)/\(label)")
        let r = try runner.run("/bin/launchctl", args)
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }

    func bootstrap(plistPath: String) throws {
        let r = try runner.run("/bin/launchctl",
                               ["bootstrap", "gui/\(uid)", plistPath])
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }

    func bootout(label: String) throws {
        let r = try runner.run("/bin/launchctl",
                               ["bootout", "gui/\(uid)/\(label)"])
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }
}

enum LaunchctlError: Error {
    case commandFailed(String)
}
