import AppKit

protocol UsageProvider {
    var id: String { get }
    /// Product name — never localized ("ChatGPT · Codex", "Claude").
    var displayName: String { get }
    var glyph: NSImage { get }
    /// One entry per signed-in account. Never throws — every failure becomes a
    /// degraded ProviderStatus instead.
    func fetchAll() async -> [ProviderStatus]
}
