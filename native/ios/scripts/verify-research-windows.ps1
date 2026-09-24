$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
New-Item -ItemType Directory -Force DerivedData/windows | Out-Null
swift test --package-path Packages/StereoCore *> DerivedData/windows/swift-tests.log
if ($LASTEXITCODE -ne 0) { Get-Content DerivedData/windows/swift-tests.log -Tail 100; throw 'Swift tests failed' }
swift build --package-path Packages/StereoCore -c release --product foa-replay
if ($LASTEXITCODE -ne 0) { throw 'Swift build failed' }
$binaryDirectory = (swift build --package-path Packages/StereoCore -c release --show-bin-path).Trim()
$distribution = Join-Path (Get-Location) 'DerivedData/windows/foa-replay-windows'
New-Item -ItemType Directory -Force $distribution | Out-Null
$runtimePaths = @((swift -print-target-info | ConvertFrom-Json).paths.runtimeLibraryPaths)
$runtimePaths += $env:Path.Split(';') | Where-Object { $_ -match 'Swift' }
$runtimePaths | ConvertTo-Json -AsArray | Set-Content DerivedData/windows/runtime-paths.json
python scripts/package-replay-runtime.py (Join-Path $binaryDirectory 'foa-replay.exe') $distribution DerivedData/windows/runtime-paths.json
if ($LASTEXITCODE -ne 0) { throw 'Runtime packaging failed' }
$python = (Get-Command python).Source
$cli = Join-Path $distribution 'foa-replay.exe'
# Remove Swift from PATH so the portable bundle proves it contains its runtime.
$env:Path = Join-Path $env:SystemRoot 'System32'
$folder = (& $cli --fixture (Join-Path $env:RUNNER_TEMP 'research-fixture')).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Portable fixture failed' }
& $cli $folder --output DerivedData/windows/replay.json
if ($LASTEXITCODE -ne 0) { throw 'Portable replay failed' }
& $cli --zip $folder DerivedData/windows/synthetic-session.zip
if ($LASTEXITCODE -ne 0) { throw 'Portable ZIP failed' }
& $python -m pip --quiet install jsonschema==4.23.0
& $python scripts/validate-research.py $folder DerivedData/windows/replay.json DerivedData/windows/contract-verification.json
if ($LASTEXITCODE -ne 0) { throw 'Independent validation failed' }
Copy-Item -LiteralPath (Join-Path $folder 'manifest.json') -Destination DerivedData/windows/synthetic-session-manifest.json
