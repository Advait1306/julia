import AppKit
import ApplicationServices
import Combine
import Carbon.HIToolbox

@MainActor
final class HotkeyManager: ObservableObject {
    @Published private(set) var globalAccess = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var watchdog: Timer?
    private var rightCommandDown = false
    private var active = false

    func start() {
        guard localMonitor == nil else { return }
        refreshAccess()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
        installGlobalMonitor()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAccess() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.globalAccess else { return }
                self.cancelHeldKey()
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancelHeldKey() }
            })
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.globalAccess, self.rightCommandDown,
                      !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightCommand)) else { return }
                // A lost release is cancellation, never an implicit command.
                self.cancelHeldKey()
            }
        }
    }

    func requestGlobalAccess() {
        _ = CGRequestListenEventAccess()
        refreshAccess()
    }

    func refreshAccess() {
        let access = CGPreflightListenEventAccess() || AXIsProcessTrusted()
        let changed = globalAccess != access
        globalAccess = access
        if changed, localMonitor != nil { installGlobalMonitor() }
    }

    private func installGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        cancelHeldKey()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        watchdog?.invalidate()
        watchdog = nil
    }

    private func handle(_ event: NSEvent) {
        handle(type: event.type, keyCode: event.keyCode,
               flags: event.cgEvent?.flags.rawValue ?? UInt64(event.modifierFlags.rawValue))
    }

    // Device-specific right-Command bit from IOKit's NX_DEVICERCMDKEYMASK.
    // The aggregate .command flag stays set when left Command remains held.
    func handle(type: NSEvent.EventType, keyCode: UInt16, flags: UInt64) {
        let rightDown = flags & 0x10 != 0
        if type == .flagsChanged {
            if rightCommandDown, !rightDown {
                rightCommandDown = false
                let shouldRelease = active
                active = false
                if shouldRelease { onRelease?() }
            } else if keyCode == kVK_RightCommand, rightDown, !rightCommandDown {
                rightCommandDown = true
                let otherModifiers = NSEvent.ModifierFlags(rawValue: UInt(flags))
                    .intersection([.shift, .control, .option])
                guard otherModifiers.isEmpty else { return }
                active = true
                onPress?()
            }
        } else if type == .keyDown, active {
            // Escape or a normal Command shortcut cancels until the held key is released.
            active = false
            onCancel?()
        }
    }

    private func cancelHeldKey() {
        let wasActive = active
        active = false
        rightCommandDown = false
        if wasActive { onCancel?() }
    }

    isolated deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        watchdog?.invalidate()
    }
}
