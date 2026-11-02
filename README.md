# IntelligentTouchpad

An English-language macOS trackpad utility built with SwiftUI and AppKit. It lives in the menu bar instead of the Dock. The app targets macOS 14 and later; physical compatibility has only been partially verified on the developer's Mac.

## Getting started

1. Build with `./scripts/build.sh`. The Xcode project uses the Xcode 27 format.
2. Open `.build/Build/Products/Debug/IntelligentTouchpad.app`.
3. Use **Open System Settings** in the app to grant access under **Privacy & Security → Accessibility**. Gestures do not work without this permission. macOS may ask for permission again if the app's signature changes.
4. Check that the panel shows **Ready**. During normal use, close the window and reopen the panel using the hand icon in the menu bar.

**All controls require two fingers.** A single finger moves the pointer normally.

| Gesture | Action |
| --- | --- |
| Slide two fingers up or down along the left edge | Adjust built-in display brightness |
| Slide two fingers up or down along the right edge | Adjust volume |
| Swipe down with two fingers from the top-right corner | Open **Control Center**, which contains Wi-Fi and Bluetooth controls |
| Swipe up with two fingers in the top-right area | Close Control Center; reversing direction during the same gesture also works |
| Double-tap the top-right corner with two fingers | Mute or unmute |
| Swipe left or right with two fingers along the bottom edge | Previous or next track |
| Tap the bottom edge with two fingers | Play or pause; disabled by default |

The left edge, right edge, Control Center, mute, media swipes, and media tap can each be turned off independently. Settings include swapping sides, limiting gestures to the bottom quarter, requiring Option or Fn, sensitivity, edge width, fine control with Shift+Option, cursor freezing, haptics, the on-screen display, appearance, and launch at login. Preferences are stored locally in UserDefaults.

## Architecture and scope

- `GestureEngine.swift`: a system-independent two-finger state machine. It locks the initial region and cancels on a third finger, click, or settings change. It allows the second finger to land within 180 ms. To accommodate two fingers, one can be in the narrow edge strip while the other is nearby.
- `MultitouchInput.swift`: a dynamically loaded MultitouchSupport adapter using a 96-byte touch ABI. The built-in trackpad is preferred; one device is used at a time. This is a private Apple API, so compatibility across OS versions is not guaranteed.
- `InputGuard.swift`: suppresses scrolling and pointer events only for captured gestures. It does not consume normal clicks and releases input on timeout or loss of permission.
- `SystemActions.swift`: CoreAudio, DisplayServices for the built-in display, media keys, and an accessibility press on `com.apple.menuextra.controlcenter`. It supports macOS 27's MenuBarAgent and the ControlCenter process on earlier releases.
- A SwiftUI panel and a custom on-screen display. The app does not replicate Apple's private system OSD.

External display brightness/DDC, licensing and payments, an automatic update service, Mac App Store distribution, and notarization are not included in this version. Haptics use NSHapticFeedbackManager for light feedback on supported hardware. Media commands are sent to the active player; whether it handles them is outside the app's control. Launch at login uses SMAppService and may require approval in System Settings. After changing devices, use **Reconnect Trackpad** in the panel; the app also reconnects after sleep and wake.

## Tests

```sh
swift test --scratch-path .build-tests
```

The gesture tests cover single-finger input, independent edge switches, movement from the center to an edge, two-finger landing and lifting, the Control Center region, double taps, media defaults and single-command behavior, fine control, side swapping, the bottom-quarter option, and cancellation on a third finger, click, modifier, or master switch.

`scripts/HardwareProbe.swift` checks only the device adapter, the number of frames received, and whether volume and brightness can be read. It does not change settings or record raw touches. The app makes no network requests and does not collect analytics or record touches.
