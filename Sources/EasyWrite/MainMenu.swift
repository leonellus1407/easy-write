import AppKit

/// An accessory app shows no menu bar, but `NSApp.mainMenu` is still what turns ⌘C, ⌘V, ⌘A and the
/// rest into working key equivalents. Without it the popover's text pane cannot be edited from the
/// keyboard at all. Every item targets the first responder, so the text view handles them itself.
@MainActor
enum MainMenu {

    static func install() {
        let main = NSMenu()
        main.addItem(submenu("Easy Write", items: [
            (title: "Quit Easy Write", action: #selector(NSApplication.terminate(_:)), key: "q",
             modifiers: NSEvent.ModifierFlags.command),
        ]))
        main.addItem(submenu("Edit", items: [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]))
        NSApp.mainMenu = main
    }

    private static func submenu(
        _ title: String,
        items: [(title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags)]
    ) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for item in items {
            let entry = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.key)
            entry.keyEquivalentModifierMask = item.modifiers
            submenu.addItem(entry)
        }
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }
}
