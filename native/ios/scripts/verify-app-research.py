"""Verify real app recording lifecycle on synthetic simulator input before IPA."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import zipfile

container = Path(sys.argv[1])
cli = sys.argv[2]
evidence = Path("DerivedData/evidence/research/app")
evidence.mkdir(parents=True, exist_ok=True)
manifests = list((container / "Documents/ResearchSessions").glob("*/manifest.json"))
assert len(manifests) >= 2, "Stop and background must each create a complete session"
rows = []
for path in manifests:
    manifest = json.loads(path.read_text())
    assert manifest["synthetic"], "CI never uploads a user's real recording"
    folder = path.parent
    result = evidence / (folder.name + "-replay.json")
    subprocess.run([cli, str(folder), "--output", str(result)], check=True)
    report = evidence / (folder.name + "-verification.json")
    subprocess.run([sys.executable, "scripts/validate-research.py", str(folder), str(result), str(report)], check=True)
    (evidence / (folder.name + "-manifest.json")).write_bytes(path.read_bytes())
    rows.append({"sessionID": folder.name, "stopReason": manifest["stopReason"],
                 "frames": manifest["foaFrames"], "analyzedWindows": manifest["analyzedWindows"]})
assert any(row["stopReason"] == "enteredBackground" for row in rows)
archives = list((container / "tmp").glob("SoundField-research-*.zip"))
assert archives, "The app share action must produce an actual ZIP"
for path in archives:
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["synthetic"]
        names = {"manifest.json"} | {f["name"] for f in manifest["files"]}
        assert set(archive.namelist()) == names
        import hashlib
        for entry in manifest["files"]:
            data = archive.read(entry["name"])
            assert len(data) == entry["bytes"]
            assert hashlib.sha256(data).hexdigest() == entry["sha256"]
        shutil.copyfile(path, evidence / ("synthetic-shared-" + manifest["sessionID"] + ".zip"))
report = {
    "schemaVersion": 1, "sourceCommit": os.environ["GITHUB_SHA"],
    "ciRunURL": "https://github.com/doroper98/sound_detection/actions/runs/" + os.environ["GITHUB_RUN_ID"],
    "appRecordingLifecycleVerified": True, "syntheticOnly": True,
    "completedSessions": rows, "sharedArchivesVerified": len(archives),
    "realDeviceAccuracyVerified": False
}
(evidence / "app-recording-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
