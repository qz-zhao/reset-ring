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
        if (Get-ScheduledTask -TaskName 'Reset Ring' -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName 'Reset Ring'
            Unregister-ScheduledTask -TaskName 'Reset Ring' -Confirm:$false
        }
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
$codexExecutable = if ($IsWindows) { 'codex.exe' } else { 'codex' }
$codex = Get-Command $codexExecutable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$codex) { throw 'Codex CLI was not found. Install it before enabling automatic startup.' }
[IO.File]::WriteAllText((Join-Path $stateDirectory 'codex-path.txt'), $codex.Source)
$watcher = Join-Path $installed 'Watch-Codex.ps1'
$pwsh = (Get-Process -Id $PID).Path
if ($IsWindows) {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument ('-NoProfile -WindowStyle Hidden -File "' + $watcher + '"')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
    Register-ScheduledTask -TaskName 'Reset Ring' -InputObject $task -Force | Out-Null
    [IO.File]::Delete((Join-Path ([Environment]::GetFolderPath('Startup')) 'Reset Ring.lnk'))
    Start-ScheduledTask -TaskName 'Reset Ring'
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

