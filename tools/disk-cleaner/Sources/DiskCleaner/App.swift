import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, devices, map, simq
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Disk Overview"
        case .cleanup: "Cleanup"
        case .devices: "Devices & Caches"
        case .map: "Disk Map"
        case .simq: "simq"
        }
    }
    var icon: String {
        switch self {
        case .overview: "internaldrive"
        case .cleanup: "sparkles"
        case .devices: "iphone.gen3"
        case .map: "chart.pie"
        case .simq: "iphone.and.arrow.forward"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DiskCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var overview = OverviewModel()
    @StateObject private var runner = CleanupRunner()
    @StateObject private var devices = DevicesModel()
    @StateObject private var diskMap = DiskMapModel()
    @StateObject private var simq = SimqModel()

    var body: some Scene {
        Window("Disk Cleaner", id: "main") {
            ContentView()
                .environmentObject(overview)
                .environmentObject(runner)
                .environmentObject(devices)
                .environmentObject(diskMap)
                .environmentObject(simq)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Sizes on the overview go stale after a sweep or a delete.
                    runner.onFinished = { [weak overview] in overview?.scan() }
                    devices.onDeleted = { [weak overview] in overview?.refreshVolume() }
                }
        }
        .defaultSize(width: 1000, height: 720)
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @EnvironmentObject var overview: OverviewModel
    @EnvironmentObject var runner: CleanupRunner
    @EnvironmentObject var simq: SimqModel
    // `open -a DiskCleaner --args -pane devices` opens straight to a pane on launch;
    // `open diskcleaner://map` switches pane even when the app is already running. URLs only ever
    // switch panes: they never run a simq action (approval stays a human click).
    @State private var pane: Pane = UserDefaults.standard.string(forKey: "pane").flatMap(Pane.init) ?? .overview

    private func badge(_ p: Pane) -> Text? {
        switch p {
        case .cleanup where runner.isRunning: Text("\(Int(runner.progress * 100))%")
        case .simq:
            if let n = simq.simq?.pendingRequests, n > 0 { Text("\(n)") } else { nil }
        default: nil
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.icon)
                    .badge(badge(p))
                    .tag(p)
            }
            .safeAreaInset(edge: .bottom) {
                VolumeBar(info: overview.volume, compact: true).padding()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch pane {
            case .overview: OverviewView(pane: $pane)
            case .cleanup: CleanupView()
            case .devices: DevicesView()
            case .map: DiskMapView()
            case .simq: SimqView()
            }
        }
        .onOpenURL { url in
            if let p = url.host().flatMap(Pane.init) { pane = p }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            overview.refreshVolume()
        }
    }
}
