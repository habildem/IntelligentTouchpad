import AppKit
import CoreAudio
import ApplicationServices
import Darwin

@MainActor final class SystemActions {
    private var displayLibrary: UnsafeMutableRawPointer?
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private var getBrightness: GetBrightness?
    private var setBrightness: SetBrightness?
    init() {
        displayLibrary = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        if let displayLibrary {
            getBrightness = dlsym(displayLibrary, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
            setBrightness = dlsym(displayLibrary, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
        }
    }
    private func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr && device != 0 ? device : nil
    }
    private func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
    private func channels(_ device: AudioDeviceID) -> [UInt32] {
        var main = volumeAddress(kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { var address = volumeAddress(UInt32($0)); return AudioObjectHasProperty(device, &address) }.map(UInt32.init)
    }
    func volume() -> Double? {
        guard let device = outputDevice() else { return nil }
        let levels = channels(device).compactMap { channel -> Float? in
            var address = volumeAddress(channel), value: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        return levels.isEmpty ? nil : Double(levels.reduce(0,+) / Float(levels.count))
    }
    func changeVolume(_ delta: Double) -> Double? {
        guard let device = outputDevice(), let current = volume() else { return nil }
        var value = Float(min(1, max(0, current + delta)))
        let elements = channels(device)
        guard !elements.isEmpty else { return nil }
        // Verify all channels before changing any of them.
        for element in elements {
            var address = volumeAddress(element), settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
        }
        for element in elements {
            var address = volumeAddress(element)
            guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value) == noErr else { return nil }
        }
        if value > 0 { _ = setMute(false, device: device) }
        return Double(value)
    }
    func toggleMute() -> Bool? {
        guard let device = outputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        let muted = value == 0
        return setMute(muted, device: device) ? muted : nil
    }
    private func setMute(_ muted: Bool, device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
    private func builtInDisplay() -> CGDirectDisplayID? {
        NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            return CGDisplayIsBuiltin(id) != 0 ? id : nil
        }.first
    }
    func brightness() -> Double? {
        guard let display = builtInDisplay(), let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? Double(value) : nil
    }
    func changeBrightness(_ delta: Double) -> Double? {
        guard let display = builtInDisplay(), let current = brightness(), let setBrightness else { return nil }
        let value = Float(min(1, max(0, current + delta)))
        return setBrightness(display, value) == 0 ? Double(value) : nil
    }
    func mediaKey(_ code: Int) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                                data1: (code << 16) | ((down ? 0xa : 0xb) << 8), data2: -1)?.cgEvent else { return false }
            event.post(tap: .cghidEventTap)
        }
        return true // Command delivered; the active player's response is not observable here.
    }
    /// Finds the system-owned Control Center item by identifier, not by locale or
    /// screen coordinates. macOS 27 hosts it in MenuBarAgent; older releases in ControlCenter.
    func openControlCenter() -> Bool {
        if controlCenterIsOpen() { return true }
        return pressControlCenter()
    }
    func closeControlCenter() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        // A closed center must stay closed: never blindly toggle its menu item.
        guard controlCenterIsOpen() else { return true }
        return pressControlCenter()
    }
    func controlCenterIsOpen() -> Bool {
        guard let owner = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let app = AXUIElementCreateApplication(owner.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let elements = windows as? [AXUIElement] else { return false }
        return !elements.isEmpty
    }
    private func pressControlCenter() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let owners = NSWorkspace.shared.runningApplications.filter {
            ["com.apple.controlcenter", "com.apple.systemuiserver"].contains($0.bundleIdentifier ?? "") ||
            $0.executableURL?.lastPathComponent == "MenuBarAgent"
        }.sorted { ($0.executableURL?.lastPathComponent == "MenuBarAgent" ? 0 : 1) < ($1.executableURL?.lastPathComponent == "MenuBarAgent" ? 0 : 1) }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        for owner in owners {
            let app = AXUIElementCreateApplication(owner.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.08)
            var queue: [(AXUIElement, Int)] = [(app, 0)]
            var visited = 0
            while !queue.isEmpty, visited < 120, ProcessInfo.processInfo.systemUptime < deadline {
                let (element, depth) = queue.removeFirst(); visited += 1
                var identifier: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success,
                   identifier as? String == "com.apple.menuextra.controlcenter" {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                }
                guard depth < 4 else { continue }
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let elements = children as? [AXUIElement] {
                    queue.append(contentsOf: elements.map { ($0, depth+1) })
                }
            }
        }
        return false
    }
}
