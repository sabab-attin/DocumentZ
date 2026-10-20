param(
    [string]$Project = (Split-Path $PSScriptRoot -Parent),
    [string]$FlutterSdk = '',
    [string]$InnoCompiler = '',
    [string]$VcRedist = ''
)
$ErrorActionPreference='Stop'
$Project=[IO.Path]::GetFullPath($Project)
if (!$InnoCompiler) {
    $innoCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $compilerCandidates = @()
    if ($innoCommand) { $compilerCandidates += $innoCommand.Source }
    foreach ($programFolder in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if (!$programFolder) { continue }
        foreach ($majorVersion in @(7,6)) {
            $compilerCandidates += Join-Path $programFolder "Inno Setup $majorVersion\ISCC.exe"
        }
    }
    $InnoCompiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$InnoCompiler -or !(Test-Path -LiteralPath $InnoCompiler)) {
    throw 'Install Inno Setup from https://jrsoftware.org/isdl.php, then rerun. Or pass -InnoCompiler with the path to ISCC.exe.'
}
$destination=Join-Path $Project 'releases\windows'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
if (!$VcRedist) {
    $prerequisites=Join-Path $Project 'build\windows\installer-prerequisites'
    New-Item -ItemType Directory -Force -Path $prerequisites | Out-Null
    $VcRedist=Join-Path $prerequisites 'vc_redist.x64.exe'
    if (!(Test-Path -LiteralPath $VcRedist)) {
        Write-Host 'Downloading the official Microsoft Visual C++ runtime...'
        $oldProtocol=[Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri 'https://aka.ms/vc14/vc_redist.x64.exe' -OutFile $VcRedist -UseBasicParsing
        } finally { [Net.ServicePointManager]::SecurityProtocol=$oldProtocol }
    }
}
$signature=Get-AuthenticodeSignature -LiteralPath $VcRedist
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw 'Microsoft runtime signature verification failed. No installer was built. Remove the cached runtime and retry.'
}
& (Join-Path $Project 'tool\Build-Windows-Release.ps1') -Project $Project -FlutterSdk $FlutterSdk
if (!$?) { throw 'Windows release build failed.' }
$bundle=Join-Path $Project 'build\windows\x64\runner\Release'
if (!(Test-Path -LiteralPath (Join-Path $bundle 'DocumentZ.exe'))) { $bundle=Join-Path $Project 'build\windows\runner\Release' }
$versionMatch=[regex]::Match((Get-Content -LiteralPath (Join-Path $Project 'pubspec.yaml') -Raw),'(?m)^version:\s*([^\s+]+)')
if (!$versionMatch.Success) { throw 'Cannot determine version.' }
$version=$versionMatch.Groups[1].Value
$installer=Join-Path $destination "DocumentZ-$version-windows-x64-setup.exe"
if (Test-Path -LiteralPath $installer) { throw "Installer already exists: $installer. Move the old build aside before rebuilding." }
$runtimeInfo=[Diagnostics.FileVersionInfo]::GetVersionInfo($VcRedist)
& $InnoCompiler "/DRuntimeMajor=$($runtimeInfo.FileMajorPart)" "/DRuntimeMinor=$($runtimeInfo.FileMinorPart)" "/DRuntimeBuild=$($runtimeInfo.FileBuildPart)" "/DBundleDir=$bundle" "/DAppVersion=$version" "/DOutputDir=$destination" "/DVcRedist=$VcRedist" (Join-Path $Project 'windows\installer\DocumentZ.iss')
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $installer)) { throw 'Installer compilation failed.' }
$checksum=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($installer+'.SHA256SUMS.txt'), "$checksum  $([IO.Path]::GetFileName($installer))`n", [Text.UTF8Encoding]::new($false))
Write-Host "Windows installer: $installer"
Write-Host "Checksum: $installer.SHA256SUMS.txt"
Write-Host 'Test install, Open with, upgrade, sync and uninstall on a Windows PC before publishing.'
