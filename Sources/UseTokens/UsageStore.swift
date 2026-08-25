import AppKit

extension Notification.Name {
    static let usageDidUpdate = Notification.Name("br.com.nasralla.usetokens.usageDidUpdate")
    static let usageRefreshStateChanged = Notification.Name("br.com.nasralla.usetokens.refreshState")
}

/// Orchestrates the providers: parallel fetches, background timer, wake
/// refresh, reset tracking, and a disk cache (percentages/dates only) so the
/// popover paints instantly on launch.
final class UsageStore {
    let providers: [UsageProvider]
    private(set) var statuses: [ProviderStatus] = []
    private(set) var isRefreshing = false {
        didSet { NotificationCenter.default.post(name: .usageRefreshStateChanged, object: nil) }
    }
    private var backgroundTimer: Timer?

    init(providers: [UsageProvider]) {
        self.providers = providers
        loadCache()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wakeRefresh),
            name: NSWorkspace.didWakeNotification, object: nil)
        restartTimer()
    }

    /// Replaces the statuses outright. Only the screenshot renderer uses this:
    /// it needs to paint a given state exactly, without the age-stamping that
    /// loading from the cache correctly applies.
    func seed(_ statuses: [ProviderStatus]) {
        self.statuses = statuses
        NotificationCenter.default.post(name: .usageDidUpdate, object: nil)
    }

    func provider(withID id: String) -> UsageProvider? {
        providers.first { $0.id == id }
    }

    /// The provider behind a status, for its mark and product name.
    func provider(for status: ProviderStatus) -> UsageProvider? {
        providers.first { $0.id == status.providerID }
    }

    var providerNames: [String: String] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) })
    }

    @objc private func wakeRefresh() {
        refresh()
    }

    func restartTimer() {
        backgroundTimer?.invalidate()
        let interval = TimeInterval(max(5, Prefs.refreshIntervalMinutes)) * 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    /// `manual` refreshes bypass the per-provider rate gates and re-check
    /// credentials from scratch, so signing into another account shows up
    /// immediately when the user presses the button.
    func refresh(manual: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        if manual { ClaudeProvider.invalidateGate() }

        let providers = self.providers
        Task {
            // Each provider reports every account it can see; the flattened
            // list is one card per account, in provider order.
            var indexed: [(Int, [ProviderStatus])] = []
            await withTaskGroup(of: (Int, [ProviderStatus]).self) { group in
                for (index, provider) in providers.enumerated() {
                    group.addTask { (index, await provider.fetchAll()) }
                }
                for await item in group { indexed.append(item) }
            }
            let results = indexed.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
            await MainActor.run {
                let events = UsageHistory.record(results)
                self.statuses = results
                self.saveCache()
                self.isRefreshing = false
                NotificationCenter.default.post(name: .usageDidUpdate, object: nil)
                Notifier.announce(events, providerNames: self.providerNames)
            }
        }
    }

    // MARK: - Cache (never contains tokens — ProviderStatus is data-only)

    /// Painting the popover instantly at launch is worth a cache, but the
    /// numbers in it were true when they were written and not a moment since.
    /// Every window is stamped with that moment on the way in, so the card says
    /// "read N ago" instead of passing an old percentage off as current. The
    /// refresh that starts at launch replaces all of it within seconds.
    private func loadCache() {
        guard let data = Prefs.cachedStatusJSON,
              let cached = try? JSONDecoder().decode([ProviderStatus].self, from: data)
        else { return }

        statuses = cached.map { status in
            var status = status
            status.source = status.source == .live ? .localSnapshot : status.source
            status.groups = status.groups.map { group in
                var group = group
                group.windows = group.windows.map { window in
                    var window = window
                    window.readAt = window.readAt ?? status.lastUpdated
                    return window
                }
                return group
            }
            return status
        }
    }

    private func saveCache() {
        Prefs.cachedStatusJSON = try? JSONEncoder().encode(statuses)
    }

    /// Highest used percentage across every window (drives the status icon).
    var maxUsedPercent: Double {
        statuses.flatMap { $0.allWindows }.compactMap { $0.usedPercent }.max() ?? 0
    }

    /// e.g. "Codex 12% · Claude 33%" for the status item tooltip. With more
    /// than one account of the same provider, the label carries the account.
    var tooltipSummary: String {
        let parts = statuses.compactMap { status -> String? in
            guard let top = status.allWindows.compactMap({ $0.usedPercent }).max() else { return nil }
            var name = status.providerID == "codex" ? "Codex" : "Claude"
            let siblings = statuses.filter { $0.providerID == status.providerID }.count
            if siblings > 1, let account = status.accountLabel { name += " \(account)" }
            return "\(name) \(Int(top.rounded()))%"
        }
        return parts.joined(separator: " · ")
    }
}
