import AppKit
import Carbon
import Combine
import HaloCore
import SwiftUI

@main
@MainActor
enum ScreenHaloMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = HaloDelegate()
        app.delegate = delegate
        HaloStyle.installApplicationIcon()
        app.setActivationPolicy(delegate.model.showInDock ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class HaloDelegate: NSObject, NSApplicationDelegate {
    let model = HaloModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        HaloStyle.installApplicationIcon()
        model.$showInDock.receive(on: DispatchQueue.main).sink { visible in
            if visible { HaloStyle.installApplicationIcon() }
        }.store(in: &subscriptions)
        model.shortcuts.perform = { [weak self] action in self?.performShortcut(action) }
        let menu = NSMenu()
        let appMenu = NSMenu()
        let settings = appMenu.addItem(
            withTitle: "ScreenHalo Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(
            withTitle: "Quit ScreenHalo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(
            rootView: HaloPopoverView(
                model: model,
                openSettings: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showSettings()
                }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        model.$isRunning.receive(on: DispatchQueue.main).sink { [weak self] active in
            self?.statusItem.button?.image = HaloStyle.menuIcon(active: active)
            self?.statusItem.button?.toolTip = active ? "ScreenHalo — lights on" : "ScreenHalo — lights off"
        }.store(in: &subscriptions)
        let loginLaunch =
            NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(
                forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue ?? false
        if !loginLaunch { showSettings() }
        if model.autoOn && model.setupCompleted { model.start() }
    }

    private func performShortcut(_ action: String) {
        guard !model.isBusy else { return }
        if model.isTesting && action == "mode" { return }
        switch action {
        case "toggle": if model.isRunning { Task { await model.stop() } } else { model.start() }
        case "mode": model.mode = model.mode == "Screen sync" ? "Solid color" : "Screen sync"
        case "up": model.brightness = min(1, model.brightness + 0.1)
        case "down": model.brightness = max(0, model.brightness - 0.1)
        case "color":
            let colors = [
                RGB(61, 214, 245), RGB(139, 92, 246), RGB(240, 82, 156), RGB(255, 181, 71),
                RGB(255, 228, 194), RGB(232, 241, 255),
            ]
            let index = colors.firstIndex(of: model.solidColor) ?? -1
            model.solidColor = colors[(index + 1) % colors.count]
        case "popover": togglePopover()
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.shortcuts.shutdown() }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = menu.addItem(
                withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(
                withTitle: "Quit ScreenHalo", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
            quit.target = NSApp
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: HaloSettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "ScreenHalo Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 960, height: model.setupCompleted ? 680 : 800))
            window.minSize = NSSize(width: 880, height: 600)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning || model.isBusy else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task {
            await model.stop()
            if terminationPending {
                terminationPending = false
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.terminationPending else { return }
            self.terminationPending = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct PreviewWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: WindowView, context: Context) {}
    final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
