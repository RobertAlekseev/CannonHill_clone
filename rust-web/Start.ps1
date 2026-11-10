param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8000,
    [switch]$BuildOnly,
    [switch]$Lan
)

$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$dist = Join-Path $project 'dist'
$target = Join-Path $project 'target'

& cargo build --locked --manifest-path (Join-Path $project 'Cargo.toml') --target-dir $target --release --target wasm32-unknown-unknown
if ($LASTEXITCODE -ne 0) { throw 'Der WebAssembly-Build ist fehlgeschlagen.' }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'index.html'), (Join-Path $project 'app.js'), (Join-Path $target 'wasm32-unknown-unknown/release/cannon_hill_web.wasm') -Destination $dist
if ($BuildOnly) { return }

Write-Host "Cannon Hill: http://127.0.0.1:$Port"
if ($Lan) {
    Write-Host "Freunde im Heimnetz verwenden http://<IPv4-Adresse-dieses-PCs>:$Port."
    & cargo run --locked --manifest-path (Join-Path $project 'Cargo.toml') --target-dir $target --release --features lan --bin cannon-hill-lan -- "0.0.0.0:$Port" $dist
    exit $LASTEXITCODE
}
& python -m http.server $Port --bind 127.0.0.1 --directory $dist
exit $LASTEXITCODE
