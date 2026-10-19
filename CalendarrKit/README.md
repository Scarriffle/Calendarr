# CalendarrKit

Shared code between Calendarr (iOS / Mac Catalyst) and other apps from the same
developer team that want to **read** the user's calendar.

`CalendarrCore` depends on Foundation only — no SwiftUI, no UIKit, no AppKit — so
it compiles for iOS, Mac Catalyst and native macOS from one source. That
constraint is load-bearing: `swift build` against the native macOS SDK is what
catches a UIKit import before it reaches a consumer, because a Mac Catalyst build
would compile it happily.

## What a reading app gets

```swift
import CalendarrCore

let store = SnapshotStore()          // uses CalendarrAppGroup.current

switch store.read() {
case .ok(let snap):
    snap.events          // [SnapshotEvent]
    snap.theme           // the colours Calendarr is currently rendering with
    snap.writtenAt       // "as of 14:32"
    snap.coverageStart   // see "Coverage" below
    snap.coverageEnd
case .neverWritten:      // Calendarr has never run here → "open Calendarr once"
case .loggedOut:         // signed out → "sign in to Calendarr", discard old events
case .incompatible:      // Calendarr is newer than this package → "update the app"
case .unreadable(let why): // almost always a wrong App Group; log `why`
}

store.readCalendars()    // [SnapshotCalendar] for a filter UI
```

React to changes without polling:

```swift
let token = SnapshotChangeNotifier.observe { /* hop to your actor, read again */ }
// keep `token` alive; releasing it removes the observer
```

Also reload on window activation — the notification is a best-effort signal, and
missing one should leave you slightly stale, never wrong.

## Coverage — the part that bites

The snapshot is not the whole calendar. Outside `coverageStart..<coverageEnd` it
carries **no information**, which is not the same as "no events". Rendering an
empty March because it is outside the window produces a screen that looks correct
and is false. Use `snapshot.covers(date)` and grey out what you cannot speak for.

| | |
|---|---|
| Window | ~7 days back, ~42 days ahead, frozen at write time |
| Cap | 500 events, sorted by start |
| Filters | hidden and "banished" calendars are already excluded — you see the user's filtered view |
| Scope | personal only; group overlays are never published, deliberately |
| Dropped | notes, url, source, creator, privacy, read-only, reminders, recurrence |

What remains is enough to *display* a calendar and deliberately not enough to
edit one or reason about permissions.

## Setup for a consuming app

Same developer team (`PP34X97WS3`) is required — that is what makes the container
and the keychain group shared.

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>PP34X97WS3.group.com.scarriffleservices.calendarr</string></array>
```

The Team ID prefix is mandatory on macOS and forbidden on iOS. `CalendarrAppGroup.current`
resolves the right one; it must match the entitlement byte for byte, or
`containerURL(…)` returns nil and every read silently yields nothing.

Never sign in from a consuming app. Credentials, 2FA and token storage belong to
Calendarr alone.

## Wire format rules

`widget-cache.json`, `widget-calendars.json` and `session.json` live in the group
container and are read by apps that ship on independent schedules.

1. Filenames do not change within a major version, so an older build keeps reading
   after the writer updates.
2. Readers refuse `schemaVersion > maxSupportedSchema` instead of guessing.
3. Writers only ever *add* optional fields. Never rename, remove or retype one.
4. A breaking change means a new major version *and* a new filename, with the old
   file still written for one full release cycle.
5. The package version is the contract: `CalendarrKit 1.x` ⇔ snapshot schema 2.
   Depend on `.upToNextMajor(from: "1.0.0")`.

Rule 3 is why the six colour values sit flat at the top level instead of nested
under `theme`, which would read better: a v1 reader requires them flat, so nesting
would have broken every older build on the first v2 write. `theme` is a computed
view over them. `SnapshotSchemaTests` pins this down in both directions.

## Verify

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build   # native macOS — catches UIKit leaks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
