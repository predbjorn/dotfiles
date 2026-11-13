import AppKit
import SwiftUI

struct SimDevice: Identifiable {
    let udid: String
    let name: String
    let runtime: String
    let runtimeID: String
    let state: String
    let available: Bool
    let dataPath: String
    var size: Int64?
    let lastBooted: Date?
    var id: String { udid }
    var booted: Bool { state == "Booted" }
}

struct SimRuntime: Identifiable {
    let identifier: String
    let runtimeID: String
    let name: String
    let version: String
    let platform: String
    let build: String
    let size: Int64
    let lastUsed: Date?
    let deletable: Bool
    let state: String
    var id: String { identifier }
}

struct AndroidAVD: Identifiable {
    let name: String
    let displayName: String
    let dir: String
    let ini: String
    let systemImage: String?
    var size: Int64?
    let running: Bool
    var id: String { name }
}

struct SystemImage: Identifiable {
    let path: String
    let relative: String   // system-images/android-35/google_apis_playstore/arm64-v8a
    var size: Int64?
    var usedBy: [String]
    var id: String { path }
    var label: String {
        relative.split(separator: "/").dropFirst().joined(separator: " · ")
    }
}

/// A deletable folder in a build cache (one DerivedData project, one Gradle cache dir…).
struct CacheItem: Identifiable {
    let path: String
    let title: String
    let subtitle: String
    let badge: (String, Color)?
    var size: Int64?
    var orphaned = false
    /// Safe to sweep in a group: nothing is working in it right now (or nothing uses it).
    var idle = false
    var warning: String?
    /// Expandable lines under the row (who uses it).
    var details: [String] = []
    var id: String { path }
}

enum DeleteTarget: Identifiable {
    case sim(SimDevice), simCaches(SimDevice), unavailableSims(Int), runtime(SimRuntime, usedBy: Int), avd(AndroidAVD), image(SystemImage)
    case cache(CacheItem), cacheGroup([CacheItem], label: String)

    var id: String {
        switch self {
        case .sim(let d): "sim-\(d.udid)"
        case .simCaches(let d): "simcache-\(d.udid)"
        case .unavailableSims: "unavailable"
        case .runtime(let r, _): "rt-\(r.identifier)"
        case .avd(let a): "avd-\(a.name)"
        case .image(let i): "img-\(i.path)"
        case .cache(let c): "cache-\(c.path)"
        case .cacheGroup(_, let label): "group-\(label)"
        }
    }

    var title: String {
        switch self {
        case .sim(let d): "Delete simulator “\(d.name)”?"
        case .simCaches(let d): "Clear caches of “\(d.name)”?"
        case .unavailableSims(let n): "Delete \(n) unavailable simulator\(n == 1 ? "" : "s")?"
        case .runtime(let r, _): "Delete runtime \(r.name)?"
        case .avd(let a): "Delete emulator “\(a.displayName)”?"
        case .image(let i): "Delete system image \(i.label)?"
        case .cache(let c): "Delete \(c.title)?"
        case .cacheGroup(let items, let label): "Delete \(items.count) \(label)?"
        }
    }

    var message: String {
        switch self {
        case .sim(let d):
            "\(d.runtime) · \(d.size.map(formatBytes) ?? "unknown size"). Its apps and data are removed permanently."
                + (d.booted ? " It is running and will be shut down first." : "")
        case .simCaches:
            "Empties Library/Caches and tmp inside the simulator (system and app caches). "
                + "Installed apps, their data and settings stay."
        case .unavailableSims:
            "These simulators belong to runtimes that are no longer installed. Runs `xcrun simctl delete unavailable`."
        case .runtime(let r, let used):
            "Frees \(formatBytes(r.size)). Xcode can download it again."
                + (used > 0 ? " \(used) simulator\(used == 1 ? "" : "s") use this runtime and will become unavailable." : "")
        case .avd(let a):
            "\(a.size.map(formatBytes) ?? "unknown size"). The emulator's data and snapshots are removed permanently."
        case .image(let i):
            "Frees \(i.size.map(formatBytes) ?? "space"). Android Studio's SDK Manager can download it again."
                + (i.usedBy.isEmpty ? "" : " Used by: \(i.usedBy.joined(separator: ", ")) — they won't boot until it's reinstalled.")
        case .cache(let c):
            "Frees \(c.size.map(formatBytes) ?? "space"). It is rebuilt or re-downloaded on the next build."
                + (c.warning.map { " \($0)" } ?? "")
        case .cacheGroup(let items, _):
            "Frees \(formatBytes(items.compactMap(\.size).reduce(0, +))): "
                + items.map(\.title).joined(separator: ", ") + "."
        }
    }
}

@MainActor
final class DevicesModel: ObservableObject {
    @Published var sims: [SimDevice] = []
    @Published var runtimes: [SimRuntime] = []
    @Published var avds: [AndroidAVD] = []
    @Published var images: [SystemImage] = []
    @Published var derivedData: [CacheItem] = []
    @Published var gradle: [CacheItem] = []
    @Published var scratch: [CacheItem] = []
    @Published var scan: ProjectScan?
    @Published var loading = false
    @Published var loaded = false
    @Published var busy: Set<String> = []
    @Published var error: String?

    var onDeleted: (() -> Void)?

    func load() {
        guard !loading else { return }
        loading = true
        Task {
            async let s = Self.loadSims()
            async let r = Self.loadRuntimes()
            async let a = Self.loadAVDs()
            async let p = ProjectScan.load()
            async let act = Activity.load()
            let (sims, runtimes, avds, scan, activity) = await (s, r, a, p, act)
            self.sims = sims
            self.runtimes = runtimes
            self.avds = avds
            self.scan = scan
            self.images = await Self.loadImages(avds: avds, simq: scan.simq)
            self.derivedData = Self.loadDerivedData(activity: activity)
            self.scratch = Self.loadScratchBuilds(activity: activity)
            self.gradle = Self.loadGradle(daemonRunning: await Self.gradleDaemonRunning(), scan: scan)
            loading = false
            loaded = true
            // AVD and image sizes need du; fill them in after the list shows.
            for avd in self.avds {
                let size = await Shell.du(avd.dir)
                if let i = self.avds.firstIndex(where: { $0.name == avd.name }) { self.avds[i].size = size }
            }
            for img in self.images {
                let size = await Shell.du(img.path)
                if let i = self.images.firstIndex(where: { $0.path == img.path }) { self.images[i].size = size }
            }
            await fillSizes(\.derivedData)
            await fillSizes(\.scratch)
            await fillSizes(\.gradle)
        }
    }

    private func fillSizes(_ kp: ReferenceWritableKeyPath<DevicesModel, [CacheItem]>) async {
        for item in self[keyPath: kp] {
            let size = await Shell.du(item.path)
            if let i = self[keyPath: kp].firstIndex(where: { $0.path == item.path }) { self[keyPath: kp][i].size = size }
        }
    }

    func delete(_ target: DeleteTarget) {
        busy.insert(target.id)
        error = nil
        Task {
            let failure: String? = switch target {
            case .sim(let d): await Self.deleteSim(d)
            case .simCaches(let d): await Self.clearSimCaches(d)
            case .unavailableSims: Self.errorText(await Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"]))
            case .runtime(let r, _):
                Self.errorText(await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", r.identifier]))
            case .avd(let a): await Self.removeAsync([a.dir, a.ini])
            case .image(let i): await Self.removeAsync([i.path])
            case .cache(let c): await Self.removeAsync([c.path])
            case .cacheGroup(let items, _): await Self.removeAsync(items.map(\.path))
            }
            busy.remove(target.id)
            if let failure { error = failure }
            loading = false
            load()
            onDeleted?()
        }
    }

    // MARK: loaders

    nonisolated static func loadSims() async -> [SimDevice] {
        let r = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        guard let json = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
        let iso = ISO8601DateFormatter()
        var out: [SimDevice] = []
        for (runtimeID, list) in devices {
            for d in list {
                guard let udid = d["udid"] as? String else { continue }
                let dataPath = d["dataPath"] as? String ?? ""
                var size = (d["dataPathSize"] as? NSNumber)?.int64Value
                if size == nil, !dataPath.isEmpty { size = await Shell.du(dataPath) }
                out.append(SimDevice(
                    udid: udid,
                    name: d["name"] as? String ?? udid,
                    runtime: runtimeName(runtimeID),
                    runtimeID: runtimeID,
                    state: d["state"] as? String ?? "",
                    available: d["isAvailable"] as? Bool ?? true,
                    dataPath: dataPath,
                    size: size,
                    lastBooted: (d["lastBootedAt"] as? String).flatMap(iso.date)))
            }
        }
        return out.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    nonisolated static func loadRuntimes() async -> [SimRuntime] {
        let r = await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        guard let json = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: [String: Any]]
        else { return [] }
        let iso = ISO8601DateFormatter()
        return json.values.compactMap { d -> SimRuntime? in
            guard let ident = d["identifier"] as? String else { return nil }
            let platform = switch d["platformIdentifier"] as? String ?? "" {
            case "com.apple.platform.iphonesimulator": "iOS"
            case "com.apple.platform.appletvsimulator": "tvOS"
            case "com.apple.platform.watchsimulator": "watchOS"
            case "com.apple.platform.xrsimulator": "visionOS"
            default: "Simulator"
            }
            let version = d["version"] as? String ?? "?"
            return SimRuntime(
                identifier: ident,
                runtimeID: d["runtimeIdentifier"] as? String ?? "",
                name: "\(platform) \(version)",
                version: version,
                platform: platform,
                build: d["build"] as? String ?? "",
                size: (d["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                lastUsed: (d["lastUsedAt"] as? String).flatMap(iso.date),
                deletable: d["deletable"] as? Bool ?? false,
                state: d["state"] as? String ?? "")
        }
        .sorted { $0.size > $1.size }
    }

    nonisolated static func loadAVDs() async -> [AndroidAVD] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: Paths.avdDir) else { return [] }
        let ps = await Shell.run("/bin/ps", ["-axo", "command"]).out
        let runningNames = Set(ps.split(separator: "\n").compactMap { line -> String? in
            guard line.contains("qemu-system") || line.contains("emulator") else { return nil }
            let tokens = line.split(separator: " ").map(String.init)
            guard let i = tokens.firstIndex(of: "-avd"), i + 1 < tokens.count else { return nil }
            return tokens[i + 1]
        })
        return entries.filter { $0.hasSuffix(".ini") }.sorted().compactMap { file in
            let name = String(file.dropLast(4))
            let ini = "\(Paths.avdDir)/\(file)"
            let iniVals = parseIni(ini)
            let dir = iniVals["path"] ?? "\(Paths.avdDir)/\(name).avd"
            let config = parseIni("\(dir)/config.ini")
            return AndroidAVD(
                name: name,
                displayName: config["avd.ini.displayname"] ?? name.replacingOccurrences(of: "_", with: " "),
                dir: dir,
                ini: ini,
                systemImage: config["image.sysdir.1"].map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 },
                size: nil,
                running: runningNames.contains(name))
        }
    }

    nonisolated static func loadImages(avds: [AndroidAVD], simq: SimqPolicy?) async -> [SystemImage] {
        let fm = FileManager.default
        let root = "\(Paths.androidSDK)/system-images"
        var out: [SystemImage] = []
        // system-images/<api>/<tag>/<abi>
        for api in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !api.hasPrefix(".") {
            for tag in (try? fm.contentsOfDirectory(atPath: "\(root)/\(api)")) ?? [] where !tag.hasPrefix(".") {
                for abi in (try? fm.contentsOfDirectory(atPath: "\(root)/\(api)/\(tag)")) ?? [] where !abi.hasPrefix(".") {
                    let rel = "system-images/\(api)/\(tag)/\(abi)"
                    let users = avds.filter { $0.systemImage == rel }.map(\.displayName)
                        + (simq?.androidImage == rel ? ["simq pin"] : [])
                    out.append(SystemImage(path: "\(root)/\(api)/\(tag)/\(abi)", relative: rel, size: nil, usedBy: users))
                }
            }
        }
        return out
    }

    nonisolated static func loadDerivedData(activity: Activity) -> [CacheItem] {
        let fm = FileManager.default
        let root = "\(Paths.home)/Library/Developer/Xcode/DerivedData"
        let shared = ["ModuleCache.noindex": "Module cache", "SDKStatCaches.noindex": "SDK stat cache",
                      "CompilationCache.noindex": "Compilation cache"]
        return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }.compactMap { entry in
            let dir = "\(root)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
            if entry.hasSuffix(".noindex") {
                return CacheItem(path: dir, title: shared[entry] ?? entry, subtitle: "shared by all projects", badge: nil)
            }
            // <Project>-<28-letter hash>; a custom -derivedDataPath has no hash.
            let project = entry.replacingOccurrences(of: "-[a-z]{28}$", with: "", options: .regularExpression)
            let info = NSDictionary(contentsOfFile: "\(dir)/info.plist")
            guard let workspace = info?["WorkspacePath"] as? String else {
                return project == entry
                    ? CacheItem(path: dir, title: entry, subtitle: "custom derived data path", badge: nil)
                    : CacheItem(path: dir, title: project, subtitle: "no workspace recorded (build never finished)",
                                badge: ("Incomplete", .orange), orphaned: true)
            }
            var title = project
            if let r = workspace.range(of: "/.claude/worktrees/") {
                let worktree = workspace[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
                title += " · \(worktree)"
            }
            let used = (info?["LastAccessedDate"] as? Date).map { "built \($0.formatted(.relative(presentation: .named)))" }
            let orphaned = !fm.fileExists(atPath: workspace)
            let inUse = !orphaned && (activity.inUse(Activity.checkoutDir(containing: workspace))
                                      || activity.derivedDataPaths.contains(Activity.normalize(dir)))
            return CacheItem(
                path: dir, title: title,
                subtitle: [Paths.tilde((workspace as NSString).deletingLastPathComponent), used,
                           inUse ? nil : (orphaned ? nil : "no session or build running there")]
                    .compactMap { $0 }.joined(separator: " · "),
                badge: orphaned ? ("Project gone", .orange) : (inUse ? ("In use", .green) : ("Idle", .secondary)),
                orphaned: orphaned, idle: !orphaned && !inUse)
        }
    }

    /// Xcode builds Claude sessions put in their scratchpad (`xcodebuild -derivedDataPath
    /// /private/tmp/claude-<uid>/<project>/<session>/scratchpad/dd`). macOS only clears /tmp on reboot.
    nonisolated static func loadScratchBuilds(activity: Activity) -> [CacheItem] {
        let fm = FileManager.default
        let root = "/private/tmp/claude-\(getuid())"
        func subdirs(_ p: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: p)) ?? []).filter { e in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: "\(p)/\(e)", isDirectory: &isDir) && isDir.boolValue
            }
        }
        var out: [CacheItem] = []
        for project in subdirs(root) {
            for session in subdirs("\(root)/\(project)") {
                let scratch = "\(root)/\(project)/\(session)/scratchpad"
                for e in subdirs(scratch) {
                    let dir = "\(scratch)/\(e)"
                    guard ["Build", "SourcePackages", "ModuleCache.noindex", "info.plist"]
                        .contains(where: { fm.fileExists(atPath: "\(dir)/\($0)") }) else { continue }
                    let info = NSDictionary(contentsOfFile: "\(dir)/info.plist")
                    let workspace = info?["WorkspacePath"] as? String
                    // "-Users-me-Hacking-projects-tren--claude-worktrees-loving-cray-a87046"
                    let worktree = project.components(separatedBy: "--claude-worktrees-").dropFirst().first
                    let inUse = activity.derivedDataPaths.contains(dir)
                        || workspace.map { activity.inUse(Activity.checkoutDir(containing: $0)) } ?? false
                        || worktree.map { activity.inUse(worktree: $0) } ?? false
                    let name = workspace.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                    let title = [name, worktree].compactMap { $0 }.joined(separator: " · ")
                    let built = (info?["LastAccessedDate"] as? Date
                                 ?? (try? fm.attributesOfItem(atPath: dir))?[.modificationDate] as? Date)
                        .map { "built \($0.formatted(.relative(presentation: .named)))" }
                    out.append(CacheItem(
                        path: dir, title: title.isEmpty ? project : title,
                        subtitle: ["Claude scratchpad", built, inUse ? nil : "no session or build running there"]
                            .compactMap { $0 }.joined(separator: " · "),
                        badge: inUse ? ("In use", .green) : ("Idle", .secondary),
                        idle: !inUse))
                }
            }
        }
        return out
    }

    nonisolated static func loadGradle(daemonRunning: Bool, scan: ProjectScan) -> [CacheItem] {
        let fm = FileManager.default
        let caches = "\(Paths.home)/.gradle/caches"
        let dists = "\(Paths.home)/.gradle/wrapper/dists"
        let warning = daemonRunning ? "A Gradle daemon is running — run ./gradlew --stop first so an in-flight build doesn't break." : nil
        func dirs(_ root: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { e in
                var isDir: ObjCBool = false
                return !e.hasPrefix(".") && fm.fileExists(atPath: "\(root)/\(e)", isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        }
        let versionRx = "^[0-9]+(\\.[0-9]+)+$"
        let cacheDirs = dirs(caches)
        let distDirs = dirs(dists)
        let distVersions = distDirs.map { $0.replacingOccurrences(of: "^gradle-|-(bin|all)$", with: "", options: .regularExpression) }
        let versions = cacheDirs.filter { $0.range(of: versionRx, options: .regularExpression) != nil } + distVersions
        let newest = versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
        // Who pins this version in gradle/wrapper/gradle-wrapper.properties under ~/Hacking.
        func item(path: String, title: String, what: String, key: String, version: String) -> CacheItem {
            let usage = scan.gradleUsage(key)
            let newestNote = version == newest ? "newest installed" : nil
            return CacheItem(path: path, title: title,
                             subtitle: [usage.summary, newestNote, what].compactMap { $0 }.joined(separator: " · "),
                             badge: usage.badge, idle: usage.isUnused, warning: warning, details: usage.details)
        }
        let shared = "shared by every Gradle build (\(scan.gradleCheckouts) checkouts in ~/Hacking)"

        var out: [CacheItem] = cacheDirs.map { e in
            let path = "\(caches)/\(e)"
            if e.range(of: versionRx, options: .regularExpression) != nil {
                return item(path: path, title: "Gradle \(e) caches", what: "transforms, compiled build scripts, metadata",
                            key: e, version: e)
            }
            let (title, sub): (String, String) = switch e {
            case let x where x.hasPrefix("build-cache"): ("Build cache", "task outputs reused across builds · \(shared)")
            case let x where x.hasPrefix("modules"): ("Downloaded dependencies", "Maven/Google artifacts, re-downloaded on demand · \(shared)")
            case let x where x.hasPrefix("transforms"): ("Artifact transforms", "shared transform outputs · \(shared)")
            case let x where x.hasPrefix("jars"): ("Jar cache", "instrumented build-script jars · \(shared)")
            case let x where x.hasPrefix("journal"): ("Journal", "cache bookkeeping · \(shared)")
            default: (e, "~/.gradle/caches/\(e)")
            }
            return CacheItem(path: path, title: title, subtitle: sub, badge: nil, warning: warning)
        }
        out += zip(distDirs, distVersions).map { dir, v in
            let flavor = dir.hasSuffix("-all") ? "all" : "bin"
            return item(path: "\(dists)/\(dir)", title: "Gradle \(v) distribution\(flavor == "all" ? " (all)" : "")",
                        what: "wrapper download", key: "\(v)-\(flavor)", version: v)
        }
        return out
    }

    nonisolated static func gradleDaemonRunning() async -> Bool {
        await Shell.run("/usr/bin/pgrep", ["-f", "GradleDaemon"]).ok
    }

    // MARK: deleters

    nonisolated static func deleteSim(_ d: SimDevice) async -> String? {
        if d.booted { _ = await Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", d.udid]) }
        return errorText(await Shell.run("/usr/bin/xcrun", ["simctl", "delete", d.udid]))
    }

    /// Empty the simulator's own Library/Caches and tmp; apps and their data stay.
    nonisolated static func clearSimCaches(_ d: SimDevice) async -> String? {
        let fm = FileManager.default
        let dirs = ["\(d.dataPath)/Library/Caches", "\(d.dataPath)/tmp"]
        let paths = dirs.flatMap { dir in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { "\(dir)/\($0)" } }
        return await removeAsync(paths)
    }

    /// Big trees take seconds to delete; keep that off the main thread.
    nonisolated static func removeAsync(_ paths: [String]) async -> String? {
        await Task.detached(priority: .userInitiated) { remove(paths) }.value
    }

    nonisolated static func remove(_ paths: [String]) -> String? {
        for p in paths where FileManager.default.fileExists(atPath: p) {
            do { try FileManager.default.removeItem(atPath: p) } catch { return error.localizedDescription }
        }
        return nil
    }

    nonisolated static func errorText(_ r: ShellResult) -> String? {
        r.ok ? nil : (r.err.isEmpty ? "Command failed (\(r.status))" : r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated static func runtimeName(_ id: String) -> String {
        // com.apple.CoreSimulator.SimRuntime.iOS-26-5 → iOS 26.5
        let tail = id.components(separatedBy: "SimRuntime.").last ?? id
        var parts = tail.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return tail }
        let os = parts.removeFirst()
        return parts.isEmpty ? os : "\(os) \(parts.joined(separator: "."))"
    }

    nonisolated static func parseIni(_ path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            out[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}

// MARK: - View

struct DevicesView: View {
    @EnvironmentObject var model: DevicesModel
    @State private var pending: DeleteTarget?

    private var unavailable: Int { model.sims.filter { !$0.available }.count }

    /// Which projects this iOS runtime can run (deployment target ≤ runtime version), and
    /// whether it's the only installed runtime that can.
    private func runtimeUsage(_ r: SimRuntime) -> (text: String, badge: (String, Color)?, details: [String])? {
        guard r.platform == "iOS", let scan = model.scan, !scan.iosTargets.isEmpty else { return nil }
        let usage = scan.iosUsage(version: r.version, runtimeID: r.runtimeID)
        if usage.checkouts.isEmpty {
            return (usage.pinnedBy != nil ? usage.summary : "older than every project's deployment target",
                    usage.pinnedBy != nil ? usage.badge : ("Too old for all projects", .orange), usage.details)
        }
        let others = model.runtimes.filter { $0.platform == "iOS" && $0.identifier != r.identifier }
        let soleFor = usage.checkouts.filter { c in
            !others.contains { scan.iosTargets[c]!.compare($0.version, options: .numeric) != .orderedDescending }
        }
        let text = "deployment target fits · " + usage.summary
        let soleRepos = Set(soleFor.map(\.repoPath)).count
        let built = usage.recent.count
        let badge: (String, Color) = soleFor.isEmpty
            ? ("Replaceable", .yellow)
            : ("Only runtime for \(soleRepos) repo\(soleRepos == 1 ? "" : "s")"
               + (built > 0 ? " · \(built) built in \(Usage.recentDays) d" : ""), .green)
        return (text, badge, usage.details)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                DeviceSection(title: "iOS Simulators", systemImage: "iphone",
                              total: model.sims.compactMap(\.size).reduce(0, +),
                              empty: model.sims.isEmpty, loading: !model.loaded) {
                    if unavailable > 0 {
                        Button("Delete \(unavailable) unavailable") { pending = .unavailableSims(unavailable) }
                    }
                } content: {
                    ForEach(model.sims) { d in
                        DeviceRow(
                            icon: d.name.contains("iPad") ? "ipad" : (d.name.contains("Watch") ? "applewatch" : "iphone"),
                            title: d.name,
                            subtitle: [d.runtime, model.scan?.repo(named: d.name).map { "named for \($0)" },
                                       d.lastBooted.map { "booted \($0.formatted(.relative(presentation: .named)))" } ?? "never booted"]
                                .compactMap { $0 }.joined(separator: " · "),
                            badge: d.booted ? ("Running", .green) : (!d.available ? ("Unavailable", .orange)
                                : (model.scan?.simq?.iosPool.contains(d.udid) == true ? ("simq pool", .blue) : nil)),
                            secondary: d.dataPath.isEmpty ? nil : RowAction(
                                label: "Clear caches", systemImage: "sparkles", enabled: !d.booted,
                                help: d.booted ? "Shut the simulator down first" : "Empty its Library/Caches and tmp; apps and data stay"
                            ) { pending = .simCaches(d) },
                            size: d.size,
                            busy: model.busy.contains(DeleteTarget.sim(d).id) || model.busy.contains(DeleteTarget.simCaches(d).id),
                            reveal: d.dataPath.isEmpty ? nil : (d.dataPath as NSString).deletingLastPathComponent
                        ) { pending = .sim(d) }
                    }
                }

                DeviceSection(title: "Simulator Runtimes", systemImage: "square.stack.3d.up",
                              total: model.runtimes.map(\.size).reduce(0, +),
                              empty: model.runtimes.isEmpty, loading: !model.loaded) {
                    EmptyView()
                } content: {
                    ForEach(model.runtimes) { r in
                        let users = model.sims.filter { $0.runtimeID == r.runtimeID }.count
                        let projects = runtimeUsage(r)
                        DeviceRow(
                            icon: "shippingbox",
                            title: r.name,
                            subtitle: ["build \(r.build)", "\(users) simulator\(users == 1 ? "" : "s")",
                                       projects.map(\.text),
                                       r.lastUsed.map { "used \($0.formatted(.relative(presentation: .named)))" }]
                                .compactMap { $0 }.joined(separator: " · "),
                            badge: r.state != "Ready" ? (r.state, .orange)
                                : (projects?.badge ?? (users == 0 ? ("Unused", .orange) : nil)),
                            details: projects?.details ?? [],
                            size: r.size,
                            busy: model.busy.contains("rt-\(r.identifier)"),
                            reveal: nil,
                            canDelete: r.deletable
                        ) { pending = .runtime(r, usedBy: users) }
                    }
                }

                DeviceSection(title: "Android Emulators", systemImage: "candybarphone",
                              total: model.avds.compactMap(\.size).reduce(0, +),
                              empty: model.avds.isEmpty, loading: !model.loaded) {
                    EmptyView()
                } content: {
                    ForEach(model.avds) { a in
                        DeviceRow(
                            icon: "candybarphone",
                            title: a.displayName,
                            subtitle: ([a.systemImage.map { $0.split(separator: "/").dropFirst().joined(separator: " · ") } ?? a.name]
                                       + [model.scan?.repo(named: a.displayName).map { "named for \($0)" }].compactMap { $0 })
                                .joined(separator: " · "),
                            badge: a.running ? ("Running", .green)
                                : (model.scan?.simq?.androidPool.contains(a.name) == true ? ("simq pool", .blue) : nil),
                            size: a.size,
                            busy: model.busy.contains("avd-\(a.name)"),
                            reveal: a.dir,
                            canDelete: !a.running,
                            deleteHelp: a.running ? "Close the emulator first" : nil
                        ) { pending = .avd(a) }
                    }
                }

                DeviceSection(title: "Android System Images", systemImage: "opticaldisc",
                              total: model.images.compactMap(\.size).reduce(0, +),
                              empty: model.images.isEmpty, loading: !model.loaded) {
                    EmptyView()
                } content: {
                    ForEach(model.images) { i in
                        DeviceRow(
                            icon: "opticaldisc",
                            title: i.label,
                            subtitle: i.usedBy.isEmpty ? "not used by any emulator" : "used by \(i.usedBy.joined(separator: ", "))",
                            badge: i.usedBy.isEmpty ? ("Unused", .orange) : nil,
                            size: i.size,
                            busy: model.busy.contains("img-\(i.path)"),
                            reveal: i.path
                        ) { pending = .image(i) }
                    }
                }

                CacheSection(title: "Xcode DerivedData", systemImage: "hammer",
                             items: model.derivedData, loaded: model.loaded, busy: model.busy,
                             groups: [.init(button: "orphaned", label: "DerivedData folders whose project is gone", filter: \.orphaned),
                                      .init(button: "idle", label: "idle DerivedData folders (no session or build in their worktree)",
                                            filter: \.idle)],
                             pending: $pending)

                CacheSection(title: "Claude Scratch Builds", systemImage: "terminal",
                             items: model.scratch, loaded: model.loaded, busy: model.busy,
                             groups: [.init(button: "idle", label: "idle scratch builds (no session or build in their worktree)",
                                            filter: \.idle)],
                             pending: $pending)

                CacheSection(title: "Gradle", systemImage: "cube.box",
                             items: model.gradle, loaded: model.loaded, busy: model.busy,
                             groups: [.init(button: "unused", label: "Gradle versions no project pins", filter: \.idle)],
                             pending: $pending)
            }
            .padding(20)
        }
        .navigationTitle("Devices & Build Caches")
        .toolbar {
            ToolbarItem {
                if model.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.load() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                }
            }
        }
        .onAppear { if !model.loaded { model.load() } }
        .alert(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
               presenting: pending) { target in
            Button("Delete", role: .destructive) { model.delete(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(target.message)
        }
    }
}

struct CacheSection: View {
    let title: String
    let systemImage: String
    let items: [CacheItem]
    let loaded: Bool
    let busy: Set<String>
    let groups: [Group]
    @Binding var pending: DeleteTarget?

    /// A "Delete N <button>" action in the header for the items matching `filter`.
    struct Group {
        let button: String
        let label: String
        let filter: KeyPath<CacheItem, Bool>
    }

    var body: some View {
        DeviceSection(title: title, systemImage: systemImage,
                      total: items.compactMap(\.size).reduce(0, +),
                      empty: items.isEmpty, loading: !loaded) {
            HStack {
                ForEach(groups, id: \.button) { g in
                    let matched = items.filter { $0[keyPath: g.filter] }
                    if !matched.isEmpty {
                        let size = matched.compactMap(\.size).reduce(0, +)
                        Button("Delete \(matched.count) \(g.button)" + (size > 0 ? " (\(formatBytes(size)))" : "")) {
                            pending = .cacheGroup(matched, label: g.label)
                        }
                    }
                }
            }
        } content: {
            ForEach(items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }) { item in
                DeviceRow(
                    icon: "folder",
                    title: item.title,
                    subtitle: item.subtitle,
                    badge: item.badge,
                    details: item.details,
                    size: item.size,
                    busy: busy.contains(DeleteTarget.cache(item).id),
                    reveal: item.path
                ) { pending = .cache(item) }
            }
        }
    }
}

struct DeviceSection<Actions: View, Content: View>: View {
    let title: String
    let systemImage: String
    let total: Int64
    let empty: Bool
    let loading: Bool
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                if total > 0 {
                    Text(formatBytes(total)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                actions
            }
            .padding(.bottom, 4)
            if loading {
                ProgressView().controlSize(.small).padding(8)
            } else if empty {
                Text("None found").foregroundStyle(.tertiary).padding(8)
            } else {
                content
            }
        }
    }
}

/// An extra button on a row, left of Delete.
struct RowAction {
    let label: String
    let systemImage: String
    var enabled = true
    var help: String?
    let action: () -> Void
}

struct DeviceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: (String, Color)?
    var details: [String] = []
    var secondary: RowAction?
    let size: Int64?
    let busy: Bool
    let reveal: String?
    var canDelete = true
    var deleteHelp: String?
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if expanded, !details.isEmpty {
                Text(details.joined(separator: "\n"))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 44).padding(.bottom, 4)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                    if let badge {
                        Text(badge.0)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.1.opacity(0.15), in: Capsule())
                            .foregroundStyle(badge.1)
                    }
                }
                HStack(spacing: 4) {
                    if !details.isEmpty {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help(expanded ? "Hide who uses it" : "Show who uses it")
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(subtitle)
                }
            }
            Spacer()
            if let reveal, hovering {
                Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reveal) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            Group {
                if let size { Text(formatBytes(size)).monospacedDigit() } else { ProgressView().controlSize(.mini) }
            }
            .frame(width: 80, alignment: .trailing)
            if let secondary, !busy {
                Button(action: secondary.action) { Label(secondary.label, systemImage: secondary.systemImage) }
                    .disabled(!secondary.enabled)
                    .help(secondary.help ?? secondary.label)
            }
            if busy {
                ProgressView().controlSize(.small).frame(width: 76)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!canDelete)
                .help(deleteHelp ?? (canDelete ? "Delete" : "Not deletable"))
                .frame(width: 76)
            }
        }
    }
}
