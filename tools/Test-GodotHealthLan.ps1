param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$report = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $report | Out-Null
$engine = (Get-Command $Godot -ErrorAction Stop).Source
if ([IO.Path]::GetExtension($engine) -eq '.cmd') {
    $candidate = Get-ChildItem (Split-Path $engine) -Recurse -Filter '*console.exe' | Select-Object -First 1
    if (-not $candidate) { throw 'Pass a Godot console executable with -Godot.' }
    $engine = $candidate.FullName
}
$hostLog = Join-Path $report 'health-lan-host.log'
$clientLog = Join-Path $report 'health-lan-client.log'
[IO.File]::WriteAllText($hostLog, '')
[IO.File]::WriteAllText($clientLog, '')
$project = Join-Path $root 'godot'
$arguments = @('--headless', '--path', ('"' + $project + '"'), '--script', 'res://tests/health_lan_peer.gd', '--log-file')
$hostProcess = $null
$clientProcess = $null
try {
    $hostProcess = Start-Process -FilePath $engine -ArgumentList ($arguments + @(('"' + $hostLog + '"'), '--', '--host')) -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 200
        $ready = (Test-Path $hostLog) -and ((Get-Content $hostLog -Raw) -match 'HOST_READY')
        if ($hostProcess.HasExited) { throw 'Host exited before listening.' }
    } until ($ready -or [DateTime]::UtcNow -gt $deadline)
    if (-not $ready) { throw 'Host did not listen.' }
    $clientProcess = Start-Process -FilePath $engine -ArgumentList ($arguments + @(('"' + $clientLog + '"'), '--', '--join=127.0.0.1')) -WindowStyle Hidden -PassThru
    if (-not $clientProcess.WaitForExit(30000)) { throw 'Client timeout.' }
    if (-not $hostProcess.WaitForExit(10000)) { throw 'Host timeout.' }
    $hostText = Get-Content $hostLog -Raw
    $clientText = Get-Content $clientLog -Raw
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0) { throw 'A test peer failed.' }
    if ($hostText -match 'SCRIPT ERROR|ERROR:' -or $clientText -match 'SCRIPT ERROR|ERROR:') { throw 'Godot error in integration test.' }
    if ($hostText -notmatch 'HOST_HEALTH_PASS') { throw 'Host did not verify damage and winner.' }
    if ($clientText -notmatch 'CLIENT_HEALTH_PASS damage=true victory=true restart=true') { throw 'Client did not verify replicated damage, winner and restart.' }
    Write-Output 'PASS: both players fire over TCP; 1000->800->0 HP, winner and host restart replicate to the client.'
}
finally {
    foreach ($p in @($clientProcess, $hostProcess)) {
        if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id }
    }
}
