# Apple Watch app and watch-face complications

Date: 2026-09-11
Status: approved — ready for implementation planning

## Goal

Put "what is my next appointment" on the wrist as watch-face complications, with a
tap-through app that shows a plain agenda list and lets the user narrow which
calendars count. Nothing more.

## Non-goals

- Creating or editing events on the watch. The snapshot is deliberately lossy —
  no notes, recurrence rules or permissions — which is enough to *display* a
  calendar and deliberately not enough to edit one. Editing would mean a second
  API client and is out of scope.
- Running without the iPhone. The watch is a read-only consumer of the phone's
  snapshot. Direct server access stays available as a later option (the server is
  reachable over HTTPS) but is not built now.
- Wear OS parity. A separate project with its own decision.

## Platform floor

iOS 26 (unchanged) and watchOS 26. Nothing below that needs to work, so no
availability branching.

## Design rules

- **No emojis as icons**, anywhere — SF Symbols only (`Image(systemName:)`). An
  emoji renders differently on every platform and font, and complications tint
  SF Symbols with the watch face's colour, which an emoji ignores.
- Exactly one element per complication is marked `widgetAccentable()`.
- The watch app's background stays black rather than following `snapshot.theme`;
  the always-on display and OLED make that the right choice. `snapshot.theme`
  supplies accents only.

## Architecture

```
iPhone                                     Apple Watch
──────────────────────────────────         ──────────────────────────────
CalendarStore.publishWidgetSnapshot()
  ├─ SnapshotStore.write()   (App Group iOS)
  ├─ WidgetTimelineNotifier.reload()
  └─ WatchSyncService.push() ──WCSession──▶ WatchSnapshotReceiver
                                              ├─ SnapshotStore.write()  (App Group watchOS)
                                              ├─ SharedSessionStore.write()
                                              └─ WidgetCenter.reloadAllTimelines()
BGAppRefreshTask (new)
  └─ refresh → publishWidgetSnapshot()      Watch app foreground
                                              └─ sendMessage ──▶ pull when reachable
```

App Groups are per-device: the phone's container is not the watch's. The watch
therefore receives the snapshot over WatchConnectivity and writes it into *its
own* App Group container using the same `SnapshotStore` from CalendarrKit. One
format, one reader, no drift — the watch is exactly the read-only consumer the
CalendarrKit README already describes.

`CalendarrAppGroup.current` is already correct for watchOS: the
`#if os(macOS) || targetEnvironment(macCatalyst)` guard falls through to the
unprefixed identifier, which is what watchOS requires.

## Module changes

| Module | Change |
|---|---|
| `CalendarrKit` | Add `.watchOS(.v26)` to `platforms`. No code change — the Foundation-only constraint pays off here. |
| `CalendarrKit` | New `Snapshot/WatchCoverage.swift`: the transport trimming policy plus `CalendarrSnapshot.trimmedForWatch()`. Shared by sender and receiver so they cannot disagree about it. |
| iOS app | New `Services/WatchSyncService.swift` — WCSession sender, called from `publishWidgetSnapshot()`. |
| iOS app | New `Services/BackgroundRefresh.swift` — `BGAppRefreshTask` that refreshes events, republishes the snapshot and pushes to the watch. Benefits the existing widgets too. |
| New target | `CalendarrWatch` (watchOS app): receiver, agenda, event detail, calendar filter. |
| New target | `CalendarrWatchComplications` (watchOS widget extension): the complications. |

## Transport

### Trimming policy

`WatchCoverage`, mirroring the existing `SnapshotCoverage`:

- `daysBehind = 1`
- `daysAhead = 14`
- `maxEvents = 120`

`trimmedForWatch()` must narrow `coverageStart`/`coverageEnd` along with the
events. Carrying 14 days of events while still claiming a 42-day window would
make the watch render an empty week that it has no information about — the exact
failure the README warns against. If the `maxEvents` cap truncates before
`daysAhead` is reached, `coverageEnd` is pulled back to the start of the day of
the last retained event.

Trimmed payload is roughly 20–30 KB, far below the WatchConnectivity limit.

### Three delivery paths

Each one alone leaves a gap, so all three ship:

1. **`updateApplicationContext`** — the main path. Carries only the latest state,
   survives restarts, and has no queue to overflow. Delivered when the watch app
   next launches or wakes.
2. **`transferCurrentComplicationUserInfo`** — sent only when the *next* event
   changed identity (first event after now, compared by id and start). This is
   the only path that wakes the watch app while it is not running, which is why
   it exists; its daily budget (~50) is why it is not used for every write.
   Additionally rate-limited to at most 4 per hour.
3. **`sendMessage` pull on watch app foreground** — covers "I am looking at it
   right now and it is stale".

Payload is a property-list dictionary of `Data` blobs: `snapshot`, `calendars`,
`session`, plus an integer `schema` matching `CalendarrSnapshot.currentSchema`. A
receiver refuses a higher schema rather than guessing, same rule as the file
format.

Only the watch **app** runs WCSession; a widget extension cannot. The extension
always reads what the app last wrote.

## Timeline strategy

This deliberately differs from the iOS provider, which emits 24 hourly entries
(`CalendarrTimelineProvider.swift`). On the watch, entries are placed **on event
boundaries**: now, plus every event start and end inside the next 24 hours,
deduplicated and sorted, with hourly filler so at least 24 hours are covered, and
capped at 100 entries. The complication then flips in the exact minute the next
appointment changes, with no network call and no refresh budget spent.

Refresh policy is `.atEnd`. Data changes arrive by push; when the timeline simply
runs out it regenerates from the same snapshot, which is cheap and correct.

Countdowns use `Text(event.start, style: .timer)`, which updates live without
consuming timeline entries and dims correctly on the always-on display.

## Complication catalogue

Eight kinds. Families in brackets.

| Kind | Families | Content |
|---|---|---|
| `WatchNextEvent` | rectangular, inline | Time, title, location |
| `WatchCornerCountdown` | corner | Value: live countdown. Curved label: `"14:30 Zahnarzt"` |
| `WatchCornerTime` | corner | Value: start time. Curved label: event title |
| `WatchCountdown` | circular, inline | Remaining time; circular draws a draining ring |
| `WatchDate` | circular, inline | Day number and month |
| `WatchTodayCount` | circular, inline | Number of events today |
| `WatchNextTwo` | rectangular | The next two events, time plus title |
| `WatchDatePlusEvent` | rectangular | Weekday and date plus the next event |

`WatchDate`, `WatchTodayCount` and `WatchCountdown` are ports of the existing
lock-screen widgets in `LockScreenWidgetViews.swift`, which already render
`accessoryCircular`, `accessoryRectangular` and `accessoryInline`.

### Which face shows what

A round Infograph-style face has **no rectangular slot**: it offers four corners
and a circular sub-dial. The rectangular kinds therefore only appear on
Modular-family faces. Since the user's face is round, `accessoryCorner` is the
primary slot and gets the most attention; the rectangular kinds still ship
because they are cheap and cover the other faces.

### accessoryCorner

New and watchOS-only. The curved bezel text comes from
`.widgetLabel { Text(...) }` — WidgetKit lays it along the edge, so no manual arc
drawing.

The hard constraint: a corner holds **one** value plus the curved label. A second
inner line runs into the curved text and must not be attempted. Both corner kinds
therefore carry a single value and put the context in the label.

Two content variants ship rather than one, because they share the whole data path
and differ only in formatting — the user picks on the watch face. A
date-in-the-corner variant was considered and dropped: it carries no appointment
information, which is the whole point of the complication.

watchOS tints complications monochrome using the watch face's colour, so
per-calendar colours are not available in complications. Calendar colours appear
in the app only.

## Watch app

- **Agenda** — a scrolling list grouped by day, day headers, one row per event
  with a leading bar in the event's colour, time range or all-day label, and
  title. Covers the trimmed window; days outside `snapshot.covers(date)` are not
  rendered as empty but greyed with a note.
- **Event detail** — title, time, location, calendar name. Read-only.
- **Calendar filter** — one row per calendar from `readCalendars()`, rendered as a
  `Button` with an SF Symbol checkbox (`checkmark.square.fill` / `square`) plus
  the calendar's colour dot. Deliberately **not** a watchOS `Toggle`: its switch
  reads as a state indicator you wait on rather than a control you tap.

The background stays black rather than following `snapshot.theme`, because the
always-on display and OLED make black the right choice on the watch.
`snapshot.theme` is used for accents only.

## Calendar filter semantics

Stored in the watch's App Group `UserDefaults` under
`watchHiddenCalendarKeys: [String]`, so the widget extension reads the same
value and one toggle affects every complication at once.

The snapshot already excludes hidden and banished calendars, so the watch filter
narrows *further* and never contradicts the phone. `CalendarSelectionIntent` is
ported so a complication can override the app-level filter, but the in-app
toggles are the primary path: intent configuration is awkward to operate on the
watch face itself.

## Error and empty states

`SnapshotReadResult` already covers most of them. One case is new.

| State | Display |
|---|---|
| `.neverWritten` / nothing received yet | "Open Calendarr on your iPhone once" |
| `.loggedOut` | "Sign in on your iPhone" — never show the previous events |
| `.incompatible` | "Update the watch app" |
| outside `covers(date)` | Greyed with a note, never rendered as "nothing scheduled" |
| Snapshot present but visibly old | Show `writtenAt` as "as of …" rather than implying freshness |

The last one has no iPhone equivalent: the phone writes its own cache, so it is
never stale in a way the reader cannot see. The watch can hold a snapshot from
days ago because the phone was unreachable, and must say so.

## iOS background refresh

- Register `BGAppRefreshTaskRequest` with identifier
  `com.scarriffleservices.calendarr.ios.refresh` in `CalendarrApp`, rescheduling
  after every run with `earliestBeginDate` 30 minutes out.
- Info.plist needs `BGTaskSchedulerPermittedIdentifiers` and the `fetch`
  background mode.
- The task fetches the coverage window, calls `publishWidgetSnapshot()`, and lets
  the existing call chain reload widgets and push to the watch. It must finish
  well inside the ~30 s budget and set an expiration handler.

iOS decides when this runs; frequency follows how the user actually opens the
app. This improves freshness, it does not guarantee it.

## Build, signing and distribution

- Bundle identifiers: `com.scarriffleservices.calendarr.ios.watchkitapp` and
  `com.scarriffleservices.calendarr.ios.watchkitapp.complications`. The
  `.watchkitapp` suffix is required for a companion watch app;
  `WKCompanionAppBundleIdentifier` points at the iOS app.
- Both new targets need `com.apple.security.application-groups` set to
  `group.com.scarriffleservices.calendarr`, unprefixed.
- No keychain access group on the watch: there is no token there to protect.
- Register both bundle IDs and enable the App Group for them in the developer
  portal.
- App Store Connect: a watch app is not a new app record, it is a new target in
  the existing one — a normal version submission and a normal review. Watch
  screenshots are additionally required.
- The server needs no change at all.

## Risks

1. **Xcode does not currently support the test device.** Xcode 26.6 ships the
   watchOS 26.5 SDK; the target watch runs watchOS 27 beta. Installing builds on
   it needs an Xcode with watchOS 27 support. Code can be written and built
   against watchOS 26 in the meantime, but on-device verification is blocked
   until that Xcode is installed. This is the first thing to resolve.
2. **WatchConnectivity background delivery is opportunistic** and cannot be
   verified on this machine — only on a real paired device.
3. **Complication push budget.** Path 2 is deliberately rate-limited; if pushes
   are exhausted, freshness silently degrades to path 1. The stale-snapshot
   display state is what keeps that honest rather than wrong.
4. **First run is a chicken-and-egg.** The watch app can be installed before the
   phone has ever pushed. The empty state must name the fix rather than look
   broken.
5. **App review** may ask for demo credentials, since the app needs a
   self-hosted server to show anything.

## Verification

Per the project's working rules, this machine builds but does not run apps:

```
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme CalendarrWatch \
  -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build   # CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Behaviour, layout and complication refresh are verified by the user on the
device. Nothing about the look is asserted here.

## Later, not now

- Direct HTTPS fetch from the watch, for freshness independent of the phone.
- Creating events on the watch.
- Wear OS equivalent.
