"""Package only the verified Release iPhoneOS app for user-side signing."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / "DerivedData/Build/Products/Release-iphoneos/SoundFieldStereo.app"
with (app / "Info.plist").open("rb") as source:
    info = plistlib.load(source)
if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
    raise SystemExit("Refusing to package a non-device build")
if (app / "embedded.mobileprovision").exists():
    raise SystemExit("This artifact must not contain a personal provisioning profile")
binary = app / info["CFBundleExecutable"]
if not binary.is_file() or binary.stat().st_size == 0:
    raise SystemExit("Missing app executable")
output = root / "DerivedData/evidence/SoundFieldStereo-unsigned.ipa"
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        if path.is_file():
            archive.write(path, Path("Payload/SoundFieldStereo.app") / path.relative_to(app))
with zipfile.ZipFile(output) as archive:
    if archive.testzip() is not None:
        raise SystemExit("IPA CRC verification failed")
    packaged = plistlib.loads(archive.read("Payload/SoundFieldStereo.app/Info.plist"))
    assert packaged["CFBundleIdentifier"] == info["CFBundleIdentifier"]
metadata = {
    "artifact": output.name,
    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    "bytes": output.stat().st_size,
    "sourceCommit": os.environ.get("GITHUB_SHA") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "bundleIdentifier": info["CFBundleIdentifier"],
    "minimumOSVersion": info["MinimumOSVersion"],
    "platform": "iPhoneOS",
    "configuration": "Release",
    "signing": "unsigned; user must sign before installation",
    "physicalInstallationVerified": False,
}
(output.parent / "ipa-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, indent=2))
