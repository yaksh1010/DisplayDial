import AppKit
import Combine

/// An external monitor: real settings over DDC/CI when it answers, software dimming either way.
final class ExternalMonitor: ObservableObject, Identifiable {
    let id: String
    let name: String
    let displayID: CGDirectDisplayID?
    private let channel: DDCChannel?
    private let defaults = UserDefaults.standard

    @Published private(set) var values: [UInt8: Int] = [:]
    @Published private(set) var maxima: [UInt8: Int] = [:]
    /// Code → allowed values, from the monitor's capability list plus codes that answered.
    @Published private(set) var supported: [UInt8: [UInt8]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var hardwareAvailable: Bool
    /// 0 = off, 1 = darkest. Darkens the picture with the Mac's color tables, below the monitor's minimum.
    @Published var extraDim: Double {
        didSet {
            defaults.set(extraDim, forKey: "extraDim.\(id)")
            onGammaChange?()
        }
    }
    var onGammaChange: (() -> Void)?

    init(name: String, displayID: CGDirectDisplayID?, service: CFTypeRef?) {
        self.name = name
        self.displayID = displayID
        if let displayID {
            id = "\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
        } else {
            id = name
        }
        channel = service.map { DDCChannel(service: $0, label: name) }
        hardwareAvailable = service != nil
        extraDim = UserDefaults.standard.double(forKey: "extraDim.\(id)")
        if let cached = defaults.dictionary(forKey: "values.\(id)") as? [String: Int] {
            values = Dictionary(uniqueKeysWithValues: cached.compactMap { key, value in UInt8(key).map { ($0, value) } })
        }
    }

    func supports(_ code: VCP) -> Bool { supported[code.rawValue] != nil }
    func value(_ code: VCP) -> Int { values[code.rawValue] ?? 0 }
    func maximum(_ code: VCP) -> Int { max(maxima[code.rawValue] ?? 100, 1) }
    func allowedValues(_ code: VCP) -> [UInt8] { supported[code.rawValue] ?? [] }

    func set(_ code: VCP, _ value: Int) {
        let clamped = min(max(value, 0), maximum(code))
        values[code.rawValue] = clamped
        channel?.set(code.rawValue, clamped)
        saveValues()
    }

    /// Restores the monitor's own factory settings (any non-zero value to VCP 0x04).
    func resetToFactory() {
        channel?.set(VCP.factoryReset.rawValue, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    /// Reads current values from the monitor (they may have been changed with its buttons).
    func refresh() {
        guard let channel, !isLoading else { return }
        isLoading = true
        let capabilityKey = "capabilities.\(id)"
        let cachedCapabilities = defaults.string(forKey: capabilityKey)

        channel.perform { channel in
            var supported: [UInt8: [UInt8]] = [:]
            if let text = cachedCapabilities ?? channel.capabilities(), let parsed = Capabilities(text) {
                supported = parsed.codes
                if cachedCapabilities == nil {
                    DispatchQueue.main.async { self.defaults.set(text, forKey: capabilityKey) }
                }
            }

            var values: [UInt8: Int] = [:], maxima: [UInt8: Int] = [:]
            func read(_ codes: [VCP]) {
                for code in codes {
                    // Some monitors leave a few working codes out of their list, so always try the main ones.
                    let worthTrying = supported[code.rawValue] != nil
                        || [.brightness, .contrast, .sharpness].contains(code)
                    guard code != .factoryReset, worthTrying, let reply = channel.read(code.rawValue) else { continue }
                    values[code.rawValue] = reply.value
                    maxima[code.rawValue] = reply.maximum
                    if supported[code.rawValue] == nil { supported[code.rawValue] = [] }
                }
            }

            read(VCP.essentials)
            let essentials = (values, maxima, supported)
            DispatchQueue.main.async { self.apply(essentials, finished: false) }

            read(VCP.allCases.filter { !VCP.essentials.contains($0) })
            DispatchQueue.main.async { self.apply((values, maxima, supported), finished: true) }
        }
    }

    private func apply(_ result: ([UInt8: Int], [UInt8: Int], [UInt8: [UInt8]]), finished: Bool) {
        values.merge(result.0) { _, new in new }
        maxima.merge(result.1) { _, new in new }
        supported = result.2
        if finished {
            isLoading = false
            hardwareAvailable = !result.0.isEmpty
            saveValues()
        }
    }

    private func saveValues() {
        defaults.set(Dictionary(uniqueKeysWithValues: values.map { (String($0.key), $0.value) }), forKey: "values.\(id)")
    }
}

/// The MacBook's own screen, through the private DisplayServices framework.
final class BuiltInDisplay: ObservableObject {
    let displayID: CGDirectDisplayID
    @Published var brightness: Double = 0.5 {
        didSet { if brightness != oldValue { Self.setBrightness?(displayID, Float(brightness)) } }
    }

    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: Getter.self) }
    private static let setBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: Setter.self) }

    init?(displayID: CGDirectDisplayID) {
        guard Self.getBrightness != nil, Self.setBrightness != nil else { return nil }
        self.displayID = displayID
        refresh()
    }

    func refresh() {
        var value: Float = 0
        if Self.getBrightness?(displayID, &value) == 0 { brightness = Double(value) }
    }
}

/// A saved combination the user can apply in one click.
struct Preset: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var symbol: String
    var brightness: Int
    var contrast: Int
    var colorPreset: Int?
    var extraDim: Double

    static let defaults = [
        Preset(name: "Day", symbol: "sun.max.fill", brightness: 80, contrast: 50, colorPreset: 0x05, extraDim: 0),
        Preset(name: "Evening", symbol: "sunset.fill", brightness: 45, contrast: 50, colorPreset: 0x05, extraDim: 0),
        Preset(name: "Night", symbol: "moon.stars.fill", brightness: 5, contrast: 45, colorPreset: 0x05, extraDim: 0.3),
        Preset(name: "Movie", symbol: "film.fill", brightness: 70, contrast: 60, colorPreset: 0x05, extraDim: 0),
    ]
}

final class MonitorStore: ObservableObject {
    @Published private(set) var monitors: [ExternalMonitor] = []
    @Published private(set) var builtIn: BuiltInDisplay?
    @Published var presets: [Preset] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(presets), forKey: "presets") }
    }
    private var subscriptions: [AnyCancellable] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: "presets"),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = saved
        } else {
            presets = Preset.defaults
        }
    }

    /// Finds connected displays. External monitors are paired with DDC services in order.
    func discover() {
        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (screen, CGDirectDisplayID(number.uint32Value))
        }
        let external = screens.filter { CGDisplayIsBuiltin($0.1) == 0 }
        let services = DDCChannel.externalServices()

        let found = external.enumerated().map { index, entry in
            ExternalMonitor(name: entry.0.localizedName, displayID: entry.1,
                            service: index < services.count ? services[index] : nil)
        }
        // Keep existing objects for monitors that are still connected so the UI doesn't flicker.
        monitors = found.map { new in monitors.first { $0.id == new.id } ?? new }
        subscriptions = monitors.map { monitor in
            monitor.onGammaChange = { [weak self] in self?.applyGamma() }
            return monitor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        if let builtInScreen = screens.first(where: { CGDisplayIsBuiltin($0.1) != 0 }) {
            if builtIn?.displayID != builtInScreen.1 { builtIn = BuiltInDisplay(displayID: builtInScreen.1) }
        } else {
            builtIn = nil
        }
        applyGamma()
        refreshAll()
    }

    func refreshAll() {
        monitors.forEach { $0.refresh() }
        builtIn?.refresh()
    }

    /// Changes every external monitor's brightness by `step` (used by hotkeys and scrolling).
    func nudgeBrightness(by step: Int) {
        for monitor in monitors {
            if monitor.hardwareAvailable {
                // Below 0, keep going darker with software dimming.
                if step < 0, monitor.value(.brightness) == 0 {
                    monitor.extraDim = min(0.9, monitor.extraDim + Double(-step) / 100)
                } else if step > 0, monitor.extraDim > 0 {
                    monitor.extraDim = max(0, monitor.extraDim - Double(step) / 100)
                } else {
                    monitor.set(.brightness, monitor.value(.brightness) + step)
                }
            } else {
                monitor.extraDim = min(0.9, max(0, monitor.extraDim - Double(step) / 100))
            }
        }
    }

    func apply(_ preset: Preset) {
        for monitor in monitors {
            monitor.set(.brightness, preset.brightness)
            if monitor.supports(.contrast) { monitor.set(.contrast, preset.contrast) }
            if let color = preset.colorPreset, monitor.allowedValues(.colorPreset).contains(UInt8(color)) {
                monitor.set(.colorPreset, color)
            }
            monitor.extraDim = preset.extraDim
        }
    }

    func saveCurrent(into preset: Preset) {
        guard let monitor = monitors.first, let index = presets.firstIndex(of: preset) else { return }
        presets[index].brightness = monitor.value(.brightness)
        presets[index].contrast = monitor.value(.contrast)
        presets[index].colorPreset = monitor.supports(.colorPreset) ? monitor.value(.colorPreset) : nil
        presets[index].extraDim = monitor.extraDim
    }

    /// Software dimming: scale each external display's color table. Resets cleanly on quit.
    func applyGamma() {
        CGDisplayRestoreColorSyncSettings()
        for monitor in monitors where monitor.extraDim > 0 {
            guard let displayID = monitor.displayID else { continue }
            let top = CGGammaValue(1 - monitor.extraDim * 0.9)
            CGSetDisplayTransferByFormula(displayID, 0, top, 1, 0, top, 1, 0, top, 1)
        }
    }
}
