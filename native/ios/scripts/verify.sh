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
test_status=0
xcodebuild -project SoundFieldStereo.xcodeproj -scheme SoundFieldStereo \
  -configuration Debug -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath DerivedData -resultBundlePath DerivedData/evidence/NativeUI.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test \
  > DerivedData/evidence/simulator-tests.log 2>&1 || test_status=$?

# The UI tests already capture the running camera overlay and comparison with
# explicit synthetic banners. Export failures too; avoid booting another copy
# of the simulator merely to capture the inactive launch screen.
xcrun xcresulttool export attachments --path DerivedData/evidence/NativeUI.xcresult \
  --output-path DerivedData/evidence/attachments || true
if [ "$test_status" -ne 0 ]; then
  tail -150 DerivedData/evidence/simulator-tests.log
  exit "$test_status"
fi

# The user can re-sign this device build on Windows. It is not installable by
# opening a Safari link, and contains no certificate or provisioning profile.
python3 scripts/package-unsigned-ipa.py
echo 'Native verification passed. Physical microphone behavior still needs an iPhone test.'
