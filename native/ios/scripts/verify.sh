#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p DerivedData/evidence
if [ "${RESEARCH_ONLY:-false}" = true ]; then
  swift test --package-path Packages/StereoCore 2>&1 | tee DerivedData/evidence/swift-tests.log
  bash scripts/verify-research.sh
  exit 0
fi
# FOA AudioDataOutput is an iOS 26 SDK API, even with an older deployment target.
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${sdk_version%%.*}" -lt 26 ]; then
  for xcode_path in /Applications/Xcode*.app/Contents/Developer; do
    candidate_sdk=$(DEVELOPER_DIR="$xcode_path" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)
    if [ -n "$candidate_sdk" ] && [ "${candidate_sdk%%.*}" -ge 26 ]; then
      export DEVELOPER_DIR="$xcode_path"
      break
    fi
  done
fi
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${sdk_version%%.*}" -lt 26 ]; then echo "iOS 26 SDK required for FOA capture" >&2; exit 2; fi
xcodebuild -version | tee DerivedData/evidence/toolchain.txt
printf 'iPhoneOS SDK %s\n' "$sdk_version" >> DerivedData/evidence/toolchain.txt
# Manual development builds run the current fix and critical capture lifecycle
# checks first. Automatic PR/main runs retain the complete regression suite.
ui_scope="${NATIVE_UI_SCOPE:-full}"
if [ "${GITHUB_EVENT_NAME:-}" = "workflow_dispatch" ] && [ -z "${NATIVE_UI_SCOPE:-}" ]; then
  ui_scope=focused
fi
ui_args=(-parallel-testing-enabled NO)
case "$ui_scope" in
  full) ;;
  focused)
    for test_name in \
      testFOAHeatmapWithoutSixStepCalibration \
      testFOASilenceClearsHeatmap \
      testIsolatedFOACandidatesStayHiddenAndTimelineIsAvailable \
      testCompactFOACameraKeepsScreenAwakeAndRestoresOnStopAndBackground \
      testPreviousReportSurvivesRestart \
      testResearchRecordingDefaultOffAndSharedArchive \
      testResearchBackgroundFinalizesAndOptInResetsAfterRelaunch \
      testFullscreenCameraControlsAndBackgroundRelease \
      testOutputOverrideWithChangedInputStillStopsCameraAndAudio \
      testSharingStopsCapture; do
      ui_args+=("-only-testing:SoundFieldStereoUITests/CaptureUITests/$test_name")
    done ;;
  *) echo "Unknown NATIVE_UI_SCOPE: $ui_scope" >&2; exit 2 ;;
esac
printf '%s\n' "$ui_scope" > DerivedData/evidence/ui-test-scope.txt
swift test --package-path Packages/StereoCore 2>&1 | tee DerivedData/evidence/swift-tests.log
bash scripts/verify-research.sh
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
  "${ui_args[@]}" \
  -derivedDataPath DerivedData -resultBundlePath DerivedData/evidence/NativeUI.xcresult \
  CODE_SIGNING_ALLOWED=NO test \
  > DerivedData/evidence/simulator-tests.log 2>&1 || test_status=$?

# The UI tests already capture the running camera overlay and comparison with
# explicit synthetic banners. Export failures too; avoid booting another copy
# of the simulator merely to capture the inactive launch screen.
xcrun xcresulttool export attachments --path DerivedData/evidence/NativeUI.xcresult \
  --output-path DerivedData/evidence/attachments || true
app_data=$(xcrun simctl get_app_container "$device_id" dev.soundfield.stereo data)
cli="$(swift build --package-path Packages/StereoCore -c release --show-bin-path)/foa-replay"
python3 scripts/verify-app-research.py "$app_data" "$cli" --inspect-only
if [ "$test_status" -ne 0 ]; then
  tail -150 DerivedData/evidence/simulator-tests.log
  exit "$test_status"
fi

# Re-open the files actually produced by the simulator UI recording path.
"${TMPDIR:-/tmp}/soundfield-schema-env/bin/python" scripts/verify-app-research.py "$app_data" "$cli"

# The user can re-sign this device build on Windows. It is not installable by
# opening a Safari link, and contains no certificate or provisioning profile.
python3 scripts/package-unsigned-ipa.py
echo "Native verification passed ($ui_scope UI suite). Physical microphone behavior still needs an iPhone test."
