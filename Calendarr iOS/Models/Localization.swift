import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system, de, en

    var displayKey: String {
        switch self {
        case .system: return "lang.system"
        case .de:     return "lang.german"
        case .en:     return "lang.english"
        }
    }
}

enum L10n {
    static func resolved(_ stored: String) -> String {
        if stored == "de" || stored == "en" { return stored }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.lowercased().hasPrefix("de") ? "de" : "en"
    }

    static func t(_ key: String, _ stored: String) -> String {
        let lang = resolved(stored)
        return strings[lang]?[key] ?? strings["en"]?[key] ?? key
    }

    static func locale(_ stored: String) -> Locale {
        Locale(identifier: resolved(stored))
    }
}

private let strings: [String: [String: String]] = [
    "de": [
        // Top bar / navigation
        "nav.today": "Heute",
        "nav.menu": "Menü",
        "nav.done": "Fertig",

        // View types
        "view.month": "Monat",
        "view.week": "Woche",
        "view.day": "Tag",
        "view.quarter": "Quartal",
        "view.agenda": "Termine",
        "view.change": "Ansicht",

        // Calendar misc
        "cal.cw": "KW",
        "cal.allday": "Ganztägig",
        "cal.no_events_title": "Keine Termine",
        "cal.no_events_body": "In den nächsten 90 Tagen sind keine Termine vorhanden.",
        "cal.loading_more": "Lade weitere Wochen…",
        "cal.new_event": "Neues Ereignis",
        "cal.show_in_day_view": "In Tagesansicht öffnen",
        "cal.show_in_week_view": "In Wochenansicht öffnen",
        "cal.show_in_month_view": "In Monatsansicht öffnen",

        // Menu sheet
        "menu.section.settings": "Einstellungen",
        "menu.profile": "Profil",
        "menu.appearance": "Darstellung",
        "menu.accounts": "Konten & Kalender",
        "menu.server": "Server",
        "menu.logout": "Abmelden",
        "menu.admin": "Admin",

        // Settings – chrome
        "settings.title": "Darstellung",
        "settings.loading": "Lade Einstellungen…",
        "settings.save": "Speichern",
        "settings.saved": "Gespeichert",

        // Settings – sections
        "settings.appdesign": "App-Design",
        "settings.liquidglass": "Liquid Glass",
        "settings.liquidglass.desc": "Verwendet die neue iOS\u{202F}26 Glasoptik mit transparenter Navigationsleiste",
        "settings.liquidglass.footer": "Änderung wirkt sofort – kein Neustart nötig.",

        "settings.cache.header": "Vorladen",
        "settings.cache.title": "Vorladen",
        "settings.cache.desc": "Events werden beim Start im Hintergrund für diesen Zeitraum geladen, danach ist Wischen sofort.",
        "settings.cache.range": "Zeitraum",
        "settings.cache.1m": "±1 Monat",
        "settings.cache.3m": "±3 Monate",
        "settings.cache.6m": "±6 Monate",
        "settings.cache.1y": "±1 Jahr",
        "settings.cache.footer": "Mehr Monate = längerer initialer Ladevorgang, danach komplett ohne Wartezeiten navigierbar.",

        "settings.language": "Sprache",
        "lang.system": "Systemstandard",
        "lang.german": "Deutsch",
        "lang.english": "English",

        "settings.colors": "Farben",
        "settings.color.primary": "Primärfarbe",
        "settings.color.accent": "Akzentfarbe",
        "settings.color.today": "Heutige-Tag-Farbe",
        "settings.color.divider": "Monatswechsel-Linie",
        "settings.color.label": "Monatskürzel",
        "settings.color.text": "Schriftfarbe",
        "settings.color.background": "Hintergrundfarbe",
        "settings.color.line": "Linienfarbe",

        "settings.textcontrast": "Schriftkontrast",
        "settings.textcontrast.desc": "Helligkeit der Beschriftungen und Texte",
        "settings.contrast.dark": "Dunkel",
        "settings.contrast.medium": "Mittel",
        "settings.contrast.bright": "Hell",
        "settings.contrast.max": "Maximum",

        "settings.linecontrast": "Linienkontrast",
        "settings.linecontrast.desc": "Sichtbarkeit von Trennlinien und Rahmen",
        "settings.linecontrast.barely": "Kaum",
        "settings.linecontrast.subtle": "Subtil",
        "settings.linecontrast.normal": "Normal",
        "settings.linecontrast.strong": "Stark",

        "settings.calview": "Kalenderansicht",
        "settings.defaultview": "Standardansicht",
        "settings.firstweekday": "Erster Wochentag",
        "settings.monday": "Montag",
        "settings.sunday": "Sonntag",
        "settings.dimpast": "Vergangene Termine ausgrauen",

        "settings.hourheight": "Stundenhöhe",
        "settings.hourheight.desc": "Platz pro Stunde in der Wochen- & Tagesansicht",
        "settings.hourheight.compact": "Kompakt",
        "settings.hourheight.normal": "Normal",
        "settings.hourheight.comfort": "Komfort",
        "settings.hourheight.large": "Gross",

        // Common buttons
        "common.cancel": "Abbrechen",
        "common.close": "Schliessen",
        "common.ok": "OK",
        "common.error": "Fehler",

        // Server view
        "server.title": "Server",
        "server.connected": "Verbundener Server",
        "server.switch": "Server wechseln",
        "server.switch_msg": "Verbindung zu %@ wird getrennt und alle lokalen Anmeldedaten werden gelöscht.",
        "server.logout_title": "Abmelden",
        "server.logout_msg": "Du wirst von %@ abgemeldet.",
        "server.info": "Info",
        "server.imprint": "Impressum",
        "server.version": "Version",

        // Imprint
        "imprint.company": "Scarriffleservices",
        "imprint.role": "Software & Webentwicklung",
        "imprint.copyright": "Diese Software wurde von Scarriffleservices mit grösster Sorgfalt entwickelt und bereitgestellt. Alle Rechte vorbehalten © 2026 Scarriffleservices.",
        "imprint.storage.title": "Datenspeicherung",
        "imprint.storage.body": "Alle Anwendungsdaten werden auf dem Server gespeichert und verarbeitet, auf dem diese Calendarr-Instanz betrieben wird. Der Speicherort hängt damit vom Betreiber des jeweiligen Servers ab. Bei Nutzung der Google Kalender-Anbindung werden Daten über die Google API ausgetauscht; für diese Daten gelten die Datenschutzbestimmungen von Google. Bei Nutzung der Home Assistant-Anbindung werden Daten mit der jeweiligen Home Assistant-Instanz ausgetauscht. Home Assistant ist ein Projekt der Open Home Foundation.",
        "imprint.disclaimer.title": "Haftungsausschluss",
        "imprint.disclaimer.body": "Trotz sorgfältiger Erstellung wird keine Haftung für die Richtigkeit, Vollständigkeit oder Aktualität der bereitgestellten Inhalte übernommen. Die Nutzung erfolgt auf eigene Verantwortung.",
        "imprint.contact.title": "Kontakt",

        // Profile view
        "profile.title": "Profil",
        "profile.loading": "Lade Profil…",
        "profile.account": "Konto",
        "profile.username": "Benutzername",
        "profile.role": "Rolle",
        "profile.role.admin": "Administrator",
        "profile.role.user": "Benutzer",
        "profile.email": "E-Mail",
        "profile.no_email": "Keine E-Mail",
        "profile.save_email": "E-Mail speichern",
        "profile.email_saved": "E-Mail gespeichert",
        "profile.change_password": "Passwort ändern",
        "profile.current_password": "Aktuelles Passwort",
        "profile.new_password": "Neues Passwort",
        "profile.new_password_repeat": "Neues Passwort wiederholen",
        "profile.password_mismatch": "Passwörter stimmen nicht überein",
        "profile.password_changed": "Passwort geändert",
        "profile.twofa": "Zwei-Faktor-Authentifizierung",
        "profile.twofa.active": "2FA ist aktiviert",
        "profile.twofa.inactive": "2FA ist deaktiviert",
        "profile.twofa.enable": "2FA einrichten",
        "profile.twofa.disable": "2FA deaktivieren",
        "profile.twofa.enabled_toast": "2FA aktiviert",
        "profile.twofa.disabled_toast": "2FA deaktiviert",
        "twofa.setup_title": "2FA einrichten",
        "twofa.scan_hint": "Scanne den QR-Code mit deiner Authenticator-App (z.B. Bitwarden, Google Authenticator).",
        "twofa.qr_section": "QR-Code / Manueller Schlüssel",
        "twofa.confirmation": "Bestätigung",
        "twofa.code_placeholder": "6-stelliger Code",
        "twofa.activate": "Aktivieren",
        "twofa.disable_title": "2FA deaktivieren",
        "twofa.password_section": "Passwort zum Deaktivieren",
        "twofa.password_placeholder": "Passwort",
        "twofa.disable": "Deaktivieren",

        // Event editor
        "event.title_placeholder": "Titel",
        "event.allday": "Ganztägig",
        "event.start": "Start",
        "event.end": "Ende",
        "event.location": "Ort",
        "event.description": "Beschreibung",
        "event.calendar_section": "Kalender",
        "event.no_writable": "Keine beschreibbaren Kalender vorhanden",
        "event.calendar_picker": "Kalender",
        "event.color_section": "Farbe",
        "event.color": "Terminfarbe",
        "event.reset_color": "Zurücksetzen",
        "event.edit_title": "Termin bearbeiten",
        "event.new_title": "Neuer Termin",
        "event.save": "Sichern",
        "event.add": "Hinzufügen",

        // Accounts
        "accounts.title": "Konten",
        "accounts.loading": "Lade Konten…",
        "accounts.add.caldav": "CalDAV-Konto",
        "accounts.add.local": "Lokaler Kalender",
        "accounts.add.ical": "iCal-URL abonnieren",
        "accounts.add.ha": "Home Assistant",
        "accounts.caldav.header": "CalDAV-Konten",
        "accounts.caldav.empty": "Keine CalDAV-Konten",
        "accounts.caldav.add": "CalDAV hinzufügen",
        "accounts.local.header": "Lokale Kalender",
        "accounts.local.empty": "Keine lokalen Kalender",
        "accounts.local.add": "Lokalen Kalender erstellen",
        "accounts.ical.header": "iCal-Abonnements",
        "accounts.ical.empty": "Keine Abonnements",
        "accounts.ical.every": "Alle %d Min.",
        "accounts.ical.add": "iCal-URL abonnieren",
        "accounts.google.header": "Google-Konten",
        "accounts.google.empty": "Keine Google-Konten",
        "accounts.google.hint": "Google-Konten werden über den Browser verknüpft",
        "accounts.ha.header": "Home Assistant",
        "accounts.ha.empty": "Keine Home Assistant-Konten",
        "accounts.ha.add": "Home Assistant hinzufügen",
        "profile.admin_note": "Hinweis: Die Benutzerverwaltung – sowohl das Erstellen als auch das Löschen von Benutzerkonten – erfolgt ausschließlich durch den Administrator des Servers.",

        // Kalender-Filter (Sidebar)
        "filter.title": "Kalender",
        "filter.loading": "Lade Kalender…",
        "filter.empty": "Keine Kalender vorhanden",
        "filter.show_all": "Alle anzeigen",
        "filter.hide_all": "Alle ausblenden",
        "filter.button": "Kalender ein-/ausblenden",
        "filter.banish": "Dauerhaft ausblenden",
        "filter.banished_footer": "Dauerhaft ausgeblendete Kalender erscheinen unter »Konten & Kalender« und können dort wieder eingeblendet werden.",
        "accounts.banished_header": "Ausgeblendete Kalender",
        "accounts.banished_unhide": "Wieder einblenden",
        "accounts.banished_unknown": "Unbekannter Kalender",

        // CalDAV add sheet
        "caldav.section": "Konto-Details",
        "caldav.display_name": "Anzeigename",
        "caldav.url": "CalDAV-URL",
        "caldav.username": "Benutzername",
        "caldav.password": "Passwort",
        "caldav.color": "Farbe",
        "caldav.color_label": "Farbe",
        "caldav.color_section": "Farbe",
        "caldav.connect": "Verbinden",
        "caldav.title": "CalDAV-Konto",

        // Local cal add sheet
        "local.title": "Lokaler Kalender",
        "local.name": "Name",
        "local.color": "Farbe",
        "local.create": "Erstellen",

        // iCal add sheet
        "ical.title": "iCal abonnieren",
        "ical.subscription": "Abonnement",
        "ical.name": "Name",
        "ical.url": "iCal-URL",
        "ical.color": "Farbe",
        "ical.refresh_section": "Aktualisierung",
        "ical.interval": "Intervall",
        "ical.subscribe": "Abonnieren",
        "ical.refresh.15m": "Alle 15 Min.",
        "ical.refresh.30m": "Alle 30 Min.",
        "ical.refresh.1h": "Stündlich",
        "ical.refresh.6h": "Alle 6 Std.",
        "ical.refresh.1d": "Täglich",

        // HA add sheet
        "ha.section": "Home Assistant",
        "ha.display_name": "Anzeigename",
        "ha.url_placeholder": "URL (z.B. http://homeassistant.local:8123)",
        "ha.auth_section": "Authentifizierung",
        "ha.token": "Long-Lived Access Token",
        "ha.token_hint": "Token erstellen unter: Profil → Sicherheit → Long-Lived Access Tokens",
        "ha.connect": "Verbinden"
    ],
    "en": [
        "nav.today": "Today",
        "nav.menu": "Menu",
        "nav.done": "Done",

        "view.month": "Month",
        "view.week": "Week",
        "view.day": "Day",
        "view.quarter": "Quarter",
        "view.agenda": "Agenda",
        "view.change": "View",

        "cal.cw": "W",
        "cal.allday": "All-day",
        "cal.no_events_title": "No events",
        "cal.no_events_body": "No events in the next 90 days.",
        "cal.loading_more": "Loading more weeks…",
        "cal.new_event": "New event",
        "cal.show_in_day_view": "Open in day view",
        "cal.show_in_week_view": "Open in week view",
        "cal.show_in_month_view": "Open in month view",

        "menu.section.settings": "Settings",
        "menu.profile": "Profile",
        "menu.appearance": "Appearance",
        "menu.accounts": "Accounts & Calendars",
        "menu.server": "Server",
        "menu.logout": "Sign out",
        "menu.admin": "Admin",

        "settings.title": "Appearance",
        "settings.loading": "Loading settings…",
        "settings.save": "Save",
        "settings.saved": "Saved",

        "settings.appdesign": "App design",
        "settings.liquidglass": "Liquid Glass",
        "settings.liquidglass.desc": "Uses the new iOS\u{202F}26 glass look with a translucent navigation bar",
        "settings.liquidglass.footer": "Takes effect immediately – no restart required.",

        "settings.cache.header": "Preloading",
        "settings.cache.title": "Preloading",
        "settings.cache.desc": "Events are loaded in the background for this range on launch, so swiping is instant afterwards.",
        "settings.cache.range": "Range",
        "settings.cache.1m": "±1 month",
        "settings.cache.3m": "±3 months",
        "settings.cache.6m": "±6 months",
        "settings.cache.1y": "±1 year",
        "settings.cache.footer": "More months = longer initial load, but then fully wait-free navigation.",

        "settings.language": "Language",
        "lang.system": "System default",
        "lang.german": "Deutsch",
        "lang.english": "English",

        "settings.colors": "Colors",
        "settings.color.primary": "Primary color",
        "settings.color.accent": "Accent color",
        "settings.color.today": "Today color",
        "settings.color.divider": "Month divider line",
        "settings.color.label": "Month abbreviation",
        "settings.color.text": "Text color",
        "settings.color.background": "Background color",
        "settings.color.line": "Line color",

        "settings.textcontrast": "Text contrast",
        "settings.textcontrast.desc": "Brightness of labels and text",
        "settings.contrast.dark": "Dark",
        "settings.contrast.medium": "Medium",
        "settings.contrast.bright": "Bright",
        "settings.contrast.max": "Maximum",

        "settings.linecontrast": "Line contrast",
        "settings.linecontrast.desc": "Visibility of dividers and borders",
        "settings.linecontrast.barely": "Barely",
        "settings.linecontrast.subtle": "Subtle",
        "settings.linecontrast.normal": "Normal",
        "settings.linecontrast.strong": "Strong",

        "settings.calview": "Calendar view",
        "settings.defaultview": "Default view",
        "settings.firstweekday": "First day of week",
        "settings.monday": "Monday",
        "settings.sunday": "Sunday",
        "settings.dimpast": "Dim past events",

        "settings.hourheight": "Hour height",
        "settings.hourheight.desc": "Space per hour in week & day view",
        "settings.hourheight.compact": "Compact",
        "settings.hourheight.normal": "Normal",
        "settings.hourheight.comfort": "Comfort",
        "settings.hourheight.large": "Large",

        // Common buttons
        "common.cancel": "Cancel",
        "common.close": "Close",
        "common.ok": "OK",
        "common.error": "Error",

        // Server view
        "server.title": "Server",
        "server.connected": "Connected server",
        "server.switch": "Switch server",
        "server.switch_msg": "The connection to %@ will be closed and all local credentials will be removed.",
        "server.logout_title": "Sign out",
        "server.logout_msg": "You will be signed out of %@.",
        "server.info": "Info",
        "server.imprint": "Legal notice",
        "server.version": "Version",

        // Imprint
        "imprint.company": "Scarriffleservices",
        "imprint.role": "Software & web development",
        "imprint.copyright": "This software was carefully developed and provided by Scarriffleservices. All rights reserved © 2026 Scarriffleservices.",
        "imprint.storage.title": "Data storage",
        "imprint.storage.body": "All application data is stored and processed on the server on which this Calendarr instance is hosted. The storage location therefore depends on the operator of the respective server. When using the Google Calendar integration, data is exchanged via the Google API; Google's privacy policy applies to that data. When using the Home Assistant integration, data is exchanged with the respective Home Assistant instance. Home Assistant is a project of the Open Home Foundation.",
        "imprint.disclaimer.title": "Disclaimer",
        "imprint.disclaimer.body": "Despite careful preparation, no liability is assumed for the accuracy, completeness or topicality of the content provided. Use is at your own risk.",
        "imprint.contact.title": "Contact",

        // Profile view
        "profile.title": "Profile",
        "profile.loading": "Loading profile…",
        "profile.account": "Account",
        "profile.username": "Username",
        "profile.role": "Role",
        "profile.role.admin": "Administrator",
        "profile.role.user": "User",
        "profile.email": "Email",
        "profile.no_email": "No email",
        "profile.save_email": "Save email",
        "profile.email_saved": "Email saved",
        "profile.change_password": "Change password",
        "profile.current_password": "Current password",
        "profile.new_password": "New password",
        "profile.new_password_repeat": "Repeat new password",
        "profile.password_mismatch": "Passwords don't match",
        "profile.password_changed": "Password changed",
        "profile.twofa": "Two-factor authentication",
        "profile.twofa.active": "2FA is enabled",
        "profile.twofa.inactive": "2FA is disabled",
        "profile.twofa.enable": "Set up 2FA",
        "profile.twofa.disable": "Disable 2FA",
        "profile.twofa.enabled_toast": "2FA enabled",
        "profile.twofa.disabled_toast": "2FA disabled",
        "twofa.setup_title": "Set up 2FA",
        "twofa.scan_hint": "Scan the QR code with your authenticator app (e.g. Bitwarden, Google Authenticator).",
        "twofa.qr_section": "QR code / Manual key",
        "twofa.confirmation": "Verification",
        "twofa.code_placeholder": "6-digit code",
        "twofa.activate": "Activate",
        "twofa.disable_title": "Disable 2FA",
        "twofa.password_section": "Password to disable",
        "twofa.password_placeholder": "Password",
        "twofa.disable": "Disable",

        // Event editor
        "event.title_placeholder": "Title",
        "event.allday": "All-day",
        "event.start": "Start",
        "event.end": "End",
        "event.location": "Location",
        "event.description": "Description",
        "event.calendar_section": "Calendar",
        "event.no_writable": "No writable calendars available",
        "event.calendar_picker": "Calendar",
        "event.color_section": "Color",
        "event.color": "Event color",
        "event.reset_color": "Reset",
        "event.edit_title": "Edit event",
        "event.new_title": "New event",
        "event.save": "Save",
        "event.add": "Add",

        // Accounts
        "accounts.title": "Accounts",
        "accounts.loading": "Loading accounts…",
        "accounts.add.caldav": "CalDAV account",
        "accounts.add.local": "Local calendar",
        "accounts.add.ical": "Subscribe to iCal URL",
        "accounts.add.ha": "Home Assistant",
        "accounts.caldav.header": "CalDAV accounts",
        "accounts.caldav.empty": "No CalDAV accounts",
        "accounts.caldav.add": "Add CalDAV",
        "accounts.local.header": "Local calendars",
        "accounts.local.empty": "No local calendars",
        "accounts.local.add": "Create local calendar",
        "accounts.ical.header": "iCal subscriptions",
        "accounts.ical.empty": "No subscriptions",
        "accounts.ical.every": "Every %d min",
        "accounts.ical.add": "Subscribe to iCal URL",
        "accounts.google.header": "Google accounts",
        "accounts.google.empty": "No Google accounts",
        "accounts.google.hint": "Google accounts are linked via the browser",
        "accounts.ha.header": "Home Assistant",
        "accounts.ha.empty": "No Home Assistant accounts",
        "accounts.ha.add": "Add Home Assistant",
        "profile.admin_note": "Note: User management — both the creation and deletion of user accounts — is handled exclusively by the server administrator.",

        // Calendar filter (sidebar)
        "filter.title": "Calendars",
        "filter.loading": "Loading calendars…",
        "filter.empty": "No calendars available",
        "filter.show_all": "Show all",
        "filter.hide_all": "Hide all",
        "filter.button": "Show/hide calendars",
        "filter.banish": "Hide permanently",
        "filter.banished_footer": "Permanently hidden calendars appear under “Accounts & Calendars”, where you can show them again.",
        "accounts.banished_header": "Hidden calendars",
        "accounts.banished_unhide": "Show again",
        "accounts.banished_unknown": "Unknown calendar",

        // CalDAV add sheet
        "caldav.section": "Account details",
        "caldav.display_name": "Display name",
        "caldav.url": "CalDAV URL",
        "caldav.username": "Username",
        "caldav.password": "Password",
        "caldav.color": "Color",
        "caldav.color_label": "Color",
        "caldav.color_section": "Color",
        "caldav.connect": "Connect",
        "caldav.title": "CalDAV account",

        // Local cal add sheet
        "local.title": "Local calendar",
        "local.name": "Name",
        "local.color": "Color",
        "local.create": "Create",

        // iCal add sheet
        "ical.title": "Subscribe to iCal",
        "ical.subscription": "Subscription",
        "ical.name": "Name",
        "ical.url": "iCal URL",
        "ical.color": "Color",
        "ical.refresh_section": "Refresh",
        "ical.interval": "Interval",
        "ical.subscribe": "Subscribe",
        "ical.refresh.15m": "Every 15 min",
        "ical.refresh.30m": "Every 30 min",
        "ical.refresh.1h": "Hourly",
        "ical.refresh.6h": "Every 6 hours",
        "ical.refresh.1d": "Daily",

        // HA add sheet
        "ha.section": "Home Assistant",
        "ha.display_name": "Display name",
        "ha.url_placeholder": "URL (e.g. http://homeassistant.local:8123)",
        "ha.auth_section": "Authentication",
        "ha.token": "Long-Lived Access Token",
        "ha.token_hint": "Create a token under: Profile → Security → Long-Lived Access Tokens",
        "ha.connect": "Connect"
    ]
]
