# Reset Ring

[简体中文](README.zh-CN.md)

Reset Ring is a Windows overlay for Codex. It puts a small, segmented quota gauge above the controls at the bottom of the Codex sidebar.

## What the rings show

| Position | Readout |
| --- | --- |
| Outside, when shown | Remaining five-hour quota |
| Middle, or outside in two-ring mode | Remaining weekly quota |
| Inside | Time remaining in the current weekly window |

Plus uses three rings. Other plans use two unless Codex returns a five-hour quota window. Each ring has seven segments. Each segment of the weekly time ring represents one day. The center shows only the remaining weekly quota percentage.

## Requirements

- Windows with the Codex desktop app and a signed-in ChatGPT account.
- PowerShell 7 (`pwsh`) and a Codex CLI (`codex.exe`) available on PATH.

## Run

Clone or download this repository. From its root, run:

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1
```

Keep the terminal open while using the overlay. Close it to stop the overlay.

To use Reset Ring as a Codex skill, place this repository folder under `$CODEX_HOME/skills`, or under `~/.codex/skills` if `CODEX_HOME` is unset. Open a new Codex chat and invoke `$reset-ring`.

## Controls

- Hover to enlarge the ring in place and see quota details and reset times. The pointer hides over the enlarged ring.
- Left-click to cycle through Default, Night Flight, Gemstone, Craft, and Sport. The rings and tooltip backgrounds change together. Colors adjust to the sidebar's light or dark theme and deepen as each balance falls.
- Right-click to switch the tooltip between Chinese and English. By default the tooltip follows the Codex desktop language. A change in the app's language takes precedence over the manual override.

## Troubleshooting

If the ring overlaps a sidebar control, use `-Left` and `-Bottom` to adjust its center relative to the lower-left corner of the Codex window, in logical pixels.

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1 -Left 26 -Bottom 158
```

Use `-Probe` to check account data without opening a window. Use `-Demo` or `-DemoPlus` to test the layout with synthetic data. A dash means the relevant value is unavailable.

Reset Ring reads the quota data exposed by the local Codex App Server under your current sign-in. Reset times are displayed in the Windows local time zone.

## License

[MIT](LICENSE)
