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
        // The popover is repositioned the moment it appears, and an animation would animate to the
        // frame AppKit chose rather than the corrected one.
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content)
        NotificationCenter.default.addObserver(self, selector: #selector(popoverLostFocus),
                                               name: NSWindow.didResignKeyNotification, object: nil)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton, willShow: () -> Void) {
        if popover.isShown { close(); return }
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }
        willShow()
        show(relativeTo: button)
    }

    /// AppKit anchors the popover to the status item, which is inset inside the menu bar, so the
    /// popover ends up overlapping the bar and dimming the icons either side of ours. Measuring
    /// where the content actually landed and dropping the window by the overshoot is exact;
    /// guessing at the popover's own chrome, or at which way the button's y axis runs, is not.
    private func clearMenuBar() {
        guard let view = popover.contentViewController?.view,
              let window = view.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let contentTop = window.convertToScreen(view.convert(view.bounds, to: nil)).maxY
        let overshoot = contentTop - screen.visibleFrame.maxY
        guard overshoot > 0 else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY - overshoot))
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) { closedAt = Date() }

    /// A transient popover closes when the user clicks outside it, but not when the app opens a
    /// window of its own — Preferences would otherwise appear over a popover still holding the
    /// screen. Losing the keyboard is the signal that covers both cases.
    @objc private func popoverLostFocus(_ notification: Notification) {
        guard popover.isShown,
              notification.object as? NSWindow === popover.contentViewController?.view.window
        else { return }
        // Closing a window from inside its own notification is asking for trouble; the next turn
        // of the run loop is soon enough that nothing is drawn in between.
        DispatchQueue.main.async { [weak self] in self?.close() }
    }

    /// Unlike anything else this app puts on screen, the popover deliberately takes focus: the
    /// user types in it, and nothing is pasted back, so stealing focus costs nothing.
    private func show(relativeTo button: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        clearMenuBar()
        popover.contentViewController?.view.window?.makeKey()
    }
}
