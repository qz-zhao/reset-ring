param([string]$StateDirectory)
$ErrorActionPreference = 'Stop'
if (!$StateDirectory) {
    $StateDirectory = if ($IsMacOS) { Join-Path $HOME 'Library/Application Support/ResetRing' }
    else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResetRing' }
}
$null = [IO.Directory]::CreateDirectory($StateDirectory)
try {
    $lock = [IO.File]::Open((Join-Path $StateDirectory 'watcher.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] { return }
$child = $null
try {
    while (Test-Path -LiteralPath (Join-Path $StateDirectory 'autostart.enabled')) {
        $appOpen = if ($IsWindows) {
            @(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0
        } else {
            & /usr/bin/pgrep -x 'ChatGPT|Codex' *> $null
            $LASTEXITCODE -eq 0
        }
        if ($appOpen -and (!$child -or $child.HasExited)) {
            $start = [Diagnostics.ProcessStartInfo]::new()
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardError = $true
            $start.RedirectStandardOutput = $true
            if ($IsWindows) {
                $start.FileName = Join-Path $PSHOME 'pwsh.exe'
                foreach ($arg in @('-NoProfile', '-STA', '-File', (Join-Path $PSScriptRoot 'Show-Quota.ps1'))) {
                    $start.ArgumentList.Add($arg)
                }
            } else {
                $start.FileName = '/usr/bin/xcrun'
                $start.ArgumentList.Add('swift')
                $start.ArgumentList.Add((Join-Path $PSScriptRoot 'ResetRing.swift'))
            }
            $child = [Diagnostics.Process]::Start($start)
            $null = $child.StandardError.ReadToEndAsync()
            $null = $child.StandardOutput.ReadToEndAsync()
        }
        if (!$appOpen -and $child -and !$child.HasExited) { $child.Kill($true) }
        Start-Sleep -Seconds 5
    }
} finally {
    if ($child) {
        if (!$child.HasExited) { $child.Kill($true) }
        $child.Dispose()
    }
    $lock.Dispose()
}
