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
        launchesAtLogin: Binding(get: { SMAppService.mainApp.status == .enabled },
                                 set: { [weak self] _ in self?.toggleLaunchAtLogin() }),
        onPreferences: { PreferencesController.shared.show() },
        onQuit: { NSApp.terminate(nil) }))

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.onChange = { [weak self] in self?.registerHotKeys() }
        model.onBusyChange = { [weak self] busy in self?.setIcon(busy: busy) }
        setupStatusItem()
        registerHotKeys()
        enableLoginItemOnFirstRun()
        model.prewarm()
    }

    // MARK: Status item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(busy: false)
        // Assigning a menu would swallow the click that has to reach the button's action.
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopup)
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
    @objc private func togglePopup() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button) { [weak self] in self?.model.open() }
    }

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
