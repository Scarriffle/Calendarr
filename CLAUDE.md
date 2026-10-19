# Calendarr — Arbeitsweise (WICHTIG)

Dieses Repo ist ein **Monorepo**. Alles liegt hier, es gibt keine getrennten App-Repos mehr.

```
backend/       FastAPI + SQLite
frontend/      Web-Frontend
ios/           SwiftUI-App, Widgets, Watch-App, Komplikationen
android/       Kotlin/Compose-App
CalendarrKit/  Swift-Paket (CalendarrCore) — geteilt von iOS-App, Widgets und Watch
docs/          DESIGN.md u.a.
```

Gearbeitet wird auf Branch **`beta`**. Der Nutzer deployt daraus auf den Testserver
und merged später selbst `beta` → `master`.

## Diese Maschine = macOS-Entwicklungsrechner. Was hier NICHT geht:

- **KEINE Server-Tests, kein Server-Start.** Nicht `pytest` ausführen, keine venvs
  aufsetzen, den Server nicht lokal starten. Backend-Änderungen werden per
  Code-Review abgesichert; getestet wird ausschließlich auf dem Testserver.
- **Apps lassen sich hier nur bauen, nicht ausführen.** UI-, Verhaltens- und
  Visual-Tests macht der Nutzer auf Gerät bzw. Simulator. Nicht über das Aussehen
  spekulieren — bei Unsicherheit nachfragen.
- **Geräteabhängige Bugs** sind hier nicht reproduzierbar. Die Watch-Komplikationen
  und der Liquid-Glass-Titel-Bug sind Beispiele dafür.

## Build-Verifikation (das geht, und nur das)

```bash
# iOS inkl. Widgets und Watch-App
cd ios && xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# Mac Catalyst — separat prüfen, der Build bricht sonst unbemerkt
cd ios && xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" \
  -destination 'platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# CalendarrKit — gegen die native macOS-SDK, das fängt UIKit-Importe ab
cd CalendarrKit && swift build && swift test

# Android
cd android && ./gradlew assembleDebug
```

Xcode liegt unter `/Applications/Xcode.app`. Watch-Builds brauchen eine Xcode-Version,
deren watchOS-SDK zum Gerät passt.

## CalendarrKit

Liegt als `git subtree` in der Wurzel. Das Xcode-Projekt referenziert es relativ als
`../CalendarrKit` — von `ios/` aus zeigt das genau hierher. **Diesen Pfad nicht ändern
und das Verzeichnis nicht verschieben**, sonst baut iOS nicht mehr.

`CalendarrCore` ist bewusst **Foundation-only** — kein SwiftUI, kein UIKit, kein AppKit.
`swift build` gegen die macOS-SDK ist das, was einen versehentlichen UIKit-Import
auffallen lässt, bevor ein Consumer darüber stolpert. Das Wire-Format hat eigene
Regeln, siehe `CalendarrKit/README.md`.

## Plattform-Parität (WICHTIG)

Feature-Logik gehört möglichst auf den **Server**, nicht pro Client dupliziert.
Beispiel: die Gruppentermin-Dekoration liefert der Server als `display_title` im
`/combined`-Endpoint — Clients rendern nur. Sichtbare Features müssen auf **allen**
Clients umgesetzt werden (Web, iOS, Android), nicht nur einem.

Ausnahme sind plattformeigene Erweiterungen wie Watch-App und Komplikationen; ein
Wear-OS-Gegenstück ist ein eigenes Projekt.

## Konventionen

- **Keine Emojis als Icons** — überall echte Vektor-Icons (`Image(systemName:)` auf
  Apple-Plattformen, Icon-Set bzw. inline SVG sonst). Emojis sehen auf jeder
  Plattform anders aus, was der Paritäts-Anspruch nicht verträgt.
- Commit-Messages auf **Englisch**, Kommunikation mit dem Nutzer auf **Deutsch**.
- Nach jeder abgeschlossenen Einheit committen und pushen.
- Fehler nicht mit `try?` verschlucken. Eine Quelle, die scheitert, muss sagen warum —
  sonst sieht sie aus wie eine Quelle ohne Inhalt. Das hat schon zweimal Bugs
  verborgen (`KeychainStore`, `loadWritableCalendars`).

## Altlasten

`~/Projects_Coding/Calendar Stack/` enthält die früheren Einzel-Repos
(`Calendarr iOS`, `Calendarr Android`, `CalendarrKit`, `Calendarr server`).
Sie sind **veraltet** und enthalten nichts, was hier fehlt; das iOS-Remote ist
archiviert. Dort nicht mehr arbeiten.
