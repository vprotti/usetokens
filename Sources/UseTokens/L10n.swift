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
            en: "No current reading — open Claude Code and the limits appear here.",
            pt: "Sem leitura atual — abra o Claude Code e os limites aparecem aqui."),
        "claude.noReadingHint": (
            en: "No current reading. Open Claude Code once and the limits appear here.",
            pt: "Sem leitura atual. Abra o Claude Code uma vez e os limites aparecem aqui."),
        "state.localReadingTip": (en: "Read from the app installed on this Mac, not from the API.",
                                  pt: "Lido do app instalado neste Mac, não da API."),
        "state.estimateTip": (en: "Estimated from local Claude Code transcripts.",
                              pt: "Estimado a partir das conversas locais do Claude Code."),
        "state.estimate": (en: "estimate", pt: "estimativa"),
        "state.expiredToken.claude": (en: "Session expired — open Claude Code to renew",
                                      pt: "Sessão expirada — abra o Claude Code para renovar"),
        "state.rateLimited": (en: "API rate limited — retrying soon",
                              pt: "Limite da API — tentando de novo em breve"),

        "tokens.last5h": (en: "≈ %@ tokens in the last 5 h",
                          pt: "≈ %@ tokens nas últimas 5 h"),

        "claude.connect": (en: "Connect to Claude", pt: "Conectar ao Claude"),
        "claude.keychainHint": (
            en: "macOS will ask for Keychain access to read the Claude Code credential. Click \"Always Allow\" — this happens only once.",
            pt: "O macOS vai pedir acesso às Chaves para ler a credencial do Claude Code. Clique em \"Sempre Permitir\" — isso acontece só uma vez."),

        "welcome.title": (en: "Welcome to UseTokens", pt: "Bem-vindo ao UseTokens"),
        "welcome.subtitle": (en: "Choose your language", pt: "Escolha seu idioma"),
        "welcome.continue": (en: "Continue", pt: "Continuar"),
        "welcome.hint": (en: "Your ChatGPT and Claude usage, right in the menu bar.",
                         pt: "Seu uso do ChatGPT e do Claude, direto na barra de menus."),

        "settings.title": (en: "UseTokens Settings", pt: "Ajustes do UseTokens"),
        "settings.launchAtLogin": (en: "Launch at login", pt: "Iniciar com o Mac"),
        "settings.loginHint": (en: "Move UseTokens to the Applications folder to enable this.",
                               pt: "Mova o UseTokens para a pasta Aplicativos para ativar isto."),
        "settings.autoUpdate": (en: "Update automatically", pt: "Atualizar automaticamente"),
        "settings.autoUpdateHint": (en: "Checks nasmac.app daily and installs new versions on its own.",
                                    pt: "Verifica o nasmac.app diariamente e instala as novidades sozinho."),
        "settings.language": (en: "Language", pt: "Idioma"),
        "settings.refreshEvery": (en: "Refresh every", pt: "Atualizar a cada"),
        "settings.minutes": (en: "%d min", pt: "%d min"),
        "settings.claudeCredential": (en: "Use the Claude Code credential",
                                     pt: "Usar a credencial do Claude Code"),
        "settings.claudeCredentialHint": (
            en: "Optional: reads Claude Code's saved login to show exact limits and reset times. macOS will ask for Keychain access once.",
            pt: "Opcional: lê o login salvo do Claude Code para mostrar limites e horários exatos. O macOS vai pedir acesso às Chaves uma vez."),
        "settings.claudeStatusLine": (en: "Read Claude Code usage",
                                      pt: "Ler o uso do Claude Code"),
        "settings.claudeStatusLineHint": (
            en: "Adds a status line to Claude Code so it reports its own limits to UseTokens. No login is read. Turning this off restores your previous status line.",
            pt: "Adiciona uma linha de status ao Claude Code para ele informar os próprios limites ao UseTokens. Nenhum login é lido. Ao desligar, sua linha de status anterior volta."),

        "settings.privacy": (en: "Privacy", pt: "Privacidade"),
        "settings.privacyBody": (
            en: "Everything stays on this Mac. UseTokens has no server, no account and no analytics — nothing about you is stored on the internet or shipped inside the app. It reads what ChatGPT and Claude already wrote on your own disk, and asks their APIs directly using the login those apps already made.",
            pt: "Tudo fica neste Mac. O UseTokens não tem servidor, conta nem análise de uso — nada seu é guardado na internet nem vai dentro do app. Ele lê o que o ChatGPT e o Claude já gravaram no seu próprio disco e consulta as APIs deles direto, usando o login que esses apps já fizeram."),

        "settings.notifyOnReset": (en: "Notify when limits reset", pt: "Notificar quando resetar"),
        "settings.notifyHint": (en: "Plays a short sound and notifies you when a spent limit rolls over.",
                                pt: "Toca um som curto e avisa quando um limite esgotado volta ao zero."),
    ]
}
