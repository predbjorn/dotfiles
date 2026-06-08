import AppKit
import SwiftUI

/// Owns a single Tunnel Routes window; re-shows the same window if already open.
final class TunnelRoutesWindowController {
    private var window: NSWindow?
    private let controller: CloudflaredController

    init(controller: CloudflaredController) { self.controller = controller }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let vm = TunnelRoutesViewModel(controller: controller)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = "Tunnel Routes"
        w.contentViewController = NSHostingController(rootView: TunnelRoutesView(vm: vm))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        vm.reload()
    }
}
