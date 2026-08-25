import AppKit

/// Owns the NSStatusItem. Left click toggles the usage popover; right click
/// (or Ctrl-click) opens a transient menu — the Caffeine pattern.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let store: UsageStore
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.contentViewController = PopoverViewController(store: store)
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        return p
    }()

    var onOpenSettings: (() -> Void)?

    /// Closes the popover on any click outside it. `.transient` alone is
    /// unreliable for an accessory app whose popover never becomes key.
    private var outsideClickMonitor: Any?

    /// `popover.isShown` stays true throughout the close animation, so a quick
    /// second click would be swallowed. Track visibility ourselves.
    private(set) var popoverVisible = false

    init(store: UsageStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.store = store
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        // Default is left-mouse-down only; without this right-click never arrives.
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshIcon), name: .usageDidUpdate, object: nil)
        refreshIcon()
    }

    /// True while the popover is on screen (the updater waits for it to close).
    var isPopoverVisible: Bool { popoverVisible }

    @objc private func refreshIcon() {
        statusItem.button?.image = StatusIcons.icon(forPercent: store.maxUsedPercent)
        let summary = store.tooltipSummary
        statusItem.button?.toolTip = summary.isEmpty ? "UseTokens" : summary
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popoverVisible {
            popoverVisible = false
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popoverVisible = true
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startWatchingForOutsideClicks()
        }
    }

    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.popoverVisible = false
                self?.popover.performClose(nil)
            }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverVisible = false
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func showMenu() {
        // Attach the menu only while it is open; a permanently assigned
        // statusItem.menu would hijack the left click.
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Rebuilt on every open so it always reflects the current language.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: L10n.t("menu.refresh"),
                                 action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: L10n.t("menu.settings"),
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("menu.quit"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    @objc private func refreshFromMenu() {
        store.refresh()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
