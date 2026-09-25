[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $projectRoot 'mod\ExpandedQuickAccess'
$OutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectRoot 'dist'
} else {
    $OutputDirectory
}
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path $output 'ExpandedQuickAccess'
$archive = Join-Path $output 'ExpandedQuickAccess-v0.1.4.zip'

if (-not (Test-Path $source -PathType Container)) {
    throw "The mod source was not found: $source"
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
if (Test-Path $stage) {
    Remove-Item $stage -Recurse -Force
}
Copy-Item $source $stage -Recurse

if (Test-Path $archive) {
    Remove-Item $archive -Force
}
Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal

Write-Host "Built folder: $stage"
Write-Host "Built package: $archive"
