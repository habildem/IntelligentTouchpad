# IntelligentTouchpad
<!-- impeccable:product-schema 1 -->
## Platform
Native macOS (SwiftUI + AppKit).
## Users and purpose
A Mac trackpad utility requested by the owner of this repository. Control volume, brightness and media from trackpad edges without interrupting work.
## Confirmed requirements
EdgeBar is the functional and visual reference. Every gesture feature must have its own persistent enable switch, especially the left and right edges. All controls require TWO fingers, including edge slides, media tap/swipe and double-tap mute. A top-right two-finger downward swipe opens macOS Control Center (Wi-Fi/Bluetooth panel); an upward swipe closes it, including reversal within the same touch session. User clarified that the earlier menu-bar interpretation was incorrect.
## Constraints
Preserve normal center-trackpad input. Media tap defaults off. No payment, license server or update infrastructure requested. Hardware integration must report unavailable features truthfully. Private macOS APIs require direct distribution and compatibility testing.
## Evidence
User report: EdgeBar product report supplied by the user. Reference: https://edgebar.xyz/ . Only starter SwiftUI files existed.
## Open decisions
Commercial distribution, signing identity, supported external displays and tested hardware matrix.
