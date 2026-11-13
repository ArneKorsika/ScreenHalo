import AppKit
import Carbon
import SwiftUI

struct ShortcutBinding: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let label: String
}

@MainActor
final class ShortcutCenter: ObservableObject {
    static let actions: [(String, String, String)] = [
        ("toggle", "Turn lights on / off", "Same as the power switch in the menu bar popover."),
        ("mode", "Switch mode", "Cycle between Screen sync and Solid color."),
        ("up", "Brightness up", "Raise brightness by 10%."),
        ("down", "Brightness down", "Lower brightness by 10%."),
        ("color", "Next solid color", "Step through the color presets."),
        ("popover", "Open ScreenHalo", "Show the menu bar popover."),
    ]
    static let defaults: [String: ShortcutBinding] = [
        "toggle": .init(key: 4, modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ H"),
        "mode": .init(key: 46, modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ M"),
        "up": .init(key: 126, modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ ↑"),
        "down": .init(key: 125, modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ ↓"),
        "color": .init(key: 8, modifiers: UInt32(controlKey | optionKey), label: "⌃ ⌥ C"),
    ]
    @Published private(set) var bindings: [String: ShortcutBinding]
    @Published var error = ""
    var perform: ((String) -> Void)?
    private let preferences: UserDefaults
    private var refs: [String: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var recording = false

    init(defaults: UserDefaults) {
        preferences = defaults
        bindings =
            defaults.data(forKey: "shortcuts").flatMap {
                try? JSONDecoder().decode([String: ShortcutBinding].self, from: $0)
            } ?? Self.defaults
        var kind = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotkey = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
                guard result == noErr else { return result }
                let center = Unmanaged<ShortcutCenter>.fromOpaque(context).takeUnretainedValue()
                let index = Int(hotkey.id) - 1
                Task { @MainActor in
                    if ShortcutCenter.actions.indices.contains(index) {
                        center.perform?(ShortcutCenter.actions[index].0)
                    }
                }
                return noErr
            }, 1, &kind, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for action in Self.actions {
            if let binding = bindings[action.0] { registerBinding(action.0, binding) }
        }
    }
    private func registerBinding(_ action: String, _ binding: ShortcutBinding) {
        guard !recording, let index = Self.actions.firstIndex(where: { $0.0 == action }) else { return }
        var ref: EventHotKeyRef?
        let code = RegisterEventHotKey(
            binding.key, binding.modifiers, EventHotKeyID(signature: 0x5348_4C4F, id: UInt32(index + 1)),
            GetApplicationEventTarget(), 0, &ref)
        if code == noErr {
            refs[action] = ref
        } else {
            error = "The shortcut for \(Self.actions[index].1) is unavailable. Choose different keys."
        }
    }
    func beginRecording() {
        guard !recording else { return }
        recording = true
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        for (action, binding) in bindings { registerBinding(action, binding) }
    }
    func set(_ action: String, binding: ShortcutBinding?) {
        if let binding,
            bindings.contains(where: {
                $0.key != action && $0.value.key == binding.key && $0.value.modifiers == binding.modifiers
            })
        {
            error = "That shortcut is already assigned in ScreenHalo."
            return
        }
        error = ""
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        let previous = bindings[action]
        if let binding {
            registerBinding(action, binding)
            if !error.isEmpty {
                if let previous { registerBinding(action, previous) }
                return
            }
        }
        bindings[action] = binding
        if let data = try? JSONEncoder().encode(bindings) { preferences.set(data, forKey: "shortcuts") }
    }
    func reset() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        error = ""
        bindings = Self.defaults
        for (action, binding) in bindings { registerBinding(action, binding) }
        if let data = try? JSONEncoder().encode(bindings) { preferences.set(data, forKey: "shortcuts") }
    }
    func shutdown() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let action: (ShortcutBinding?) -> Void
    let recordingChanged: (Bool) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.isBordered = false
        button.focusRingType = .none
        button.toolTip = "Click to change this shortcut. Press Escape to cancel."
        button.actionClosure = action
        button.recordingChanged = recordingChanged
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        button.setAccessibilityLabel("Record keyboard shortcut")
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.setAccessibilityValue(label.isEmpty ? "No shortcut assigned" : label)
        button.savedLabel = label
        button.actionClosure = action
        button.recordingChanged = recordingChanged
        if !button.recording { button.title = label.isEmpty ? "Record shortcut" : label }
    }
    static func dismantleNSView(_ nsView: RecorderButton, coordinator: ()) { nsView.cancelRecording() }
    final class RecorderButton: NSButton {
        var actionClosure: ((ShortcutBinding?) -> Void)?
        var recordingChanged: ((Bool) -> Void)?
        var savedLabel = ""
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let font = NSFont.systemFont(ofSize: recording || savedLabel.isEmpty ? 12 : 19, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor,
            ]
            let keys =
                recording || savedLabel.isEmpty ? [title] : savedLabel.split(separator: " ").map(String.init)
            let widths = keys.map { max(34, ($0 as NSString).size(withAttributes: attributes).width + 18) }
            let spacing: CGFloat = 6
            let totalWidth = widths.reduce(0, +) + CGFloat(max(0, keys.count - 1)) * spacing
            var x = bounds.maxX - totalWidth - 2
            for (key, width) in zip(keys, widths) {
                let rect = NSRect(x: x, y: bounds.midY - 17, width: width, height: 34)
                let shadow = NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -2), xRadius: 8, yRadius: 8)
                NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
                shadow.fill()
                let cap = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                NSColor(calibratedWhite: isHighlighted ? 0.23 : 0.16, alpha: 1).setFill()
                cap.fill()
                let focused = window?.firstResponder === self
                (recording || focused ? NSColor.systemCyan : NSColor(calibratedWhite: 0.22, alpha: 1))
                    .setStroke()
                cap.lineWidth = 1
                cap.stroke()
                let size = (key as NSString).size(withAttributes: attributes)
                (key as NSString).draw(
                    at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                    withAttributes: attributes)
                x += width + spacing
            }
        }
        @objc func beginRecording() {
            window?.makeFirstResponder(self)
            if !recording {
                recording = true
                recordingChanged?(true)
            }
            title = "Press keys…"
        }
        func cancelRecording() {
            if recording {
                recording = false
                recordingChanged?(false)
            }
            title = savedLabel.isEmpty ? "Record shortcut" : savedLabel
        }
        override func resignFirstResponder() -> Bool {
            cancelRecording()
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if recording {
                keyDown(with: event)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
        override func keyDown(with event: NSEvent) {
            guard recording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 {
                cancelRecording()
                return
            }
            let f = event.modifierFlags
            guard !f.intersection([.command, .option, .control]).isEmpty else {
                title = "Include ⌃, ⌥ or ⌘"
                return
            }
            if f.contains(.command) && [UInt16(12), 43].contains(event.keyCode) {
                title = "Reserved app shortcut"
                return
            }
            var modifiers: UInt32 = 0
            var parts: [String] = []
            if f.contains(.control) {
                modifiers |= UInt32(controlKey)
                parts.append("⌃")
            }
            if f.contains(.option) {
                modifiers |= UInt32(optionKey)
                parts.append("⌥")
            }
            if f.contains(.shift) {
                modifiers |= UInt32(shiftKey)
                parts.append("⇧")
            }
            if f.contains(.command) {
                modifiers |= UInt32(cmdKey)
                parts.append("⌘")
            }
            let special: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space", 36: "↩"]
            parts.append(special[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased())
            recording = false
            recordingChanged?(false)
            title = savedLabel.isEmpty ? "Record shortcut" : savedLabel
            actionClosure?(
                .init(key: UInt32(event.keyCode), modifiers: modifiers, label: parts.joined(separator: " ")))
        }
    }
}
