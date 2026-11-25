#!/bin/zsh
# Build "Mac Intel Local AI.app" with the Command Line Tools (no Xcode needed).
#   ./build.sh           build into ./build
#   ./build.sh install   also copy to ~/Applications and open it
set -e
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
version_pattern='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
build_pattern='^[0-9]+$'
if ! [[ "$APP_VERSION" =~ $version_pattern && "$APP_BUILD_NUMBER" =~ $build_pattern ]]; then
  echo "Invalid app version or build number" >&2; exit 1
fi
D="$(cd "$(dirname $0)" && pwd)"
APP="$D/build/Mac Intel Local AI.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
# Some Command Line Tools releases ship both module.modulemap and
# bridging.modulemap defining SwiftBridging ("redefinition of module").
# Hide the duplicate for this build only, without touching the system files.
CLT_SWIFT_INC="$(dirname "$(xcrun -f swiftc)")/../include/swift"
OVERLAY=()
if [ -f "$CLT_SWIFT_INC/module.modulemap" ] && [ -f "$CLT_SWIFT_INC/bridging.modulemap" ]; then
  mkdir -p "$D/build/vfs"; : > "$D/build/vfs/empty.modulemap"
  INC="$(cd "$CLT_SWIFT_INC" && pwd -P)"
  cat > "$D/build/vfs/overlay.yaml" <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$INC",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$D/build/vfs/empty.modulemap" } ] } ] }
YAML
  OVERLAY=(-vfsoverlay "$D/build/vfs/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$D/build/vfs/overlay.yaml")
fi
swiftc -swift-version 5 -O -parse-as-library -target x86_64-apple-macos13.0 "${OVERLAY[@]}" \
  "$D/Sources/MacIntelLocalAI.swift" -o "$APP/Contents/MacOS/MacIntelLocalAI"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.github.jirbis.mac-intel-local-ai</string>
  <key>CFBundleName</key><string>Mac Intel Local AI</string>
  <key>CFBundleExecutable</key><string>MacIntelLocalAI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "built: $APP"
if [ "$1" = install ]; then
  mkdir -p ~/Applications
  pkill -x MacIntelLocalAI 2>/dev/null || true
  rm -rf ~/Applications/"Mac Intel Local AI.app"; cp -R "$APP" ~/Applications/
  open ~/Applications/"Mac Intel Local AI.app"; echo "installed: ~/Applications/Mac Intel Local AI.app"
fi
