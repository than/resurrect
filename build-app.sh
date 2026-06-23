#!/usr/bin/env bash
# Build `res` in release mode and assemble Res.app by hand (no Xcode).
# Idempotent / re-runnable. Start-at-login is managed inside the app via
# SMAppService ("Start at Login" in the menu / first-run prompt) — not a
# LaunchAgent — so this script no longer installs one.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXE_NAME="res"
APP_NAME="Resurrect.app"
APP="$HERE/$APP_NAME"
BUNDLE_ID="com.than.resurrect"
ICNS="$HERE/icon/Resurrect.icns"

echo "==> swift build -c release"
swift build -c release --package-path "$HERE"

BUILT_EXE="$HERE/.build/release/$EXE_NAME"
if [[ ! -x "$BUILT_EXE" ]]; then
  echo "ERROR: built executable not found at $BUILT_EXE" >&2
  exit 1
fi

echo "==> assembling $APP_NAME"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT_EXE" "$APP/Contents/MacOS/$EXE_NAME"
chmod +x "$APP/Contents/MacOS/$EXE_NAME"
[[ -f "$ICNS" ]] && cp "$ICNS" "$APP/Contents/Resources/Resurrect.icns"

cat > "$APP/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Resurrect</string>
    <key>CFBundleDisplayName</key>
    <string>Resurrect</string>
    <key>CFBundleIconFile</key>
    <string>Resurrect</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${EXE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST_EOF

# Ad-hoc sign so the app runs without Gatekeeper friction; ignore if codesign
# is unavailable.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> built bundle: $APP"
echo "==> done."
echo "    App:        $APP"
echo "    Launch:     open \"$APP\""
echo "    Login start: toggle \"Start at Login\" in the menu (SMAppService)."
