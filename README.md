# Reset Ring

[简体中文](README.zh-CN.md)

Reset Ring displays Codex and Claude quota and reset times. On Windows it follows the active desktop window. On macOS it appears in the menu bar.

## Switch colors and language

| Platform | Change palette | Switch Chinese / English |
| --- | --- | --- |
| Windows | Left-click the ring to cycle through Default, Night Flight, Gemstone, Craft, and Sport. | Right-click the ring to switch the hover text. By default it follows the Codex interface language. If the Codex language changes again, the hover text follows that change. |
| macOS | Click the menu bar ring and select a palette by name. | Change the system's preferred language. Quota labels use Chinese when Chinese is first in that list, and English otherwise. |

## What the rings show

| Position | Readout |
| --- | --- |
| Outside, when shown | Remaining five-hour quota |
| Middle, or outside in two-ring mode | Remaining weekly quota |
| Inside | Time remaining in the current weekly window |

Codex Plus and accounts with an active five-hour window use three rings. Other accounts use two. Each ring has seven segments. Each segment of the weekly time ring represents one day. The center shows only the remaining weekly quota percentage.

## Run on Windows

Install PowerShell 7. For Codex, put the Codex CLI on PATH and sign in with ChatGPT. Clone or download this repository and run from its root:

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1
```

The overlay uses the foreground Codex or Claude desktop window. Keep the terminal open while using it. Add `-Provider Claude` or `-Provider Codex` to limit it to one app.

## Run on macOS

The macOS menu bar implementation is a preview. It requires macOS 12 or later, the Xcode Command Line Tools, and PowerShell 7 on PATH. For Codex, the signed-in Codex CLI must also be on PATH.

```sh
swift scripts/ResetRing.swift
```

The menu bar follows Codex or Claude when either desktop app comes forward. Choose a provider manually from the menu when using a terminal. Choose a palette or quit from the same menu. Run with `--demo` to preview a simulated Codex Plus dial. The Mac menu adapts to system appearance and uses the system's preferred language for quota labels.

## Enable Claude data

Claude data comes from Claude Code's [status line](https://code.claude.com/docs/en/statusline). Add the following entry to `~/.claude/settings.json` using the actual absolute script path. If you already have a status line, integrate this command into your existing handler before replacing anything.

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"/absolute/path/to/reset-ring/scripts/Claude-StatusLine.ps1\""
  }
}
```

On Windows you can use an absolute path with forward slashes, such as `C:/Tools/reset-ring/scripts/Claude-StatusLine.ps1`. Once Claude Code receives a reply with quota data, the status line updates a local cache used by the gauge. The cache holds usage percentages and reset timestamps. Claude Desktop displays the last Claude Code snapshot until the relevant window expires. The Claude Code status line also works in the terminal independently of the gauge.

To use Reset Ring as a Codex skill, place this repository folder under `$CODEX_HOME/skills`, or under `~/.codex/skills` if `CODEX_HOME` is unset. Open a new Codex chat and invoke `$reset-ring`.

## Windows controls

- Hover to enlarge the ring in place and see quota details and reset times. The pointer hides over the enlarged ring.
- Left-click to cycle through Default, Night Flight, Gemstone, Craft, and Sport. The rings and tooltip backgrounds change together. Colors adjust to the sidebar's light or dark theme and deepen as each balance falls.
- Right-click to switch the tooltip between Chinese and English. By default the tooltip follows the Codex desktop language. A change in the app's language takes precedence over the manual override.

## Troubleshooting

If the ring overlaps a sidebar control, use `-Left` and `-Bottom` to adjust its center relative to the lower-left corner of the Codex window, in logical pixels.

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1 -Left 26 -Bottom 158
```

Use `-Probe` to check account data without opening a window. Use `-Demo` or `-DemoPlus` to test the layout with synthetic data. A dash means the relevant value is unavailable.

Codex data comes from the local Codex App Server under your current sign-in. Reset times use the system time zone.

## License

[MIT](LICENSE)
