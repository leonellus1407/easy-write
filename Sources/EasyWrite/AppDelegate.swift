import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let llm = LLMTranslator()
    private lazy var model = TranslatorModel(llm: llm)
    private lazy var panel = TranslatorPanel(content: TranslatorView(
        model: model,
        version: Self.appVersion,
        launchesAtLogin: Binding(get: { SMAppService.mainApp.status == .enabled },
                                 set: { [weak self] _ in self?.toggleLaunchAtLogin() }),
        onPreferences: { PreferencesController.shared.show() },
        onQuit: { NSApp.terminate(nil) }))

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.onChange = { [weak self] in self?.registerHotKeys() }
        model.onBusyChange = { [weak self] busy in self?.setIcon(busy: busy) }
        MainMenu.install()
        setupStatusItem()
        registerHotKeys()
        enableLoginItemOnFirstRun()
        model.prewarm()
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    // MARK: Status item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(busy: false)
        // Assigning a menu would swallow the click that has to reach the button's action.
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusButtonClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setIcon(busy: Bool) {
        let symbol = busy ? "ellipsis.bubble" : "character.bubble"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Easy Write")
    }

    // MARK: Hot-keys (read from Store; re-registered when the binding changes)
    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        let sc = Store.shared.shortcut(for: "translate")
        HotKeyCenter.shared.register(keyCode: sc.keyCode, modifiers: sc.modifiers) { [weak self] in
            self?.togglePopup()
        }
    }

    // MARK: Actions
    /// A right-click — or a control-click, which macOS reports the same way — opens the settings
    /// menu, so the menu-bar icon offers everything the popover's gear button does.
    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showSettingsMenu()
        } else {
            togglePopup()
        }
    }

    @objc private func togglePopup() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button) { [weak self] in self?.model.open() }
    }

    private func showSettingsMenu() {
        panel.close()
        let menu = NSMenu()
        let header = NSMenuItem(title: "Easy Write \(Self.appVersion)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Preferences…", #selector(menuPreferences)))
        let login = item("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Easy Write", #selector(menuQuit)))
        // Handing the menu to the status item and clicking it is what buys AppKit's own
        // positioning and the highlighted icon; it is cleared again so the next left-click
        // still reaches the button's action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    @objc private func menuPreferences() { PreferencesController.shared.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            notify("Couldn’t change Launch at Login:\n\(error.localizedDescription)")
        }
    }

    // MARK: Launch at login
    private func enableLoginItemOnFirstRun() {
        let key = "didInitLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: Helpers
    private func notify(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Easy Write"
        alert.informativeText = message
        alert.runModal()
    }
}
