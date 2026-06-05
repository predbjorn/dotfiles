import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let ownLabel = "com.prebenhafnor.launch-dashboard"

    private var menuBar: MenuBarController!
    private var server: HTTPServer!
    private var timer: Timer?
    private let monitor: ServiceMonitor
    private let client: LaunchctlClient
    private let restarter: AutoRestarter
    private let crashTracker = CrashTracker()
    private let notifier = CrashNotifier()
    private let config: Config
    private var notificationsAuthorized = false
    // one serial queue serializes ALL launchctl + shared-state access.
    private let workQueue = DispatchQueue(label: "com.prebenhafnor.launch-dashboard.work")

    override init() {
        // Missing config → create. Unreadable/corrupt → ephemeral RANDOM token (never a
        // guessable constant), and we still bind loopback-only so the blast radius is local.
        let loaded = try? Config.loadOrCreate(at: Config.defaultURL)
        if loaded == nil {
            NSLog("LaunchDashboard: config unreadable; using an ephemeral in-memory token for this run")
        }
        self.config = loaded ?? Config(bearerToken: Config.makeToken(), httpPort: 8765,
                                       pollIntervalSeconds: 5, autoRestartEnabled: false,
                                       watchedLabels: nil)
        let client = LaunchctlClient.makeReal()
        self.client = client
        self.monitor = ServiceMonitor(
            scanner: PlistScanner(directory: PlistScanner.userLaunchAgents),
            client: client,
            watchedLabels: self.config.watchedLabels
        )
        self.restarter = AutoRestarter(
            now: { Date().timeIntervalSince1970 },
            restart: { label in try? client.kickstart(label: label, restart: true) },
            ownLabel: AppDelegate.ownLabel
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(
            onStart:   { [weak self] label in self?.run { try $0.startService(label) } },
            onStop:    { [weak self] label in self?.run { try $0.client.bootout(label: label) } },
            onRestart: { [weak self] label in self?.run { try $0.client.kickstart(label: label, restart: true) } },
            onLoad:    { [weak self] label in self?.run { try $0.loadService(label) } }
        )

        // UNUserNotificationCenter requires a bundle identifier; a bare SwiftPM binary run
        // outside an .app bundle has none and crashes when touching it. Only use notifications
        // when bundled. (notifyCrash is additionally gated by notificationsAuthorized below.)
        if let bundleID = Bundle.main.bundleIdentifier {
            NSLog("LaunchDashboard: notifications enabled (bundle \(bundleID))")
            notifier.requestAuthorization { [weak self] granted in
                self?.workQueue.async { self?.notificationsAuthorized = granted }
            }
        } else {
            NSLog("LaunchDashboard: notifications disabled (running unbundled)")
        }

        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: client, token: config.bearerToken)
        server = HTTPServer(router: router, port: config.httpPort, workQueue: workQueue)
        do { try server.start() }
        catch { NSLog("HTTPServer failed to start: \(error)") }
        // NEVER log the bearer token. It lives only in the 0600 config.json.
        NSLog("LaunchDashboard listening on 127.0.0.1:\(config.httpPort) (token in config.json)")

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.pollIntervalSeconds),
                                     repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    // run a mutating action on the work queue, surface failures in the UI, refresh now.
    // Passing `self` into the action keeps the closure's trailing call non-optional (returns Void).
    private func run(_ action: @escaping (AppDelegate) throws -> Void) {
        workQueue.async { [weak self] in
            guard let self else { return }
            var message: String?
            do { try action(self) } catch { message = "\(error)" }
            DispatchQueue.main.async { self.menuBar.vm.lastError = message }
            self.pollOnQueue()
        }
    }

    private func startService(_ label: String) throws {
        let loaded = try client.listLoaded()
        if loaded[label] == nil {
            if let e = try monitor.scanner.scan().first(where: { $0.label == label }) {
                try client.bootstrap(plistPath: e.plistPath)
            }
        }
        try client.kickstart(label: label, restart: false)
    }

    private func loadService(_ label: String) throws {
        guard let e = try monitor.scanner.scan().first(where: { $0.label == label })
        else { throw LaunchctlError.commandFailed("no plist for \(label)") }
        try client.bootstrap(plistPath: e.plistPath)
    }

    @objc private func poll() {
        workQueue.async { [weak self] in self?.pollOnQueue() }
    }

    // runs on workQueue: snapshot, crash-tracking, and auto-restart are serialized.
    private func pollOnQueue() {
        do {
            let snap = try monitor.snapshot()
            let events = crashTracker.update(snap)
            if config.autoRestartEnabled { restarter.observe(snap) }
            let crashedSet = crashTracker.crashed
            DispatchQueue.main.async {
                self.menuBar.vm.services = snap
                self.menuBar.vm.crashed = crashedSet
                self.menuBar.updateBadge(failedCount: crashedSet.count)
            }
            if notificationsAuthorized {
                for e in events { notifier.notifyCrash(label: e.label, exitCode: e.exitCode) }
            }
        } catch {
            NSLog("poll failed: \(error)")
        }
    }
}
