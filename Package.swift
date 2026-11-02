// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "IntelligentTouchpadCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GestureCore", targets: ["GestureCore"])],
    targets: [
        .target(name: "GestureCore", path: "IntelligentTouchpad", exclude: ["NativeGlassSurface.swift", "MyApp.swift", "ContentView.swift", "Preferences.swift", "AppModel.swift", "HUDController.swift", "InputGuard.swift", "MultitouchInput.swift", "SystemActions.swift", "Assets.xcassets"], sources: ["GestureEngine.swift"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"], path: "Tests")
    ]
)
