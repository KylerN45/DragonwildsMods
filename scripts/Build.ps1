[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$UE4SSDll,
    [string]$Version = '0.2.0'
)

$ErrorActionPreference = 'Stop'

function Find-UE4SSDll {
    $steamRoots = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    try {
        $steamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' `
            -Name SteamPath -ErrorAction Stop).SteamPath
        if ($steamPath) {
            [void]$steamRoots.Add($steamPath)
        }
    }
    catch {
        # The caller receives one clear error if discovery does not find UE4SS.
    }

    foreach ($root in @($steamRoots)) {
        $libraryFile = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile)) {
            continue
        }

        $libraryText = Get-Content -LiteralPath $libraryFile -Raw
        foreach ($match in [regex]::Matches($libraryText, '"path"\s+"([^"]+)"')) {
            $libraryPath = $match.Groups[1].Value -replace '\\\\', '\'
            [void]$steamRoots.Add($libraryPath)
        }
    }

    $found = @(
        @(
            foreach ($root in $steamRoots) {
                $candidate = Join-Path $root `
                    'steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\UE4SS.dll'
                if (Test-Path -LiteralPath $candidate) {
                    (Resolve-Path -LiteralPath $candidate).Path
                }
            }
        ) | Select-Object -Unique
    )

    if ($found.Count -eq 1) {
        return $found[0]
    }
    if ($found.Count -gt 1) {
        throw 'More than one UE4SS installation was found. Use -UE4SSDll with one complete absolute file path.'
    }
    throw 'UE4SS.dll was not found in a Steam library. Use -UE4SSDll with its complete absolute file path.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $projectRoot 'mods\ExpandedQuickAccess'
$nativeSource = Join-Path $projectRoot 'native\ExpandedQuickAccess'
$buildDirectory = Join-Path $projectRoot 'build\ExpandedQuickAccess-native'
$OutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectRoot 'dist'
} else {
    $OutputDirectory
}
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path $output 'ExpandedQuickAccess'
$archive = Join-Path $output "ExpandedQuickAccess-v$Version.zip"
$checksum = "$archive.sha256"
$dllDirectory = Join-Path $stage 'dlls'

foreach ($path in @($source, $nativeSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "A source directory was not found: $path"
    }
}

if ([string]::IsNullOrWhiteSpace($UE4SSDll)) {
    $UE4SSDll = Find-UE4SSDll
}
$UE4SSDll = (Resolve-Path -LiteralPath $UE4SSDll -ErrorAction Stop).Path

$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "Visual Studio Installer is not available at $vswhere"
}

$visualStudio = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $visualStudio) {
    throw 'Visual Studio 2022 with the x64 C++ build tools is required.'
}

$vcvars = Join-Path $visualStudio 'VC\Auxiliary\Build\vcvars64.bat'
$msvcToolsRoot = Join-Path $visualStudio 'VC\Tools\MSVC'
$msvcTools = Get-ChildItem -LiteralPath $msvcToolsRoot -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $msvcTools) {
    throw "The MSVC toolset is not available in $msvcToolsRoot"
}

$dumpbin = Join-Path $msvcTools.FullName 'bin\Hostx64\x64\dumpbin.exe'
$mainSource = Join-Path $nativeSource 'main.cpp'
$testSource = Join-Path $nativeSource 'routing_tests.cpp'
$moduleDefinition = Join-Path $nativeSource 'UE4SS.def'
$builtDll = Join-Path $buildDirectory 'main.dll'
$testExecutable = Join-Path $buildDirectory 'routing_tests.exe'
$ue4ssImportLibrary = Join-Path $buildDirectory 'UE4SS.lib'

foreach ($requiredFile in @(
    $vcvars,
    $dumpbin,
    $mainSource,
    $testSource,
    $moduleDefinition,
    $UE4SSDll
)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "A required build file is not available: $requiredFile"
    }
}

$dumpbinOutput = & $dumpbin /exports $UE4SSDll 2>&1 | Out-String
foreach ($symbol in @(
    '??0CppUserModBase@RC@@QEAA@XZ',
    '??1CppUserModBase@RC@@UEAA@XZ'
)) {
    if (-not $dumpbinOutput.Contains($symbol)) {
        throw "The selected UE4SS DLL does not export the required C++ interface: $symbol"
    }
}

if (Test-Path -LiteralPath $buildDirectory) {
    Remove-Item -LiteralPath $buildDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

$testObject = Join-Path $buildDirectory 'routing_tests.obj'
$mainObject = Join-Path $buildDirectory 'main.obj'
$builtImportLibrary = Join-Path $buildDirectory 'ExpandedQuickAccess.lib'
$pdb = Join-Path $buildDirectory 'main.pdb'
$developerCommand = @(
    "call `"$vcvars`"",
    "cl /nologo /std:c++20 /EHsc /MD /O2 /DNDEBUG /I`"$nativeSource`" /Fo:`"$testObject`" `"$testSource`" /link /OUT:`"$testExecutable`"",
    "`"$testExecutable`"",
    "lib /nologo /def:`"$moduleDefinition`" /machine:x64 /out:`"$ue4ssImportLibrary`"",
    "cl /nologo /std:c++20 /EHsc /MD /O2 /DNDEBUG /LD /I`"$nativeSource`" /Fo:`"$mainObject`" `"$mainSource`" /link /Brepro /OUT:`"$builtDll`" /IMPLIB:`"$builtImportLibrary`" /PDB:`"$pdb`" `"$ue4ssImportLibrary`""
) -join ' && '

& cmd.exe /d /s /c $developerCommand
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $builtDll)) {
    throw 'The native mod build failed.'
}

$nativeExports = & $dumpbin /exports $builtDll 2>&1 | Out-String
foreach ($export in @('start_mod', 'uninstall_mod')) {
    if (-not $nativeExports.Contains($export)) {
        throw "The built native mod does not export $export."
    }
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($path in @($stage, $archive, $checksum)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

Copy-Item -LiteralPath $source -Destination $stage -Recurse
New-Item -ItemType Directory -Path $dllDirectory -Force | Out-Null
Copy-Item -LiteralPath $builtDll -Destination (Join-Path $dllDirectory 'main.dll')
Compress-Archive -Path $stage -DestinationPath $archive -CompressionLevel Optimal

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksum `
    -Value "$hash  ExpandedQuickAccess-v$Version.zip" -Encoding ascii

Write-Host "Native routing tests: passed"
Write-Host "Built folder: $stage"
Write-Host "Built package: $archive"
Write-Host "SHA-256: $hash"
