import AppKit
import SwiftUI
import Keymapper

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var vm: KeymapperViewModel!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        vm = KeymapperViewModel()
        let content = ContentView(vm: vm)
        let hosting = NSHostingController(rootView: content)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keymapper"
        window.contentViewController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Load on launch — errors are surfaced in the UI.
        vm.loadReportingError()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
