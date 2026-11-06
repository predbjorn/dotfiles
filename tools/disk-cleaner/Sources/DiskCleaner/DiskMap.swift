import AppKit
import SwiftUI
import WebKit

/// Spaceburst (github.com/cfmatre/spaceburst): a sunburst map of the whole Data
/// volume. scan.py writes data.json + a self-contained diskmap.html, which we show
/// in a web view and drive from here.
enum Spaceburst {
    static let dir = ProcessInfo.processInfo.environment["SPACEBURST"]
        ?? "\(Paths.home)/Hacking/projects/spaceburst"
    static var script: String { "\(dir)/scan.py" }
    static var map: URL { URL(fileURLWithPath: "\(dir)/diskmap.html") }
    static var data: String { "\(dir)/data.json" }
    /// Shared with the sketchybar storage item so a bar click and the app never scan at once.
    static let lock = "/tmp/sketchybar-spaceburst.lock"

    struct Meta {
        var scannedAt: String
        var seconds: Int
        var blocked: Int
    }

    static func meta() -> Meta? {
        guard let raw = FileManager.default.contents(atPath: data),
              let d = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        return Meta(scannedAt: d["scanned_at"] as? String ?? "?",
                    seconds: d["scan_seconds"] as? Int ?? 0,
                    blocked: (d["blocked"] as? [Any])?.count ?? 0)
    }
}

@MainActor
final class DiskMapModel: ObservableObject {
    @Published var installed = FileManager.default.fileExists(atPath: Spaceburst.script)
    @Published var meta = Spaceburst.meta()
    @Published private(set) var scanning: String?   // path being scanned, "/" for the whole disk
    @Published var status = ""
    @Published var startedAt: Date?
    @Published var error: String?
    /// Bumped after every scan so the web view reloads.
    @Published var revision = 0
    private var process: Process?
    private var stopRequested = false
    /// Keeps App Nap from throttling the scan while the window is in the background.
    private var activity: NSObjectProtocol?

    var hasMap: Bool { FileManager.default.fileExists(atPath: Spaceburst.map.path) }

    func scan(_ path: String? = nil) {
        guard scanning == nil else { return }
        guard installed else { error = "spaceburst not found at \(Paths.tilde(Spaceburst.dir))"; return }
        guard (try? FileManager.default.createDirectory(atPath: Spaceburst.lock, withIntermediateDirectories: false)) != nil else {
            error = "A scan is already running (started from the bar)."
            return
        }
        error = nil
        stopRequested = false
        scanning = path ?? "/"
        status = "Starting…"
        startedAt = Date()

        let p = Shell.makeProcess("/usr/bin/python3", ["-u", Spaceburst.script] + (path.map { [$0] } ?? []))
        p.currentDirectoryURL = URL(fileURLWithPath: Spaceburst.dir)
        p.qualityOfService = .userInitiated
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Scanning the disk")
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p

        Task.detached { [weak self] in
            do { try p.run() } catch {
                await self?.finish(status: -1, signaled: false, last: error.localizedDescription)
                return
            }
            var last = ""
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    last = line
                    await self?.progress(line)
                }
            } catch {}
            p.waitUntilExit()
            await self?.finish(status: p.terminationStatus,
                               signaled: p.terminationReason == .uncaughtSignal, last: last)
        }
    }

    func stop() {
        stopRequested = true
        process?.terminate()
    }

    private func progress(_ line: String) {
        // "  ... 1,234,567 files, now in /System/Volumes/Data/Users/…"
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("... "), let r = t.range(of: ", now in ") {
            let files = t.dropFirst(4)[..<r.lowerBound]
            let where_ = String(t[r.upperBound...]).replacingOccurrences(of: "/System/Volumes/Data", with: "")
            status = "\(files) · \(Paths.tilde(where_))"
        } else if !t.isEmpty {
            status = t
        }
    }

    private func finish(status code: Int32, signaled: Bool, last: String) {
        try? FileManager.default.removeItem(atPath: Spaceburst.lock)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        process = nil
        scanning = nil
        startedAt = nil
        if code != 0 {
            error = stopRequested ? "Scan stopped."
                : signaled ? "Scan killed by signal \(code). Last output: \(last)"
                : "Scan failed (exit \(code)): \(last)"
        }
        meta = Spaceburst.meta()
        revision += 1
    }

    /// Rough 0…1 for the full-disk scan, from how long the previous one took.
    func estimate(at now: Date) -> Double? {
        guard scanning == "/", let startedAt, let s = meta?.seconds, s > 0 else { return nil }
        return min(0.97, now.timeIntervalSince(startedAt) / Double(s))
    }
}

// MARK: - Views

struct DiskMapView: View {
    @EnvironmentObject var model: DiskMapModel
    @EnvironmentObject var overview: OverviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Disk Map")
        .toolbar {
            ToolbarItem {
                if model.scanning != nil {
                    Button { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { model.scan() } label: { Label("Rescan disk", systemImage: "arrow.clockwise") }
                        .disabled(!model.installed)
                }
            }
        }
        .onChange(of: model.revision) { overview.refreshVolume() }
    }

    @ViewBuilder private var header: some View {
        if let scanning = model.scanning {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(scanning == "/" ? "Scanning the whole disk" : "Rescanning \(Paths.tilde(scanning))")
                            .font(.headline)
                        Spacer()
                        if let s = model.startedAt {
                            Text(Duration.seconds(ctx.date.timeIntervalSince(s)).formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if let frac = model.estimate(at: ctx.date) {
                        ProgressView(value: frac)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding()
            }
        } else {
            HStack(spacing: 12) {
                if let m = model.meta {
                    Label("Scanned \(m.scannedAt) in \(m.seconds / 60) min \(m.seconds % 60) s", systemImage: "clock")
                    if m.blocked > 0 {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        } label: {
                            Label("\(m.blocked) folders unreadable", systemImage: "lock")
                        }
                        .buttonStyle(.link)
                        .help("Give Disk Cleaner Full Disk Access so the scan can read them, then rescan.")
                    }
                } else if model.installed {
                    Label("No scan yet", systemImage: "clock")
                }
                Spacer()
                if let e = model.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
                } else {
                    Text("Right-click a wedge to reveal, copy or rescan it.").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    @ViewBuilder private var content: some View {
        if !model.installed {
            ContentUnavailableView {
                Label("spaceburst isn't installed", systemImage: "chart.pie")
            } description: {
                Text("Clone cfmatre/spaceburst to \(Paths.tilde(Spaceburst.dir)) (it's in githubProjects), or set SPACEBURST.")
            }
        } else if !model.hasMap {
            ContentUnavailableView {
                Label("No disk map yet", systemImage: "chart.pie")
            } description: {
                Text("A full scan of the Data volume takes a few minutes.")
            } actions: {
                Button("Scan disk") { model.scan() }.disabled(model.scanning != nil)
            }
        } else {
            MapWebView(url: Spaceburst.map, revision: model.revision) { path in
                model.scan(path)
            }
        }
    }
}

/// diskmap.html in a WKWebView, with the page's clipboard and right-click routed to the app.
struct MapWebView: NSViewRepresentable {
    let url: URL
    let revision: Int
    let rescan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(rescan: rescan) }

    func makeNSView(context: Context) -> WKWebView {
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "diskmap")
        ucc.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground") // no white flash before the dark page paints
        context.coordinator.loaded = revision
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.rescan = rescan
        if context.coordinator.loaded != revision {
            context.coordinator.loaded = revision
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// The map's paths are relative to the Data volume root, which firmlinks make
    /// identical to normal paths ("/Users/…"). Synthetic wedges (free, unaccounted)
    /// have no path. `itemFor` is the page's own hit-test.
    static let bridge = """
    (() => {
      const post = m => window.webkit.messageHandlers.diskmap.postMessage(m);
      try {
        Object.defineProperty(navigator, "clipboard", { configurable: true,
          value: { writeText: t => { post({ copy: String(t) }); return Promise.resolve(); } } });
      } catch (e) {}
      const svg = document.querySelector("svg");
      if (!svg || typeof itemFor !== "function") return;
      svg.addEventListener("contextmenu", e => {
        e.preventDefault();
        const it = itemFor(e);
        if (it && it.p) post({ menu: it.p, dir: !!it.n.c && !it.n.file });
      });
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var rescan: (String) -> Void
        var loaded = -1
        private var menuPath = ""

        init(rescan: @escaping (String) -> Void) { self.rescan = rescan }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let text = body["copy"] as? String {
                copy(text)
            } else if let path = body["menu"] as? String {
                showMenu(for: path, isDir: body["dir"] as? Bool ?? false, in: message.webView)
            }
        }

        private func copy(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private func showMenu(for path: String, isDir: Bool, in view: NSView?) {
            menuPath = path
            let menu = NSMenu()
            let title = NSMenuItem(title: Paths.tilde(path), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            let exists = FileManager.default.fileExists(atPath: path)
            menu.addItem(item("Reveal in Finder", #selector(reveal), enabled: exists))
            menu.addItem(item("Copy Path", #selector(copyPath)))
            if isDir {
                menu.addItem(item("Rescan This Folder", #selector(rescanFolder), enabled: exists))
            }
            guard let view, let window = view.window else { return }
            let pt = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            menu.popUp(positioning: nil, at: pt, in: view)
        }

        private func item(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            i.target = self
            return i
        }

        @objc private func reveal() { NSWorkspace.shared.selectFile(menuPath, inFileViewerRootedAtPath: "") }
        @objc private func copyPath() { copy(menuPath) }
        @objc private func rescanFolder() { rescan(menuPath) }
    }
}
