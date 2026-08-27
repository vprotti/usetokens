import AppKit

/// Headless verification helpers (never part of the user flow).
/// Output is ProviderStatus data only — percentages, dates, states. No tokens.
enum SelfTest {
    static func printStatus(_ status: ProviderStatus?) {
        guard let status else {
            print("null")
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(status), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    /// Fires the reset announcement once, to verify the notification + sound
    /// path from inside a real bundle (it is a no-op under `swift run`).
    static func testNotification() {
        Prefs.registerDefaults()
        let wasEnabled = Prefs.notifyOnReset
        Prefs.notifyOnReset = true
        Notifier.requestAuthorizationIfNeeded()

        let event = UsageHistory.ResetEvent(
            windowID: "selftest.5h", providerID: "claude", labelKey: "window.5h",
            groupTitle: nil, at: Date(), percentBefore: 93)
        Notifier.announce([event], providerNames: ["claude": "Claude"])
        print("notification requested (authorization prompt may appear)")

        // Give the center time to deliver before the process exits.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        Prefs.notifyOnReset = wasEnabled
    }

    /// Renders the three menu bar states over both menu bar shades.
    /// Renders the menu bar bars over both menu bar shades, in the states that
    /// matter: two services, one service, a nearly-full window, a full one.
    static func renderBars(to path: String) {
        let scale: CGFloat = 5
        let teal = StatusIcons.teal, claude = StatusIcons.claudeTint
        let cases: [[StatusIcons.Bars]] = [
            [.init(session: 12, week: 2, tint: teal),
             .init(session: 72, week: 32, tint: claude)],
            [.init(session: 4, week: 24, tint: claude)],
            [.init(session: 93, week: 41, tint: teal),
             .init(session: 100, week: 88, tint: claude)],
            [.init(session: 0, week: 0, tint: teal),
             .init(session: nil, week: 55, tint: claude)],
        ]
        let images = cases.compactMap { StatusIcons.barsIcon($0) }
        guard !images.isEmpty else { return }

        // Wider than the 5 pt that separates two services inside one menu bar
        // item, or the cases would read as one long row of unrelated bars.
        let gap: CGFloat = 80
        let width = images.reduce(gap) { $0 + $1.size.width * scale + gap }
        let rowHeight = 18 * scale + 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(rowHeight * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: rowHeight, width: width, height: rowHeight).fill()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: rowHeight).fill()

        for (row, appearance) in [NSAppearance(named: .darkAqua), NSAppearance(named: .aqua)].enumerated() {
            appearance?.performAsCurrentDrawingAppearance {
                var x = gap
                for image in images {
                    let w = image.size.width * scale
                    image.draw(in: NSRect(x: x, y: CGFloat(1 - row) * rowHeight + 8,
                                          width: w, height: 18 * scale))
                    x += w + gap
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    static func renderTrayStates(to path: String) {
        let scale: CGFloat = 4
        let cell = 18 * scale
        let width = Int(cell) * 3 + 40
        let height = Int(cell) * 2 + 30
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: CGFloat(height) / 2, width: CGFloat(width),
               height: CGFloat(height) / 2).fill()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height) / 2).fill()

        for (index, percent) in [0.0, 93.0, 100.0].enumerated() {
            let x = CGFloat(10 + index * (Int(cell) + 10))
            for y in [CGFloat(height) / 2 + 12, 12] {
                let image = StatusIcons.icon(forPercent: percent)
                image.draw(in: NSRect(x: x, y: y, width: cell, height: cell))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    /// Renders the popover with the real providers' current data.
    @MainActor
    static func renderLivePopover(to path: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var live: [ProviderStatus] = []
        Task {
            live = await CodexProvider().fetchAll() + ClaudeProvider().fetchAll()
            semaphore.signal()
        }
        // The fetch runs on a background executor; keep the main runloop alive.
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let saved = Prefs.cachedStatusJSON
        defer { Prefs.cachedStatusJSON = saved }
        Prefs.cachedStatusJSON = try? JSONEncoder().encode(live)
        renderCurrentCache(to: path)
    }

    /// Renders the popover with crafted statuses to a PNG for visual review.
    @MainActor
    static func renderPopover(to path: String) {
        let saved = Prefs.cachedStatusJSON
        defer { Prefs.cachedStatusJSON = saved }

        let now = Date()
        func window(_ id: String, _ label: String, _ percent: Double?,
                    _ resetsIn: TimeInterval, _ minutes: Int) -> LimitWindow {
            LimitWindow(id: id, labelKey: label, usedPercent: percent,
                        resetsAt: now.addingTimeInterval(resetsIn),
                        windowMinutes: minutes, tokensUsed: nil, readAt: nil)
        }

        /// A weekly window that belongs to one model, the way Claude reports them.
        func model(_ id: String, _ name: String, _ percent: Double,
                   _ resetsIn: TimeInterval) -> LimitWindow {
            LimitWindow(id: id, labelKey: "window.weekModel", labelArgument: name,
                        usedPercent: percent, resetsAt: now.addingTimeInterval(resetsIn),
                        windowMinutes: 10080, tokensUsed: nil, readAt: nil)
        }

        let fake: [ProviderStatus] = [
            ProviderStatus(
                providerID: "codex", accountID: "c1",
                accountLabel: Accounts.mask(email: "pessoa@exemplo.com"),
                groups: [
                    LimitGroup(title: nil, windows: [
                        window("d.codex.week", "window.week", 9, 535_000, 10080),
                    ]),
                    LimitGroup(title: "GPT-5.3-Codex-Spark", windows: [
                        window("d.spark.5h", "window.5h", 86, 5_760, 300),
                        window("d.spark.week", "window.week", 41, 604_000, 10080),
                    ]),
                ],
                planType: "pro", source: .live, lastUpdated: now, state: .ok, noteKey: nil),
            ProviderStatus(
                providerID: "claude", accountID: "a1",
                accountLabel: Accounts.mask(email: "pessoa@exemplo.com"),
                groups: [
                    LimitGroup(title: nil, windows: [
                        window("d.claude.5h", "window.5h", 72, 10_400, 300),
                        window("d.claude.week", "window.weekAll", 32, 200_000, 10080),
                        model("d.claude.fable", "Fable", 33, 200_000),
                    ]),
                ],
                planType: "Max 20x", source: .live, lastUpdated: now, state: .ok, noteKey: nil),
            ProviderStatus(
                providerID: "claude", accountID: "a2",
                accountLabel: Accounts.mask(email: "trabalho@exemplo.com"),
                groups: [
                    LimitGroup(title: nil, windows: [
                        window("d.claude2.5h", "window.5h", 8, 9_000, 300),
                    ]),
                ],
                planType: "pro", source: .live, lastUpdated: now, state: .ok, noteKey: nil),
        ]
        renderCurrentCache(to: path, seeding: fake)
    }

    /// Snapshots the popover as it would paint from whatever is in the cache.
    @MainActor
    private static func renderCurrentCache(to path: String,
                                           seeding statuses: [ProviderStatus]? = nil) {
        let store = UsageStore(providers: [CodexProvider(), ClaudeProvider()])
        if let statuses { store.seed(statuses) }
        let vc = PopoverViewController(store: store)
        let content = vc.view

        // Stand-in for the popover's dark material so the snapshot is readable.
        let view = NSView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let size = content.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("could not create rep"); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        Self.lastPopover = rep
        guard !path.isEmpty else { return }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    /// Kept by `renderCurrentCache` so the site shot can reuse the popover it
    /// just painted instead of building the whole view tree a second time.
    private static var lastPopover: NSBitmapImageRep?

    /// The landscape image the website shows on the UseTokens card: the menu
    /// bar reading on the left, the popover it opens on the right, on the same
    /// dark slab the other two apps use so the three cards read as a set.
    @MainActor
    static func renderSiteShot(to path: String) {
        renderPopover(to: "")
        guard let popover = lastPopover,
              let bars = StatusIcons.barsIcon([
                .init(session: 12, week: 9, tint: StatusIcons.teal),
                .init(session: 72, week: 32, tint: StatusIcons.claudeTint)])
        else { return }

        let scale: CGFloat = 2
        let size = NSSize(width: 1180, height: 700)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.114, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                         xRadius: 26, yRadius: 26).fill()

            // The popover, at its own proportions, down the right-hand side.
            let popHeight: CGFloat = 620
            let popWidth = popHeight * (popover.size.width / popover.size.height)
            let popRect = NSRect(x: size.width - 56 - popWidth,
                                 y: (size.height - popHeight) / 2,
                                 width: popWidth, height: popHeight)
            let rounded = NSBezierPath(roundedRect: popRect, xRadius: 16, yRadius: 16)
            NSGraphicsContext.saveGraphicsState()
            rounded.setClip()
            popover.draw(in: popRect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
            rounded.lineWidth = 1
            rounded.stroke()

            // A slice of menu bar on the left, at the size it really appears,
            // and the same reading blown up underneath so the bars are legible
            // on a website. The two together are what the app looks like.
            let column = NSRect(x: 56, y: 0, width: popRect.minX - 56 - 40, height: size.height)
            let stripHeight: CGFloat = 64
            let bigScale: CGFloat = 9
            let big = NSSize(width: bars.size.width * bigScale,
                             height: bars.size.height * bigScale)
            let spacing: CGFloat = 96
            let blockHeight = stripHeight + spacing + big.height
            let strip = NSRect(x: column.minX, y: column.midY + blockHeight / 2 - stripHeight,
                               width: column.width, height: stripHeight)

            NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
            NSBezierPath(roundedRect: strip, xRadius: 15, yRadius: 15).fill()

            // Status items live at the right end of a menu bar, next to the
            // clock — putting them anywhere else would not read as one.
            let clock = NSAttributedString(string: "14:07", attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.74, alpha: 1)])
            let clockSize = clock.size()
            clock.draw(at: NSPoint(x: strip.maxX - 34 - clockSize.width,
                                   y: strip.midY - clockSize.height / 2))

            let barScale: CGFloat = 2.6
            let barSize = NSSize(width: bars.size.width * barScale,
                                 height: bars.size.height * barScale)
            bars.draw(in: NSRect(x: strip.maxX - 34 - clockSize.width - 30 - barSize.width,
                                 y: strip.midY - barSize.height / 2,
                                 width: barSize.width, height: barSize.height))

            bars.draw(in: NSRect(x: column.midX - big.width / 2,
                                 y: strip.minY - spacing - big.height,
                                 width: big.width, height: big.height))
        }
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    /// `--consent` opts the run into the Keychain path. Claude is always
    /// exercised; the flag only decides whether the credential route is allowed
    /// to run, so the credential-free detection can be checked on its own —
    /// which is the case that has to work for everybody.
    static func runFetch(includeClaude: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for status in await CodexProvider().fetchAll() {
                print("== codex ==")
                printStatus(status)
            }
            Prefs.registerDefaults()
            let hadConsent = Prefs.claudeKeychainConsent
            Prefs.claudeKeychainConsent = includeClaude
            let claudeStatuses = await ClaudeProvider().fetchAll()
            Prefs.claudeKeychainConsent = hadConsent

            if claudeStatuses.isEmpty { print("== claude ==\nno signed-in Claude found") }
            for status in claudeStatuses {
                print("== claude ==")
                printStatus(status)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
    // MARK: - Claude status-line bridge

    /// Exercises install/uninstall against a scratch home, so the real
    /// ~/.claude/settings.json is never a test subject. Checks the three
    /// things that would hurt a user: unrelated keys survive, an existing
    /// status line is chained rather than replaced, and uninstall puts it back.
    /// Runs `sh -c <command>` with a usage payload on stdin, the way Claude
    /// Code invokes a status line, and reports whether it exited cleanly.
    private static func shellRuns(_ command: String, home: URL) -> Bool {
        guard !command.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        // The script runs this binary again; without this the child would
        // write its fixture over the user's real reading.
        var environment = ProcessInfo.processInfo.environment
        environment["USETOKENS_HOME"] = home.path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        input.fileHandleForWriting.write(
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#.utf8))
        try? input.fileHandleForWriting.close()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func runStatusLine(in scratch: URL) {
        let fm = FileManager.default
        ClaudeStatusLine.homeOverride = scratch
        defer { ClaudeStatusLine.homeOverride = nil }

        let settings = scratch.appendingPathComponent(".claude/settings.json")
        try? fm.createDirectory(at: settings.deletingLastPathComponent(),
                                withIntermediateDirectories: true)

        func read() -> [String: Any] {
            guard let data = try? Data(contentsOf: settings),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return obj
        }
        func write(_ obj: [String: Any]) {
            let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            try! data.write(to: settings)
        }

        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(label)")
            if !condition { failures += 1 }
        }

        // 1. A user with unrelated settings and no status line.
        write(["someOtherSetting": true])
        check("install succeeds", ClaudeStatusLine.install())
        var now = read()
        check("unrelated key kept", now["someOtherSetting"] as? Bool == true)
        check("registered", ClaudeStatusLine.isInstalled())
        check("script is executable",
              fm.isExecutableFile(atPath: ClaudeStatusLine.scriptURL.path))
        check("install is idempotent", ClaudeStatusLine.install())

        // The regression this whole path exists for. Claude Code runs the
        // configured command *through a shell* — that is what lets people write
        // `ccusage | tail -1` — so a path containing a space is split into two
        // words and the command dies with "No such file or directory", every
        // time, in silence. Ask a shell to run it exactly the way Claude Code
        // does, unquoted, and insist the reading comes out the other end.
        let registered = (read()["statusLine"] as? [String: Any])?["command"] as? String ?? ""
        check("command path has no space", !registered.contains(" "))
        try? fm.removeItem(at: ClaudeStatusLine.dumpURL)
        check("a shell can run it unquoted", shellRuns(registered, home: scratch))
        check("the reading reached disk",
              fm.fileExists(atPath: ClaudeStatusLine.dumpURL.path))

        // 2. Uninstall removes the key and leaves everything else alone.
        check("uninstall succeeds", ClaudeStatusLine.uninstall())
        now = read()
        check("statusLine gone", now["statusLine"] == nil)
        check("unrelated key still kept", now["someOtherSetting"] as? Bool == true)

        // 3. A user who already had their own status line keeps it.
        write(["statusLine": ["type": "command", "command": "/usr/local/bin/mine.sh",
                              "padding": 2, "hideVimModeIndicator": true]])
        check("install over existing", ClaudeStatusLine.install())
        now = read()
        let entry = now["statusLine"] as? [String: Any] ?? [:]
        check("ours is the command",
              entry["command"] as? String == ClaudeStatusLine.scriptURL.path)
        let stashed = entry["UseTokensOriginal"] as? [String: Any] ?? [:]
        check("theirs is stashed whole", stashed["command"] as? String == "/usr/local/bin/mine.sh")
        let script = (try? String(contentsOf: ClaudeStatusLine.scriptURL, encoding: .utf8)) ?? ""
        check("script calls theirs", script.contains("/usr/local/bin/mine.sh"))
        check("uninstall restores theirs", ClaudeStatusLine.uninstall())
        let restored = read()["statusLine"] as? [String: Any] ?? [:]
        check("theirs is back", restored["command"] as? String == "/usr/local/bin/mine.sh")
        check("their extra keys survive", restored["hideVimModeIndicator"] as? Bool == true)

        // 4. Reading a payload back.
        try? fm.createDirectory(at: ClaudeStatusLine.supportDirectory,
                                withIntermediateDirectories: true)
        // Relative to now: a window whose reset has already passed is treated
        // as rolled over, so a hard-coded timestamp would rot the test.
        let fiveHourReset = Int(Date().addingTimeInterval(2 * 3600).timeIntervalSince1970)
        let weekReset = Int(Date().addingTimeInterval(3 * 24 * 3600).timeIntervalSince1970)
        let payload = """
        {"rate_limits":{"five_hour":{"used_percentage":72,"resets_at":\(fiveHourReset)},\
        "seven_day":{"used_percentage":32,"resets_at":\(weekReset)},\
        "broken":{"used_percentage":1787620380}}}
        """
        try? payload.write(to: ClaudeStatusLine.dumpURL, atomically: true, encoding: .utf8)
        let reading = ClaudeStatusLine.latest()
        check("payload parsed", reading != nil)
        check("two sane windows, bogus one dropped", reading?.windows.count == 2)
        check("five_hour is 72",
              reading?.windows.first { $0.field == "five_hour" }?.percent == 72)
        check("reset parsed", reading?.windows.first { $0.field == "five_hour" }?.resetsAt
                == Date(timeIntervalSince1970: TimeInterval(fiveHourReset)))

        print(failures == 0 ? "\nstatusline: all checks passed"
                            : "\nstatusline: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

}
