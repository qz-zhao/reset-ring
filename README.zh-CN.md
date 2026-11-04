# Reset Ring

[English](README.md)

Reset Ring 显示 Codex 和 Claude 的额度与重置时间。Windows 版贴在当前应用窗口上，macOS 版显示在菜单栏。

## 圆环含义

| 位置 | 显示内容 |
| --- | --- |
| 最外环（显示时） | 5 小时额度余额 |
| 中环，双环模式下为外环 | 周额度余额 |
| 内环 | 本轮周额度窗口的剩余时间 |

Codex Plus 和存在有效 5 小时额度窗口的账户显示三环，其余情况显示双环。每道环分七格，时间环每格代表一天。圆心只显示周额度剩余百分比。

## Windows 启动

安装 PowerShell 7。使用 Codex 时，还需将已登录 ChatGPT 的 Codex CLI 加入系统路径。克隆或下载本仓库，在仓库目录运行：

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1
```

浮层跟随前台的 Codex 或 Claude 桌面窗口。使用时保持终端运行。用 `-Provider Claude` 或 `-Provider Codex` 可以限定为单一应用。

## macOS 启动

macOS 菜单栏版目前是预览。需要 macOS 12 或更高版本、Xcode 命令行工具，以及系统路径中的 PowerShell 7。使用 Codex 时，还需将已登录的 Codex CLI 加入系统路径。

```sh
swift scripts/ResetRing.swift
```

切到 Codex 或 Claude 桌面应用时，菜单栏仪表自动切换。使用终端时可以从菜单手动选定数据源，菜单里也能换配色和退出。加 `--demo` 可查看模拟 Plus 三环。菜单栏配色适配系统明暗外观，额度提示跟随系统首选语言。

## 接入 Claude

Claude 使用 Claude Code 官方的 [状态栏](https://code.claude.com/docs/en/statusline) 数据。将以下配置合并到 `~/.claude/settings.json`，把路径替换为脚本的绝对路径。如果已有状态栏，先把命令整合到现有脚本里。

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"/absolute/path/to/reset-ring/scripts/Claude-StatusLine.ps1\""
  }
}
```

Windows 也可使用正斜线，例如 `C:/Tools/reset-ring/scripts/Claude-StatusLine.ps1`。Claude Code 收到包含额度的回复后，会把用量百分比和重置时间写到本机缓存。Claude 桌面浮层读取最近一次缓存，额度窗口过期后停止显示该读数。终端里也可直接通过 Claude Code 状态栏查看。

如果想作为 Codex skill 使用，把仓库文件夹放到 `$CODEX_HOME/skills` 下。若未设置 `CODEX_HOME`，则放到 `~/.codex/skills`。打开新的 Codex 聊天并调用 `$reset-ring`。

## Windows 操作

- 悬停时圆盘在原位放大，指针在圆盘上隐藏，上方显示额度详情和重置时间。
- 左键依次切换默认、夜航、宝石、工艺、运动五套配色。圆环和提示底色成套切换，适配侧栏的明暗主题，并随各自余额减少逐渐加深。
- 右键切换中英文。默认跟随 Codex 界面语言，Codex 切换语言时会覆盖手动选择。

## 排查

如果圆盘遮挡侧栏控件，可以用 `-Left` 和 `-Bottom` 调整圆心距 Codex 窗口左下角的位置，单位为逻辑像素。

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1 -Left 26 -Bottom 158
```

用 `-Probe` 检查当前账户数据。用 `-Demo` 或 `-DemoPlus` 查看模拟数据下的布局。短横线表示该项数据暂不可用。

Codex 额度通过本机 Codex App Server 读取，重置时刻按系统时区显示。

## 许可证

[MIT](LICENSE)
