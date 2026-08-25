import Foundation

enum RelativeTime {
    /// "reseta às 20:57 · em 1 h 36 min" — the clock time answers *when*, the
    /// countdown answers *how long*, and together they need no mental math.
    static func resetString(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds < 60 { return L10n.t("resets.now") }

        let pt = L10n.current == .ptBR
        let sameDay = Calendar.current.isDate(date, inSameDayAs: Date())
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = sameDay
            ? (pt ? "HH:mm" : "h:mm a")
            : (pt ? "dd/MM HH:mm" : "M/d h:mm a")

        return String(format: L10n.t(sameDay ? "resets.lineTime" : "resets.lineDate"),
                      formatter.string(from: date), duration(seconds: seconds))
    }

    /// "resetou às 20:57 · estava em 93%".
    static func resetNotice(at date: Date, percentBefore: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = L10n.current == .ptBR ? "HH:mm" : "h:mm a"
        return String(format: L10n.t("state.reset"),
                      formatter.string(from: date), Int(percentBefore.rounded()))
    }

    static func duration(seconds: TimeInterval) -> String {
        let pt = L10n.current == .ptBR
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return pt ? "\(minutes) min" : "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            let m = minutes % 60
            if pt { return m > 0 ? "\(hours) h \(m) min" : "\(hours) h" }
            return m > 0 ? "\(hours)h \(m)m" : "\(hours)h"
        }
        let days = hours / 24
        let h = hours % 24
        if pt { return h > 0 ? "\(days) d \(h) h" : "\(days) d" }
        return h > 0 ? "\(days)d \(h)h" : "\(days)d"
    }

    /// Absolute timestamp in the language's regional convention:
    /// pt-BR → 24/08/2026 15:45 · en → 8/24/2026 3:45 PM.
    static func lastChecked(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = L10n.current == .ptBR ? "dd/MM/yyyy HH:mm" : "M/d/yyyy h:mm a"
        return formatter.string(from: date)
    }

    /// Compact token count: 1.234 → "1,2 k" (pt) / "1.2k" (en); 2_400_000 → "2,4 mi" / "2.4M".
    static func formatTokens(_ n: Int) -> String {
        let pt = L10n.current == .ptBR
        func decimal(_ v: Double) -> String {
            let s = String(format: "%.1f", v)
            return pt ? s.replacingOccurrences(of: ".", with: ",") : s
        }
        if n >= 1_000_000 { return decimal(Double(n) / 1_000_000) + (pt ? " mi" : "M") }
        if n >= 1_000 { return decimal(Double(n) / 1_000) + (pt ? " mil" : "k") }
        return "\(n)"
    }
}
