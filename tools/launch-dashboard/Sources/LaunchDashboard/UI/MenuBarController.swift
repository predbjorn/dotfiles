import AppKit
import SwiftUI

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    let vm = ServicesViewModel()

    init(onStart: @escaping (String) -> Void,
         onStop: @escaping (String) -> Void,
         onRestart: @escaping (String) -> Void,
         onLoad: @escaping (String) -> Void,
         onOpenURL: @escaping (URL) -> Void,
         onOpenTunnelRoutes: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: ServicesView(vm: vm,
                                   onStart: onStart, onStop: onStop,
                                   onRestart: onRestart, onLoad: onLoad,
                                   onOpenURL: onOpenURL,
                                   onOpenTunnelRoutes: onOpenTunnelRoutes))
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent",
                                           accessibilityDescription: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func updateBadge(failedCount: Int) {
        statusItem.button?.title = failedCount > 0 ? " \(failedCount)" : ""
    }
}
