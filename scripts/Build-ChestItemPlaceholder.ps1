[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $projectRoot 'mods\ChestItemPlaceholder'
$output = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectRoot 'dist'
} else {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
$stage = Join-Path $output 'ChestItemPlaceholder'
$archive = Join-Path $output "ChestItemPlaceholder-v$Version.zip"
$checksum = "$archive.sha256"

& (Join-Path $PSScriptRoot 'Test-ChestItemPlaceholder.ps1')

New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($path in @($stage, $archive, $checksum)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

Copy-Item -LiteralPath $source -Destination $stage -Recurse
Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksum -Value "$hash  ChestItemPlaceholder-v$Version.zip" -Encoding ascii

Write-Host "Built folder: $stage"
Write-Host "Built package: $archive"
Write-Host "SHA-256: $hash"
