param(
    [int]$Left = 26,
    [int]$Bottom = 158,
    [switch]$Demo,
    [switch]$DemoPlus,
    [switch]$Probe,
    [switch]$SnapshotJson
)

$ErrorActionPreference = 'Stop'

function Get-QuotaWindow($snapshot, [int]$minutes) {
    @($snapshot.primary, $snapshot.secondary) |
        Where-Object { $_.windowDurationMins -eq $minutes -and $_.resetsAt -gt 0 -and $null -ne $_.usedPercent } |
        Select-Object -First 1
}

function Get-Percentages($weekly, [long]$now) {
    if (!$weekly -or $weekly.resetsAt -le $now) { return }
    [pscustomobject]@{
        Quota = [Math]::Clamp(100.0 - $weekly.usedPercent, 0, 100)
        Time = [Math]::Clamp(100.0 * ($weekly.resetsAt - $now) / (60 * $weekly.windowDurationMins), 0, 100)
        ResetsAt = [DateTimeOffset]::FromUnixTimeSeconds($weekly.resetsAt).LocalDateTime
    }
}

function Send-Request($server, $message) {
    $server.StandardInput.WriteLine(($message | ConvertTo-Json -Depth 8 -Compress))
}

function Get-CodexLocale([string]$configPath) {
    try {
        $config = [IO.File]::ReadAllText($configPath)
        $desktop = [regex]::Match($config, '(?ms)^\s*\[desktop\][^\r\n]*\r?\n(.*?)(?=^\s*\[|\z)')
        $locale = [regex]::Match($desktop.Groups[1].Value, '(?m)^\s*localeOverride\s*=\s*["'']([a-zA-Z0-9_-]+)["'']')
        if ($locale.Success) { return $locale.Groups[1].Value }
    } catch [IO.FileNotFoundException] {
    } catch [IO.DirectoryNotFoundException] {
    } catch [IO.IOException] {
        return
    } catch [UnauthorizedAccessException] {
        return
    }
    [Globalization.CultureInfo]::CurrentUICulture.Name
}

$overlayMutex = $null
if ($IsWindows -and !$Probe -and !$SnapshotJson) {
    $overlayMutex = [Threading.Mutex]::new($false, 'Local\ResetRing.Overlay')
    try { $acquired = $overlayMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (!$acquired) { $overlayMutex.Dispose(); return }
}
$server = $null
try {
    $Demo = $Demo -or $DemoPlus
    $Probe = $Probe -or $SnapshotJson
    if (!$IsWindows -and !$Probe) { throw 'Use scripts/ResetRing.swift for the macOS menu bar.' }
    $codexExecutable = if ($IsWindows) { 'codex.exe' } else { 'codex' }
    $codexCommand = Get-Command $codexExecutable -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$codexCommand -and $env:RESET_RING_CODEX_EXE -and (Test-Path -LiteralPath $env:RESET_RING_CODEX_EXE)) {
        $codexCommand = [pscustomobject]@{ Source = $env:RESET_RING_CODEX_EXE }
    }
    if (!$Demo -and !$codexCommand) {
        throw 'Codex CLI was not found on PATH.'
    }
    if (!$Demo -and $codexCommand) {
        try {
            $start = [Diagnostics.ProcessStartInfo]::new($codexCommand.Source, 'app-server --listen stdio://')
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardInput = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $server = [Diagnostics.Process]::Start($start)
            $null = $server.StandardError.ReadToEndAsync()
            Send-Request $server @{ id = 1; method = 'initialize'; params = @{
                clientInfo = @{ name = 'codex-quota-overlay'; version = '0.1.0' }
            }}
            do {
                $line = $server.StandardOutput.ReadLineAsync().WaitAsync([TimeSpan]::FromSeconds(15)).GetAwaiter().GetResult()
                if (!$line) { throw 'Codex App Server exited during initialization.' }
                $message = $line | ConvertFrom-Json
            } until ($message.id -eq 1)
            if ($message.error) { throw $message.error.message }
            Send-Request $server @{ method = 'initialized' }
        } catch {
            throw
        }
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($Demo) {
        $weekly = @{ usedPercent = 32; windowDurationMins = 10080; resetsAt = $now + 345600 }
    }
    if ($DemoPlus) {
        $plan = 'plus'
        $short = @{ usedPercent = 23; windowDurationMins = 300; resetsAt = $now + 7200 }
    }
    if ($Probe) {
        if ($server) {
            Send-Request $server @{ id = 2; method = 'account/rateLimits/read' }
            do {
                $line = $server.StandardOutput.ReadLineAsync().WaitAsync([TimeSpan]::FromSeconds(20)).GetAwaiter().GetResult()
                if (!$line) { throw 'Codex App Server exited while reading quota.' }
                $message = $line | ConvertFrom-Json
            } until ($message.id -eq 2)
            if ($message.error) { throw $message.error.message }
            $snapshot = $message.result.rateLimitsByLimitId.codex ?? $message.result.rateLimits
            $weekly = Get-QuotaWindow $snapshot 10080
            $short = Get-QuotaWindow $snapshot 300
            $plan = $snapshot.planType
        }
        if ($SnapshotJson) {
            $source = 'codex'
            @{ provider = $source; plan = $plan; weekly = $weekly; short = $short } | ConvertTo-Json -Depth 4 -Compress
            return
        }
        $percentages = Get-Percentages $weekly ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        if (!$percentages) { throw 'No active weekly quota window was found.' }
        $percentages | Add-Member -NotePropertyName Plan -NotePropertyValue $plan
        $percentages | Add-Member -NotePropertyName FiveHourQuota -NotePropertyValue (Get-Percentages $short $now).Quota
        $percentages
        return
    }

    Add-Type -AssemblyName PresentationFramework
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class OverlayWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out int id);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern uint GetPixel(IntPtr dc, int x, int y);
    public static bool? IsLightSidebar(int x, int y, int step) {
        IntPtr dc = GetDC(IntPtr.Zero);
        if (dc == IntPtr.Zero) return null;
        try {
            int light = 0, dark = 0;
            for (int i = -1; i <= 1; i++) {
                uint rgb = GetPixel(dc, x, y + i * step);
                if (rgb == uint.MaxValue) continue;
                uint brightness = 299 * (rgb & 255) + 587 * ((rgb >> 8) & 255) + 114 * ((rgb >> 16) & 255);
                if (brightness > 150000) light++; else dark++;
            }
            return light == dark ? (bool?)null : light > dark;
        } finally { ReleaseDC(IntPtr.Zero, dc); }
    }
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr window, int index, int value);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int w, int h, uint flags);
}
"@
    $window = [Windows.Window]::new()
    $window.Width = $window.Height = 40
    $window.WindowStyle = 'None'
    $window.ResizeMode = 'NoResize'
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Topmost = $true

    $grid = [Windows.Controls.Grid]::new()
    $grid.Width = $grid.Height = 40
    $grid.Background = [Windows.Media.Brushes]::Transparent
    $grid.ForceCursor = $true
    $grid.Cursor = [Windows.Input.Cursors]::Hand
    $zoom = [Windows.Media.ScaleTransform]::new(1, 1)
    $grid.LayoutTransform = $zoom
    $converter = [Windows.Media.BrushConverter]::new()
    $hitSurface = [Windows.Shapes.Ellipse]::new()
    $hitSurface.Width = $hitSurface.Height = 36
    $hitSurface.Fill = $converter.ConvertFromString('#161A20')
    $null = $grid.Children.Add($hitSurface)
    $window.Content = $grid
    function Set-Segment($path, [double]$radius, [int]$day, [double]$fill) {
        if ($fill -le 0) { $path.Data = $null; return }
        $gapDegrees = 4
        $startAngle = 90 + 360 * $day / 7 + $gapDegrees / 2
        $endAngle = $startAngle + (360 / 7 - $gapDegrees) * $fill
        $start = $startAngle * [Math]::PI / 180
        $end = $endAngle * [Math]::PI / 180
        $figure = [Windows.Media.PathFigure]::new()
        $figure.StartPoint = [Windows.Point]::new((20 + $radius * [Math]::Cos($start)), (20 + $radius * [Math]::Sin($start)))
        $arc = [Windows.Media.ArcSegment]::new()
        $arc.Point = [Windows.Point]::new((20 + $radius * [Math]::Cos($end)), (20 + $radius * [Math]::Sin($end)))
        $arc.Size = [Windows.Size]::new($radius, $radius)
        $arc.SweepDirection = 'Clockwise'
        $figure.Segments.Add($arc)
        $geometry = [Windows.Media.PathGeometry]::new()
        $geometry.Figures.Add($figure)
        $path.Data = $geometry
    }

    $palettes = Get-Content -Raw (Join-Path $PSScriptRoot "palettes.json") | ConvertFrom-Json
    $rings = @(
        foreach ($kind in @('FiveHour', 'Weekly', 'Time')) {
            $tracks = [Collections.Generic.List[object]]::new()
            $segments = @(
                for ($day = 0; $day -lt 7; $day++) {
                    $track = [Windows.Shapes.Path]::new()
                    $track.IsHitTestVisible = $false
                    $tracks.Add($track)
                    $null = $grid.Children.Add($track)
                    $segment = [Windows.Shapes.Path]::new()
                    $segment.IsHitTestVisible = $false
                    $null = $grid.Children.Add($segment)
                    $segment
                }
            )
            @{ Kind = $kind; Tracks = $tracks; Segments = $segments }
        }
    )

    $label = [Windows.Controls.TextBlock]::new()
    $label.FontSize = 11
    $label.FontWeight = 'SemiBold'
    $label.TextAlignment = 'Center'
    $label.HorizontalAlignment = $label.VerticalAlignment = 'Center'
    $label.Foreground = [Windows.Media.Brushes]::White
    $label.IsHitTestVisible = $false
    $readout = [Windows.Controls.Viewbox]::new()
    $readout.Width = 20
    $readout.Height = 14
    $readout.StretchDirection = 'DownOnly'
    $readout.HorizontalAlignment = $readout.VerticalAlignment = 'Center'
    $readout.IsHitTestVisible = $false
    $readout.Child = $label
    $null = $grid.Children.Add($readout)
    function Get-RemainingBrush([string]$hex, [double]$percent) {
        $color = [Windows.Media.ColorConverter]::ConvertFromString($hex)
        $tint = 0.14 * [Math]::Clamp($percent, 0, 100) / 100
        $red = [byte]($color.R + (255 - $color.R) * $tint)
        $green = [byte]($color.G + (255 - $color.G) * $tint)
        $blue = [byte]($color.B + (255 - $color.B) * $tint)
        [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb($red, $green, $blue))
    }

    function Get-ContrastingText($background) {
        $color = $background.Color
        $linear = foreach ($channel in @($color.R, $color.G, $color.B)) {
            $value = $channel / 255.0
            if ($value -le 0.04045) { $value / 12.92 }
            else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        $luminance = 0.2126 * $linear[0] + 0.7152 * $linear[1] + 0.0722 * $linear[2]
        if ($luminance -ge 0.17913) { [Windows.Media.Brushes]::Black }
        else { [Windows.Media.Brushes]::White }
    }

    $hoverPanel = [Windows.Controls.StackPanel]::new()
    $hoverRows = @(
        for ($row = 0; $row -lt 3; $row++) {
            $text = [Windows.Controls.TextBlock]::new()
            $text.FontSize = 13
            $text.FontWeight = 'Bold'
            $card = [Windows.Controls.Border]::new()
            $card.CornerRadius = [Windows.CornerRadius]::new(6)
            $card.Padding = [Windows.Thickness]::new(8, 4, 8, 4)
            if ($row -lt 2) { $card.Margin = [Windows.Thickness]::new(0, 0, 0, 3) }
            $card.Child = $text
            $null = $hoverPanel.Children.Add($card)
            @{ Card = $card; Text = $text }
        }
    )
    $popup = [Windows.Controls.Primitives.Popup]::new()
    $popup.AllowsTransparency = $true
    $popup.IsHitTestVisible = $false
    $popup.PlacementTarget = $grid
    $popup.Placement = 'Top'
    $popup.VerticalOffset = -5
    $popup.Child = $hoverPanel

    $handle = [Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
    $extendedStyle = [OverlayWindow]::GetWindowLong($handle, -20)
    $null = [OverlayWindow]::SetWindowLong($handle, -20, ($extendedStyle -bor 0x08000080))

    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $configPath = Join-Path $codexHome 'config.toml'
    $state = @{
        Weekly = $weekly
        Short = $short
        Plan = $plan
        Palette = 0
        Locale = $null
        English = $true
        NextLocaleRead = 0
        NextRead = 0
        PendingSince = 0
        RequestId = 1
        FreshUntil = 0
        LastForeground = [IntPtr]::Zero
        ActiveProvider = $null
        LightTheme = $false
    }
    $hitSurface.Add_MouseRightButtonDown({
        $state.English = !$state.English
        $_.Handled = $true
    })
    $hitSurface.Add_MouseLeftButtonDown({
        $state.Palette = ($state.Palette + 1) % $palettes.Count
        $_.Handled = $true
    })
    if ($server) {
        Send-Request $server @{ id = -1; method = 'account/read'; params = @{ refreshToken = $false } }
        $state.Line = $server.StandardOutput.ReadLineAsync()
    }
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($now -ge $state.NextLocaleRead) {
            $state.NextLocaleRead = $now + 1
            $locale = Get-CodexLocale $configPath
            if ($locale -and $locale -ne $state.Locale) {
                $state.Locale = $locale
                $state.English = $locale -notmatch '^zh(?:[-_]|$)'
            }
        }
        if ($server -and !$server.HasExited -and !$state.EndOfStream) {
            for ($i = 0; $i -lt 32 -and $state.Line.IsCompleted; $i++) {
                $line = $state.Line.GetAwaiter().GetResult()
                if ($null -eq $line) { $state.EndOfStream = $true; break }
                $state.Line = $server.StandardOutput.ReadLineAsync()
                $message = $line | ConvertFrom-Json
                if ($message.id -eq -1 -and $message.result.account.planType) {
                    $state.Plan = $message.result.account.planType
                }
                if ($message.id -eq $state.RequestId) {
                    $state.PendingSince = 0
                    if ($message.result) {
                        $snapshot = $message.result.rateLimitsByLimitId.codex ?? $message.result.rateLimits
                        $state.Weekly = Get-QuotaWindow $snapshot 10080
                        $state.Short = Get-QuotaWindow $snapshot 300
                        if ($snapshot.planType) { $state.Plan = $snapshot.planType }
                        $state.FreshUntil = $now + 120
                    }
                }
                if ($message.method -eq 'account/rateLimits/updated') {
                    $snapshot = $message.params.rateLimits
                    if ($snapshot.limitId -eq 'codex') {
                        $updated = Get-QuotaWindow $snapshot 10080
                        $shortUpdate = Get-QuotaWindow $snapshot 300
                        if ($shortUpdate) { $state.Short = $shortUpdate }
                        if ($snapshot.planType) { $state.Plan = $snapshot.planType }
                        if ($updated) {
                            $state.Weekly = $updated
                            $state.FreshUntil = $now + 120
                        }
                    }
                }
            }
            if ($state.PendingSince -and $now - $state.PendingSince -ge 20) { $state.PendingSince = 0 }
            if (!$state.EndOfStream -and !$state.PendingSince -and $now -ge $state.NextRead) {
                $state.RequestId++
                Send-Request $server @{ id = $state.RequestId; method = 'account/rateLimits/read' }
                $state.PendingSince = $now
                $state.NextRead = $now + 30
                if ($state.Weekly.resetsAt -gt $now) {
                    $state.NextRead = [Math]::Min($state.NextRead, $state.Weekly.resetsAt)
                }
            }
        }

        $target = [OverlayWindow]::GetForegroundWindow()
        if ($target -ne $state.LastForeground) {
            $state.LastForeground = $target
            $ownerId = 0
            $null = [OverlayWindow]::GetWindowThreadProcessId($target, [ref]$ownerId)
            $processName = (Get-Process -Id $ownerId -ErrorAction SilentlyContinue).ProcessName
            $state.ActiveProvider = $processName -in @('Codex', 'ChatGPT')
        }
        if (!$state.ActiveProvider -or [OverlayWindow]::IsIconic($target)) {
            $popup.IsOpen = $false
            if ($window.IsVisible) { $window.Hide() }
            return
        }

        $rect = [OverlayWindow+Rect]::new()
        if (![OverlayWindow]::GetClientRect($target, [ref]$rect)) { return }
        $origin = [OverlayWindow+Point]::new()
        if (![OverlayWindow]::ClientToScreen($target, [ref]$origin)) { return }
        $scale = [OverlayWindow]::GetDpiForWindow($target) / 96.0
        $centerX = $origin.X + [int]($Left * $scale)
        $centerY = $origin.Y + $rect.Bottom - [int]($Bottom * $scale)
        $cursor = [OverlayWindow+Point]::new()
        $hover = [OverlayWindow]::GetCursorPos([ref]$cursor) -and
            ([Math]::Pow($cursor.X - $centerX, 2) + [Math]::Pow($cursor.Y - $centerY, 2) -le [Math]::Pow(20 * $scale, 2))
        $factor = if ($hover) { 1.5 } else { 1.0 }
        if ($zoom.ScaleX -ne $factor) {
            $zoom.ScaleX = $zoom.ScaleY = $factor
            $window.Width = $window.Height = 40 * $factor
            $grid.Cursor = if ($hover) { [Windows.Input.Cursors]::None } else { [Windows.Input.Cursors]::Hand }
        }
        $size = [int](40 * $scale * $factor)
        $x = $centerX - [int]($size / 2)
        $y = $centerY - [int]($size / 2)
        $null = [OverlayWindow]::SetWindowPos($handle, [IntPtr](-1), $x, $y, $size, $size, 0x0010)
        if (!$window.IsVisible) { $window.Show() }
        $fresh = $Demo -or $now -lt $state.FreshUntil
        $weeklyWindow = $state.Weekly
        $shortWindow = $state.Short
        $plan = $state.Plan
        $values = if ($fresh) { Get-Percentages $weeklyWindow $now }
        # Sample the composited sidebar at its left edge, outside the overlay.
        $sampleX = $origin.X + [int](4 * $scale)
        $sampleY = $origin.Y + $rect.Bottom - [int](108 * $scale)
        $lightTheme = [OverlayWindow]::IsLightSidebar($sampleX, $sampleY, [int](19 * $scale))
        if ($null -ne $lightTheme) { $state.LightTheme = $lightTheme }
        $showFiveHour = $plan -eq 'plus' -or ($fresh -and $shortWindow.resetsAt -gt $now)
        $shortValues = if ($fresh -and $showFiveHour) { Get-Percentages $shortWindow $now }
        $fiveHour = $shortValues.Quota
        $weeklyText = if ($values) { '{0:0}%' -f $values.Quota } else { '—' }
        $timeText = if ($values) { '{0:0}%' -f $values.Time } else { '—' }
        $readout.Width = if ($showFiveHour) { 11.5 } else { 17 }
        $readout.Height = if ($showFiveHour) { 9 } else { 12.5 }
        $label.Text = $weeklyText.TrimEnd('%')

        if ($hover) {
            $duration = '—'
            $resetDate = '—'
            if ($values) {
                $remaining = [TimeSpan]::FromSeconds($weeklyWindow.resetsAt - $now)
                $duration = if ($remaining.Days -gt 0) {
                    '{0}d {1}h' -f $remaining.Days, $remaining.Hours
                } else {
                    '{0}h {1}m' -f $remaining.Hours, $remaining.Minutes
                }
                $resetDate = $values.ResetsAt.ToString('MM-dd HH:mm')
            }
            $hoverRows[0].Card.Visibility = if ($showFiveHour) { 'Visible' } else { 'Collapsed' }
            if ($showFiveHour) {
                $shortText = if ($shortValues) { '{0:0}%' -f $fiveHour } else { '—' }
                $shortReset = if ($shortValues) { $shortValues.ResetsAt.ToString('HH:mm') } else { '—' }
                $hoverRows[0].Text.Text = if ($state.English) { "5h-use Left $shortText (reset at $shortReset)" }
                else { "5h额度剩余 $shortText" }
            }
            $hoverRows[1].Text.Text = if ($state.English) { "Weekly Left $weeklyText ($duration)" }
            else { "周额度剩余 $weeklyText ($duration)" }
            $hoverRows[2].Text.Text = if ($state.English) { "Time Left $timeText ($resetDate)" }
            else { "重置倒计时 $timeText ($resetDate)" }
        }
        $popup.IsOpen = $hover

        $renderKey = "$($state.LightTheme)/$showFiveHour/$($state.Palette)/$($values.Quota)/$($values.Time)/$fiveHour"
        if ($state.RenderKey -ne $renderKey) {
            $state.RenderKey = $renderKey
            $palette = $palettes[$state.Palette]
            $colors = if ($state.LightTheme) { $palette.Light } else { $palette.Dark }
            $shortBrush = Get-RemainingBrush $colors[0] $fiveHour
            $weeklyBrush = Get-RemainingBrush $colors[1] $values.Quota
            $timeBrush = Get-RemainingBrush $colors[2] $values.Time
            $hitSurface.Fill = $converter.ConvertFromString($(if ($state.LightTheme) { '#F8FAFB' } else { '#161A20' }))
            $trackBrush = $converter.ConvertFromString($(if ($state.LightTheme) { '#B9C1C9' } else { '#3E4652' }))
            $label.Foreground = Get-ContrastingText $hitSurface.Fill
            $hoverRows[0].Card.Background = $shortBrush
            $hoverRows[1].Card.Background = $weeklyBrush
            $hoverRows[2].Card.Background = $timeBrush
            foreach ($row in $hoverRows) {
                $row.Text.Foreground = Get-ContrastingText $row.Card.Background
            }
            foreach ($ring in $rings) {
                switch ($ring.Kind) {
                    'FiveHour' { $radius = 17; $percent = $fiveHour; $width = 1.5; $brush = $shortBrush }
                    'Weekly' { $radius = if ($showFiveHour) { 13 } else { 17 }; $percent = $values.Quota; $width = 2.4; $brush = $weeklyBrush }
                    'Time' { $radius = if ($showFiveHour) { 9 } else { 12 }; $percent = $values.Time; $width = 1.5; $brush = $timeBrush }
                }
                for ($day = 0; $day -lt 7; $day++) {
                    $track = $ring.Tracks[$day]
                    $segment = $ring.Segments[$day]
                    $strokeWidth = if ($state.LightTheme -and $ring.Kind -eq 'Weekly') { 2.7 } else { $width }
                    $track.StrokeThickness = $segment.StrokeThickness = $strokeWidth
                    $track.Stroke = $trackBrush
                    $segment.Stroke = $brush
                    $trackFill = if ($ring.Kind -eq 'FiveHour' -and !$showFiveHour) { 0 } else { 1 }
                    $fill = [Math]::Clamp(7 * [double]$percent / 100 - $day, 0, 1)
                    Set-Segment $track $radius $day $trackFill
                    Set-Segment $segment $radius $day $fill
                }
            }
        }
    })
    $timer.Start()
    [Windows.Threading.Dispatcher]::Run()
} finally {
    if ($overlayMutex) { $overlayMutex.ReleaseMutex(); $overlayMutex.Dispose() }
    if ($timer) { $timer.Stop() }
    if ($server) {
        if (!$server.HasExited) { $server.Kill() }
        $server.Dispose()
    }
}
