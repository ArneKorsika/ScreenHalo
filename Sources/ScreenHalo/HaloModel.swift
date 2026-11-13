import AppKit
import HaloCore
import ServiceManagement
import SwiftUI

@MainActor
final class HaloModel: ObservableObject {
    @Published var displays: [DisplayChoice] = []
    @Published var ports: [String] = []
    @Published var displayUUID: String { didSet { defaults.set(displayUUID, forKey: "displayUUID") } }
    @Published var port: String { didSet { defaults.set(port, forKey: "port") } }
    @Published var leftLEDs: Int { didSet { defaults.set(leftLEDs, forKey: "leftLEDs") } }
    @Published var topLEDs: Int { didSet { defaults.set(topLEDs, forKey: "topLEDs") } }
    @Published var rightLEDs: Int { didSet { defaults.set(rightLEDs, forKey: "rightLEDs") } }
    var layout: EdgeLayout { EdgeLayout(left: leftLEDs, top: topLEDs, right: rightLEDs) }
    var ledCount: Int { layout.count }
    var effectiveFrameRate: Int {
        min(frameRate, max(1, Int(11520 * 0.85 / Double(6 + 3 * ledCount))))
    }
    @Published var brightness: Double {
        didSet {
            defaults.set(brightness, forKey: "brightness")
            startRendering()
        }
    }
    @Published var reversed: Bool {
        didSet {
            defaults.set(reversed, forKey: "reversed")
            startRendering()
        }
    }
    @Published var smoothing: Double {
        didSet {
            defaults.set(smoothing, forKey: "smoothing")
            startRendering()
        }
    }
    @Published var frameRate: Int { didSet { defaults.set(frameRate, forKey: "frameRate") } }
    @Published var edgeDepth: Double { didSet { defaults.set(edgeDepth, forKey: "edgeDepth") } }
    @Published var autoOn: Bool { didSet { defaults.set(autoOn, forKey: "autoOn") } }
    @Published var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "showInDock")
            NSApp?.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }
    @Published var offOnSleep: Bool {
        didSet {
            defaults.set(offOnSleep, forKey: "offOnSleep")
            updateAutoOff()
        }
    }
    @Published var offOnLock: Bool {
        didSet {
            defaults.set(offOnLock, forKey: "offOnLock")
            updateAutoOff()
        }
    }
    @Published var loginEnabled = false
    @Published var isTesting = false
    @Published var loginUpdating = false
    @Published var loginNeedsApproval = false
    @Published var screenRecordingAllowed = false
    @Published var mode: String {
        didSet {
            defaults.set(mode, forKey: "mode")
            if !isRestoringMode && isRunning && oldValue != mode { changeMode(from: oldValue) }
        }
    }
    @Published var solidColor: RGB {
        didSet {
            defaults.set([Int(solidColor.r), Int(solidColor.g), Int(solidColor.b)], forKey: "solidColor")
            if mode == "Solid color" {
                latestColors = Array(repeating: solidColor, count: ledCount)
                startRendering()
            }
        }
    }
    @Published private(set) var setupCompleted: Bool {
        didSet { defaults.set(setupCompleted, forKey: "setupCompleted") }
    }
    @Published var isRunning = false
    @Published var isBusy = false
    @Published var status = "Ready when you are. Click Turn on lights to start."
    @Published var preview: [RGB] = []
    let shortcuts: ShortcutCenter

    private let defaults = UserDefaults.standard
    @Published private(set) var hasRequestedPermission = false
    private var isRestoringMode = false
    private var asleep = false
    private var locked = false
    private var resumeAfterAutoOff = false
    private var capture: ScreenCapture?
    private var strip: USBStrip?
    private var renderer = ColorRenderer()
    private var pendingOutput: [RGB]?
    private let previewWindows = NSHashTable<NSWindow>.weakObjects()
    private var previewObserver: NSObjectProtocol?
    private var lastPreviewUpdate = 0.0
    private var latestColors: [RGB] = []
    private var renderTimer: DispatchSourceTimer?
    private var sessionID = UUID()
    private var sourceID = UUID()
    private var startTask: Task<Void, Never>?
    private var modeTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        setupCompleted = defaults.bool(forKey: "setupCompleted")
        shortcuts = ShortcutCenter(defaults: defaults)
        displayUUID = defaults.string(forKey: "displayUUID") ?? ""
        port = defaults.string(forKey: "port") ?? ""
        let leftCount = defaults.object(forKey: "leftLEDs") as? Int ?? 13
        let topCount = defaults.object(forKey: "topLEDs") as? Int ?? 26
        let rightCount = defaults.object(forKey: "rightLEDs") as? Int ?? 13
        let validLayout =
            [leftCount, topCount, rightCount].allSatisfy { (0...255).contains($0) }
            && (1...255).contains(leftCount + topCount + rightCount)
        leftLEDs = validLayout ? leftCount : 13
        topLEDs = validLayout ? topCount : 26
        rightLEDs = validLayout ? rightCount : 13
        brightness = max(0, min(1, defaults.object(forKey: "brightness") as? Double ?? 0.6))
        reversed = defaults.bool(forKey: "reversed")
        smoothing = max(0, min(1, defaults.object(forKey: "smoothing") as? Double ?? 0.5))
        let rate = defaults.integer(forKey: "frameRate")
        frameRate = [30, 40, 60].contains(rate) ? rate : 40
        edgeDepth = max(0.02, min(0.30, defaults.object(forKey: "edgeDepth") as? Double ?? 0.20))
        autoOn = defaults.bool(forKey: "autoOn")
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        offOnSleep = defaults.object(forKey: "offOnSleep") as? Bool ?? true
        offOnLock = defaults.object(forKey: "offOnLock") as? Bool ?? true
        mode = defaults.string(forKey: "mode") == "Solid color" ? "Solid color" : "Screen sync"
        let savedColor = defaults.array(forKey: "solidColor") as? [Int] ?? []
        solidColor =
            savedColor.count == 3
            ? RGB(
                UInt8(clamping: savedColor[0]), UInt8(clamping: savedColor[1]), UInt8(clamping: savedColor[2])
            ) : RGB(61, 214, 245)
        refresh()
        startObservers()
        refreshPermission()
        refreshLogin()
    }

    private func startObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refresh()
                    if self.mode == "Screen sync" && (self.isRunning || self.isBusy) {
                        await self.stop(
                            reason: "Display arrangement changed. Check your selection and start again.")
                    }
                }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main)
            { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermission()
                    self?.refreshLogin()
                }
            })
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [
            (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.setDisplaySleeping(sleeping) }
                })
        }
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(
                DistributedNotificationCenter.default().addObserver(
                    forName: .init(name), object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.setScreenLocked(value) }
                })
        }
    }
    func setDisplaySleeping(_ value: Bool) {
        asleep = value
        updateAutoOff()
    }
    func setScreenLocked(_ value: Bool) {
        locked = value
        updateAutoOff()
    }
    private var automaticOff: Bool { (offOnSleep && asleep) || (offOnLock && locked) }
    private func updateAutoOff() {
        if automaticOff && (isRunning || isBusy) {
            resumeAfterAutoOff = true
            Task { await stop(reason: "Lights paused with the display or lock screen.", automatic: true) }
        } else if !automaticOff && resumeAfterAutoOff {
            resumeAfterAutoOff = false
            Task {
                if let pending = stopTask { await pending.value }
                start()
            }
        }
    }
    func refresh() {
        displays = DisplayChoice.connected()
        ports = USBStrip.ports()
        if displayUUID.isEmpty { displayUUID = displays.first?.id ?? "" }
        if port.isEmpty { port = ports.first ?? "" }
    }
    func refreshPermission() {
        let previouslyAllowed = screenRecordingAllowed
        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
        if screenRecordingAllowed && !previouslyAllowed && !isRunning && !isBusy
            && status.contains("Screen Recording")
        {
            status = "Screen Recording allowed. Ready to start."
        }
    }
    func openScreenRecordingSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }
    func requestScreenPermission() {
        refreshPermission()
        guard !screenRecordingAllowed else { return }
        if hasRequestedPermission {
            openScreenRecordingSettings()
            return
        }
        do {
            try requirePermission()
            status = "Screen access allowed. Turn on the lights when you’re ready."
        } catch {
            status = "Enable ScreenHalo in System Settings, then return and click Check access."
        }
    }
    var startHint: String? {
        if automaticOff { return "Wake and unlock your display to turn on the lights." }
        if !ports.contains(port) { return "Connect your USB strip, then choose it in Setup." }
        if !(1...255).contains(ledCount) { return "Choose between 1 and 255 LEDs in LED layout." }
        if mode == "Screen sync" {
            if !selectionAvailable { return "Choose the display with your lights in Setup." }
            if !screenRecordingAllowed { return "Allow screen access so the lights can follow your display." }
        }
        return nil
    }
    private func requirePermission() throws {
        var allowed = CGPreflightScreenCaptureAccess()
        if !allowed && !hasRequestedPermission {
            hasRequestedPermission = true
            _ = CGRequestScreenCaptureAccess()
            allowed = CGPreflightScreenCaptureAccess()
        }
        screenRecordingAllowed = allowed
        if !allowed {
            throw NSError(
                domain: "ScreenHalo.Permission", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Screen Recording is not allowed. Open Screen Recording Settings, enable ScreenHalo, then Check again. If already enabled, quit and reopen ScreenHalo."
                ])
        }
    }
    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLogin(_ enabled: Bool) {
        guard !loginUpdating else { return }
        loginUpdating = true
        Task {
            defer {
                loginUpdating = false
                refreshLogin()
            }
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch { status = "Login item could not be changed: \(error.localizedDescription)" }
        }
    }
    var selectionAvailable: Bool { displays.contains { $0.id == displayUUID } }
    var canStart: Bool {
        !automaticOff && (mode == "Solid color" || selectionAvailable) && ports.contains(port)
            && (1...255).contains(ledCount)
    }
    private func failureHandler(token: UUID) -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor in
                guard let self, self.sessionID == token else { return }
                await self.stop(reason: message)
                self.refreshPermission()
            }
        }
    }
    private func receiver(token: UUID) -> FrameReceiver {
        let generation = UUID()
        sourceID = generation
        return FrameReceiver(
            layout: layout, depth: edgeDepth,
            onFrame: { [weak self] colors in
                Task { @MainActor in
                    guard let self, self.sessionID == token, self.sourceID == generation else { return }
                    self.latestColors = colors
                    self.startRendering()
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    guard let self, self.sessionID == token, self.sourceID == generation else { return }
                    await self.stop(reason: message)
                    self.refreshPermission()
                }
            })
    }

    func start() {
        guard !isBusy, !isRunning, canStart else { return }
        let display = displays.first(where: { $0.id == displayUUID })
        let screenSync = mode == "Screen sync"
        isBusy = true
        status = "Starting lights…"
        sessionID = UUID()
        let token = sessionID
        let count = ledCount
        let path = port
        renderer = ColorRenderer()
        pendingOutput = nil
        lastPreviewUpdate = 0
        latestColors = []
        startTask = Task {
            var opened: USBStrip?
            var source: ScreenCapture?
            do {
                if screenSync { try requirePermission() }
                try Task.checkCancellation()
                let usb = try USBStrip(path: path, onFailure: failureHandler(token: token))
                opened = usb
                if screenSync {
                    guard let display else { throw missingDisplay() }
                    let screen = ScreenCapture(
                        receiver: receiver(token: token), frameRate: effectiveFrameRate)
                    source = screen
                    try await screen.start(displayID: display.displayID)
                    try Task.checkCancellation()
                    capture = screen
                } else {
                    latestColors = Array(repeating: solidColor, count: count)
                }
                strip = usb
                isRunning = true
                if !isTesting { setupCompleted = true }
                startRendering()
                status = "\(mode) · \(count) LEDs · USB connected"
            } catch {
                await source?.stop()
                await opened?.close(count: count)
                if !Task.isCancelled { status = error.localizedDescription }
            }
            if !Task.isCancelled { isBusy = false }
        }
    }
    private func missingDisplay() -> NSError {
        NSError(
            domain: "ScreenHalo", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Choose a connected display."])
    }

    private func changeMode(from previous: String) {
        guard !isBusy else {
            restoreMode(previous)
            return
        }
        isBusy = true
        let desired = mode
        modeTask = Task {
            var newCapture: ScreenCapture?
            do {
                if desired == "Screen sync" {
                    try requirePermission()
                    guard let display = displays.first(where: { $0.id == displayUUID }) else {
                        throw missingDisplay()
                    }
                    let token = sessionID
                    let source = ScreenCapture(
                        receiver: receiver(token: token), frameRate: effectiveFrameRate)
                    newCapture = source
                    try await source.start(displayID: display.displayID)
                    try Task.checkCancellation()
                    capture = source
                } else {
                    sourceID = UUID()
                    let old = capture
                    capture = nil
                    await old?.stop()
                    try Task.checkCancellation()
                    latestColors = Array(repeating: solidColor, count: ledCount)
                }
                startRendering()
                status = "\(desired) · \(ledCount) LEDs · USB connected"
            } catch {
                await newCapture?.stop()
                if !Task.isCancelled {
                    restoreMode(previous)
                    status = error.localizedDescription
                }
            }
            if !Task.isCancelled { isBusy = false }
        }
    }
    private func restoreMode(_ previous: String) {
        isRestoringMode = true
        mode = previous
        isRestoringMode = false
    }

    func reconnect() {
        guard !isBusy else { return }
        Task {
            let resume = isRunning
            await stop()
            refresh()
            if resume { start() }
        }
    }
    func testPattern() {
        if isTesting {
            testTask?.cancel()
            return
        }
        guard !isBusy else { return }
        let previousMode = mode
        let previousColor = solidColor
        let wasOn = isRunning
        isTesting = true
        testTask = Task {
            defer {
                isTesting = false
                testTask = nil
            }
            do {
                mode = "Solid color"
                while isBusy { try await Task.sleep(for: .milliseconds(10)) }
                try Task.checkCancellation()
                if !isRunning { start() }
                while isBusy { try await Task.sleep(for: .milliseconds(10)) }
                try Task.checkCancellation()
                if isRunning {
                    for color in [RGB(255, 0, 0), RGB(0, 255, 0), RGB(0, 0, 255)] {
                        solidColor = color
                        try await Task.sleep(for: .milliseconds(600))
                        if !isRunning { break }
                    }
                }
            } catch {}
            if let transition = modeTask { await transition.value }
            solidColor = previousColor
            if !wasOn && isRunning { await stop() }
            mode = previousMode
        }
    }

    func setPreviewWindow(_ window: NSWindow?) {
        guard let window else { return }
        previewWindows.add(window)
        if previewObserver == nil {
            previewObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshPreviewIfVisible() }
            }
        }
        refreshPreviewIfVisible()
    }

    private func refreshPreviewIfVisible() {
        guard
            previewWindows.allObjects.contains(where: {
                $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
            }), preview != renderer.output
        else { return }
        preview = renderer.output
        lastPreviewUpdate = Date.timeIntervalSinceReferenceDate
    }

    private func startRendering() {
        guard isRunning, renderTimer == nil, latestColors.count == ledCount else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now(), repeating: .nanoseconds(1_000_000_000 / effectiveFrameRate),
            leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            if let output = self.renderer.update(
                self.latestColors, brightness: self.brightness,
                reversed: self.reversed, smoothing: self.smoothing)
            {
                self.pendingOutput = output
            }
            if let pending = self.pendingOutput, self.strip?.send(pending) == true {
                self.pendingOutput = nil
            }
            if self.renderer.isSettled || Date.timeIntervalSinceReferenceDate - self.lastPreviewUpdate >= 0.2
            {
                self.refreshPreviewIfVisible()
            }
            if self.renderer.isSettled && self.pendingOutput == nil {
                self.renderTimer?.cancel()
                self.renderTimer = nil
            }
        }
        renderTimer = timer
        timer.resume()
    }

    func stop(reason: String = "Lights stopped. LEDs off.", automatic: Bool = false) async {
        if !automatic { resumeAfterAutoOff = false }
        testTask?.cancel()
        if let stopping = stopTask {
            await stopping.value
            return
        }
        sessionID = UUID()
        sourceID = UUID()
        isRunning = false
        renderTimer?.cancel()
        renderTimer = nil
        latestColors = []
        pendingOutput = nil
        isBusy = true
        let pending = startTask
        let transition = modeTask
        startTask = nil
        modeTask = nil
        pending?.cancel()
        transition?.cancel()
        let cleanup = Task {
            await pending?.value
            await transition?.value
            let oldCapture = capture
            let oldStrip = strip
            capture = nil
            strip = nil
            await oldCapture?.stop()
            await oldStrip?.close(count: ledCount)
            renderer = ColorRenderer()
            preview = []
            isBusy = false
            status = reason
            stopTask = nil
        }
        stopTask = cleanup
        await cleanup.value
    }
}
