# Calendarr Android

## Projektübersicht
Android-App für den Calendarr-Server. Funktionsgleich mit der iOS-App (Swift, liegt unter ../Calendarr iOS/).
Der Server-Code liegt unter ../Calendarr server/.

## ⚠️ WICHTIG: Read-Only Ordner
Die folgenden Ordner dienen NUR zur Referenz. NIEMALS Dateien darin verändern, löschen oder erstellen:
- `../Calendarr iOS/` → READ ONLY – nur zur Analyse der Features und API-Nutzung
- `../Calendarr server/` → READ ONLY – nur zur Analyse der API-Endpunkte und Datenmodelle

Alle Änderungen und neue Dateien kommen ausschliesslich in `../Calendarr Android/`.

## Server
- Basis-URL (Prod): https://calendar.scarriffle.com
- Auth: Erst Server-URL eingeben, dann Benutzername + Passwort
- Credentials werden auf Android im EncryptedSharedPreferences gespeichert (Äquivalent zu Apple Keychain)

## Tech Stack
- Sprache: Kotlin
- UI: Jetpack Compose + Material 3
- Architektur: MVVM
- Netzwerk: Retrofit + OkHttp
- Lokale Speicherung: EncryptedSharedPreferences (Credentials), Room (Cache)
- Async: Coroutines + Flow
- DI: Hilt

## Projektstruktur
- `../Calendarr iOS/` → READ ONLY – Swift-App als Referenz
- `../Calendarr server/` → READ ONLY – Server als Referenz
- `../Calendarr Android/` → dieses Projekt, hier wird gebaut

## Git
- Remote: https://git.scarriffle.com/Scarriffle/Calendarr-Android.git
- Nach jeder abgeschlossenen Funktionseinheit committen und pushen
- Commit-Messages auf Englisch, format: `feat: ...` / `fix: ...` / `chore: ...`
- Niemals halbfertigen oder nicht-kompilierenden Code pushen

## Build
- Debug APK: `./gradlew assembleDebug`
- Release APK: `./gradlew assembleRelease`
- Tests: `./gradlew test`

## Konventionen
- Kein XML für Layouts – ausschliesslich Jetpack Compose
- ViewModels dürfen keine Android-Framework-Klassen direkt referenzieren
- StateFlow für UI-State, keine LiveData
- Alle Strings in res/values/strings.xml
- Vor jedem Push: `./gradlew build` muss fehlerfrei durchlaufen
