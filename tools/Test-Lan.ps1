param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$report = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $report | Out-Null
$engine = (Get-Command $Godot -ErrorAction Stop).Source
$project = Join-Path $root 'godot'
# The Godot PATH shim may be a .cmd. Use its adjacent console executable
# when installed that way; otherwise the selected executable is used directly.
if ([IO.Path]::GetExtension($engine) -eq '.cmd') {
    $candidate = Get-ChildItem (Split-Path $engine) -Recurse -Filter '*console.exe' | Select-Object -First 1
    if (-not $candidate) { throw 'Please pass a Godot console executable with -Godot.' }
    $engine = $candidate.FullName
}
$hostLog = Join-Path $report 'lan-host.log'
$clientLog = Join-Path $report 'lan-client.log'
[IO.File]::WriteAllText($hostLog, '')
[IO.File]::WriteAllText($clientLog, '')
$hostProcess = $null
$clientProcess = $null
try {
    $hostProcess = Start-Process -FilePath $engine -ArgumentList @('--headless', '--path', ('"' + $project + '"'), '--log-file', ('"' + $hostLog + '"'), '--', '--host', '--smoke') -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 200
        $ready = (Test-Path $hostLog) -and ((Get-Content $hostLog -Raw) -match 'HOST_READY')
        if ($hostProcess.HasExited) { throw 'Host exited before listening.' }
    } until ($ready -or [DateTime]::UtcNow -gt $deadline)
    if (-not $ready) { throw 'Host did not listen within 20 seconds.' }
    $clientProcess = Start-Process -FilePath $engine -ArgumentList @('--headless', '--path', ('"' + $project + '"'), '--log-file', ('"' + $clientLog + '"'), '--', '--join=127.0.0.1', '--smoke') -WindowStyle Hidden -PassThru
    if (-not $clientProcess.WaitForExit(45000)) { throw 'Client timeout.' }
    if (-not $hostProcess.WaitForExit(15000)) { throw 'Host timeout.' }
    $hostText = Get-Content $hostLog -Raw
    $clientText = Get-Content $clientLog -Raw
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0) { throw 'A Godot process failed.' }
    if ($hostText -match 'SCRIPT ERROR' -or $clientText -match 'SCRIPT ERROR') { throw 'GDScript runtime error.' }
    if ($hostText -notmatch 'PEER_CONNECTED') { throw 'Host did not accept client.' }
    if ($clientText -notmatch 'STATE_RECEIVED') { throw 'Client did not receive a world snapshot.' }
    if ($hostText -notmatch 'SMOKE_FINISHED tick=200 impacts=2') { throw 'Expected one shot from each player to impact.' }
    if ($clientText -notmatch 'STATE_RECEIVED tick=\d+ impacts=2') { throw 'Client did not receive both impacts.' }
    Write-Output 'PASS: two Godot processes, authoritative state sync, both players fire and both impacts reach the client.'
}
finally {
    foreach ($p in @($clientProcess, $hostProcess)) {
        if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id }
    }
}
