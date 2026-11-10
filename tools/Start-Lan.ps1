param(
    [Parameter(Mandatory)]
    [ValidateSet('Godot', 'Unity', 'Unreal')]
    [string]$Engine,

    [Parameter(Mandatory)]
    [ValidateSet('Host', 'Join')]
    [string]$Role,

    [string]$Address,
    [string]$UnrealEditor = 'C:\Program Files\Epic Games\UE_5.8\Engine\Binaries\Win64\UnrealEditor.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if ($Role -eq 'Join') {
    if ($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or
        ($Address.Split('.') | Where-Object { [int]$_ -gt 255 })) {
        throw 'Bei Join die IPv4-Adresse des Hosts angeben, z.B. -Address 192.168.178.42.'
    }
    $Address = (($Address.Split('.') | ForEach-Object { [int]$_ }) -join '.')
}

switch ($Engine) {
    'Godot' {
        $program = (Get-Command godot -CommandType Application).Source
        $arguments = @('--path', (Join-Path $root 'godot'), '--')
    }
    'Unity' {
        $program = Join-Path $root 'builds/unity/CannonHill.exe'
        $arguments = @()
    }
    'Unreal' {
        $program = $UnrealEditor
        $arguments = @((Join-Path $root 'unreal 5.8/CannonHill.uproject'), '-game')
    }
}

if (-not (Test-Path -LiteralPath $program -PathType Leaf)) {
    throw "Spiel oder Engine fehlt: $program. Siehe README.md fuer die Startvoraussetzungen."
}

if ($Role -eq 'Host') {
    Write-Host "Host: $Engine auf TCP 28741. Beide Rechner brauchen denselben Spielstand."
    try {
        $addresses = Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object { $_.NetAdapter.Status -eq 'Up' } |
            ForEach-Object {
                $adapter = $_.InterfaceAlias
                foreach ($ip in $_.IPv4Address) {
                    if ($ip.IPAddress -notmatch '^(127\.|169\.254\.)') {
                        "$adapter : $($ip.IPAddress)"
                    }
                }
            }
        if ($addresses) { $addresses | ForEach-Object { Write-Host $_ } }
        else { Write-Host 'LAN-Adresse mit ipconfig nachsehen.' }
    } catch {
        Write-Host 'LAN-Adresse mit ipconfig nachsehen.'
    }
    $arguments += if ($Engine -eq 'Unreal') { '-Host' } else { '--host' }
} else {
    $arguments += if ($Engine -eq 'Unreal') { "-Join=$Address" } else { "--join=$Address" }
}

& $program @arguments
