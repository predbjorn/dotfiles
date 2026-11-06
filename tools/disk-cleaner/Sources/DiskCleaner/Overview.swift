import AppKit
import SwiftUI

/// Who reclaims a location, shown as a badge next to it.
enum Coverage {
    case script      // removed by every cleanup run
    case deep        // removed only with --deep
    case devices     // manage from the Simulators & Emulators pane
    case manual      // yours to sort out
}

struct Location: Identifiable {
    let group: String
    let label: String
    let path: String
    let coverage: Coverage
    var id: String { path }
}

enum SizeState: Equatable {
    case pending
    case size(Int64)
    case missing
    case relocated(String) // symlink to another volume (e.g. the T9)

    var bytes: Int64 { if case .size(let b) = self { return b } else { return 0 } }
}

/// The usual suspects when the internal disk fills up.
let knownLocations: [Location] = {
    let h = Paths.home
    let sdk = Paths.androidSDK
    return [
        Location(group: "Xcode & iOS", label: "Xcode DerivedData", path: "\(h)/Library/Developer/Xcode/DerivedData", coverage: .script),
        Location(group: "Xcode & iOS", label: "iOS DeviceSupport", path: "\(h)/Library/Developer/Xcode/iOS DeviceSupport", coverage: .script),
        Location(group: "Xcode & iOS", label: "Xcode Archives", path: "\(h)/Library/Developer/Xcode/Archives", coverage: .manual),
        Location(group: "Xcode & iOS", label: "Simulator devices", path: "\(h)/Library/Developer/CoreSimulator/Devices", coverage: .devices),
        Location(group: "Xcode & iOS", label: "CoreSimulator caches", path: "\(h)/Library/Developer/CoreSimulator/Caches", coverage: .manual),
        Location(group: "Xcode & iOS", label: "CoreSimulator logs", path: "\(h)/Library/Logs/CoreSimulator", coverage: .script),
        Location(group: "Xcode & iOS", label: "CocoaPods cache", path: "\(h)/Library/Caches/CocoaPods", coverage: .script),

        Location(group: "Android", label: "Emulators (AVDs)", path: Paths.avdDir, coverage: .devices),
        Location(group: "Android", label: "SDK system images", path: "\(sdk)/system-images", coverage: .devices),
        Location(group: "Android", label: "Gradle caches", path: "\(h)/.gradle/caches", coverage: .script),
        Location(group: "Android", label: "Gradle wrapper dists", path: "\(h)/.gradle/wrapper/dists", coverage: .manual),

        Location(group: "JavaScript", label: "npm cache", path: "\(h)/.npm/_cacache", coverage: .script),
        Location(group: "JavaScript", label: "pnpm store", path: "\(h)/Library/pnpm/store", coverage: .script),
        Location(group: "JavaScript", label: "Yarn cache", path: "\(h)/Library/Caches/Yarn", coverage: .deep),
        Location(group: "JavaScript", label: "Bun cache", path: "\(h)/.bun/install/cache", coverage: .manual),

        Location(group: "ML & Python", label: "HuggingFace models", path: "\(h)/.cache/huggingface", coverage: .deep),
        Location(group: "ML & Python", label: "torch cache", path: "\(h)/.cache/torch", coverage: .deep),
        Location(group: "ML & Python", label: "Codex runtimes", path: "\(h)/.cache/codex-runtimes", coverage: .deep),
        Location(group: "ML & Python", label: "pip cache", path: "\(h)/Library/Caches/pip", coverage: .manual),

        Location(group: "System & other", label: "Docker data", path: "\(h)/Library/Containers/com.docker.docker/Data", coverage: .manual),
        Location(group: "System & other", label: "Homebrew downloads", path: "\(h)/Library/Caches/Homebrew", coverage: .manual),
        Location(group: "System & other", label: "All app caches", path: "\(h)/Library/Caches", coverage: .manual),
        Location(group: "System & other", label: "Downloads", path: "\(h)/Downloads", coverage: .manual),
        Location(group: "System & other", label: "Trash", path: "\(h)/.Trash", coverage: .manual),
        Location(group: "System & other", label: "Hacking (repos)", path: ProcessInfo.processInfo.environment["HACKING"] ?? "\(h)/Hacking", coverage: .manual),
    ]
}()

@MainActor
final class OverviewModel: ObservableObject {
    @Published var sizes: [String: SizeState] = [:]
    @Published var volume: Volume.Info? = Volume.info()
    @Published var isScanning = false
    @Published var lastScan: Date?

    func refreshVolume() { volume = Volume.info() }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        refreshVolume()
        for loc in knownLocations { sizes[loc.path] = .pending }
        Task {
            // A few du's in parallel; the big trees (Hacking, Caches) dominate anyway.
            await withTaskGroup(of: (String, SizeState).self) { group in
                var queue = knownLocations[...]
                func next() {
                    guard let loc = queue.popFirst() else { return }
                    group.addTask { (loc.path, await Self.measure(loc.path)) }
                }
                for _ in 0..<4 { next() }
                for await (path, state) in group {
                    sizes[path] = state
                    next()
                }
            }
            isScanning = false
            lastScan = Date()
            refreshVolume()
        }
    }

    nonisolated static func measure(_ path: String) async -> SizeState {
        let fm = FileManager.default
        if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
            return .relocated(dest)
        }
        guard fm.fileExists(atPath: path) else { return .missing }
        return .size(await Shell.du(path) ?? 0)
    }
}

// MARK: - Views

struct VolumeBar: View {
    let info: Volume.Info?
    var compact = false

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 6) {
                if !compact {
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatBytes(info.free)).font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("free of \(formatBytes(info.total))").foregroundStyle(.secondary)
                        Spacer()
                        if info.available - info.free > 500_000_000 {
                            Text("+\(formatBytes(info.available - info.free)) purgeable")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                GeometryReader { geo in
                    let usedFrac = Double(info.used) / Double(max(info.total, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(barColor(usedFrac).gradient)
                            .frame(width: geo.size.width * usedFrac)
                    }
                }
                .frame(height: compact ? 6 : 12)
                if compact {
                    Text("\(formatBytes(info.free)) free").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func barColor(_ used: Double) -> Color {
        used > 0.92 ? .red : used > 0.8 ? .orange : .accentColor
    }
}

struct CoverageBadge: View {
    let coverage: Coverage
    var body: some View {
        let (text, color): (String, Color) = switch coverage {
        case .script: ("cleanup", .green)
        case .deep: ("deep", .orange)
        case .devices: ("devices", .blue)
        case .manual: ("manual", .gray)
        }
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: OverviewModel
    @Binding var pane: Pane

    private var groups: [String] {
        var seen = Set<String>()
        return knownLocations.map(\.group).filter { seen.insert($0).inserted }
    }

    private var maxBytes: Int64 {
        knownLocations.filter { $0.label != "All app caches" && !$0.label.hasPrefix("Hacking") }
            .map { model.sizes[$0.path]?.bytes ?? 0 }.max() ?? 1
    }

    private var reclaimableByScript: Int64 {
        knownLocations.filter { $0.coverage == .script }.map { model.sizes[$0.path]?.bytes ?? 0 }.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VolumeBar(info: model.volume)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Label("Cleanup can reclaim about \(formatBytes(reclaimableByScript)) from the green rows, plus project build output.",
                          systemImage: "sparkles")
                        .font(.callout)
                    Spacer()
                    Button("Open Cleanup") { pane = .cleanup }
                }

                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group).font(.headline).padding(.bottom, 4)
                        ForEach(knownLocations.filter { $0.group == group }.sorted {
                            (model.sizes[$0.path]?.bytes ?? 0) > (model.sizes[$1.path]?.bytes ?? 0)
                        }) { loc in
                            LocationRow(loc: loc, state: model.sizes[loc.path] ?? .pending, maxBytes: maxBytes)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Disk Overview")
        .toolbar {
            ToolbarItem {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                }
            }
        }
        .onAppear { if model.lastScan == nil { model.scan() } }
    }
}

struct LocationRow: View {
    let loc: Location
    let state: SizeState
    let maxBytes: Int64
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(loc.label)
                    CoverageBadge(coverage: loc.coverage)
                }
                Text(Paths.tilde(loc.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 300, alignment: .leading)

            GeometryReader { geo in
                let frac = min(1, Double(state.bytes) / Double(max(maxBytes, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5))
                    Capsule().fill(color.gradient).frame(width: max(state.bytes > 0 ? 3 : 0, geo.size.width * frac))
                }
            }
            .frame(height: 8)

            Group {
                switch state {
                case .pending: ProgressView().controlSize(.mini)
                case .size(let b): Text(formatBytes(b)).monospacedDigit()
                case .missing: Text("—").foregroundStyle(.tertiary)
                case .relocated(let dest): Text("→ \(Paths.tilde(dest))").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            .frame(width: 130, alignment: .trailing)

            Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: loc.path) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .opacity(hovering && state != .missing ? 1 : 0)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }

    private var color: Color {
        switch loc.coverage {
        case .script: .green
        case .deep: .orange
        case .devices: .blue
        case .manual: .gray
        }
    }
}
