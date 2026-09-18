import SwiftUI
import Carbon

@main struct JuliaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
extension Notification.Name {
    static let juliaPanelOpened = Notification.Name("juliaPanelOpened")
    static let juliaShowPanel = Notification.Name("juliaShowPanel")
}
final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CommandPanel?
    private var statusItem: NSStatusItem?
    private var state: AssistantState?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AssistantState(); self.state = state
        let panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 490),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Julia"; panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ContentView(assistant: state)); self.panel = panel
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Julia")
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Julia", action: #selector(showPanel), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]; open.target = self
        let log = menu.addItem(withTitle: "Show trace log", action: #selector(showLog), keyEquivalent: ""); log.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Julia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu; statusItem = item
        NotificationCenter.default.addObserver(self, selector: #selector(showPanel), name: .juliaShowPanel, object: nil)
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in NotificationCenter.default.post(name: .juliaShowPanel, object: nil) }
            return noErr
        }, 1, &type, nil, &hotKeyHandler)
        let id = EventHotKeyID(signature: 0x4a554c49, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        showPanel()
    }
    @objc func showPanel() {
        guard let panel else { return }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 370, y: f.midY - 180))
        }
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .juliaPanelOpened, object: nil)
    }
    @objc func showLog() { state?.revealLog() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}
