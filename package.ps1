[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'EasyFishing.zip')
)

$ErrorActionPreference = 'Stop'
$addonRoot = $PSScriptRoot
$manifestPath = Join-Path $addonRoot 'EasyFishing.toc'
$manifest = Get-Content $manifestPath
$versionLine = $manifest | Where-Object { $_ -match '^## Version:\s*(.+)$' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^## Version:\s*(.+)$') {
    throw 'EasyFishing.toc must contain a ## Version field.'
}
$version = $Matches[1].Trim()
if (-not $OutputPath -or $OutputPath -eq (Join-Path ([Environment]::GetFolderPath('Desktop')) 'EasyFishing.zip')) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "EasyFishing-$version.zip"
}

if ($manifest | Where-Object { $_ -match '^(?i)Bindings\.xml$' }) {
    throw 'Bindings.xml is auto-loaded by WoW and must not be listed as regular UI XML in the TOC.'
}

$packageFiles = @(
    'EasyFishing.toc',
    'Bindings.xml',
    'Core.lua',
    'Data.lua',
    'Tracking.lua',
    'UI.lua',
    'Tools.lua',
    'EasyFishing.tga',
    'README.md'
)
$missingFiles = @($packageFiles | Where-Object { -not (Test-Path (Join-Path $addonRoot $_) -PathType Leaf) })
if ($missingFiles.Count -gt 0) {
    throw "Required package file(s) are missing: $($missingFiles -join ', ')"
}

$loadFiles = @($manifest | Where-Object { $_ -match '^[^#\s].*\.lua$' })
$missingLoads = @($loadFiles | Where-Object { $_ -notin $packageFiles })
if ($missingLoads.Count -gt 0) {
    throw "The package file list omits TOC-loaded Lua file(s): $($missingLoads -join ', ')"
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path $resolvedOutput) {
    throw "Output already exists; choose another -OutputPath: $resolvedOutput"
}
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ("EasyFishing-package-" + [guid]::NewGuid().ToString('N'))
$stageAddon = Join-Path $stageRoot 'EasyFishing'
try {
    New-Item -ItemType Directory -Path $stageAddon -Force | Out-Null
    foreach ($file in $packageFiles) {
        Copy-Item (Join-Path $addonRoot $file) $stageAddon
    }
    Compress-Archive -Path $stageAddon -DestinationPath $resolvedOutput -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($resolvedOutput)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('/', '\') })
        foreach ($file in $packageFiles) {
            if ("EasyFishing\$file" -notin $entryNames) {
                throw "The archive is missing EasyFishing/$file"
            }
        }
        if ($entryNames | Where-Object { $_ -match '(^|\\)(\.git|tests|FISHING_NOTES\.md)(\\|$)' }) {
            throw 'The archive unexpectedly contains development-only files.'
        }
    }
    finally {
        $archive.Dispose()
    }
}
finally {
    if (Test-Path $stageRoot) {
        Remove-Item $stageRoot -Recurse -Force
    }
}

Write-Output "CurseForge package ready: $resolvedOutput"
Write-Output "Version: $version | Files: $($packageFiles.Count) | AddOn folder: EasyFishing/"
