#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p DerivedData/evidence/research
swift build --package-path Packages/StereoCore -c release --product foa-replay
cli="$(swift build --package-path Packages/StereoCore -c release --show-bin-path)/foa-replay"
folder="$("$cli" --fixture "${TMPDIR:-/tmp}/soundfield-research-fixtures")"
"$cli" "$folder" --output DerivedData/evidence/research/replay.json
"$cli" --zip "$folder" DerivedData/evidence/research/synthetic-session.zip
python3 -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; assert len(z.namelist())==6' DerivedData/evidence/research/synthetic-session.zip
python3 -m venv "${TMPDIR:-/tmp}/soundfield-schema-env"
"${TMPDIR:-/tmp}/soundfield-schema-env/bin/pip" --quiet install jsonschema==4.23.0
"${TMPDIR:-/tmp}/soundfield-schema-env/bin/python" scripts/validate-research.py \
    "$folder" DerivedData/evidence/research/replay.json DerivedData/evidence/research/contract-verification.json
cp "$folder/manifest.json" DerivedData/evidence/research/synthetic-session-manifest.json
cp "$cli" DerivedData/evidence/research/foa-replay
node ../../scripts/audit-foa-feasibility.mjs --grid-cli "$cli" --output DerivedData/evidence/research/synthetic-grid.json
