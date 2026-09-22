#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p DerivedData/evidence
swift test --package-path Packages/StereoCore 2>&1 | tee DerivedData/evidence/swift-tests.log
plutil -lint SoundFieldStereo/Info.plist SoundFieldStereo.xcodeproj/project.pbxproj
xcodebuild -project SoundFieldStereo.xcodeproj -scheme SoundFieldStereo \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build \
  > DerivedData/evidence/device-build.log 2>&1 || { tail -100 DerivedData/evidence/device-build.log; exit 1; }

# Use an installed iPhone simulator, avoiding a hard-coded model/runtime.
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
data=json.load(sys.stdin)
phones=[d for runtime,devices in data["devices"].items() if "iOS" in runtime for d in devices if d["name"].startswith("iPhone") and d.get("isAvailable")]
if not phones: raise SystemExit("No available iPhone simulator")
print(phones[0]["udid"])
')
xcodebuild -project SoundFieldStereo.xcodeproj -scheme SoundFieldStereo \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath DerivedData -resultBundlePath DerivedData/evidence/NativeUI.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test \
  > DerivedData/evidence/simulator-tests.log 2>&1 || { tail -150 DerivedData/evidence/simulator-tests.log; exit 1; }

# Native screenshot contains an explicit synthetic-fixture banner.
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" DerivedData/Build/Products/Debug-iphonesimulator/SoundFieldStereo.app
xcrun simctl launch "$device_id" dev.soundfield.stereo --synthetic-stereo
xcrun simctl io "$device_id" screenshot DerivedData/evidence/native-start.png
xcrun xcresulttool export attachments --path DerivedData/evidence/NativeUI.xcresult \
  --output-path DerivedData/evidence/attachments || true
echo 'Native verification passed. Physical microphone behavior still needs an iPhone test.'
