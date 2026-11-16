import Foundation
import SwiftUI

/// Live simq state for the simq pane and the sidebar badge. Reads `$SIMQ_HOME` (never writes it):
/// every change goes through the `simq` CLI, run as the human.
@MainActor
final class SimqModel: ObservableObject {
    @Published var simq: Simq?
    @Published var running = false
    /// CLI output per row: `"req-<id>"`, `"dev-<name>"` or `"doctor"`.
    @Published var rowMessage: [String: String] = [:]

    private let home: String
    private var source: DispatchSourceFileSystemObject?
    private var poll: Timer?

    init(home: String = Simq.home) {
        self.home = home
        reload()
        watch()
    }

    deinit {
        source?.cancel()
        poll?.invalidate()
    }

    /// `Simq.load` returns nil only without a readable policy (not set up); a state.json caught
    /// mid-write still gives the policy with an empty state, so just replace.
    func reload() {
        simq = Simq.load(home: home)
    }

    /// Runs one CLI command at a time, keeps its output on the row, then re-reads the state.
    func act(_ key: String, _ args: [String]) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let r = await SimqCLI.run(args)
        let output = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        rowMessage[key] = r.code == 0
            ? (output.isEmpty ? "Done." : output)
            : "\(Self.exitText(r.code))" + (output.isEmpty ? "" : "\n\(output)")
        reload()
    }

    static func exitText(_ code: Int32) -> String {
        switch code {
        case 1: "Error (exit 1)"
        case 2: "Queued or timed out (exit 2)"
        case 3: "Refused (exit 3)"
        case 4: "Not allowed: simq didn't see a human (exit 4)"
        default: "Failed (exit \(code))"
        }
    }

    // MARK: watching

    /// simq writes state.json by temp file + rename, which shows up as a write on the directory.
    /// While the directory is missing, poll every 5 s until it appears.
    private func watch() {
        source?.cancel()
        source = nil
        poll?.invalidate()
        poll = nil

        let fd = open(home, O_EVTONLY)
        guard fd >= 0 else {
            poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                    self?.watch()
                }
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reload()
                // The directory itself went away or moved: watch the path again.
                if let src, !src.data.isDisjoint(with: [.delete, .rename]) { self.watch() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }
}

struct SimqView: View {
    @EnvironmentObject var model: SimqModel

    var body: some View {
        if let simq = model.simq {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SimqRequestsSection(simq: simq, now: context.date)
                        SimqPoolSection(simq: simq, now: context.date)
                        SimqQueuesSection(simq: simq, now: context.date)
                        SimqHealthSection()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ContentUnavailableView("simq not set up", systemImage: "iphone.slash",
                                   description: Text("Run `simq init` in a terminal."))
        }
    }
}

/// "12m ago" style age, or nil without a date.
private func age(_ date: Date?, now: Date) -> String? {
    date.map { Simq.minutes(max(0, Int(now.timeIntervalSince($0)) / 60)) }
}

/// Output of the last CLI run on a row, in secondary text. Shown verbatim (it can echo request text).
struct SimqRowMessage: View {
    let text: String?

    var body: some View {
        if let text {
            Text(verbatim: text)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Waiting for you

struct SimqRequestsSection: View {
    @EnvironmentObject var model: SimqModel
    let simq: Simq
    let now: Date

    var body: some View {
        DeviceSection(title: "Waiting for you", systemImage: "hand.raised",
                      total: 0, empty: simq.requests.isEmpty, loading: false) {
            EmptyView()
        } content: {
            ForEach(simq.requests, id: \.id) { r in row(r) }
        }
    }

    // Request fields come from Claude sessions: plain verbatim text only, never a shell argument.
    private func row(_ r: Simq.Request) -> some View {
        let key = "req-\(r.id)"
        let message = model.rowMessage[key]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "#\(r.id) \(r.type) · \(r.projectName)").font(.body.weight(.medium))
                if let a = age(r.created, now: now) {
                    Text(verbatim: "\(a) ago").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Approve") { run(key, ["approve", "\(r.id)"]) }
                if r.type == "download" {
                    Button("Approve + pin") { run(key, ["approve", "\(r.id)", "--pin"]) }
                }
                if let message, SimqCLI.needsForce(message) {
                    Button("Force") { run(key, ["approve", "\(r.id)", "--force"]) }
                }
                Button("Deny", role: .destructive) { run(key, ["deny", "\(r.id)"]) }
            }
            .disabled(model.running)
            Text(verbatim: r.command).font(.callout.monospaced()).textSelection(.enabled)
            if let d = r.detail, !d.isEmpty { Text(verbatim: d).font(.callout) }
            if let reason = r.reason, !reason.isEmpty {
                Text(verbatim: "Reason: \(reason)").font(.callout).foregroundStyle(.secondary)
            }
            if let cwd = r.cwd, !cwd.isEmpty {
                Text(verbatim: cwd).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            SimqRowMessage(text: message)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private func run(_ key: String, _ args: [String]) {
        Task { await model.act(key, args) }
    }
}

// MARK: Pool

struct SimqPoolSection: View {
    @EnvironmentObject var model: SimqModel
    let simq: Simq
    let now: Date
    @State private var confirm: Simq.Lease?

    private var devices: [(name: String, kind: String)] {
        simq.iosPool.keys.sorted().map { ($0, "ios") } + simq.androidPool.map { ($0, "android") }
    }

    var body: some View {
        DeviceSection(title: "Pool", systemImage: "iphone.and.arrow.forward",
                      total: 0, empty: devices.isEmpty, loading: false) {
            EmptyView()
        } content: {
            ForEach(devices, id: \.name) { d in row(d.name, kind: d.kind) }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { l in
            Button("Release", role: .destructive) { release(l.device) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var confirmTitle: Text {
        guard let l = confirm else { return Text(verbatim: "") }
        let last = age(l.lastActivity, now: now).map { "last activity \($0) ago" } ?? "no recorded activity"
        return Text(verbatim: "\(l.device) is in use by \(l.projectName) (\(last)). Release anyway?")
    }

    private func row(_ device: String, kind: String) -> some View {
        let key = "dev-\(device)"
        let lease = simq.leases.first { $0.device == device }
        let state = simq.state(of: device, now: now)
        let idle = lease.map { simq.isIdle($0, now: now) } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: kind == "ios" ? "iphone" : "candybarphone").foregroundStyle(.secondary)
                Text(verbatim: device).font(.body.weight(.medium))
                Text(verbatim: description(state, lease: lease)).foregroundStyle(.secondary)
                Spacer()
                if let lease {
                    Button(lease.sessionID == "human" ? "Release mine" : "Release") {
                        if lease.sessionID == "human" || idle { release(device) } else { confirm = lease }
                    }
                }
                if state == .free || idle {
                    Button("Take") { Task { await model.act(key, ["acquire", kind, "--device", device]) } }
                }
            }
            .disabled(model.running)
            if idle {
                Text("idle, will be handed over on request").font(.callout).foregroundStyle(.orange)
            }
            SimqRowMessage(text: model.rowMessage[key])
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
    }

    /// "held by tren (s-1…) · held for 2h · idle 10m"
    private func description(_ state: Simq.DeviceState, lease: Simq.Lease?) -> String {
        guard let lease else { return state.text }
        let holder = lease.sessionID == "human" ? "you" : "\(lease.projectName) (\(lease.sessionID.prefix(4))…)"
        var parts = ["held by \(holder)"]
        if let a = age(lease.since, now: now) { parts.append("held for \(a)") }
        if let a = age(lease.lastActivity, now: now) { parts.append("idle \(a)") }
        return parts.joined(separator: " · ")
    }

    private func release(_ device: String) {
        Task { await model.act("dev-\(device)", ["release", device]) }
    }
}

// MARK: Queues

struct SimqQueuesSection: View {
    let simq: Simq
    let now: Date

    private var kinds: [String] { simq.queues.keys.filter { !(simq.queues[$0] ?? []).isEmpty }.sorted() }

    var body: some View {
        DeviceSection(title: "Queues", systemImage: "list.number",
                      total: 0, empty: kinds.isEmpty, loading: false) {
            EmptyView()
        } content: {
            ForEach(kinds, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: kind).font(.callout.weight(.medium))
                    ForEach(Array((simq.queues[kind] ?? []).enumerated()), id: \.offset) { i, w in
                        let name = w.project.map { ($0 as NSString).lastPathComponent } ?? "unknown project"
                        let wait = age(w.since, now: now).map { " · waiting \($0)" } ?? ""
                        Text(verbatim: "\(i + 1). \(name)\(wait)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 8)
            }
        }
    }
}

// MARK: Health

struct SimqHealthSection: View {
    @EnvironmentObject var model: SimqModel

    var body: some View {
        DeviceSection(title: "Health", systemImage: "stethoscope", total: 0, empty: false, loading: false) {
            Button("Run doctor") { Task { await model.act("doctor", ["doctor"]) } }
                .disabled(model.running)
        } content: {
            if let out = model.rowMessage["doctor"] {
                ScrollView {
                    Text(verbatim: out)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 260)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Run `simq doctor` to check the pool.").foregroundStyle(.tertiary).padding(8)
            }
        }
    }
}
