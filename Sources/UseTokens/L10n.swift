import Foundation

extension Notification.Name {
    static let languageDidChange = Notification.Name("br.com.nasralla.usetokens.languageDidChange")
}

enum Language: String, CaseIterable {
    case en = "en"
    case ptBR = "pt-BR"
}

enum L10n {
    /// Pre-selects the welcome picker. `preferredLanguages` reflects the user's
    /// real language ranking (AppleLanguages), unlike the region-biased Locale.current.
    static func detectSystemLanguage() -> Language {
        (Locale.preferredLanguages.first?.lowercased().hasPrefix("pt") ?? false) ? .ptBR : .en
    }

    static var current: Language {
        get {
            guard let raw = Prefs.appLanguage, let lang = Language(rawValue: raw) else {
                return detectSystemLanguage()
            }
            return lang
        }
        set {
            Prefs.appLanguage = newValue.rawValue
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    static var locale: Locale {
        Locale(identifier: current == .ptBR ? "pt_BR" : "en_US")
    }

    static func t(_ key: String) -> String {
        guard let pair = table[key] else { return key }
        return current == .ptBR ? pair.pt : pair.en
    }

    private static let table: [String: (en: String, pt: String)] = [
        "menu.refresh": (en: "Refresh", pt: "Atualizar"),
        "menu.settings": (en: "Settings…", pt: "Ajustes…"),
        "menu.quit": (en: "Quit UseTokens", pt: "Sair do UseTokens"),

        "popover.lastChecked": (en: "Last checked: %@", pt: "Última verificação: %@"),
        "popover.refreshTooltip": (en: "Refresh now", pt: "Atualizar agora"),

        "window.5h": (en: "Current session", pt: "Sessão atual"),
        "window.week": (en: "Week", pt: "Semana"),
        "window.weekAll": (en: "Week · all models", pt: "Semana · todos os modelos"),
        "window.weekModel": (en: "Week · %@", pt: "Semana · %@"),
        "window.extra": (en: "Extra usage", pt: "Uso extra"),
        "group.general": (en: "General limits", pt: "Limites gerais"),

        "resets.now": (en: "resets now", pt: "reseta agora"),
        "resets.lineTime": (en: "resets at %@ · in %@", pt: "reseta às %@ · em %@"),
        "resets.lineDate": (en: "resets %@ · in %@", pt: "reseta %@ · em %@"),
        "resets.unknown": (en: "waiting for the first reset", pt: "aguardando o primeiro reset"),
        "state.reset": (en: "reset at %@ · was at %d%%", pt: "resetou às %@ · estava em %d%%"),

        "notify.resetTitle": (en: "%@ reset", pt: "%@ resetou"),
        "notify.resetBody": (en: "The %@ limit is back to zero (was at %d%%).",
                             pt: "O limite de %@ voltou ao zero (estava em %d%%)."),

        "state.notConnected.codex": (en: "Not connected — open the ChatGPT app",
                                     pt: "Não conectado — abra o app ChatGPT"),
        "state.notConnected.claude": (en: "Not connected — open the Claude app",
                                      pt: "Não conectado — abra o app Claude"),
        "state.localReading": (en: "local", pt: "local"),
        "state.readAgo": (en: "read %@ ago", pt: "lido há %@"),
        "state.expiredToken.codex": (en: "Credential expired — open the ChatGPT app to renew",
                                     pt: "Credencial expirada — abra o app ChatGPT para renovar"),
        "claude.connectHint": (en: "Connect Claude Code in Settings for exact limits",
                               pt: "Conecte o Claude Code nos Ajustes para limites exatos"),
        // Shown instead of a percentage when the only reading available is old.
        // Repeating a stale number as if it were current is the one thing this
        // app must never do.
        "claude.noReading": (
            en: "Signed in, no reading yet. Open Claude Code in Terminal once and the limits appear here.",
            pt: "Conectado, ainda sem leitura. Abra o Claude Code no Terminal uma vez e os limites aparecem aqui."),
        "claude.noReadingHint": (
            en: "This reading is from earlier — nothing has reported since. Open Claude Code in Terminal for a current one.",
            pt: "Esta leitura é de antes — nada reportou desde então. Abra o Claude Code no Terminal para ter uma atual."),

        "settings.claudeStatusLine": (en: "Read Claude Code usage",
                                      pt: "Ler o uso do Claude Code"),
        "settings.claudeStatusLineHint": (
            en: "Adds a status line to Claude Code in Terminal so it reports its own limits here. No login is read, and turning this off restores your previous status line. The Claude desktop app has no status line, so it cannot report this way — for exact limits there, run \"claude auth login\" in Terminal once.",
            pt: "Adiciona uma linha de status ao Claude Code no Terminal para ele informar os próprios limites aqui. Nenhum login é lido, e ao desligar sua linha de status anterior volta. O app Claude para Mac não tem linha de status, então não consegue informar por essa via — para limites exatos nele, rode \"claude auth login\" no Terminal uma vez."),

        "settings.menuBarBars": (en: "Show usage in the menu bar",
                                 pt: "Mostrar o uso na barra de menus"),
        "settings.menuBarBarsHint": (
            en: "Two bars for each service: the current session on top, the week below. Only current readings are drawn — a service with nothing to report is left out rather than shown at an old length.",
            pt: "Duas barrinhas para cada serviço: a sessão atual em cima, a semana embaixo. Só leituras atuais são desenhadas — um serviço sem número recente fica de fora em vez de aparecer com um valor velho."),

        "settings.privacy": (en: "Privacy", pt: "Privacidade"),
        "settings.privacyBody": (
            en: "Everything stays on this Mac. UseTokens has no server, no account and no analytics — nothing about you is stored on the internet or shipped inside the app. It reads what ChatGPT and Claude already wrote on your own disk, and asks their APIs directly using the login those apps already made.",
            pt: "Tudo fica neste Mac. O UseTokens não tem servidor, conta nem análise de uso — nada seu é guardado na internet nem vai dentro do app. Ele lê o que o ChatGPT e o Claude já gravaram no seu próprio disco e consulta as APIs deles direto, usando o login que esses apps já fizeram."),

        "settings.notifyOnReset": (en: "Notify when limits reset", pt: "Notificar quando resetar"),
        "settings.notifyHint": (en: "Plays a short sound and notifies you when a spent limit rolls over.",
                                pt: "Toca um som curto e avisa quando um limite esgotado volta ao zero."),
    ]
}
