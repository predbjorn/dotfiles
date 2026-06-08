import SwiftUI

final class TunnelRoutesViewModel: ObservableObject {
    @Published var rules: [IngressRule] = []
    @Published var status: String = ""
    private let controller: CloudflaredController
    private let queue = DispatchQueue(label: "com.prebenhafnor.launch-dashboard.cloudflared")

    init(controller: CloudflaredController) { self.controller = controller }

    func reload() {
        queue.async {
            do {
                let r = try self.controller.rules()
                DispatchQueue.main.async { self.rules = r; self.status = "Loaded \(r.count) route(s)" }
            } catch {
                DispatchQueue.main.async { self.status = "Error: \(error.localizedDescription)" }
            }
        }
    }

    func setEnabled(_ rule: IngressRule, _ enabled: Bool) {
        guard let host = rule.hostname else { return }
        queue.async {
            do {
                try self.controller.setEnabled(hostname: host, enabled: enabled)
                let r = try self.controller.rules()
                DispatchQueue.main.async {
                    self.rules = r
                    self.status = "\(enabled ? "Enabled" : "Disabled") \(host) · tunnel reloaded"
                }
            } catch {
                DispatchQueue.main.async { self.status = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

struct TunnelRoutesView: View {
    @ObservedObject var vm: TunnelRoutesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cloudflared Tunnel Routes").font(.headline).padding(8)
            Divider()
            ScrollView {
                ForEach(vm.rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.hostname ?? "(catch-all)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(rule.enabled ? .primary : .secondary)
                            Text(rule.service).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if rule.isCatchAll {
                            Text("always on").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { vm.setEnabled(rule, $0) }
                            )).labelsHidden()
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    Divider()
                }
            }
            Divider()
            HStack {
                Button("Reload") { vm.reload() }
                Spacer()
                Text(vm.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
        }
        .frame(width: 460, height: 420)
    }
}
