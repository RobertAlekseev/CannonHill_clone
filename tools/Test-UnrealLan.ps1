param(
    [string]$Editor = 'C:/Program Files/Epic Games/UE_5.8/Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'unreal 5.8/CannonHill.uproject'
$reports = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
$run = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$hostLog = Join-Path $reports "unreal-lan-$run-host.log"
$guestLog = Join-Path $reports "unreal-lan-$run-guest.log"
$hostProcess = $null
$guestProcess = $null

function Start-Game([string]$Role, [string]$Log) {
    $flags = @(('"' + $project + '"'), '-game', $Role, '-nullrhi', '-nosound',
        '-unattended', '-nop4', '-nosplash', '-CannonHillLanSmoke',
        '-ExecCmds="t.MaxFPS 60"', ('-abslog="' + $Log + '"'))
    Start-Process -FilePath $Editor -ArgumentList $flags -WindowStyle Hidden -PassThru
}

function Wait-Log($Process, [string]$Path, [string]$Marker, [int]$Seconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) { throw "Unreal beendet sich vor dem Test. Log: $Path" }
        if (Test-Path -LiteralPath $Path) {
            $line = Select-String -LiteralPath $Path -SimpleMatch $Marker | Select-Object -Last 1
            if ($line) { return $line.Line }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Zeitlimit fuer $Marker. Log: $Path"
}

try {
    $hostProcess = Start-Game '-Host' $hostLog
    Wait-Log $hostProcess $hostLog 'CANNONHILL_LAN_READY' 180
    $guestProcess = Start-Game '-Join=127.0.0.1' $guestLog
    Wait-Log $guestProcess $guestLog 'CANNONHILL_LAN_JOIN' 180
    Wait-Log $hostProcess $hostLog 'CANNONHILL_LAN_ACCEPT' 12
    Wait-Log $guestProcess $guestLog 'CANNONHILL_LAN_PASS' 25
    if ($hostProcess.HasExited) { throw "Host unerwartet beendet. Log: $hostLog" }
    Write-Output "PASS: zwei Unreal-Prozesse, Gastbewegung, schwere Waffe, beide Einschlaege, Kisten-Snapshot. Logs: $run"
}
finally {
    foreach ($process in @($guestProcess, $hostProcess)) {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        }
    }
}
