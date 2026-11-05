param(
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT.lnk'),
    [string]$AppTarget = 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App',
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'This shortcut installer supports Windows.' }
$directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResetRing'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Reset Ring.lnk'
[IO.File]::Delete((Join-Path $directory 'autostart.enabled'))
[IO.File]::Delete($startup)
if ($Remove) {
    [IO.File]::Delete($ShortcutPath)
    'Reset Ring app shortcut removed.'
    return
}
$null = [IO.Directory]::CreateDirectory($directory)
$installed = Join-Path $directory 'scripts'
$null = [IO.Directory]::CreateDirectory($installed)
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File) {
    $destination = Join-Path $installed $file.Name
    if ($file.FullName -ne $destination) { Copy-Item -LiteralPath $file.FullName -Destination $destination -Force }
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$launcher = Join-Path $directory 'ResetRing.Launcher.exe'
& $compiler /nologo /target:winexe "/out:$launcher" (Join-Path $installed 'AppLauncher.cs')
if ($LASTEXITCODE) { throw 'Unable to compile the shortcut launcher.' }
[IO.File]::WriteAllLines((Join-Path $directory 'shortcut.txt'), @(
    $AppTarget,
    (Get-Process -Id $PID).Path,
    (Join-Path $installed 'Show-Quota.ps1')
))
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($ShortcutPath)
$link.TargetPath = $launcher
$link.WindowStyle = 7
$link.Description = 'Open ChatGPT, then launch Reset Ring in the background'
$app = Get-AppxPackage '*Codex*' | Select-Object -First 1
if ($app) {
    $icon = Get-ChildItem -LiteralPath $app.InstallLocation -Filter 'ChatGPT.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($icon) { $link.IconLocation = $icon.FullName + ',0' }
}
$link.Save()
$ShortcutPath


