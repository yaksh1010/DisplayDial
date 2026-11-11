import AppKit
import SwiftUI

let arguments = CommandLine.arguments

// `DisplayDial --snapshot out.png` draws the popover with live values, for docs and testing.
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    _ = NSApplication.shared
    let store = MonitorStore()
    store.discover()
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    let view = NSHostingView(rootView: PopoverView(store: store).background(Color(nsColor: .windowBackgroundColor)))
    view.appearance = NSAppearance(named: .darkAqua)
    view.frame = NSRect(origin: .zero, size: view.fittingSize)
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[index + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
