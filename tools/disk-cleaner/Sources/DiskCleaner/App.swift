import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, devices
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Disk Overview"
        case .cleanup: "Cleanup"
        case .devices: "Devices & Caches"
        }
    }
    var icon: String {
        switch self {
        case .overview: "internaldrive"
        case .cleanup: "sparkles"
        case .devices: "iphone.gen3"
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

    var body: some Scene {
        Window("Disk Cleaner", id: "main") {
            ContentView()
                .environmentObject(overview)
                .environmentObject(runner)
                .environmentObject(devices)
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
    // `open -a DiskCleaner --args -pane devices` opens straight to a pane.
    @State private var pane: Pane = UserDefaults.standard.string(forKey: "pane").flatMap(Pane.init) ?? .overview

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.icon)
                    .badge(p == .cleanup && runner.isRunning ? Text("\(Int(runner.progress * 100))%") : nil)
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
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            overview.refreshVolume()
        }
    }
}
