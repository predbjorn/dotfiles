import Foundation
import SwiftUI

/// One checkout of a repo under ~/Hacking: the main clone or one of its git worktrees.
struct Checkout: Hashable {
    let repo: String        // display name of the main repo, e.g. "tren"
    let repoPath: String
    let worktree: String?   // nil = the main checkout
    let path: String        // the checkout's own folder

    var label: String { worktree.map { "\(repo)/\($0)" } ?? "\(repo) (main)" }
}

/// Who depends on an item (a Gradle version, a simulator runtime…), for the "safe to delete?" call.
/// `checkouts` only *pin* it; `built` says which of them actually built with it, and when.
struct Usage {
    static let recentDays = 14

    var checkouts: Set<Checkout> = []
    var built: [Checkout: Date] = [:]
    var daemonRunning = false
    var pinnedBy: String?   // "simq" when ~/.simq/policy.json pins it

    var isUnused: Bool { checkouts.isEmpty && pinnedBy == nil }
    var repoCount: Int { Set(checkouts.map(\.repoPath)).count }

    /// Checkouts that built with it in the last `recentDays`, newest first.
    var recent: [(Checkout, Date)] {
        let cutoff = Date().addingTimeInterval(-Double(Self.recentDays) * 86_400)
        return built.filter { $0.value > cutoff }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var byRepo: [(path: String, name: String, main: Bool, worktrees: [String])] {
        Dictionary(grouping: checkouts, by: \.repoPath).map { path, cs in
            (path, cs.first!.repo, cs.contains { $0.worktree == nil }, cs.compactMap(\.worktree).sorted())
        }
        .sorted { ($0.worktrees.count + ($0.main ? 1 : 0), $1.name) > ($1.worktrees.count + ($1.main ? 1 : 0), $0.name) }
    }

    /// "daemon running · built in 14 d: tren/x, nors/y · pinned by tren (main + 70 worktrees) · Bedrock"
    var summary: String {
        var parts: [String] = []
        if daemonRunning { parts.append("daemon running") }
        let r = recent
        if !r.isEmpty {
            let names = r.prefix(3).map { $0.0.label }.joined(separator: ", ")
            parts.append("built in \(Self.recentDays) d: \(names)" + (r.count > 3 ? " +\(r.count - 3)" : ""))
        }
        let repos = byRepo.map { r -> String in
            let n = r.worktrees.count
            let wt = "\(n) worktree\(n == 1 ? "" : "s")"
            return switch (r.main, n) {
            case (true, 0): r.name
            case (true, _): "\(r.name) (main + \(wt))"
            default: "\(r.name) (\(wt))"
            }
        }
        if !repos.isEmpty { parts.append("pinned by " + repos.joined(separator: " · ")) }
        if let pinnedBy { parts.append("pinned by \(pinnedBy)") }
        return parts.isEmpty ? "no project in ~/Hacking pins it" : parts.joined(separator: " · ")
    }

    /// Recent builds first, then one line per repo naming its worktrees, for the expandable row.
    var details: [String] {
        let r = recent
        let builds = r.isEmpty ? [] : ["built in the last \(Self.recentDays) days:"] + r.map { c, d in
            "    \(c.label) — \(d.formatted(.relative(presentation: .named)))"
        }
        let pins = byRepo.map { r in
            var line = "pinned by \(r.name) — \(Paths.tilde(r.path))"
            if r.main { line += " (main checkout)" }
            if !r.worktrees.isEmpty {
                let shown = r.worktrees.prefix(12).joined(separator: ", ")
                line += "\n    worktrees: \(shown)" + (r.worktrees.count > 12 ? ", … +\(r.worktrees.count - 12) more" : "")
            }
            return line
        }
        return builds + pins + (pinnedBy.map { ["pinned in ~/.\($0)/policy.json"] } ?? [])
    }

    var badge: (String, Color) {
        if checkouts.isEmpty { return pinnedBy != nil ? ("Pinned by \(pinnedBy!)", .blue) : ("Unused", .orange) }
        let n = recent.count
        if n > 0 { return ("Built by \(n) · \(Self.recentDays) d", .green) }
        if daemonRunning { return ("Daemon running", .green) }
        return ("Idle · pinned by \(repoCount) repo\(repoCount == 1 ? "" : "s")", .yellow)
    }
}

/// `~/.simq/policy.json`, written by the simq tool (optional).
struct SimqPolicy {
    var iosRuntime: String?          // com.apple.CoreSimulator.SimRuntime.iOS-26-5
    var androidImage: String?        // system-images/android-35/google_apis_playstore/arm64-v8a
    var iosPool: Set<String> = []    // UDIDs
    var androidPool: Set<String> = [] // AVD names
    var gradleVersions: Set<String> = []

    static func load() -> SimqPolicy? {
        let path = "\(Paths.home)/.simq/policy.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var p = SimqPolicy()
        p.iosRuntime = json["ios_runtime"] as? String
        p.androidImage = (json["android_image"] as? String)?.replacingOccurrences(of: ";", with: "/")
        p.iosPool = Set(((json["ios_pool"] as? [String: String]) ?? [:]).values)
        p.androidPool = Set((json["android_pool"] as? [String]) ?? [])
        p.gradleVersions = Set((json["gradle_versions"] as? [String]) ?? [])
        return p
    }
}

/// What the repos under ~/Hacking (main checkouts and worktrees) pin: Gradle wrapper
/// versions and iOS deployment targets.
struct ProjectScan {
    /// "8.11.1" → checkouts whose gradle-wrapper.properties pins it; flavors keyed as "8.11.1-bin".
    var gradle: [String: Set<Checkout>] = [:]
    /// version → checkout → last build (mtime inside `<project>/.gradle/<version>`).
    var gradleBuilt: [String: [Checkout: Date]] = [:]
    var gradleDaemons: Set<String> = []
    /// Last Xcode build per checkout (DerivedData info.plist LastAccessedDate).
    var iosBuilt: [Checkout: Date] = [:]
    /// Lowest IPHONEOS_DEPLOYMENT_TARGET per checkout.
    var iosTargets: [Checkout: String] = [:]
    var repoNames: Set<String> = []
    var simq: SimqPolicy?

    var gradleCheckouts: Int { Set(gradle.filter { !$0.key.contains("-") }.values.flatMap { $0 }).count }

    func gradleUsage(_ key: String) -> Usage {
        let version = key.replacingOccurrences(of: "-(bin|all)$", with: "", options: .regularExpression)
        return Usage(checkouts: gradle[key] ?? [], built: gradleBuilt[version] ?? [:],
                     daemonRunning: gradleDaemons.contains(version),
                     pinnedBy: simq?.gradleVersions.contains(version) == true ? "simq" : nil)
    }

    /// Checkouts whose deployment target this iOS version satisfies.
    func iosUsage(version: String, runtimeID: String) -> Usage {
        let cs = Set(iosTargets.filter { $0.value.compare(version, options: .numeric) != .orderedDescending }.keys)
        return Usage(checkouts: cs, built: iosBuilt.filter { cs.contains($0.key) },
              pinnedBy: simq?.iosRuntime == runtimeID ? "simq" : nil)
    }

    /// The repo a simulator/emulator is named after ("Tren BoxRead 17 Pro" → tren).
    func repo(named deviceName: String) -> String? {
        let lower = deviceName.lowercased()
        return repoNames.filter { $0.count >= 3 && lower.contains($0.lowercased()) }.max { $0.count < $1.count }
    }

    static var root: String { ProcessInfo.processInfo.environment["HACKING"] ?? "\(Paths.home)/Hacking" }

    nonisolated static func load() async -> ProjectScan {
        let root = root
        // One find pass; prune dependency/build trees and hidden dirs (except worktree folders).
        let prune = ["node_modules", "Pods", "build", "DerivedData", "vendor", "SourcePackages", "Carthage"]
        var args = [root, "("]
        for (i, name) in prune.enumerated() { args += (i == 0 ? [] : ["-o"]) + ["-name", name] }
        args += ["-o", "(", "-name", ".*", "!", "-name", ".claude", "!", "-name", ".worktrees", "!", "-path", root, ")",
                 ")", "-prune", "-o",
                 "(", "-path", "*/gradle/wrapper/gradle-wrapper.properties", "-o", "-name", "project.pbxproj", ")", "-print"]
        let findArgs = args
        async let found = Shell.run("/usr/bin/find", findArgs)
        async let ps = Shell.run("/bin/ps", ["-axo", "command"])
        let out = await found.out
        var scan = ProjectScan()
        scan.simq = SimqPolicy.load()
        var checkouts: [String: Checkout] = [:]
        for file in out.split(separator: "\n").map(String.init) {
            let c = checkout(for: file, root: root, cache: &checkouts)
            scan.repoNames.insert(c.repo)
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            if file.hasSuffix(".properties") {
                // distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-bin.zip
                guard let m = text.range(of: "gradle-[^/]+-(bin|all)\\.zip", options: .regularExpression) else { continue }
                let flavored = String(text[m].dropFirst("gradle-".count).dropLast(".zip".count))
                let version = flavored.replacingOccurrences(of: "-(bin|all)$", with: "", options: .regularExpression)
                scan.gradle[version, default: []].insert(c)
                // Gradle keeps per-version state in <project>/.gradle/<version>; it exists only if
                // this checkout actually built with that version.
                let project = String(file.dropLast("/gradle/wrapper/gradle-wrapper.properties".count))
                if let d = lastModified(inside: "\(project)/.gradle/\(version)") {
                    scan.gradleBuilt[version, default: [:]][c] = max(d, scan.gradleBuilt[version]?[c] ?? d)
                }
                scan.gradle[flavored, default: []].insert(c)
            } else {
                let rx = try! NSRegularExpression(pattern: "IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);")
                let targets = rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                    Range($0.range(at: 1), in: text).map { String(text[$0]) }
                }
                guard let lowest = targets.min(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else { continue }
                if let cur = scan.iosTargets[c], cur.compare(lowest, options: .numeric) != .orderedDescending { continue }
                scan.iosTargets[c] = lowest
            }
        }
        // Running daemons: "… org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.11.1"
        for line in await ps.out.split(separator: "\n") {
            if let r = line.range(of: "GradleDaemon [0-9.]+", options: .regularExpression) {
                scan.gradleDaemons.insert(String(line[r].dropFirst("GradleDaemon ".count)))
            }
        }
        // Last Xcode build per checkout, matched by the longest checkout path containing the workspace.
        let roots = Set(checkouts.values).sorted { $0.path.count > $1.path.count }
        let dd = "\(Paths.home)/Library/Developer/Xcode/DerivedData"
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: dd)) ?? [] {
            guard let info = NSDictionary(contentsOfFile: "\(dd)/\(entry)/info.plist"),
                  let ws = info["WorkspacePath"] as? String, let date = info["LastAccessedDate"] as? Date,
                  let c = roots.first(where: { ws.hasPrefix($0.path + "/") }) else { continue }
            scan.iosBuilt[c] = max(date, scan.iosBuilt[c] ?? date)
        }
        return scan
    }

    nonisolated static func lastModified(inside dir: String) -> Date? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        return ([dir] + entries.map { "\(dir)/\($0)" })
            .compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
    }

    /// Walk up to the nearest `.git`: a directory is a main checkout, a file points into
    /// `<main>/.git/worktrees/<name>` for a worktree.
    nonisolated static func checkout(for file: String, root: String, cache: inout [String: Checkout]) -> Checkout {
        let fm = FileManager.default
        var dir = (file as NSString).deletingLastPathComponent
        var visited: [String] = []
        var result: Checkout?
        while dir.count > root.count, result == nil {
            if let hit = cache[dir] { result = hit; break }
            visited.append(dir)
            let git = "\(dir)/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                if !isDir.boolValue, let text = try? String(contentsOfFile: git, encoding: .utf8),
                   let r = text.range(of: "gitdir:") {
                    var gitdir = text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !gitdir.hasPrefix("/") { gitdir = URL(fileURLWithPath: "\(dir)/\(gitdir)").standardized.path }
                    if let w = gitdir.range(of: "/.git/worktrees/") {
                        let main = String(gitdir[..<w.lowerBound])
                        result = Checkout(repo: (main as NSString).lastPathComponent, repoPath: main,
                                          worktree: (dir as NSString).lastPathComponent, path: dir)
                        break
                    }
                }
                result = Checkout(repo: (dir as NSString).lastPathComponent, repoPath: dir, worktree: nil, path: dir)
                break
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        let c = result ?? {
            // Not in git: use the top folder under the root.
            let rel = file.dropFirst(root.count + 1).split(separator: "/").first.map(String.init) ?? file
            return Checkout(repo: rel, repoPath: "\(root)/\(rel)", worktree: nil, path: "\(root)/\(rel)")
        }()
        for d in visited { cache[d] = c }
        return c
    }
}
