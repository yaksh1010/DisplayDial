import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: MonitorStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.monitors.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 28))
                    Text("No external monitor found").font(.headline)
                    Text("Plug in your monitor, then click the sun again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                presets
                ForEach(store.monitors) { MonitorSection(monitor: $0) }
            }

            if let builtIn = store.builtIn {
                Divider()
                BuiltInRow(display: builtIn)
            }

            Divider()
            HStack {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text("⌃⌥↑ ⌃⌥↓ or scroll on ☀︎").font(.caption2).foregroundStyle(.tertiary)
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(store.presets) { preset in
                Button { store.apply(preset) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: preset.symbol).font(.system(size: 15))
                        Text(preset.name).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Apply \(preset.name). Right-click to save your current settings here.")
                .contextMenu {
                    Button("Save Current Settings as “\(preset.name)”") { store.saveCurrent(into: preset) }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct MonitorSection: View {
    @ObservedObject var monitor: ExternalMonitor
    @State private var showMore = false
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "display").foregroundStyle(.secondary)
                Text(monitor.name).font(.headline)
                Text(monitor.hardwareAvailable ? "DDC" : "Software")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(monitor.hardwareAvailable ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                    .help(monitor.hardwareAvailable
                          ? "Changing the monitor's real settings over DDC/CI."
                          : "This monitor isn't answering DDC/CI, so brightness is simulated by dimming the picture. Check that DDC/CI is turned on in the monitor's own menu.")
                Spacer()
                if monitor.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Read the monitor's current settings")
                }
            }

            if monitor.hardwareAvailable {
                hardwareControls
            } else {
                SliderRow(symbol: "sun.max.fill", title: "Brightness",
                          value: Binding(get: { (1 - monitor.extraDim) * 100 },
                                         set: { monitor.extraDim = min(0.9, 1 - $0 / 100) }),
                          range: 10...100)
            }
        }
        .alert("Reset \(monitor.name) to factory settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { monitor.resetToFactory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Brightness, contrast and colors go back to how the monitor came out of the box.")
        }
    }

    @ViewBuilder private var hardwareControls: some View {
        SliderRow(symbol: "sun.max.fill", title: "Brightness", value: binding(.brightness),
                  range: 0...Double(monitor.maximum(.brightness)))
        if monitor.supports(.contrast) {
            SliderRow(symbol: "circle.lefthalf.filled", title: "Contrast", value: binding(.contrast),
                      range: 0...Double(monitor.maximum(.contrast)))
        }
        SliderRow(symbol: "moon.fill", title: "Extra dim", value: $monitor.extraDim, range: 0...0.9,
                  format: { "\(Int($0 / 0.9 * 100))%" })
            .help("Goes darker than the monitor's lowest brightness by dimming the picture on the Mac.")

        if monitor.supports(.colorPreset), !monitor.allowedValues(.colorPreset).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Color temperature", systemImage: "thermometer.medium").font(.callout)
                Picker("Color temperature", selection: binding(.colorPreset, as: Int.self)) {
                    ForEach(monitor.allowedValues(.colorPreset), id: \.self) { code in
                        Text(ColorPresetName.short(code)).tag(Int(code))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }

        if isCustomColor, monitor.supports(.redGain) {
            ColorGainRow(monitor: monitor, title: "Red", color: .red, code: .redGain)
            ColorGainRow(monitor: monitor, title: "Green", color: .green, code: .greenGain)
            ColorGainRow(monitor: monitor, title: "Blue", color: .blue, code: .blueGain)
        } else if monitor.supports(.redGain) {
            Text("Choose Custom to fine-tune red, green and blue.")
                .font(.caption).foregroundStyle(.secondary)
        }

        if monitor.supports(.sharpness) {
            SliderRow(symbol: "triangle.lefthalf.filled", title: "Sharpness", value: binding(.sharpness),
                      range: 0...Double(monitor.maximum(.sharpness)), step: 1)
        }

        DisclosureGroup("More settings", isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: 8) {
                if monitor.supports(.redBlackLevel) {
                    Text("Black level").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ColorGainRow(monitor: monitor, title: "Red", color: .red, code: .redBlackLevel)
                    ColorGainRow(monitor: monitor, title: "Green", color: .green, code: .greenBlackLevel)
                    ColorGainRow(monitor: monitor, title: "Blue", color: .blue, code: .blueBlackLevel)
                }
                if monitor.supports(.redSaturation) {
                    Text("Saturation").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ColorGainRow(monitor: monitor, title: "Red", color: .red, code: .redSaturation)
                    ColorGainRow(monitor: monitor, title: "Yellow", color: .yellow, code: .yellowSaturation)
                    ColorGainRow(monitor: monitor, title: "Green", color: .green, code: .greenSaturation)
                    ColorGainRow(monitor: monitor, title: "Cyan", color: .cyan, code: .cyanSaturation)
                    ColorGainRow(monitor: monitor, title: "Blue", color: .blue, code: .blueSaturation)
                    ColorGainRow(monitor: monitor, title: "Magenta", color: .pink, code: .magentaSaturation)
                }
                if monitor.supports(.factoryReset) {
                    Button("Reset Monitor to Factory Settings…", role: .destructive) { confirmReset = true }
                        .padding(.top, 4)
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }

    private var isCustomColor: Bool {
        !monitor.supports(.colorPreset) || (0x0B...0x0D).contains(monitor.value(.colorPreset))
    }

    private func binding(_ code: VCP) -> Binding<Double> {
        Binding(get: { Double(monitor.value(code)) }, set: { monitor.set(code, Int($0.rounded())) })
    }

    private func binding(_ code: VCP, as: Int.Type) -> Binding<Int> {
        Binding(get: { monitor.value(code) }, set: { monitor.set(code, $0) })
    }
}

/// Friendly names for the MCCS color presets (VCP 0x14).
enum ColorPresetName {
    static func short(_ code: UInt8) -> String {
        switch code {
        case 0x01: "sRGB"
        case 0x02: "Native"
        case 0x03: "4000K"
        case 0x04: "5000K"
        case 0x05: "Warm"
        case 0x06: "Neutral"
        case 0x07: "8200K"
        case 0x08: "Cool"
        case 0x09: "10000K"
        case 0x0A: "11500K"
        case 0x0B: "Custom"
        case 0x0C: "Custom 2"
        case 0x0D: "Custom 3"
        default: "Mode \(code)"
        }
    }
}

private struct SliderRow: View {
    let symbol: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).font(.callout).frame(width: 74, alignment: .leading)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
            Text(format(value)).font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
        }
        .accessibilityLabel(title)
    }
}

private struct ColorGainRow: View {
    @ObservedObject var monitor: ExternalMonitor
    let title: String
    let color: Color
    let code: VCP

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.caption).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { Double(monitor.value(code)) },
                                  set: { monitor.set(code, Int($0.rounded())) }),
                   in: 0...Double(monitor.maximum(code)))
                .tint(color)
            Text("\(monitor.value(code))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
        }
    }
}

private struct BuiltInRow: View {
    @ObservedObject var display: BuiltInDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                Text("MacBook screen").font(.headline)
            }
            SliderRow(symbol: "sun.max.fill", title: "Brightness", value: $display.brightness, range: 0...1,
                      format: { "\(Int($0 * 100))" })
        }
    }
}
