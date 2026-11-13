import AppKit
import HaloCore
import SwiftUI

extension RGB {
    fileprivate var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    fileprivate init(color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            UInt8((c.redComponent * 255).rounded()), UInt8((c.greenComponent * 255).rounded()),
            UInt8((c.blueComponent * 255).rounded()))
    }
}

private let colorPresets: [(String, UInt32)] = [
    ("Cyan", 0x3DD6F5), ("Violet", 0x8B5CF6), ("Pink", 0xF0529C),
    ("Amber", 0xFFB547), ("Warm white", 0xFFE4C2), ("Cool white", 0xE8F1FF),
]

private struct LightingControls: View {
    @ObservedObject var model: HaloModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $model.mode) {
                Text("Screen sync").tag("Screen sync")
                Text("Solid color").tag("Solid color")
            }.pickerStyle(.segmented).labelsHidden().disabled(model.isBusy || model.isTesting)
            if model.mode == "Solid color" {
                HStack(spacing: 10) {
                    ForEach(Array(colorPresets.enumerated()), id: \.offset) { _, preset in
                        let color = Color(hex: preset.1)
                        Button {
                            model.solidColor = RGB(color: color)
                        } label: {
                            Circle().fill(color).frame(width: 25, height: 25)
                                .overlay(
                                    Circle().strokeBorder(
                                        .white, lineWidth: model.solidColor == RGB(color: color) ? 2 : 0))
                        }.buttonStyle(.plain).accessibilityLabel(preset.0)
                    }
                    ColorPicker(
                        "Custom color",
                        selection: Binding(
                            get: { model.solidColor.color }, set: { model.solidColor = RGB(color: $0) })
                    )
                    .labelsHidden()
                }
            }
            slider("Brightness", value: $model.brightness)
            slider("Smoothing", value: $model.smoothing)
        }
    }
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.font(.system(size: 13))
            Slider(value: value, in: 0...1).accessibilityLabel(title)
        }
    }
}

private struct PowerSwitch: View {
    @ObservedObject var model: HaloModel
    var body: some View {
        Toggle(
            "Lights",
            isOn: Binding(
                get: { model.isRunning },
                set: { on in
                    if on { model.start() } else { Task { await model.stop() } }
                })
        ).labelsHidden().toggleStyle(.switch)
            .disabled(model.isBusy || (!model.isRunning && !model.canStart))
            .accessibilityLabel("Turn lights on or off")
    }
}

struct HaloPopoverView: View {
    @ObservedObject var model: HaloModel
    let openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                HaloLogo().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ScreenHalo").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(model.isRunning ? "\(model.mode) · Strip connected" : "Lights off")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                PowerSwitch(model: model)
            }
            MonitorPreview(model: model).frame(height: 150)
            LightingControls(model: model)
            if model.mode == "Screen sync" && !model.screenRecordingAllowed {
                PermissionCard(model: model)
            }
            if !model.isRunning {
                Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Settings…", action: openSettings).buttonStyle(.plain).foregroundStyle(HaloStyle.cyan)
                Spacer()
                Button("Quit ScreenHalo") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(
                    .secondary)
            }.font(.system(size: 13))
        }.padding(18).frame(width: 340).background(HaloStyle.background)
            .tint(HaloStyle.cyan).preferredColorScheme(.dark)
            .background(
                PreviewWindowReader { window in Task { @MainActor in model.setPreviewWindow(window) } })
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case setup = "Setup"
    case general = "General"
    case layout = "LED layout"
    case device = "Device"
    case shortcuts = "Shortcuts"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .setup: return "sparkles"
        case .general: return "slider.horizontal.3"
        case .layout: return "rectangle.dashed"
        case .device: return "cable.connector"
        case .shortcuts: return "command"
        }
    }
}

struct HaloSettingsView: View {
    @ObservedObject var model: HaloModel
    @State private var section: SettingsSection?
    init(model: HaloModel, section: SettingsSection? = nil) {
        self.model = model
        _section = State(initialValue: section ?? (model.setupCompleted ? .general : .setup))
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    HaloLogo().frame(width: 34, height: 34)
                    (Text("Screen") + Text("Halo").foregroundColor(HaloStyle.cyan))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }.padding(.horizontal, 18).padding(.top, 18)
                List(SettingsSection.allCases, selection: $section) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .foregroundStyle(section == item ? .white : Color(hex: 0xA3A9B3)).tag(item)
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local light. No cloud.").foregroundStyle(.secondary)
                    Link("Made by Arne Korsika", destination: URL(string: "https://github.com/ArneKorsika/ScreenHalo")!)
                        .foregroundStyle(HaloStyle.cyan)
                }.font(.caption).padding(18)
            }.background(HaloStyle.sidebar).navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        switch section ?? .setup {
                        case .setup: setup
                        case .general: general
                        case .layout: layout
                        case .device: device
                        case .shortcuts: shortcuts
                        }
                    }.padding(28).frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }.id(section)
                powerBar
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(HaloStyle.background)
        }.frame(minWidth: 850, minHeight: 560)
            .onChange(of: model.setupCompleted) { _, completed in
                if completed && section == .setup { section = .general }
            }
            .tint(HaloStyle.cyan).preferredColorScheme(.dark)
            .background(
                PreviewWindowReader { window in Task { @MainActor in model.setPreviewWindow(window) } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(section == .setup ? "Let’s light up your screen" : (section ?? .setup).rawValue).font(
                .system(size: 27, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var subtitle: String {
        switch section ?? .setup {
        case .setup: return "Choose your screen, connect your strip, then turn on the lights."
        case .general: return "How ScreenHalo starts, what it watches and when it goes dark."
        case .layout: return "Match the strip behind your monitor so each LED picks up the right edge."
        case .device: return "The controller that drives your LED strip."
        case .shortcuts: return "Global keyboard shortcuts that work from any app."
        }
    }
    private var powerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        model.isRunning ? "Lights are on" : "Lights are off",
                        systemImage: model.isRunning ? "lightbulb.fill" : "lightbulb"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    Text(model.isRunning || model.isBusy ? model.status : model.startHint ?? model.status)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Spacer(minLength: 12)
                if model.isBusy { ProgressView().controlSize(.small) }
                Button {
                    if model.isRunning {
                        Task { await model.stop() }
                    } else if model.mode == "Screen sync" && !model.screenRecordingAllowed {
                        model.requestScreenPermission()
                    } else {
                        model.start()
                    }
                } label: {
                    Label(powerTitle, systemImage: model.isRunning ? "stop.fill" : "power")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.isBusy || model.isTesting || (!model.isRunning && !model.canStart))
            }.padding(.horizontal, 28).padding(.vertical, 18)
        }.background(HaloStyle.sidebar)
    }
    private var powerTitle: String {
        if model.isRunning { return "Turn off lights" }
        if model.mode == "Screen sync" && !model.screenRecordingAllowed {
            return model.hasRequestedPermission ? "Enable screen access…" : "Allow screen access"
        }
        return "Turn on lights"
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup("1 · CHOOSE YOUR DISPLAY") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose the monitor with the LED strip behind it.").font(.system(size: 13))
                    Picker("Display", selection: $model.displayUUID) {
                        if !model.selectionAvailable {
                            Text(model.displays.isEmpty ? "No display found" : "Choose a connected display")
                                .tag(model.displayUUID)
                        }
                        ForEach(model.displays) { Text($0.name).tag($0.id) }
                    }.disabled(model.isRunning || model.isBusy)
                    Text("Only this display’s left, top, and right edges control the lights.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }
            settingsGroup("2 · CONNECT YOUR LIGHTS") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Plug in your USB strip and close any other app controlling it.")
                        .font(.system(size: 13))
                    HStack {
                        Picker("USB strip", selection: $model.port) {
                            if !model.ports.contains(model.port) {
                                Text("Connect a USB strip").tag(model.port)
                            }
                            ForEach(model.ports, id: \.self) { Text($0).tag($0) }
                        }
                        Button("Refresh") { model.refresh() }
                    }.disabled(model.isRunning || model.isBusy)
                    HStack {
                        Text("\(model.leftLEDs) left · \(model.topLEDs) top · \(model.rightLEDs) right LEDs")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit LED layout") { section = .layout }.buttonStyle(.link)
                    }
                    Text("Two port names can refer to the same strip. Choose one.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }
            settingsGroup("3 · CHOOSE HOW TO LIGHT UP") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Lighting mode", selection: $model.mode) {
                        Text("Screen sync").tag("Screen sync")
                        Text("Solid color").tag("Solid color")
                    }.pickerStyle(.segmented).disabled(model.isBusy || model.isTesting)
                    if model.mode == "Screen sync" {
                        PermissionCard(model: model)
                    } else {
                        Text(
                            "One steady color. No screen access needed. Choose your color from the menu bar after turning on the lights."
                        )
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }.padding(16)
            }
            Label(
                "Ready? Use the button below. You can turn the lights on or off anytime from the ScreenHalo icon in your menu bar.",
                systemImage: "menubar.rectangle"
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("STARTUP") {
                settingRow(
                    "Open at login", hint: "Start ScreenHalo in the menu bar when you log in.",
                    value: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })
                )
                .disabled(model.loginUpdating)
                if model.loginNeedsApproval {
                    Text("Allow ScreenHalo in System Settings → General → Login Items.").font(.caption)
                        .foregroundStyle(.orange).padding(.horizontal, 16)
                }
                Divider()
                settingRow(
                    "Turn lights on at launch", hint: "Resume the last mode when the app starts.",
                    value: $model.autoOn)
                Divider()
                settingRow(
                    "Show in Dock", hint: "Off keeps ScreenHalo in the menu bar only.",
                    value: $model.showInDock)
            }
            settingsGroup("AUTO OFF") {
                settingRow(
                    "When the display sleeps", hint: "Pause the lights with the display, resume on wake.",
                    value: $model.offOnSleep)
                Divider()
                settingRow(
                    "When the Mac is locked", hint: "Lights come back when you unlock.",
                    value: $model.offOnLock)
            }
            settingsGroup("SCREEN CAPTURE") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Display").font(.caption).foregroundStyle(.secondary)
                            Picker("Display", selection: $model.displayUUID) {
                                if !model.selectionAvailable {
                                    Text("Saved display disconnected").tag(model.displayUUID)
                                }
                                ForEach(model.displays) { Text($0.name).tag($0.id) }
                            }.labelsHidden()
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Update rate").font(.caption).foregroundStyle(.secondary)
                            Picker("Update rate", selection: $model.frameRate) {
                                ForEach([30, 40, 60], id: \.self) { Text("\($0) fps").tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Edge depth")
                                Spacer()
                                Text(model.edgeDepth, format: .percent.precision(.fractionLength(0)))
                            }.font(.caption).foregroundStyle(.secondary)
                            Slider(value: $model.edgeDepth, in: 0.02...0.30).accessibilityLabel(
                                "Edge sampling depth")
                        }.frame(maxWidth: .infinity)
                    }
                    Text(
                        "Stop the lights to change capture settings. Current USB update limit: \(model.effectiveFrameRate) fps."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }.padding(16).disabled(model.isRunning || model.isBusy)
            }
            PermissionCard(model: model)
        }
    }
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0, content: content)
                .background(HaloStyle.sidebar, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func settingRow(_ title: String, hint: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch)
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var layout: some View {
        VStack(alignment: .leading, spacing: 20) {
            MonitorPreview(model: model, showLayout: true).frame(height: 270)
            HStack(spacing: 16) {
                count("Left", value: $model.leftLEDs)
                count("Top", value: $model.topLEDs)
                count("Right", value: $model.rightLEDs)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bottom").foregroundStyle(.secondary)
                    Text("0 · Unlit").frame(height: 23)
                }.font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.isRunning || model.isBusy)
            Picker("Strip starts at", selection: $model.reversed) {
                Text("Bottom left · clockwise").tag(false)
                Text("Bottom right · counter-clockwise").tag(true)
            }.pickerStyle(.menu)
            Text(
                "\(model.ledCount) LEDs total · Maximum 255. The ring marks the first LED.\nYour strip follows the left, top, and right edges; the bottom is not sampled."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func count(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Stepper(value: value, in: 0...255) { Text("\(value.wrappedValue)").monospacedDigit() }
        }.font(.system(size: 13)).frame(maxWidth: .infinity)
    }
    private var device: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Circle().fill(model.isRunning ? .green : .orange).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isRunning ? "Connected" : "Ready to connect").font(.headline)
                    Text("USB serial · \(model.ledCount) LEDs").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.isTesting ? "Stop test" : "Test pattern") { model.testPattern() }.disabled(
                    model.isBusy && !model.isTesting)
                Button("Reconnect") { model.reconnect() }.buttonStyle(.borderedProminent).disabled(
                    model.isBusy || model.isTesting)
            }.padding(18).background(HaloStyle.sidebar, in: RoundedRectangle(cornerRadius: 12))
            settingsGroup("CONNECTION") {
                VStack(alignment: .leading, spacing: 18) {
                    Label("USB serial", systemImage: "cable.connector").foregroundStyle(HaloStyle.cyan)
                    Picker("Serial port", selection: $model.port) {
                        if !model.ports.contains(model.port) { Text("Connect a USB strip").tag(model.port) }
                        ForEach(model.ports, id: \.self) { Text($0).tag($0) }
                    }.disabled(model.isRunning || model.isBusy)
                    HStack {
                        Button("Refresh devices") { model.refresh() }
                        Spacer()
                    }
                    Grid(alignment: .leading, horizontalSpacing: 50, verticalSpacing: 18) {
                        GridRow {
                            detail("Protocol", "Skydimo")
                            detail("Baud rate", "115200")
                        }
                        GridRow {
                            detail("Wire color order", "RGB")
                            detail("LED count", "\(model.ledCount)")
                        }
                    }
                }.padding(18)
            }
            Text(
                "All communication stays on the local USB cable. Color order and baud rate match this controller’s firmware. Wi-Fi and other LED protocols are not enabled."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
                "The test shows red, green, blue, then restores your previous mode. A CH340 adapter may expose both macOS and WCH ports; use one port."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var shortcuts: some View { ShortcutSettings(center: model.shortcuts) }

}

private struct MonitorPreview: View {
    @ObservedObject var model: HaloModel
    var showLayout = false
    var body: some View {
        let reversed = model.reversed
        let layout = model.layout
        let colors = reversed ? Array(model.preview.reversed()) : model.preview
        let glow =
            model.mode == "Solid color"
            ? AnyShapeStyle(model.solidColor.color) : AnyShapeStyle(HaloStyle.spectrum)
        GeometryReader { proxy in
            let w = min(proxy.size.width * 0.78, 460.0)
            let h = min(proxy.size.height * 0.65, 210.0)
            ZStack {
                if model.isRunning {
                    RoundedRectangle(cornerRadius: 16).fill(glow)
                        .frame(width: w, height: h).blur(radius: 18).opacity(model.brightness * 0.45)
                }
                Canvas { context, size in
                    let rect = CGRect(
                        x: (size.width - w) / 2 + 14, y: (size.height - h) / 2 + 14, width: w - 28,
                        height: h - 28)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 7),
                        with: .linearGradient(
                            Gradient(colors: [Color(hex: 0x1C1E26), Color(hex: 0x0B0C10)]),
                            startPoint: rect.origin,
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 7), with: .color(.white.opacity(0.1)),
                        lineWidth: 1)
                    func dot(_ index: Int, _ point: CGPoint) {
                        let color: Color
                        if index < colors.count {
                            color = colors[index].color
                        } else if showLayout {
                            color = Color(
                                hue: Double(index) / Double(max(1, layout.count)) * 0.8 + 0.5,
                                saturation: 0.8, brightness: 0.95)
                        } else {
                            color = .white.opacity(0.12)
                        }
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                            with: .color(color))
                        if showLayout && index == (reversed ? layout.count - 1 : 0) {
                            context.stroke(
                                Path(
                                    ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                                with: .color(.white), lineWidth: 1.5)
                        }
                    }
                    for i in 0..<layout.left {
                        dot(
                            i,
                            CGPoint(
                                x: rect.minX - 10,
                                y: rect.maxY - CGFloat(i + 1) / CGFloat(layout.left + 1) * rect.height))
                    }
                    for i in 0..<layout.top {
                        dot(
                            layout.left + i,
                            CGPoint(
                                x: rect.minX + CGFloat(i + 1) / CGFloat(layout.top + 1) * rect.width,
                                y: rect.minY - 10))
                    }
                    for i in 0..<layout.right {
                        dot(
                            layout.left + layout.top + i,
                            CGPoint(
                                x: rect.maxX + 10,
                                y: rect.minY + CGFloat(i + 1) / CGFloat(layout.right + 1) * rect.height))
                    }
                    if showLayout {
                        context.draw(
                            Text("\(layout.count) LEDs").font(.system(size: 13)).foregroundColor(.secondary),
                            at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
                if !showLayout {
                    Image(systemName: "display").font(.system(size: 23, weight: .light)).foregroundStyle(
                        .white.opacity(0.2))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(HaloStyle.inset, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(
                "Monitor with \(model.leftLEDs) left, \(model.topLEDs) top, and \(model.rightLEDs) right LEDs"
            )
    }
}

private struct PermissionCard: View {
    @ObservedObject var model: HaloModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                model.screenRecordingAllowed ? "Screen access is ready" : "Let your lights follow the screen",
                systemImage: model.screenRecordingAllowed ? "checkmark.shield" : "display"
            )
            .foregroundStyle(model.screenRecordingAllowed ? .green : HaloStyle.cyan)
            .font(.system(size: 13, weight: .semibold))
            if model.screenRecordingAllowed {
                Text("You’re ready to use Screen sync. Turn on the lights below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(
                    "ScreenHalo needs macOS Screen Recording permission to read colors from your chosen display. Everything stays on your Mac. No video is saved or sent anywhere."
                )
                .font(.caption).foregroundStyle(.secondary)
                Text(
                    model.hasRequestedPermission
                        ? "Enable ScreenHalo in System Settings → Screen Recording, then return here. If macOS asks you to quit and reopen, do that first."
                        : "Click Allow screen access, then follow the macOS prompt. macOS shows a capture indicator while Screen sync is running."
                )
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.hasRequestedPermission ? "Open System Settings…" : "Allow screen access") {
                        model.requestScreenPermission()
                    }.buttonStyle(.borderedProminent)
                    Button("Check access") { model.refreshPermission() }
                }.controlSize(.small)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(HaloStyle.inset, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var center: ShortcutCenter
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                ForEach(Array(ShortcutCenter.actions.enumerated()), id: \.offset) { index, action in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.1).font(.system(size: 13, weight: .medium))
                            Text(action.2).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShortcutRecorder(
                            label: center.bindings[action.0]?.label ?? "",
                            action: { binding in
                                center.set(action.0, binding: binding)
                            },
                            recordingChanged: { recording in
                                if recording { center.beginRecording() } else { center.endRecording() }
                            }
                        ).frame(width: 220, height: 40)
                        Button {
                            center.set(action.0, binding: nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(
                            "Clear \(action.1) shortcut")
                    }.padding(14)
                }
            }.background(HaloStyle.sidebar, in: RoundedRectangle(cornerRadius: 12))
            if !center.error.isEmpty { Text(center.error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("Include Control, Option or Command. Escape cancels recording.").font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore defaults") { center.reset() }
            }
            Text("App shortcuts: ⌘ , opens settings and ⌘ Q quits while ScreenHalo is active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
