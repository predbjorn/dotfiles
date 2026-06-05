import SwiftUI

final class ServicesViewModel: ObservableObject {
    @Published var services: [ServiceStatus] = []
    @Published var priority: Set<String> = []     // priority labels (shown on top)
    @Published var crashed: Set<String> = []      // currently-crashed labels → red
    @Published var lastError: String?             // surfaced action failures
}

struct ServicesView: View {
    @ObservedObject var vm: ServicesViewModel
    let onStart: (String) -> Void
    let onStop: (String) -> Void
    let onRestart: (String) -> Void
    let onLoad: (String) -> Void
    @State private var showMore = false

    // When a priority set is configured, split it out; otherwise everything is "priority".
    private var priorityServices: [ServiceStatus] {
        vm.priority.isEmpty ? vm.services : vm.services.filter { vm.priority.contains($0.label) }
    }
    private var otherServices: [ServiceStatus] {
        vm.priority.isEmpty ? [] : vm.services.filter { !vm.priority.contains($0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LaunchAgents (\(vm.services.count))")
                .font(.headline).padding(8)
            Divider()

            if let err = vm.lastError {
                Text(err)
                    .font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
            }

            ScrollView {
                ForEach(priorityServices) { row($0) }

                if !otherServices.isEmpty {
                    DisclosureGroup(isExpanded: $showMore) {
                        ForEach(otherServices) { row($0) }
                    } label: {
                        Text(showMore ? "Show less" : "Show more (\(otherServices.count))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
            }

            Divider()
            legend
        }
        .frame(width: 420, height: 480)
    }

    @ViewBuilder
    private func row(_ s: ServiceStatus) -> some View {
        HStack {
            Circle().fill(color(for: s)).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(s.label).font(.system(.body, design: .monospaced))
                Text(detail(for: s)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("⋯") {
                if s.state == .notLoaded { Button("Load") { onLoad(s.label) } }
                if s.state != .running { Button("Start") { onStart(s.label) } }
                if s.state == .running { Button("Stop") { onStop(s.label) } }
                Button("Restart") { onRestart(s.label) }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        Divider()
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "Running")
            legendDot(.red, "Crashed")
            legendDot(.yellow, "Stopped")
            legendDot(.gray, "Not loaded")
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(label) }
    }

    private func color(for s: ServiceStatus) -> Color {
        if vm.crashed.contains(s.label) { return .red }
        switch s.state {
        case .running: return .green
        case .loadedNotRunning: return .yellow
        case .notLoaded: return .gray
        case .unknown: return .orange
        }
    }

    private func humanState(_ s: ServiceStatus) -> String {
        if vm.crashed.contains(s.label) { return "Crashed" }
        switch s.state {
        case .running: return "Running"
        case .loadedNotRunning: return "Stopped"
        case .notLoaded: return "Not loaded"
        case .unknown: return "Unknown"
        }
    }

    private func detail(for s: ServiceStatus) -> String {
        var bits: [String] = [humanState(s)]
        if let pid = s.pid { bits.append("pid \(pid)") }
        if let code = s.lastExitCode { bits.append("last exit \(code)") }
        return bits.joined(separator: " · ")
    }
}
