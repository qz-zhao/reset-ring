import AppKit

struct QuotaWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval

    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    var timeLeft: Double {
        guard windowDurationMins > 0 else { return 0 }
        return max(0, min(100, 100 * (resetsAt - Date().timeIntervalSince1970) / Double(60 * windowDurationMins)))
    }
    var isActive: Bool { resetsAt > Date().timeIntervalSince1970 }
}

struct Snapshot: Decodable {
    let plan: String?
    let weekly: QuotaWindow?
    let short: QuotaWindow?
}

struct Palette: Decodable {
    let name: String
    let Dark: [String]
    let Light: [String]
}

enum Provider: String, CaseIterable {
    case codex = "Codex"
    case claude = "Claude"
}

final class ResetRing: NSObject {
    private let scripts: URL
    private let palettes: [Palette]
    private let demo: Bool
    private let item = NSStatusBar.system.statusItem(withLength: 28)
    private let menu = NSMenu()
    private let details = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let claudeCache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ResetRing/claude-quota.json")
    private var provider: Provider = .codex
    private var pinned: Provider?
    private var paletteIndex = 0
    private var codexSnapshot: Snapshot?
    private var codexUpdatedAt = Date.distantPast
    private var nextCodexRead = Date.distantPast
    private var codexReadPending = false
    private var lastDrawing = ""

    init(scripts: URL, palettes: [Palette], demo: Bool) {
        self.scripts = scripts
        self.palettes = palettes
        self.demo = demo
        super.init()
        menu.addItem(details)
        menu.addItem(.separator())
        addItem("Follow active app", #selector(selectProvider(_:)), tag: 0)
        for (index, value) in Provider.allCases.enumerated() {
            addItem(value.rawValue, #selector(selectProvider(_:)), tag: index + 1)
        }
        menu.addItem(.separator())
        for (index, palette) in palettes.enumerated() {
            addItem(palette.name, #selector(selectPalette(_:)), tag: index)
        }
        menu.addItem(.separator())
        addItem("Quit Reset Ring", #selector(quit), tag: 0)
        item.menu = menu
        update()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }

    private func addItem(_ title: String, _ action: Selector, tag: Int) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        menu.addItem(entry)
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        pinned = sender.tag == 0 ? nil : Provider.allCases[sender.tag - 1]
        update()
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        paletteIndex = sender.tag
        update()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshCodex() {
        guard !codexReadPending, Date() >= nextCodexRead else { return }
        codexReadPending = true
        nextCodexRead = Date().addingTimeInterval(45)
        let script = scripts.appendingPathComponent("Show-Quota.ps1").path
        let useDemo = demo
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["pwsh", "-NoProfile", "-File", script, "-Provider", "Codex", "-SnapshotJson"]
            if useDemo { process.arguments?.append("-DemoPlus") }
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var snapshot: Snapshot?
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                }
            } catch {
                // The status item displays unavailable data if the probe fails.
            }
            let result = snapshot
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.codexReadPending = false
                if let result = result {
                    self.codexSnapshot = result
                    self.codexUpdatedAt = Date()
                    if let weekly = result.weekly, weekly.isActive {
                        self.nextCodexRead = min(self.nextCodexRead, Date(timeIntervalSince1970: weekly.resetsAt))
                    }
                }
                self.update()
            }
        }
    }

    private func update() {
        if let pinned = pinned {
            provider = pinned
        } else if let active = NSWorkspace.shared.frontmostApplication {
            let name = (active.localizedName ?? "").lowercased()
            let bundle = (active.bundleIdentifier ?? "").lowercased()
            if name == "claude" || bundle.hasPrefix("com.anthropic.claude") {
                provider = .claude
            } else if ["codex", "chatgpt"].contains(name) || bundle.hasPrefix("com.openai.codex") {
                provider = .codex
            }
        }

        let snapshot: Snapshot?
        if provider == .codex {
            refreshCodex()
            snapshot = Date().timeIntervalSince(codexUpdatedAt) < 120 ? codexSnapshot : nil
        } else if let data = try? Data(contentsOf: claudeCache) {
            snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        } else {
            snapshot = nil
        }
        let weekly = snapshot?.weekly.flatMap { $0.isActive ? $0 : nil }
        let short = snapshot?.short.flatMap { $0.isActive ? $0 : nil }
        let showShort = short != nil || snapshot?.plan == "plus"
        let text = weekly.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        let time = weekly.map { "\(Int($0.timeLeft.rounded()))%" } ?? "—"
        let shortText = short.map { "\(Int($0.remaining.rounded()))%" } ?? "—"
        let date = weekly.map { Date(timeIntervalSince1970: $0.resetsAt).formatted(date: .abbreviated, time: .shortened) }
        let chinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let weeklyLabel = chinese ? "周额度剩余" : "Weekly Left"
        let timeLabel = chinese ? "重置倒计时" : "Time Left"
        var lines = [provider.rawValue]
        if showShort {
            lines.append(chinese ? "5h额度剩余 \(shortText)" : "5h-use Left \(shortText)")
        }
        lines.append("\(weeklyLabel) \(text)")
        lines.append("\(timeLabel) \(time)" + (date.map { " (\($0))" } ?? ""))
        let description = lines.joined(separator: "\n")
        details.title = lines.joined(separator: "  ·  ")
        guard let button = item.button else { return }
        button.toolTip = description
        button.setAccessibilityLabel(description)
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let values = [short?.remaining ?? 0, weekly?.remaining ?? 0, weekly?.timeLeft ?? 0]
        let drawing = "\(dark)/\(paletteIndex)/\(showShort)/\(text)/\(values.map { Int($0 * 10) })"
        if drawing != lastDrawing {
            lastDrawing = drawing
            let palette = palettes[paletteIndex]
            button.image = dial(colors: dark ? palette.Dark : palette.Light, dark: dark,
                                showShort: showShort, values: values, text: text)
        }
    }

    private func dial(colors: [String], dark: Bool, showShort: Bool, values: [Double], text: String) -> NSImage {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: 12, y: 12)
            let radii: [CGFloat] = showShort ? [10.5, 8.2, 5.9] : [0, 10.5, 7.4]
            let track = NSColor(white: dark ? 0.42 : 0.68, alpha: 1)
            for index in (showShort ? 0 : 1)..<3 {
                let width: CGFloat = index == 1 ? 1.55 : 1
                let rgb = UInt32(colors[index].dropFirst(), radix: 16) ?? 0
                let tint = 0.14 * values[index] / 100
                func channel(_ shift: UInt32) -> CGFloat {
                    let base = Double((rgb >> shift) & 255) / 255
                    return CGFloat(base + (1 - base) * tint)
                }
                let fill = NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
                for segment in 0..<7 {
                    let start = CGFloat(-92 - Double(segment) * 360 / 7)
                    let length = CGFloat(360.0 / 7 - 4)
                    func stroke(_ fraction: CGFloat, color: NSColor) {
                        guard fraction > 0 else { return }
                        let path = NSBezierPath()
                        path.appendArc(withCenter: center, radius: radii[index], startAngle: start,
                                       endAngle: start - length * fraction, clockwise: true)
                        path.lineWidth = width
                        color.setStroke()
                        path.stroke()
                    }
                    stroke(1, color: track)
                    stroke(CGFloat(max(0, min(1, values[index] * 7 / 100 - Double(segment)))), color: fill)
                }
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: showShort ? 4.5 : 6, weight: .semibold),
                .foregroundColor: dark ? NSColor.white : NSColor.black
            ]
            let label = NSAttributedString(string: text, attributes: attributes)
            let measured = label.size()
            label.draw(at: NSPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}

let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let paletteFile = scripts.appendingPathComponent("palettes.json")
let palettes = try JSONDecoder().decode([Palette].self, from: Data(contentsOf: paletteFile))
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let resetRing = ResetRing(scripts: scripts, palettes: palettes, demo: CommandLine.arguments.contains("--demo"))
withExtendedLifetime(resetRing) { app.run() }
