import AppKit
import SwiftUI
import Keymapper

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    let vm = KeymapperViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        Task { @MainActor in self.vm.loadReportingError() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
