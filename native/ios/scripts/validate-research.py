"""Independent schema/hash/container/replay comparison; synthetic CI only."""
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
from jsonschema import Draft202012Validator, FormatChecker

folder = Path(sys.argv[1]).resolve()
result = json.loads(Path(sys.argv[2]).read_text())
schema = json.loads((Path(__file__).resolve().parents[3] / 'docs/schemas/session-manifest.schema.json').read_text())
manifest = json.loads((folder / 'manifest.json').read_text())
Draft202012Validator(schema, format_checker=FormatChecker()).validate(manifest)
required = {'foa.wav', 'pose.jsonl', 'audio-timeline.jsonl', 'analysis.jsonl'}
names = [entry['name'] for entry in manifest['files']]
assert len(set(names)) == len(names) and required.issubset(names)
for entry in manifest['files']:
    data = (folder / entry['name']).read_bytes()
    assert len(data) == entry['bytes']
    assert hashlib.sha256(data).hexdigest() == entry['sha256']
wav = (folder / 'foa.wav').read_bytes()
assert wav[:4] == b'RIFF' and wav[8:12] == b'WAVE'
assert struct.unpack_from('<I', wav, 4)[0] + 8 == len(wav)
assert struct.unpack_from('<HHI', wav, 20) == (3, 4, manifest['sampleRate'])
assert struct.unpack_from('<H', wav, 34)[0] == 32
assert (len(wav) - 56) // 16 == manifest['foaFrames']
assert all(math.isfinite(x[0]) for x in struct.iter_unpack('<f', wav[56:]))
live = [json.loads(line) for line in (folder / 'analysis.jsonl').read_text().splitlines()]

def same(a, b):
    if isinstance(a, dict):
        return set(a) == set(b) and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, (float, int)) and not isinstance(a, bool):
        return abs(a - b) <= 1e-6
    return a == b

assert manifest['synthetic'] and result['synthetic']
assert result['mismatchedWindows'] == result['unmatchedLiveWindows'] == 0
assert result['comparedWindows'] == len(live) > 0
for expected in live:
    matches = [w for w in result['windows'] if abs(w['midpointHostSeconds'] - expected['midpointHostSeconds']) <= 1e-6]
    assert len(matches) == 1 and same(matches[0]['analysis'], expected['analysis'])
assert any(w['poseAlignment']['issue'] == 'matched' for w in result['windows'])
report = {
    'schemaVersion': 1,
    'kind': 'synthetic-research-recording-replay-contract',
    'sourceCommit': os.environ.get('GITHUB_SHA', 'local'),
    'ciRunURL': 'https://github.com/doroper98/sound_detection/actions/runs/' + os.environ.get('GITHUB_RUN_ID', 'local'),
    'schemaValidated': True,
    'hashlibMatchesSwiftSHA256': True,
    'float32WAVValidated': True,
    'liveReplayComparedWindows': len(live),
    'absoluteNumericTolerance': 1e-6,
    'mismatches': 0,
    'realDeviceAccuracyVerified': False,
    'appRecordingLifecycleVerified': False
}
Path(sys.argv[3]).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
