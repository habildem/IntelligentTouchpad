import SwiftUI
import Combine

@MainActor final class Preferences: ObservableObject {
    @Published var gestures: GestureSettings {
        didSet {
            if let data = try? JSONEncoder().encode(gestures) { defaults.set(data, forKey: "gestureSettings.v1") }
        }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gestures = defaults.data(forKey: "gestureSettings.v1").map { data in
            guard let text = String(data: data, encoding: .utf8) else { return data }
            return Data(text.replacingOccurrences(of: "menuBarEnabled", with: "controlCenterEnabled").utf8)
        }
            .flatMap { try? JSONDecoder().decode(GestureSettings.self, from: $0) } ?? GestureSettings()
    }
    var colorScheme: ColorScheme? {
        switch gestures.appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
