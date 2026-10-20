param([string]$Project = (Split-Path $PSScriptRoot -Parent), [string]$OutputDirectory = '', [string]$FlutterSdk = '')
$ErrorActionPreference = 'Stop'
$Project = [IO.Path]::GetFullPath($Project)
if (!(Test-Path -LiteralPath (Join-Path $Project 'pubspec.yaml'))) { throw 'Choose the DocumentZ project folder.' }
function Find-FlutterSdk([string]$ExplicitSdk) {
    $candidates = @()
    if ($ExplicitSdk) { $candidates += $ExplicitSdk }
    $properties = Join-Path $Project 'android\local.properties'
    if (Test-Path -LiteralPath $properties) {
        foreach ($line in Get-Content -LiteralPath $properties) {
            if ($line -match '^\s*flutter\.sdk\s*=(.+)$') {
                $candidates += $Matches[1].Trim().Replace('\\','\').Replace('\:',':')
            }
        }
    }
    if ($env:FLUTTER_ROOT) { $candidates += $env:FLUTTER_ROOT }
    $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($command) { $candidates += Split-Path (Split-Path $command.Source -Parent) -Parent }
    $candidates += 'D:\develop\flutter'
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'bin\flutter.bat')) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'bin\dart.bat'))) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Flutter SDK not found. Run this script with -FlutterSdk followed by your Flutter folder.'
}
$resolvedSdk = Find-FlutterSdk $FlutterSdk
$flutter = Join-Path $resolvedSdk 'bin\flutter.bat'
$env:Path = (Join-Path $resolvedSdk 'bin') + [IO.Path]::PathSeparator + $env:Path
Write-Host "Using Flutter SDK: $resolvedSdk"

function Run-Flutter([string[]]$Arguments) {
    & $flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Flutter failed: ' + ($Arguments -join ' ')) }
}
Push-Location -LiteralPath $Project
try {
    Run-Flutter -Arguments @('pub','get')
    Run-Flutter -Arguments @('build','windows','--release')
    $candidates = @('build\windows\x64\runner\Release','build\windows\runner\Release')
    $bundle = $null
    foreach ($relative in $candidates) {
        $candidate = Join-Path $Project $relative
        if (Test-Path -LiteralPath (Join-Path $candidate 'DocumentZ.exe')) { $bundle = $candidate; break }
    }
    if (!$bundle) { throw 'The complete Windows release bundle was not found.' }
    foreach ($required in @('DocumentZ.exe','flutter_windows.dll','data\icudtl.dat','data\flutter_assets')) {
        if (!(Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Missing release component: $required" }
    }
    $match = [regex]::Match((Get-Content -LiteralPath 'pubspec.yaml' -Raw), '(?m)^version:\s*([^\s+]+)')
    if (!$match.Success) { throw 'Cannot read the project version.' }
    $version = $match.Groups[1].Value
    if (!$OutputDirectory) { $OutputDirectory = Join-Path $Project 'releases\windows' }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $zip = Join-Path $OutputDirectory ("DocumentZ-$version-windows-x64-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    if (Test-Path -LiteralPath $zip) { throw 'Output already exists; try again with a different output folder.' }
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashPath = [IO.Path]::ChangeExtension($zip, '.SHA256SUMS.txt')
    [IO.File]::WriteAllText($hashPath, "$hash  $([IO.Path]::GetFileName($zip))`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Windows release: $zip"
    Write-Host "Checksum: $hashPath"
    Write-Host 'Test the extracted folder on a clean Windows PC before publishing.'
    Write-Host 'Users need the supported Microsoft Visual C++ runtime. Upload the ZIP, not the EXE alone.'
} finally { Pop-Location }
