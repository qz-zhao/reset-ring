---
name: reset-ring
description: Launch, position, or troubleshoot Reset Ring for ChatGPT Codex quota on Windows and macOS.
---

Run `scripts/Show-Quota.ps1` with PowerShell 7 in STA mode from the signed-in Windows desktop. Keep the process running while the overlay is needed.

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1
```

The overlay follows the foreground ChatGPT Codex window without taking focus. Left-click the rings to cycle through five palettes. Hover text follows the Codex interface language. Right-click to override it until the Codex language changes again. The rings start at the bottom and fill clockwise. Hover to enlarge the icon and see weekly quota and the reset countdown. Plus and accounts with an active five-hour quota window show three rings for five-hour quota, weekly quota, and weekly time remaining, from outside in. Other accounts use the last two colors. All five palettes adapt to the visible sidebar theme. The time ring starts at 100% at the beginning of the weekly window. Each ring has seven segments. Each quota segment is one seventh of its quota window and each weekly time segment is one day. The center readout shows only weekly quota remaining and scales to fit. Hover enlarges the original icon in place and hides the pointer over it. A dash indicates unavailable data.

Use `-Left` and `-Bottom` to adjust the center of the overlay relative to the Codex client area's lower-left corner, in logical pixels. Use `-Demo` or `-DemoPlus` to check the layouts with synthetic data. Use `-Probe` to check account data without opening a window. Close the PowerShell process to stop the overlay.

The script uses Codex App Server with the current Codex sign-in. It selects the 10,080-minute window in the Codex bucket. If the account omits that window, report that weekly data is unavailable.
On macOS, run `swift scripts/ResetRing.swift` from the skill directory. The preview displays ChatGPT Codex quota in the macOS menu bar.

## Install on Windows

When asked to install Reset Ring on Windows, run `pwsh -NoProfile -File scripts/Set-AutoStart.ps1` after placing the skill in its final location, unless the user opts out. A login watcher starts the gauge when ChatGPT or Codex desktop opens, regardless of which shortcut was used. It stops the gauge when the desktop app exits. Verify that the watcher starts a gauge process. Use `-Remove` to disable automatic startup. Re-run the installer after updates.
