# Reset Ring

[English](README.md)

Reset Ring 是一个 Windows 浮层，把分段额度仪表放在 Codex 侧栏底部控件的上方。

## 圆环含义

| 位置 | 显示内容 |
| --- | --- |
| 最外环（显示时） | 5 小时额度余额 |
| 中环，双环模式下为外环 | 周额度余额 |
| 内环 | 本轮周额度窗口的剩余时间 |

Plus 显示三环。其他方案在 Codex 返回 5 小时额度窗口时也显示三环，否则显示双环。每道环分七格，时间环每格代表一天。圆心只显示周额度剩余百分比。

## 使用要求

- Windows 上已打开 Codex 桌面应用，并登录 ChatGPT 账户。
- 已安装 PowerShell 7（`pwsh`），且系统路径中有 Codex CLI（`codex.exe`）。

## 启动

克隆或下载仓库，在仓库目录运行：

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1
```

使用浮层时保持终端运行。关闭该终端即可停止浮层。

如果想作为 Codex skill 使用，把仓库文件夹放到 `$CODEX_HOME/skills` 下。若未设置 `CODEX_HOME`，则放到 `~/.codex/skills`。打开新的 Codex 聊天并调用 `$reset-ring`。

## 操作

- 悬停时圆盘在原位放大，指针在圆盘上隐藏，上方显示额度详情和重置时间。
- 左键依次切换默认、夜航、宝石、工艺、运动五套配色。圆环和提示底色成套切换，适配侧栏的明暗主题，并随各自余额减少逐渐加深。
- 右键切换中英文。默认跟随 Codex 界面语言，Codex 切换语言时会覆盖手动选择。

## 排查

如果圆盘遮挡侧栏控件，可以用 `-Left` 和 `-Bottom` 调整圆心距 Codex 窗口左下角的位置，单位为逻辑像素。

```powershell
pwsh -STA -NoProfile -File scripts/Show-Quota.ps1 -Left 26 -Bottom 158
```

用 `-Probe` 检查当前账户数据。用 `-Demo` 或 `-DemoPlus` 查看模拟数据下的布局。短横线表示该项数据暂不可用。

Reset Ring 通过本机 Codex App Server 读取当前登录账户的额度数据，重置时刻按 Windows 本地时区显示。

## 许可证

[MIT](LICENSE)
