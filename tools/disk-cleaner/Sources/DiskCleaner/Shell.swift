import Foundation

/// Paths and process helpers shared by every pane.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let dotfiles = ProcessInfo.processInfo.environment["DOTFILES"] ?? "\(home)/.dotfiles"
    static let engine = "\(dotfiles)/bin/disk-cleanup.sh"
    static let barPlugin = "\(home)/.config/sketchybar/plugins/diskclean.sh"
    /// Shared with the sketchybar plugin so the bar and the app never sweep at once.
    static let lock = "/tmp/sketchybar-diskclean.lock"
    static var androidSDK: String {
        let env = ProcessInfo.processInfo.environment
        return env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] ?? "\(home)/Library/Android/sdk"
    }
    static let avdDir = "\(home)/.android/avd"

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ShellResult {
    let status: Int32
    let out: String
    let err: String
    var ok: Bool { status == 0 }
}

enum Shell {
    /// Apps opened via `open`/launchd get a bare PATH; add the places our tools live.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let home = Paths.home
        var extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                     "\(home)/.local/bin", "\(home)/Library/pnpm", "\(home)/.bun/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            extra += versions.sorted().reversed().map { "\(nvm)/\($0)/bin" }
        }
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extra + [current]).joined(separator: ":")
        return env
    }()

    static func makeProcess(_ exe: String, _ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        return p
    }

    /// Run to completion, capturing stdout and stderr.
    static func run(_ exe: String, _ args: [String]) async -> ShellResult {
        await Task.detached(priority: .userInitiated) { runBlocking(exe, args) }.value
    }

    private static func runBlocking(_ exe: String, _ args: [String]) -> ShellResult {
        let p = makeProcess(exe, args)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return ShellResult(status: -1, out: "", err: error.localizedDescription)
        }
        // Drain both pipes concurrently so a chatty stderr can't deadlock stdout.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return ShellResult(status: p.terminationStatus,
                           out: String(decoding: outData, as: UTF8.self),
                           err: String(decoding: errData, as: UTF8.self))
    }

    /// Fire-and-forget (used to poke sketchybar).
    static func spawn(_ exe: String, _ args: [String]) {
        let p = makeProcess(exe, args)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Size on disk in bytes via `du -sk` (follows nothing, so symlinks report ~0).
    static func du(_ path: String) async -> Int64? {
        let r = await run("/usr/bin/du", ["-sk", path])
        guard let first = r.out.split(separator: "\t").first, let kb = Int64(first) else { return nil }
        return kb * 1024
    }
}

enum Volume {
    struct Info {
        var total: Int64
        var free: Int64        // truly free right now
        var available: Int64   // free + purgeable (what Finder shows)
        var used: Int64 { total - free }
    }

    static func info() -> Info? {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        guard let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacity
        else { return nil }
        return Info(total: Int64(total), free: Int64(free),
                    available: v.volumeAvailableCapacityForImportantUsage ?? Int64(free))
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatMB(_ mb: Int) -> String { formatBytes(Int64(mb) * 1_048_576) }
