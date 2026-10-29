param(
    [ValidateSet('godot', 'unity')][string]$HostEngine = 'unity',
    [ValidateSet('godot', 'unity')][string]$ClientEngine = 'godot'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$report = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $report | Out-Null
function Start-Engine([string]$engine, [string]$role, [string]$log) {
    $mode = if ($role -eq 'host') { '--host' } else { '--join=127.0.0.1' }
    if ($engine -eq 'unity') {
        $exe = Join-Path $root 'builds\unity\CannonHill.exe'
        if (-not (Test-Path $exe)) { throw 'Build Unity first using ProjectSetup.Build.' }
        $arguments = @('-batchmode', '-nographics', '-logFile', ('"' + $log + '"'), $mode, '--smoke')
    }
    else {
        $exe = (Get-Command godot -ErrorAction Stop).Source
        if ([IO.Path]::GetExtension($exe) -eq '.cmd') {
            $exe = (Get-ChildItem (Split-Path $exe) -Recurse -Filter '*console.exe' | Select-Object -First 1).FullName
        }
        $arguments = @('--headless', '--path', ('"' + (Join-Path $root 'godot') + '"'), '--log-file', ('"' + $log + '"'), '--', $mode, '--smoke')
    }
    Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
}
$hostLog = Join-Path $report "$HostEngine-$ClientEngine-host.log"
$clientLog = Join-Path $report "$HostEngine-$ClientEngine-client.log"
[IO.File]::WriteAllText($hostLog, '')
[IO.File]::WriteAllText($clientLog, '')
$hostProcess = $null
$clientProcess = $null
try {
    $hostProcess = Start-Engine $HostEngine 'host' $hostLog
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 200
        $ready = (Test-Path $hostLog) -and ((Get-Content $hostLog -Raw) -match 'HOST_READY')
        if ($hostProcess.HasExited) { throw 'Host exited before listening.' }
    } until ($ready -or [DateTime]::UtcNow -gt $deadline)
    if (-not $ready) { throw 'Host did not listen within 30 seconds.' }
    $clientProcess = Start-Engine $ClientEngine 'client' $clientLog
    if (-not $clientProcess.WaitForExit(45000)) { throw 'Client timeout.' }
    if (-not $hostProcess.WaitForExit(15000)) { throw 'Host timeout.' }
    $hostText = Get-Content $hostLog -Raw
    $clientText = Get-Content $clientLog -Raw
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0) { throw 'A process failed.' }
    if ($hostText -match 'SCRIPT ERROR|Exception:' -or $clientText -match 'SCRIPT ERROR|Exception:') { throw 'Runtime error.' }
    if ($hostText -notmatch 'PEER_CONNECTED') { throw 'Host did not accept client.' }
    if ($clientText -notmatch 'STATE_RECEIVED') { throw 'No world snapshot received.' }
    if ($hostText -notmatch 'SMOKE_FINISHED tick=200 impacts=2') { throw 'Expected both player shots to impact on host.' }
    if ($clientText -notmatch 'STATE_RECEIVED tick=\d+ impacts=2') { throw 'Client did not receive both impacts.' }
    Write-Output "PASS: $HostEngine host -> $ClientEngine client; both players fire and receive the authoritative result."
}
finally {
    foreach ($p in @($clientProcess, $hostProcess)) {
        if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id }
    }
}
