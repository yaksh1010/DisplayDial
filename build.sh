#!/bin/bash
# Builds DisplayDial.app as a universal (Apple Silicon + Intel) app.
#
#   ./build.sh             build into build/DisplayDial.app
#   ./build.sh --install   also copy it to /Applications and launch it
#   ./build.sh --dmg       also make dist/DisplayDial.dmg for sharing
#
# Set SIGN_IDENTITY to a certificate name (see `security find-identity -p codesigning`)
# to keep the same identity across rebuilds. Without it the app is ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DisplayDial.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
    -import-objc-header Sources/PrivateAPI.h \
    Sources/*.swift \
    -framework AppKit -framework SwiftUI -framework IOKit -framework Carbon -framework ServiceManagement \
    -o "build/DisplayDial-$ARCH"
done
lipo -create build/DisplayDial-arm64 build/DisplayDial-x86_64 -output "$APP/Contents/MacOS/DisplayDial"
rm build/DisplayDial-arm64 build/DisplayDial-x86_64

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP ($VERSION)"

for ARG in "$@"; do
  case "$ARG" in
    --install)
      pkill -x DisplayDial 2>/dev/null && sleep 1 || true
      rm -rf /Applications/DisplayDial.app
      cp -R "$APP" /Applications/
      open /Applications/DisplayDial.app
      echo "Installed to /Applications/DisplayDial.app"
      ;;
    --dmg)
      STAGE=build/dmg
      mkdir -p "$STAGE" dist
      cp -R "$APP" "$STAGE/"
      ln -s /Applications "$STAGE/Applications"
      rm -f dist/DisplayDial.dmg
      hdiutil create -volname "DisplayDial $VERSION" -srcfolder "$STAGE" -ov -format UDZO dist/DisplayDial.dmg >/dev/null
      rm -rf "$STAGE"
      echo "Made dist/DisplayDial.dmg"
      ;;
  esac
done
