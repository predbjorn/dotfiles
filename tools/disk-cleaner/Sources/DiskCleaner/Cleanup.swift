import SwiftUI

/// Drives bin/disk-cleanup.sh --progress and turns its "::" events into steps.
@MainActor
final class CleanupRunner: ObservableObject {
    struct Step: Identifiable {
        enum Status { case running, done, skipped }
        let id: Int
        let label: String
        var status: Status = .running
        var mb: Int?
        var note: String?
        var started = Date()
        var finished: Date?
    }

    @Published var deep = false
    @Published var dryRun = false
    @Published private(set) var steps: [Step] = []
    @Published private(set) var total = 0
    @Published private(set) var isRunning = false
    @Published private(set) var log: [String] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var freeBefore: Int64?
    @Published private(set) var freeAfter: Int64?
    @Published private(set) var error: String?
    @Published private(set) var wasDryRun = false

    private var process: Process?
    var onFinished: (() -> Void)?

    var completed: Int { steps.filter { $0.status != .running }.count }
    var progress: Double {
        guard total > 0 else { return isRunning ? 0 : (steps.isEmpty ? 0 : 1) }
        let running = steps.contains { $0.status == .running } ? 0.5 : 0
        return min(1, (Double(completed) + running) / Double(total))
    }
    var foundMB: Int { steps.compactMap(\.mb).reduce(0, +) }
    var freed: Int64? {
        guard let b = freeBefore, let a = freeAfter else { return nil }
        return a - b
    }

    func start() {
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: Paths.engine) else {
            error = "Cleanup script not found at \(Paths.tilde(Paths.engine))"
            return
        }
        if !acquireLock() {
            error = "A cleanup is already running (started from the bar). Try again when it finishes."
            return
        }
        steps = []; log = []; total = 0; error = nil
        finishedAt = nil; freeAfter = nil
        wasDryRun = dryRun
        freeBefore = Volume.info()?.free
        startedAt = Date()
        isRunning = true
        if !dryRun { Shell.spawn(Paths.barPlugin, ["busy"]) }

        var args = ["--progress"]
        if dryRun { args.append("--dry-run") }
        if deep { args.append("--deep") }

        let p = Shell.makeProcess(Paths.engine, args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p

        Task.detached { [weak self] in
            do { try p.run() } catch {
                await self?.finish(status: -1, launchError: error.localizedDescription)
                return
            }
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    await self?.handle(line)
                }
            } catch {}
            p.waitUntilExit()
            await self?.finish(status: p.terminationStatus, launchError: nil)
        }
    }

    func stop() {
        process?.terminate()
    }

    private func handle(_ line: String) {
        guard line.hasPrefix("::") else {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { log.append(line) }
            return
        }
        let body = line.dropFirst(2)
        let parts = body.split(separator: " ", maxSplits: 1)
        let kind = parts.first.map(String.init) ?? ""
        let value = parts.count > 1 ? String(parts[1]) : ""
        switch kind {
        case "total":
            total = Int(value) ?? 0
        case "step":
            closeCurrent()
            steps.append(Step(id: steps.count, label: value))
        case "result":
            if let i = steps.indices.last { steps[i].mb = Int(value) }
        case "note":
            if let i = steps.indices.last {
                steps[i].note = value
                if value.hasPrefix("skipped") { steps[i].status = .skipped; steps[i].finished = Date() }
            }
        default:
            log.append(line)
        }
    }

    private func closeCurrent() {
        if let i = steps.indices.last, steps[i].status == .running {
            steps[i].status = .done
            steps[i].finished = Date()
        }
    }

    private func finish(status: Int32, launchError: String?) {
        closeCurrent()
        isRunning = false
        finishedAt = Date()
        freeAfter = Volume.info()?.free
        process = nil
        releaseLock()
        if let launchError {
            error = launchError
        } else if status != 0 {
            error = status == 15 ? "Stopped." : "Cleanup exited with status \(status). See the log below."
        }
        if !wasDryRun {
            if error == nil {
                let gb = max(0, Int((freed ?? 0) / 1_000_000_000))
                Shell.spawn(Paths.barPlugin, ["finish", "\(gb)"])
            } else {
                Shell.spawn(Paths.barPlugin, ["fail"])
            }
        }
        onFinished?()
    }

    // MARK: lock shared with the sketchybar plugin

    private func acquireLock() -> Bool {
        let fm = FileManager.default
        // A lock older than two hours is a leftover from a crashed run.
        if let attrs = try? fm.attributesOfItem(atPath: Paths.lock),
           let created = attrs[.creationDate] as? Date, Date().timeIntervalSince(created) > 7200 {
            try? fm.removeItem(atPath: Paths.lock)
        }
        return (try? fm.createDirectory(atPath: Paths.lock, withIntermediateDirectories: false)) != nil
    }

    private func releaseLock() { try? FileManager.default.removeItem(atPath: Paths.lock) }
}

// MARK: - View

struct CleanupView: View {
    @EnvironmentObject var runner: CleanupRunner
    @EnvironmentObject var overview: OverviewModel
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error = runner.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if runner.startedAt != nil { progressCard }
                if !runner.steps.isEmpty || runner.total > 0 { stepList }
                if !runner.log.isEmpty {
                    DisclosureGroup("Script output (\(runner.log.count) lines)", isExpanded: $showLog) {
                        Text(runner.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if runner.startedAt == nil { explainer }
            }
            .padding(20)
        }
        .navigationTitle("Cleanup")
    }

    private var header: some View {
        HStack(spacing: 16) {
            if runner.isRunning {
                Button(role: .destructive) { runner.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(minWidth: 120)
                }
                .controlSize(.large)
            } else {
                Button { runner.start() } label: {
                    Label(runner.dryRun ? "Preview Cleanup" : "Run Cleanup", systemImage: "sparkles")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Toggle("Dry run", isOn: $runner.dryRun)
                .help("Report what each target holds without deleting anything")
            Toggle("Deep", isOn: $runner.deep)
                .help("Also clear slow-to-refetch caches: HuggingFace, torch, Codex runtimes, Yarn")
            Spacer()
        }
        .disabled(false)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusTitle).font(.title2.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsed).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ProgressView(value: runner.progress)
                .progressViewStyle(.linear)
                .animation(.easeInOut, value: runner.progress)
            HStack {
                Text(runner.total > 0 ? "Step \(min(runner.completed + (runner.isRunning ? 1 : 0), runner.total)) of \(runner.total)" : "Starting…")
                Spacer()
                if runner.wasDryRun {
                    Text("Found \(formatMB(runner.foundMB)) reclaimable")
                } else if runner.isRunning {
                    Text("Removing \(formatMB(runner.foundMB)) so far")
                } else if let freed = runner.freed {
                    Text("Freed \(formatBytes(max(0, freed)))").fontWeight(.semibold).foregroundStyle(.green)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let before = runner.freeBefore {
                HStack(spacing: 6) {
                    Text("Free space: \(formatBytes(before))")
                    if let after = runner.freeAfter, !runner.wasDryRun {
                        Image(systemName: "arrow.right")
                        Text(formatBytes(after)).fontWeight(.medium)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusTitle: String {
        if runner.isRunning { return runner.steps.last?.label ?? "Starting…" }
        if runner.error != nil { return "Stopped" }
        return runner.wasDryRun ? "Preview complete" : "Cleanup complete"
    }

    private var elapsed: String {
        guard let start = runner.startedAt else { return "" }
        let end = runner.finishedAt ?? Date()
        let s = Int(end.timeIntervalSince(start))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(runner.steps) { step in
                StepRow(step: step, dryRun: runner.wasDryRun)
            }
            if runner.isRunning {
                ForEach(0..<max(0, runner.total - runner.steps.count), id: \.self) { _ in
                    HStack(spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(.tertiary).frame(width: 18)
                        Text("Waiting").foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                }
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the cleanup does").font(.headline)
            Text("Runs \(Paths.tilde(Paths.engine)). Everything it removes is rebuilt or re-downloaded on demand, and it never touches repo state, simulators, the Trash, or anything you authored. Symlinked caches (moved to another drive) are skipped.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(["Xcode DerivedData", "Gradle caches", "Xcode DeviceSupport", "CoreSimulator logs",
                         "npm cache", "App updater leftovers + CocoaPods cache",
                         "Project build output in ~/Hacking (Gradle, iOS, .next, __pycache__…)",
                         "Docker build cache (if Docker is running)", "pnpm store prune", "Stale git worktree entries"],
                        id: \.self) { item in
                    GridRow {
                        Image(systemName: "checkmark.circle").foregroundStyle(.green)
                        Text(item)
                    }
                }
                ForEach(["HuggingFace models, torch cache, Codex runtimes, Yarn cache"], id: \.self) { item in
                    GridRow {
                        Image(systemName: "plus.circle").foregroundStyle(.orange)
                        Text("\(item) — only with Deep")
                    }
                }
            }
            .font(.callout)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StepRow: View {
    let step: CleanupRunner.Step
    let dryRun: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch step.status {
                case .running: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.label).fontWeight(step.status == .running ? .semibold : .regular)
                if let note = step.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let mb = step.mb {
                Text(mb > 0 ? (dryRun ? formatMB(mb) : "−\(formatMB(mb))") : "empty")
                    .monospacedDigit()
                    .foregroundStyle(mb > 0 ? .primary : .tertiary)
            }
            if let end = step.finished {
                Text(String(format: "%.1fs", end.timeIntervalSince(step.started)))
                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Spacer().frame(width: 44)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(step.status == .running ? Color.accentColor.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}
