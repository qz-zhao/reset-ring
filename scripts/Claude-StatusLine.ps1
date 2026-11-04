param(
    [string]$CachePath = $(if ($IsMacOS) { Join-Path $HOME 'Library/Application Support/ResetRing/claude-quota.json' }
        else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResetRing/claude-quota.json' })
)

$ErrorActionPreference = 'Stop'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$limits = $payload.rate_limits
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$snapshot = @{
    provider = 'claude'
    capturedAt = $now
}

foreach ($window in @(
    @{ Key = 'short'; Minutes = 300; Data = $limits.five_hour }
    @{ Key = 'weekly'; Minutes = 10080; Data = $limits.seven_day }
)) {
    $data = $window.Data
    if ($null -ne $data.used_percentage -and $data.resets_at -gt $now) {
        $snapshot[$window.Key] = @{
            usedPercent = [Math]::Clamp([double]$data.used_percentage, 0, 100)
            windowDurationMins = $window.Minutes
            resetsAt = [long]$data.resets_at
        }
    }
}

if ($snapshot.weekly -or $snapshot.short) {
    $CachePath = [IO.Path]::GetFullPath($CachePath)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($CachePath))
    $temporary = "$CachePath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($snapshot | ConvertTo-Json -Depth 4 -Compress))
        [IO.File]::Move($temporary, $CachePath, $true)
    } finally {
        [IO.File]::Delete($temporary)
    }
}

$parts = @(
    if ($snapshot.short) { '5h {0:0}% Left' -f (100 - $snapshot.short.usedPercent) }
    if ($snapshot.weekly) { 'Weekly {0:0}% Left' -f (100 - $snapshot.weekly.usedPercent) }
)
if ($parts.Count) { 'Reset Ring · ' + ($parts -join ' · ') }
else { 'Reset Ring · Claude quota unavailable' }

