import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var scrollMonitor: Any?
    private var scrollRemainder: CGFloat = 0
    private let hotKeys = HotKeys()
    private var rediscover: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "DisplayDial")
        statusItem.button?.toolTip = "DisplayDial: click for settings, scroll to change brightness"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        let content = NSHostingController(rootView: PopoverView(store: store))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient

        store.discover()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged),
                                                          name: NSWorkspace.didWakeNotification, object: nil)

        // Scrolling over the menu bar icon changes brightness.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window == self.statusItem.button?.window else { return event }
            self.scrolled(event)
            return nil
        }

        hotKeys.register(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.store.nudgeBrightness(by: 10)
        }
        hotKeys.register(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.store.nudgeBrightness(by: -10)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGDisplayRestoreColorSyncSettings()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            store.refreshAll()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Displays come and go (plugging in, sleep). Wait for things to settle, then look again.
    @objc private func screensChanged() {
        rediscover?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.discover() }
        rediscover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func scrolled(_ event: NSEvent) {
        // Finger up = brighter, whatever the natural scrolling setting.
        var delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        delta *= event.hasPreciseScrollingDeltas ? 0.25 : 2
        scrollRemainder += delta
        let steps = Int(scrollRemainder)
        guard steps != 0 else { return }
        scrollRemainder -= CGFloat(steps)
        store.nudgeBrightness(by: steps)
    }
}

/// System-wide keyboard shortcuts through Carbon (needs no extra permission).
final class HotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef?] = []

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKeys.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var reference: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4444_4C31), id: id),
                            GetApplicationEventTarget(), 0, &reference)
        references.append(reference)
    }
}
