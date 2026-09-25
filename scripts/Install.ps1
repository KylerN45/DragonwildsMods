[CmdletBinding()]
param(
    [string]$UE4SSModsDirectory = 'F:\SteamLibrary\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\Mods'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $projectRoot 'mods\ExpandedQuickAccess'
$destination = Join-Path $UE4SSModsDirectory 'ExpandedQuickAccess'

if (-not (Test-Path $UE4SSModsDirectory -PathType Container)) {
    throw "The UE4SS Mods directory was not found: $UE4SSModsDirectory"
}
if (-not (Test-Path $source -PathType Container)) {
    throw "The mod source was not found: $source"
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item (Join-Path $source '*') $destination -Recurse -Force

Write-Host "Installed Expanded Quick Access to: $destination"
Write-Host 'Restart the game to load the mod.'
