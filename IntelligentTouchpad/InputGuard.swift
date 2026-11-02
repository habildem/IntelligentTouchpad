import AppKit
import ApplicationServices

@MainActor final class InputGuard {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var freezePointer = false
    var suppressScroll = false
    var lastFrame = ProcessInfo.processInfo.systemUptime
    var onClick: (() -> Void)?
    func start() -> Bool {
        stop()
        let types: [CGEventType] = [.mouseMoved, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let suppress = MainActor.assumeIsolated {
                let owner = Unmanaged<InputGuard>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    owner.releaseCapture()
                    if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return false
                }
                if ProcessInfo.processInfo.systemUptime - owner.lastFrame > 0.25 { owner.releaseCapture() }
                if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                    owner.releaseCapture(); owner.onClick?()
                }
                if (type == .mouseMoved && owner.freezePointer) || (type == .scrollWheel && owner.suppressScroll) { return true }
                return false
            }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func releaseCapture() { freezePointer = false; suppressScroll = false }
    func stop() {
        releaseCapture()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
}
