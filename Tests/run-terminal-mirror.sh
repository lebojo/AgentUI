#!/bin/bash
# Run after macOS + iOS Simulator Debug builds using these derived-data directories.
set -euo pipefail
cd "$(dirname "$0")/.."
mac_build="${1:-/tmp/heka-mobile-build}/Build/Products/Debug"
ios_build="${2:-/tmp/heka-ios-build}/Build/Products/Debug-iphonesimulator"
fixture="$(mktemp -d -t heka-mirror-tests)"
simulator=""
cleanup() {
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
  rm -rf "$fixture"
}
trap cleanup EXIT
xcrun swiftc -parse-as-library -I "$mac_build" \
  Heka/Core/Session/TerminalMirrorModes.swift Heka/Core/Session/TerminalScreen.swift \
  Tests/TerminalMirrorTests.swift "$mac_build/SwiftTerm.o" -o "$fixture/mirror-tests"
"$fixture/mirror-tests"
app="$fixture/MobileTerminalTests.app"
mkdir -p "$app"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>test.heka.terminal-mirror</string>
<key>CFBundleName</key><string>Mirror tests</string>
<key>CFBundleExecutable</key><string>MobileTerminalTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict></plist>
PLIST
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SDKROOT="$sdk" xcrun swiftc -parse-as-library -target arm64-apple-ios17.0-simulator -sdk "$sdk" -I "$ios_build" \
  Heka/Models/Data/SessionMessage.swift Heka/Models/Data/RemoteTerminalSnapshot.swift Heka/Models/Data/TerminalGridSize.swift \
  Heka/Models/TerminalAppearance.swift Heka/Models/TerminalTheme.swift \
  Heka/Platforms/iOS/MobileTerminalView.swift Heka/Views/MobileWorkspaceView/MobileTerminalViewport/MobileTerminalViewport.swift Heka/Views/MobileWorkspaceView/MobileTerminalViewport/MobileTerminalCanvas.swift Heka/Platforms/iOS/MobileTerminalScrollView.swift Tests/MobileTerminalTests.swift \
  "$ios_build/SwiftTerm.o" -o "$app/MobileTerminalTests"
cp -R "$ios_build/SwiftTerm_SwiftTerm.bundle" "$app/"
codesign --force --sign - "$app" >/dev/null
# A disposable simulator keeps this run isolated from the user's running devices.
device=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro
runtime="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in reversed(json.load(sys.stdin)["runtimes"]) if r["isAvailable"] and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and any(d["identifier"] == sys.argv[1] for d in r.get("supportedDeviceTypes", []))))' "$device")"
simulator="$(xcrun simctl create Heka-Mirror-Regression "$device" "$runtime")"
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b >/dev/null
xcrun simctl install "$simulator" "$app"
xcrun simctl launch "$simulator" test.heka.terminal-mirror >/dev/null
container="$(xcrun simctl get_app_container "$simulator" test.heka.terminal-mirror data)"
for ((attempt=0; attempt<45; attempt++)); do
  if [[ -f "$container/Documents/result.txt" ]]; then
    cat "$container/Documents/result.txt"
    if grep -q '^FAIL' "$container/Documents/result.txt"; then exit 1; fi
    exit 0
  fi
  sleep 1
done
echo 'FAIL: Simulator test app did not report a result' >&2
exit 1
