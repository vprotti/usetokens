import AppKit

let args = CommandLine.arguments

// Claude Code runs the bundled bridge script, which pipes its status-line JSON
// back into this binary to draw the line. Must stay ahead of any AppKit setup:
// it has to be quick and must never touch the UI.
if args.contains("--statusline") {
    ClaudeStatusLine.renderLine()
    exit(0)
}

// Headless self-tests (used by the build verification, not end users).
if let i = args.firstIndex(of: "--selftest-rollouts"), i + 1 < args.count {
    let snapshot = CodexRollouts.latestSnapshot(baseDir: URL(fileURLWithPath: args[i + 1]))
    SelfTest.printStatus(snapshot)
    exit(0)
}
if args.contains("--selftest-fetch") {
    SelfTest.runFetch(includeClaude: args.contains("--consent"))
    exit(0)
}
if let i = args.firstIndex(of: "--debug-endpoints"), i + 1 < args.count {
    Debug.run(args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--selftest-statusline"), i + 1 < args.count {
    SelfTest.runStatusLine(in: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}
if args.contains("--selftest-notify") {
    _ = NSApplication.shared
    SelfTest.testNotification()
    exit(0)
}
if let i = args.firstIndex(of: "--selftest-shot"), i + 1 < args.count {
    _ = NSApplication.shared
    let path = args[i + 1]
    MainActor.assumeIsolated { SelfTest.renderSiteShot(to: path) }
    exit(0)
}
if let i = args.firstIndex(of: "--selftest-bars"), i + 1 < args.count {
    _ = NSApplication.shared
    SelfTest.renderBars(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--selftest-icons"), i + 1 < args.count {
    _ = NSApplication.shared
    SelfTest.renderTrayStates(to: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--selftest-ui"), i + 1 < args.count {
    _ = NSApplication.shared
    let path = args[i + 1]
    MainActor.assumeIsolated {
        args.contains("--live") ? SelfTest.renderLivePopover(to: path)
                                : SelfTest.renderPopover(to: path)
    }
    exit(0)
}

if args.contains("--selftest-single") { SingleInstance.runSelfTest() }

// One copy at a time, and nothing on this Mac guarantees it on its own: a
// binary exec'd directly — by launchd, or by a LaunchAgent some other
// installer left behind pointing at this path — never passes through Launch
// Services and starts a second app right on top of the first.
guard SingleInstance.claim() else {
    SingleInstance.wakeRunningInstance()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
