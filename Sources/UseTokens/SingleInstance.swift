import AppKit

/// Refuses to let a second copy of this app run.
///
/// macOS already prevents this for anything opened the normal way: Launch
/// Services sees the bundle is running and activates it instead. But a binary
/// exec'd directly — by launchd, by a script, by a stale LaunchAgent another
/// installer left behind pointing at this path — never goes through Launch
/// Services, and nothing stops it. Two menu bar icons appear, two sets of
/// timers run, and for an app that installs an event tap the two copies fight
/// over every keystroke.
///
/// The claim is a file lock rather than a file. A lock belongs to the process,
/// so the kernel releases it however the app ends — quit, crash, force quit —
/// and there is no such thing as a stale lock left behind to wedge the app
/// shut. A PID file would need exactly that cleanup, and would get it wrong.
enum SingleInstance {

    /// Held open for the lifetime of the process. Never closed on purpose:
    /// closing it is what releases the claim.
    private static var descriptor: CInt = -1

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "br.com.nasralla.unknown"
    }

    /// Posted by a second copy on its way out, so the one already running can
    /// show itself instead of the launch appearing to do nothing at all.
    private static var secondLaunchName: String { "\(bundleID).secondLaunch" }

    // MARK: - Claiming

    /// True if this process may run. False means another copy holds the claim
    /// and this one should leave immediately.
    ///
    /// Anything that goes wrong here answers true. A lock that cannot be taken
    /// is a reason to carry on, never a reason to lock someone out of their
    /// own app.
    static func claim() -> Bool {
        guard let url = lockURL() else { return true }

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return true }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        Self.descriptor = descriptor
        return true
    }

    private static func lockURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        else { return nil }

        let directory = support.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent("instance.lock")
    }

    // MARK: - Talking to the copy that won

    /// Called by the copy that is leaving. Delivered immediately because the
    /// process is about to exit and a queued notification would never arrive.
    static func wakeRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(secondLaunchName), object: nil, userInfo: nil,
            deliverImmediately: true)
    }

    /// Called once by the copy that is staying, to react when someone tries to
    /// open the app again — the moment a person most wants to see it.
    static func onSecondLaunch(_ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(secondLaunchName), object: nil, queue: .main
        ) { _ in handler() }
    }

    // MARK: - Proving it

    /// `--selftest-single`: a real second process is asked to start, and has to
    /// be turned away.
    ///
    /// It has to be a second *process*. Two claims inside one would both
    /// succeed — the lock is held per open file, and what matters is what
    /// happens to somebody else.
    static func runSelfTest() -> Never {
        let marker = "NASMAC_SINGLE_INSTANCE_CHILD"
        if ProcessInfo.processInfo.environment[marker] != nil {
            exit(claim() ? 0 : 3)
        }

        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            print("\(condition ? "ok  " : "FAIL") \(label)")
            if !condition { failures += 1 }
        }

        check("the first copy claims it", claim())

        let child = Process()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--selftest-single"]
        var environment = ProcessInfo.processInfo.environment
        environment[marker] = "1"
        child.environment = environment
        do { try child.run() } catch { check("second copy started", false) }
        child.waitUntilExit()
        check("a second copy is turned away", child.terminationStatus == 3)

        print("\nsingle instance: \(failures == 0 ? "all checks passed" : "\(failures) FAILED")")
        exit(failures == 0 ? 0 : 1)
    }
}
