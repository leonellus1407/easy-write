import AppKit
import SwiftUI

/// Owns the popover anchored to the menu-bar icon, so AppKit positions and clamps it.
@MainActor
final class TranslatorPanel: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    /// AppKit dismisses a transient popover on the very click that then reaches the status
    /// button, so a plain toggle would close and immediately reopen it. Refusing an open that
    /// lands right after a close is what makes a second click mean "close".
    private var closedAt = Date.distantPast

    init(content: TranslatorView) {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton, willShow: () -> Void) {
        if popover.isShown { close(); return }
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
        willShow()
        show(relativeTo: button)
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) { closedAt = Date() }

    /// Unlike anything else this app puts on screen, the popover deliberately takes focus: the
    /// user types in it, and nothing is pasted back, so stealing focus costs nothing.
    private func show(relativeTo button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
