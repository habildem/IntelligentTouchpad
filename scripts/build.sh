#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project IntelligentTouchpad.xcodeproj -scheme IntelligentTouchpad \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO build
# Use a stable development identity to preserve Accessibility consent between builds.
# For another developer's Mac, set TOUCHPAD_SIGN_IDENTITY to their identity or '-'.
signing_identity="${TOUCHPAD_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$signing_identity" .build/Build/Products/Debug/IntelligentTouchpad.app
codesign --verify --deep --strict .build/Build/Products/Debug/IntelligentTouchpad.app
