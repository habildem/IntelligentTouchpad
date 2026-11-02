import SwiftUI
import Combine
@preconcurrency import ApplicationServices
import ServiceManagement

@MainActor final class AppModel: ObservableObject {
    let preferences = Preferences()
    @Published var trusted = false
    @Published var connected = false
    @Published var inputProtected = false
    @Published var deviceStatus = "Starting"
    @Published var volume: Double?
    @Published var brightness: Double?
    @Published var lastAction = "Slide along an edge to get started"
    @Published var issue: String?
    @Published var touchPoints: [TouchPoint] = []
    @Published var loginEnabled = false
    let hud = HUDController()
    private let input = MultitouchInput()
    private let inputGuard = InputGuard()
    private let actions = SystemActions()
    private var engine = GestureEngine()
    private var timer: Timer?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var lastHaptic = 0.0
    private var lastVisualFrame = 0.0
    private var clickCancelled = false
    private var sleeping = false
    private var centerOpen = false
    private var centerCheck = 0.0
    var panelVisible = false

    var ready: Bool { trusted && connected && inputProtected }
    var status: String {
        if !preferences.gestures.enabled { return "Paused" }
        if !trusted { return "Permission required" }
        if !connected { return "No trackpad" }
        if !inputProtected { return "Input permission required" }
        return "Ready"
    }
    func start() {
        input.onFrame = { [weak self] points, time in self?.receive(points, time: time) }
        inputGuard.onClick = { [weak self] in
            self?.clickCancelled = true
            self?.engine.reset()
        }
        subscription = preferences.$gestures.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.engine.reset(); self.inputGuard.releaseCapture()
            self.clickCancelled = true
        }
        refresh(reconnect: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true; self?.stopInput()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = false; self?.refresh(reconnect: true)
            }
        })
    }
    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        stopInput()
    }
    private func stopInput() {
        input.stop(); inputGuard.stop(); engine.reset()
        connected = false; inputProtected = false; touchPoints = []
    }
    func refresh(reconnect: Bool = false) {
        guard !sleeping else { return }
        let permission = AXIsProcessTrusted()
        let changed = trusted != permission
        trusted = permission
        if !permission { stopInput(); deviceStatus = "Waiting for Accessibility permission" }
        else if changed || reconnect {
            connected = input.start()
            deviceStatus = input.status
            inputProtected = inputGuard.start()
            if !inputProtected { issue = "Could not start input protection. Check Accessibility permission in System Settings and try again." }
            else { issue = nil }
        }
        if panelVisible || reconnect {
            volume = actions.volume(); brightness = actions.brightness()
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                issue = "Approve launch at login in System Settings → General → Login Items."
            }
        } catch { issue = "Could not configure launch at login: \(error.localizedDescription)" }
    }
    private func receive(_ points: [TouchPoint], time: Double) {
        guard ready else { inputGuard.releaseCapture(); return }
        inputGuard.lastFrame = ProcessInfo.processInfo.systemUptime
        if points.isEmpty { clickCancelled = false; hud.endInteraction() }
        let flags = NSEvent.modifierFlags
        let config = preferences.gestures
        let modifierOK = config.modifier == .none || (config.modifier == .option && flags.contains(.option)) || (config.modifier == .fn && flags.contains(.function))
        if points.count == 2, points.allSatisfy({ $0.x >= 0.72 }), time-centerCheck > 0.2 {
            centerOpen = actions.controlCenterIsOpen()
            centerCheck = time
        }
        let output = engine.process(points, time: time, settings: config, modifierSatisfied: modifierOK,
                                    precise: flags.contains([.shift, .option]), mouseDown: clickCancelled || NSEvent.pressedMouseButtons != 0, controlCenterOpen: centerOpen)
        inputGuard.freezePointer = engine.capturesPointer
        inputGuard.suppressScroll = engine.capturesScroll
        if panelVisible && (time - lastVisualFrame > 1/30 || points.isEmpty) {
            touchPoints = points; lastVisualFrame = time
        }
        output.forEach(perform)
    }
    private func perform(_ action: GestureAction) {
        var symbol = "checkmark", value: Double?
        var shouldTick = true
        switch action {
        case .volume(let delta):
            let before = actions.volume()
            guard let level = actions.changeVolume(delta) else { fail("This audio output does not support software volume control."); return }
            shouldTick = LevelFeedback.shouldTick(from: before, to: level)
            volume = level; value = level; symbol = "speaker.wave.2.fill"; lastAction = "Volume"
        case .brightness(let delta):
            let before = actions.brightness()
            guard let level = actions.changeBrightness(delta) else { fail("Cannot access built-in display brightness. External displays are not supported."); return }
            shouldTick = LevelFeedback.shouldTick(from: before, to: level)
            brightness = level; value = level; symbol = "sun.max.fill"; lastAction = "Brightness"
        case .mute:
            guard let muted = actions.toggleMute() else { fail("This audio output does not support mute."); return }
            symbol = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"; value = muted ? 0 : actions.volume()
        case .nextTrack, .previousTrack, .playPause:
            let code = action == .nextTrack ? 17 : action == .previousTrack ? 18 : 16
            guard actions.mediaKey(code) else { fail("Could not send media command. Check Accessibility permission."); return }
            symbol = action == .nextTrack ? "forward.end.fill" : action == .previousTrack ? "backward.end.fill" : "playpause.fill"
            lastAction = ""
        case .openControlCenter:
            inputGuard.releaseCapture()
            guard actions.openControlCenter() else { fail("Could not open Control Center. Check Accessibility permission."); return }
            symbol = "switch.2"; lastAction = ""
        case .closeControlCenter:
            inputGuard.releaseCapture()
            guard actions.closeControlCenter() else { fail("Could not close Control Center."); return }
            symbol = "switch.2"; lastAction = ""
        }
        issue = nil
        if preferences.gestures.showHUD, let value { hud.show(symbol: symbol, value: value) }
        let now = ProcessInfo.processInfo.systemUptime
        if preferences.gestures.haptics && shouldTick && now-lastHaptic > 0.12 {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            lastHaptic = now
        }
    }
    private func fail(_ text: String) {
        if issue != text {
            issue = text
        }
    }
}
