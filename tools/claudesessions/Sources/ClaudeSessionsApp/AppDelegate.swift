import AppKit
import SwiftUI
import ClaudeSessions

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var vm: SessionsViewModel!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        vm = SessionsViewModel()
        let content = ContentView(vm: vm)
        let hosting = NSHostingController(rootView: content)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Sessions"
        window.contentViewController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        vm.reload()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
