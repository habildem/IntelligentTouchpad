import SwiftUI
import AppKit

@main struct IntelligentTouchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var welcomeWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "IntelligentTouchpad")
        item.button?.toolTip = "IntelligentTouchpad — trackpad controls"
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        statusItem = item
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model, preferences: model.preferences))
        popover.behavior = .transient; popover.delegate = self
        model.start()
        #if DEBUG
        if CommandLine.arguments.contains("--preview-hud") {
            model.hud.show(symbol: "sun.max.fill", value: 0.64, duration: 30)
        }
        #endif
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show-panel") {
            showWelcome()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem?.button {
            model.panelVisible = true; model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func showWelcome() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "IntelligentTouchpad"
        window.contentView = NSHostingView(rootView: ContentView(model: model, preferences: model.preferences))
        window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }
    func popoverDidClose(_ notification: Notification) { model.panelVisible = welcomeWindow?.isVisible ?? false }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}
