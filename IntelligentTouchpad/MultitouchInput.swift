import Foundation
import Darwin

/// Isolates the undocumented ABI. No touch history is saved or transmitted.
@MainActor final class MultitouchInput {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
    typealias Register = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    private var library: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var device: UnsafeMutableRawPointer?
    private var unregister: Register?
    private var stopDevice: Stop?
    static weak var active: MultitouchInput?
    var onFrame: (([TouchPoint], Double) -> Void)?
    private(set) var status = "Waiting for trackpad"

    private static let callback: FrameCallback = { _, data, count, timestamp, _ in
        guard count >= 0, count <= 16 else { return }
        var points: [TouchPoint] = []
        if let data {
            for index in 0..<Int(count) {
                // macOS MultitouchSupport's 96-byte Finger record (arm64 / x86_64).
                let record = data.advanced(by: index * 96)
                let state = record.loadUnaligned(fromByteOffset: 20, as: Int32.self)
                guard state == 3 || state == 4 else { continue }
                let x = Double(record.loadUnaligned(fromByteOffset: 32, as: Float.self))
                let y = Double(record.loadUnaligned(fromByteOffset: 36, as: Float.self))
                guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { continue }
                points.append(TouchPoint(id: Int(record.loadUnaligned(fromByteOffset: 16, as: Int32.self)), x: x, y: y))
            }
        }
        let copiedPoints = points
        DispatchQueue.main.async { MultitouchInput.active?.onFrame?(copiedPoints, timestamp) }
    }

    func start() -> Bool {
        stop()
        if library == nil {
            library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL)
        }
        guard let library,
              let listSymbol = dlsym(library, "MTDeviceCreateList"),
              let registerSymbol = dlsym(library, "MTRegisterContactFrameCallback"),
              let unregisterSymbol = dlsym(library, "MTUnregisterContactFrameCallback"),
              let startSymbol = dlsym(library, "MTDeviceStart"),
              let stopSymbol = dlsym(library, "MTDeviceStop"),
              let dimensionsSymbol = dlsym(library, "MTDeviceGetSensorSurfaceDimensions") else {
            status = "The trackpad interface is unavailable on this version of macOS"; return false
        }
        typealias List = @convention(c) () -> Unmanaged<CFArray>?
        typealias Dimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
        typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
        let list = unsafeBitCast(listSymbol, to: List.self)().map { $0.takeRetainedValue() }
        guard let list else { status = "No trackpad found"; return false }
        let dimensions = unsafeBitCast(dimensionsSymbol, to: Dimensions.self)
        let builtIn = dlsym(library, "MTDeviceIsBuiltIn").map { unsafeBitCast($0, to: BuiltIn.self) }
        var candidates: [(UnsafeMutableRawPointer, Bool)] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let candidate = UnsafeMutableRawPointer(mutating: raw)
            var width: Int32 = 0, height: Int32 = 0
            guard dimensions(candidate, &width, &height) == 0, width > 40, height > 30 else { continue }
            candidates.append((candidate, builtIn?(candidate) ?? false))
        }
        guard let selected = candidates.first(where: { $0.1 }) ?? candidates.first else {
            status = "No compatible trackpad found. Connect one and try again."; return false
        }
        deviceList = list
        device = selected.0
        unregister = unsafeBitCast(unregisterSymbol, to: Register.self)
        stopDevice = unsafeBitCast(stopSymbol, to: Stop.self)
        Self.active = self
        unsafeBitCast(registerSymbol, to: Register.self)(selected.0, Self.callback)
        unsafeBitCast(startSymbol, to: Start.self)(selected.0, 0)
        status = selected.1 ? "Built-in trackpad connected" : "External trackpad connected"
        return true
    }
    func stop() {
        if let device { unregister?(device, Self.callback); stopDevice?(device) }
        device = nil
        deviceList = nil
        if Self.active === self { Self.active = nil }
    }
}
