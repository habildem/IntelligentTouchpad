import Foundation

@main struct HardwareProbe {
    @MainActor static func main() {
        let input = MultitouchInput()
        var frames = 0
        input.onFrame = { _, _ in frames += 1 }
        let started = input.start()
        print("Input adapter started: \(started); \(input.status)")
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        input.stop()
        let actions = SystemActions()
        print("Frames observed: \(frames)")
        print("Volume readable: \(actions.volume() != nil)")
        print("Built-in brightness readable: \(actions.brightness() != nil)")
    }
}
