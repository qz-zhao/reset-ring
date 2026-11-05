param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$stateDirectory = if ($IsMacOS) { Join-Path $HOME 'Library/Application Support/ResetRing' }
else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResetRing' }
$enabled = Join-Path $stateDirectory 'autostart.enabled'
$label = 'io.github.qz-zhao.reset-ring'
if ($Remove) {
    [IO.File]::Delete($enabled)
    if ($IsWindows) {
        [IO.File]::Delete((Join-Path ([Environment]::GetFolderPath('Startup')) 'Reset Ring.lnk'))
    } else {
        $plist = Join-Path $HOME "Library/LaunchAgents/$label.plist"
        & /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$label" 2>$null
        [IO.File]::Delete($plist)
    }
    'Reset Ring automatic startup disabled. The watcher will stop within five seconds.'
    return
}
$null = [IO.Directory]::CreateDirectory($stateDirectory)
$installed = Join-Path $stateDirectory 'scripts'
$null = [IO.Directory]::CreateDirectory($installed)
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File) {
    $destination = Join-Path $installed $file.Name
    if ($file.FullName -ne $destination) { Copy-Item -LiteralPath $file.FullName -Destination $destination -Force }
}
[IO.File]::WriteAllText($enabled, '')
$watcher = Join-Path $installed 'Watch-Codex.ps1'
$pwsh = (Get-Process -Id $PID).Path
if ($IsWindows) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut(
        (Join-Path ([Environment]::GetFolderPath('Startup')) 'Reset Ring.lnk'))
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -File "' + $watcher + '"'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    Start-Process $pwsh -ArgumentList ('-NoProfile -WindowStyle Hidden -File "' + $watcher + '"') -WindowStyle Hidden
} else {
    $plist = Join-Path $HOME "Library/LaunchAgents/$label.plist"
    $null = [IO.Directory]::CreateDirectory((Split-Path $plist))
    $escapedPwsh = [Security.SecurityElement]::Escape($pwsh)
    $escapedWatcher = [Security.SecurityElement]::Escape($watcher)
    $escapedPath = [Security.SecurityElement]::Escape($env:PATH)
    @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>$escapedPwsh</string><string>-NoProfile</string><string>-File</string><string>$escapedWatcher</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$escapedPath</string></dict>
<key>RunAtLoad</key><true/>
</dict></plist>
"@ | Set-Content -LiteralPath $plist
    $domain = "gui/$(/usr/bin/id -u)"
    & /bin/launchctl bootout "$domain/$label" 2>$null
    & /bin/launchctl bootstrap $domain $plist
    if ($LASTEXITCODE) { throw 'Unable to enable the macOS login agent.' }
}
'Reset Ring automatic startup enabled.'
'Open Codex or ChatGPT desktop. The gauge starts within five seconds.'
'Run this installer again after updating Reset Ring to refresh the installed files.'
