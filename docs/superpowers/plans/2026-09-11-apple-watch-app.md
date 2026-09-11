# Apple Watch App and Complications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only Apple Watch app plus eight watch-face complications that show the next Calendarr appointment, fed from the iPhone over WatchConnectivity.

**Architecture:** The watch is a read-only consumer of the phone's snapshot. Every piece of logic that can be tested lives in `CalendarrCore` (testable with `swift test` on the dev machine); the watch targets hold only thin SwiftUI and WCSession glue, which can only be build-verified here. The phone trims its 42-day snapshot to a 14-day watch payload and sends it; the watch writes it into its *own* App Group container through the same `SnapshotStore`, so there is one wire format and one reader.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftUI, WidgetKit (complications), WatchConnectivity, BackgroundTasks, Swift Testing (`import Testing`), Swift Package Manager (local package `CalendarrKit`).

**Spec:** `docs/superpowers/specs/2026-09-11-apple-watch-app-design.md`

---

## Note on the source files

`Calendarr iOS/`, `CalendarrWidgets/` and `Shared/` are
`PBXFileSystemSynchronizedRootGroup`s, so **new `.swift` files are picked up
automatically** — no `project.pbxproj` surgery to add them. This does not extend
to new *targets* (Task 9), and it is why a partial Info.plist has to live
outside those folders (Task 7).

## Prerequisite (blocks device verification only)

Xcode 26.6 ships the watchOS 26.5 SDK. The target device runs watchOS 27 beta, so builds cannot be installed on it until an Xcode with watchOS 27 support is present. Every task below can be written and build-verified without it. Do not block on this; note it when handing back.

## Working rules for this repo

- **Never pass `-sdk` to xcodebuild.** It overrides SDKROOT for every target in
  the dependency graph, so the watch app gets built against the iOS SDK: the
  build still succeeds, but `WKApplication` is missing from the result and
  `DTSDKName` reads `iphonesimulator`. Select the platform with `-destination`
  alone and let each target keep its own SDK.

- Never run or start the server, and never run the apps. Apps are **build-verified only**; behaviour, layout and complication refresh are verified by the user on the device.
- Commit messages in English. Commit after every task.
- `CalendarrKit` is a **separate git repo** at `../CalendarrKit` with **no remote** — commit there, do not push. The iOS repo (`.`) pushes to `origin main`.
- `CalendarrCore` must stay Foundation-only. No SwiftUI, no UIKit, no WidgetKit imports in the package.

## File structure

### `../CalendarrKit` (new files)

| File | Responsibility |
|---|---|
| `Sources/CalendarrCore/Snapshot/WatchCoverage.swift` | Watch trimming policy and `trimmedForWatch()`. The only place the watch window is defined. |
| `Sources/CalendarrCore/Snapshot/SnapshotFilter.swift` | Calendar-key filtering, shared by the iOS and watch timeline providers. |
| `Sources/CalendarrCore/Transport/WatchTransportPayload.swift` | The WatchConnectivity wire format: encode, decode, schema refusal. |
| `Sources/CalendarrCore/Transport/WatchPushPolicy.swift` | "Did the next appointment change?" — decides when to spend a complication push. |
| `Sources/CalendarrCore/Complications/ComplicationTimeline.swift` | Event-boundary entry dates for a WidgetKit timeline. Pure function. |
| `Tests/CalendarrCoreTests/WatchTrimmingTests.swift` | Tests for `WatchCoverage`. |
| `Tests/CalendarrCoreTests/SnapshotFilterTests.swift` | Tests for filtering. |
| `Tests/CalendarrCoreTests/WatchTransportTests.swift` | Tests for the wire format. |
| `Tests/CalendarrCoreTests/WatchPushPolicyTests.swift` | Tests for push throttling. |
| `Tests/CalendarrCoreTests/ComplicationTimelineTests.swift` | Tests for entry dates. |

### `.` (iOS repo, new files)

| File | Responsibility |
|---|---|
| `Calendarr-Info.plist` | Partial Info.plist for the two background-task array keys, merged into the generated one. At the project root, not in the target folder. |
| `Calendarr iOS/Services/BackgroundRefresh.swift` | `BGAppRefreshTask` registration and handling. |
| `Calendarr iOS/Services/WatchSyncService.swift` | WCSession sender on the phone. |
| `CalendarrWatch/CalendarrWatchApp.swift` | watchOS app entry point. |
| `CalendarrWatch/WatchSnapshotReceiver.swift` | WCSession delegate; writes the received payload. |
| `CalendarrWatch/WatchFilterStore.swift` | Per-watch hidden-calendar set in the App Group. |
| `CalendarrWatch/WatchSnapshotModel.swift` | Observable read model shared by the watch views. |
| `CalendarrWatch/Views/WatchAgendaView.swift` | Day-grouped agenda list. |
| `CalendarrWatch/Views/WatchEventRow.swift` | One event row. |
| `CalendarrWatch/Views/WatchEventDetailView.swift` | Read-only event detail. |
| `CalendarrWatch/Views/WatchCalendarFilterView.swift` | Checkbox rows for calendars. |
| `CalendarrWatch/Views/WatchStatusView.swift` | Empty and error states. |
| `CalendarrWatch/WatchL10n.swift` | German/English strings for the watch app and complications. |
| `CalendarrWatchComplications/WatchComplicationProvider.swift` | `AppIntentTimelineProvider` for all kinds. |
| `CalendarrWatchComplications/WatchComplicationSupport.swift` | Colour helper, time formatting, next-event helpers. |
| `CalendarrWatchComplications/CornerComplicationViews.swift` | The two corner kinds. |
| `CalendarrWatchComplications/RectangularComplicationViews.swift` | The three rectangular kinds. |
| `CalendarrWatchComplications/SmallComplicationViews.swift` | Circular and inline kinds. |
| `CalendarrWatchComplications/CalendarrWatchComplications.swift` | `WidgetBundle` with all eight kinds. |

### Modified

| File | Change |
|---|---|
| `../CalendarrKit/Package.swift` | Add `.watchOS(.v26)`. |
| `Calendarr iOS/CalendarrApp.swift` | Register the background task; start `WatchSyncService`. |
| `Calendarr iOS/Models/CalendarStore.swift:574-628` | Push to the watch at the end of `publishWidgetSnapshot()`. |
| `CalendarrWidgets/CalendarrTimelineProvider.swift:38-55` | Use the shared filter from `CalendarrCore`. |
| `Calendarr iOS.xcodeproj/project.pbxproj` | Two new targets, entitlements, Info.plist keys. |

---

## Task 1: Make CalendarrKit build for watchOS

**Files:**
- Modify: `../CalendarrKit/Package.swift:6-11`

- [ ] **Step 1: Add the watchOS platform**

In `../CalendarrKit/Package.swift`, change the `platforms` array to:

```swift
    platforms: [
        .iOS(.v17),
        .watchOS(.v26),
        .macOS(.v14),
        .macCatalyst(.v17),
    ],
```

- [ ] **Step 2: Verify the package still builds and tests green**

Run from `../CalendarrKit`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: build succeeds, all existing tests pass. This builds for native macOS, which is what catches a UIKit import before a consumer sees it.

- [ ] **Step 3: Commit**

```bash
cd ../CalendarrKit
git add Package.swift
git commit -m "Declare watchOS support so a watch app can consume the snapshot"
```

---

## Task 2: Watch trimming policy

The phone publishes ~42 days and up to 500 events. The watch gets a narrower window. The window must be narrowed **with** the events: carrying 14 days while still claiming 42 would make the watch render an empty week it has no information about.

**Files:**
- Create: `../CalendarrKit/Sources/CalendarrCore/Snapshot/WatchCoverage.swift`
- Test: `../CalendarrKit/Tests/CalendarrCoreTests/WatchTrimmingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `../CalendarrKit/Tests/CalendarrCoreTests/WatchTrimmingTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarrCore

/// The watch payload is a narrower snapshot, not a different one. These tests
/// pin down the part that is easy to get wrong: the coverage window has to
/// shrink with the events, or the watch renders an empty week it knows nothing
/// about.
struct WatchTrimmingTests {

    private static let cal = Calendar(identifier: .gregorian)
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, dayOffset: Int, hour: Int = 9) -> SnapshotEvent {
        let dayStart = cal.startOfDay(for: now)
        let day = cal.date(byAdding: .day, value: dayOffset, to: dayStart)!
        let start = cal.date(byAdding: .hour, value: hour, to: day)!
        return SnapshotEvent(id: id, title: "Event \(id)",
                             start: start, end: start.addingTimeInterval(3600),
                             isAllDay: false, colorHex: "#4285f4",
                             location: "", calendarKey: "local:1")
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        let dayStart = cal.startOfDay(for: now)
        return CalendarrSnapshot(
            writtenAt: now,
            coverageStart: cal.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart)!,
            coverageEnd: cal.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart)!,
            isLoggedIn: true,
            writerVersion: "1.0",
            events: events,
            theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                 line: "#4", primary: "#5", accent: "#6"),
            language: "de")
    }

    @Test("The window narrows to the watch policy, not just the events")
    func narrowsWindow() {
        let trimmed = Self.snapshot([]).trimmedForWatch(now: Self.now, calendar: Self.cal)
        let dayStart = Self.cal.startOfDay(for: Self.now)

        #expect(trimmed.coverageStart == Self.cal.date(byAdding: .day, value: -WatchCoverage.daysBehind, to: dayStart))
        #expect(trimmed.coverageEnd == Self.cal.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart))
    }

    @Test("Events outside the watch window are dropped")
    func dropsEventsOutsideWindow() {
        let inside = Self.event("in", dayOffset: 3)
        let outside = Self.event("out", dayOffset: 30)
        let trimmed = Self.snapshot([inside, outside]).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.map(\.id) == ["in"])
    }

    @Test("An event still running at the window start is kept")
    func keepsRunningEvent() {
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let start = Self.cal.date(byAdding: .day, value: -5, to: dayStart)!
        let running = SnapshotEvent(id: "running", title: "Urlaub",
                                    start: start,
                                    end: Self.cal.date(byAdding: .day, value: 5, to: dayStart)!,
                                    isAllDay: true, colorHex: "#4285f4",
                                    location: "", calendarKey: "local:1")
        let trimmed = Self.snapshot([running]).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.map(\.id) == ["running"])
    }

    @Test("Metadata survives trimming unchanged")
    func preservesMetadata() {
        let original = Self.snapshot([Self.event("a", dayOffset: 1)])
        let trimmed = original.trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.language == "de")
        #expect(trimmed.isLoggedIn == true)
        #expect(trimmed.writerVersion == "1.0")
        #expect(trimmed.theme.accent == "#6")
        #expect(trimmed.writtenAt == original.writtenAt)
        #expect(trimmed.schemaVersion == CalendarrSnapshot.currentSchema)
    }

    @Test("When the event cap truncates, coverageEnd pulls back to what we can prove")
    func capPullsBackCoverage() {
        // Two events per day for 14 days is 28; ask for a cap of 4 by building
        // far more events than the policy allows.
        var many: [SnapshotEvent] = []
        for day in 0..<14 {
            for hour in 8..<18 { many.append(Self.event("d\(day)h\(hour)", dayOffset: day, hour: hour)) }
        }
        #expect(many.count > WatchCoverage.maxEvents)

        let trimmed = Self.snapshot(many).trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.events.count <= WatchCoverage.maxEvents)
        // Everything we kept starts before the window we claim.
        #expect(trimmed.events.allSatisfy { $0.start < trimmed.coverageEnd })
        // And we no longer claim the full 14 days, because we cannot speak for them.
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let fullEnd = Self.cal.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart)!
        #expect(trimmed.coverageEnd < fullEnd)
        #expect(trimmed.coverageEnd > trimmed.coverageStart)
    }

    @Test("Trimming never widens a window the writer already narrowed")
    func neverWidens() {
        let dayStart = Self.cal.startOfDay(for: Self.now)
        let narrow = CalendarrSnapshot(
            writtenAt: Self.now,
            coverageStart: dayStart,
            coverageEnd: Self.cal.date(byAdding: .day, value: 2, to: dayStart)!,
            isLoggedIn: true, writerVersion: "1.0", events: [],
            theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                 line: "#4", primary: "#5", accent: "#6"),
            language: "de")

        let trimmed = narrow.trimmedForWatch(now: Self.now, calendar: Self.cal)

        #expect(trimmed.coverageStart == dayStart)
        #expect(trimmed.coverageEnd == Self.cal.date(byAdding: .day, value: 2, to: dayStart))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchTrimmingTests
```

Expected: FAIL to compile — `cannot find 'WatchCoverage' in scope` and `value of type 'CalendarrSnapshot' has no member 'trimmedForWatch'`.

- [ ] **Step 3: Write the implementation**

Create `../CalendarrKit/Sources/CalendarrCore/Snapshot/WatchCoverage.swift`:

```swift
import Foundation

/// How much of the calendar travels to the watch.
///
/// Deliberately narrower than `SnapshotCoverage`: the payload crosses
/// WatchConnectivity on every publish, and a watch complication never needs six
/// weeks of history to answer "what is next".
public enum WatchCoverage {
    /// Days before today. One is enough for "still running" all-day events.
    public static let daysBehind = 1
    /// Days after today.
    public static let daysAhead = 14
    /// Hard cap on events sent, applied after sorting by start date.
    public static let maxEvents = 120
}

extension CalendarrSnapshot {
    /// A narrower copy of this snapshot, suitable for sending to the watch.
    ///
    /// The coverage window shrinks together with the events, and never widens
    /// past what the writer already claimed. If `WatchCoverage.maxEvents`
    /// truncates the list, `coverageEnd` is pulled back to the first event we
    /// had to drop: everything before that point is provably complete, and
    /// beyond it the watch must not pretend to know anything.
    public func trimmedForWatch(now: Date = Date(),
                                calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarrSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        let windowStart = max(coverageStart,
                              calendar.date(byAdding: .day, value: -WatchCoverage.daysBehind, to: dayStart) ?? dayStart)
        let windowEnd = min(coverageEnd,
                            calendar.date(byAdding: .day, value: WatchCoverage.daysAhead, to: dayStart) ?? dayStart)

        guard windowEnd > windowStart else {
            return Self.rebuilt(from: self, start: windowStart, end: windowStart, events: [])
        }

        let inWindow = events
            .filter { $0.start < windowEnd && $0.end > windowStart }
            .sorted { $0.start < $1.start }

        guard inWindow.count > WatchCoverage.maxEvents else {
            return Self.rebuilt(from: self, start: windowStart, end: windowEnd, events: inWindow)
        }

        let kept = Array(inWindow.prefix(WatchCoverage.maxEvents))
        // The first dropped event marks the edge of what we can prove. Its start
        // becomes the new end of coverage; the last kept event is dropped too
        // when it starts at that same instant, which keeps the invariant
        // "every event we carry starts before coverageEnd" exactly true.
        let provenEnd = max(windowStart, min(windowEnd, inWindow[WatchCoverage.maxEvents].start))
        return Self.rebuilt(from: self, start: windowStart, end: provenEnd,
                            events: kept.filter { $0.start < provenEnd && $0.end > windowStart })
    }

    private static func rebuilt(from source: CalendarrSnapshot,
                                start: Date, end: Date,
                                events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: source.writtenAt,
                          coverageStart: start,
                          coverageEnd: end,
                          isLoggedIn: source.isLoggedIn,
                          writerVersion: source.writerVersion,
                          events: events,
                          theme: source.theme,
                          language: source.language)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchTrimmingTests
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd ../CalendarrKit
git add Sources/CalendarrCore/Snapshot/WatchCoverage.swift Tests/CalendarrCoreTests/WatchTrimmingTests.swift
git commit -m "Add the watch coverage policy and snapshot trimming"
```

---

## Task 3: Shared calendar filtering

Both timeline providers narrow a snapshot by calendar key. `CalendarrTimelineProvider.filtered(_:by:)` already does it on iOS; the watch needs the same rule, so it moves into the package rather than being written twice.

**Files:**
- Create: `../CalendarrKit/Sources/CalendarrCore/Snapshot/SnapshotFilter.swift`
- Test: `../CalendarrKit/Tests/CalendarrCoreTests/SnapshotFilterTests.swift`
- Modify: `CalendarrWidgets/CalendarrTimelineProvider.swift:38-55`

- [ ] **Step 1: Write the failing tests**

Create `../CalendarrKit/Tests/CalendarrCoreTests/SnapshotFilterTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarrCore

struct SnapshotFilterTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, key: String) -> SnapshotEvent {
        SnapshotEvent(id: id, title: id, start: now, end: now.addingTimeInterval(3600),
                      isAllDay: false, colorHex: "#4285f4", location: "", calendarKey: key)
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(86400),
                          isLoggedIn: true, writerVersion: "1.0", events: events,
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("An empty allow-list means every calendar, not no calendar")
    func emptyAllowListKeepsEverything() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(toCalendarKeys: []).events.count == 2)
    }

    @Test("An allow-list keeps only the listed calendars")
    func allowListNarrows() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(toCalendarKeys: ["local:1"]).events.map(\.id) == ["a"])
    }

    @Test("A deny-list removes only the listed calendars")
    func denyListNarrows() {
        let snap = Self.snapshot([Self.event("a", key: "local:1"), Self.event("b", key: "caldav:2")])
        #expect(snap.filtered(excludingCalendarKeys: ["local:1"]).events.map(\.id) == ["b"])
    }

    @Test("Filtering narrows the events but never the window")
    func windowIsUntouched() {
        let snap = Self.snapshot([Self.event("a", key: "local:1")])
        let filtered = snap.filtered(toCalendarKeys: ["nothing:0"])

        #expect(filtered.events.isEmpty)
        #expect(filtered.coverageStart == snap.coverageStart)
        #expect(filtered.coverageEnd == snap.coverageEnd)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SnapshotFilterTests
```

Expected: FAIL to compile — no member `filtered(toCalendarKeys:)`.

- [ ] **Step 3: Write the implementation**

Create `../CalendarrKit/Sources/CalendarrCore/Snapshot/SnapshotFilter.swift`:

```swift
import Foundation

extension CalendarrSnapshot {
    /// Keep only the listed calendars. An empty set means "every calendar",
    /// which is what an unconfigured widget or complication asks for.
    ///
    /// Filtering narrows the events but deliberately not the window: the
    /// snapshot still speaks for the same range, it just has fewer calendars
    /// in it.
    public func filtered(toCalendarKeys keys: Set<String>) -> CalendarrSnapshot {
        guard !keys.isEmpty else { return self }
        return replacingEvents(events.filter { keys.contains($0.calendarKey) })
    }

    /// Remove the listed calendars, keeping everything else. An empty set is a
    /// no-op.
    public func filtered(excludingCalendarKeys keys: Set<String>) -> CalendarrSnapshot {
        guard !keys.isEmpty else { return self }
        return replacingEvents(events.filter { !keys.contains($0.calendarKey) })
    }

    private func replacingEvents(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: writtenAt,
                          coverageStart: coverageStart,
                          coverageEnd: coverageEnd,
                          isLoggedIn: isLoggedIn,
                          writerVersion: writerVersion,
                          events: events,
                          theme: theme,
                          language: language)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SnapshotFilterTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Adopt it in the iOS widget provider**

In `CalendarrWidgets/CalendarrTimelineProvider.swift`, replace the whole `// MARK: – Filtering` section (the `filtered(_:by:)` method, currently lines 38-55) with:

```swift
    // MARK: – Filtering

    private func filtered(_ snapshot: WidgetSnapshot?, by config: CalendarSelectionIntent) -> WidgetSnapshot? {
        // The rule lives in CalendarrCore so the watch provider cannot drift
        // from this one. Nothing selected means "show all calendars".
        snapshot?.filtered(toCalendarKeys: Set((config.selectedCalendars ?? []).map(\.id)))
    }
```

Then add the import at the top of the file, after `import AppIntents`:

```swift
import CalendarrCore
```

- [ ] **Step 6: Build the iOS app to verify the adoption compiles**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit both repos**

```bash
cd ../CalendarrKit
git add Sources/CalendarrCore/Snapshot/SnapshotFilter.swift Tests/CalendarrCoreTests/SnapshotFilterTests.swift
git commit -m "Move calendar-key filtering into the shared package"
cd "../Calendarr iOS"
git add CalendarrWidgets/CalendarrTimelineProvider.swift
git commit -m "Filter widget snapshots through the shared package rule"
```

---

## Task 4: WatchConnectivity wire format

**Files:**
- Create: `../CalendarrKit/Sources/CalendarrCore/Transport/WatchTransportPayload.swift`
- Test: `../CalendarrKit/Tests/CalendarrCoreTests/WatchTransportTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `../CalendarrKit/Tests/CalendarrCoreTests/WatchTransportTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarrCore

/// The phone and the watch ship on independent schedules, so the transport gets
/// the same treatment as the file format: refuse a newer schema rather than
/// mis-decode it.
struct WatchTransportTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func snapshot() -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(14 * 86400),
                          isLoggedIn: true, writerVersion: "1.2",
                          events: [SnapshotEvent(id: "a", title: "Zahnarzt",
                                                 start: now.addingTimeInterval(3600),
                                                 end: now.addingTimeInterval(7200),
                                                 isAllDay: false, colorHex: "#4285f4",
                                                 location: "Bern", calendarKey: "local:3")],
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("A payload survives a round trip")
    func roundTrips() throws {
        let payload = WatchTransportPayload(
            snapshot: Self.snapshot(),
            calendars: [SnapshotCalendar(id: "local:3", name: "Privat", colorHex: "#4285f4")],
            session: SharedSession(baseURL: "https://cal.example.com", username: "guido",
                                   isLoggedIn: true, writtenAt: Self.now))

        let decoded = try WatchTransportPayload.decode(try payload.encoded())

        #expect(decoded.snapshot.events.map(\.id) == ["a"])
        #expect(decoded.snapshot.language == "de")
        #expect(decoded.calendars.map(\.name) == ["Privat"])
        #expect(decoded.session?.username == "guido")
    }

    @Test("A payload with no session record still decodes")
    func sessionIsOptional() throws {
        let payload = WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil)
        let decoded = try WatchTransportPayload.decode(try payload.encoded())

        #expect(decoded.session == nil)
        #expect(decoded.calendars.isEmpty)
    }

    @Test("The encoded form only contains property-list types")
    func encodesToPlistTypes() throws {
        let dict = try WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil).encoded()

        #expect(dict[WatchTransportKey.schema] is Int)
        #expect(dict[WatchTransportKey.snapshot] is Data)
        #expect(PropertyListSerialization.propertyList(dict, isValidFor: .binary))
    }

    @Test("A newer schema is refused rather than guessed at")
    func refusesNewerSchema() throws {
        var dict = try WatchTransportPayload(snapshot: Self.snapshot(), calendars: [], session: nil).encoded()
        dict[WatchTransportKey.schema] = WatchTransportPayload.maxSupportedSchema + 1

        #expect(throws: WatchTransportError.unsupportedSchema(
            found: WatchTransportPayload.maxSupportedSchema + 1,
            maxSupported: WatchTransportPayload.maxSupportedSchema)) {
            try WatchTransportPayload.decode(dict)
        }
    }

    @Test("A payload without a snapshot is rejected")
    func rejectsMissingSnapshot() {
        let dict: [String: Any] = [WatchTransportKey.schema: WatchTransportPayload.currentSchema]

        #expect(throws: WatchTransportError.missingSnapshot) {
            try WatchTransportPayload.decode(dict)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchTransportTests
```

Expected: FAIL to compile — `cannot find 'WatchTransportPayload' in scope`.

- [ ] **Step 3: Write the implementation**

Create `../CalendarrKit/Sources/CalendarrCore/Transport/WatchTransportPayload.swift`:

```swift
import Foundation

/// Dictionary keys used on the WatchConnectivity wire. Stable within a major
/// version, like the snapshot filenames.
public enum WatchTransportKey {
    public static let schema    = "schema"
    public static let snapshot  = "snapshot"
    public static let calendars = "calendars"
    public static let session   = "session"
}

public enum WatchTransportError: Error, Equatable, LocalizedError {
    case missingSnapshot
    case unsupportedSchema(found: Int, maxSupported: Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .missingSnapshot:
            return "Watch payload carried no snapshot."
        case .unsupportedSchema(let found, let max):
            return "Watch payload schema \(found) is newer than this build understands (\(max))."
        case .malformed(let why):
            return "Watch payload could not be decoded: \(why)"
        }
    }
}

/// What the phone sends to the watch: a trimmed snapshot, the calendar list for
/// a filter UI, and the non-secret session facts so the watch can tell "signed
/// out" from "never received anything".
///
/// The auth token is deliberately absent. The watch never talks to the server,
/// so there is nothing for it to authenticate with and nothing to leak.
public struct WatchTransportPayload: Sendable {
    /// Bump only for a breaking change to the dictionary shape.
    public static let currentSchema = 1
    /// Payloads claiming a higher schema are refused rather than mis-decoded.
    public static let maxSupportedSchema = 1

    public let snapshot: CalendarrSnapshot
    public let calendars: [SnapshotCalendar]
    public let session: SharedSession?

    public init(snapshot: CalendarrSnapshot,
                calendars: [SnapshotCalendar],
                session: SharedSession?) {
        self.snapshot = snapshot
        self.calendars = calendars
        self.session = session
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Encode for `WCSession`. Values are `Data` and `Int` only, because
    /// WatchConnectivity accepts property-list types and rejects everything
    /// else at runtime rather than at compile time.
    public func encoded() throws -> [String: Any] {
        let e = Self.encoder()
        var dict: [String: Any] = [
            WatchTransportKey.schema: Self.currentSchema,
            WatchTransportKey.snapshot: try e.encode(snapshot),
            WatchTransportKey.calendars: try e.encode(calendars),
        ]
        if let session { dict[WatchTransportKey.session] = try e.encode(session) }
        return dict
    }

    public static func decode(_ dict: [String: Any]) throws -> WatchTransportPayload {
        let found = dict[WatchTransportKey.schema] as? Int ?? 1
        guard found <= maxSupportedSchema else {
            throw WatchTransportError.unsupportedSchema(found: found, maxSupported: maxSupportedSchema)
        }
        guard let snapshotData = dict[WatchTransportKey.snapshot] as? Data else {
            throw WatchTransportError.missingSnapshot
        }

        let d = decoder()
        let snapshot: CalendarrSnapshot
        do { snapshot = try d.decode(CalendarrSnapshot.self, from: snapshotData) }
        catch { throw WatchTransportError.malformed("snapshot: \(error)") }

        var calendars: [SnapshotCalendar] = []
        if let data = dict[WatchTransportKey.calendars] as? Data {
            calendars = (try? d.decode([SnapshotCalendar].self, from: data)) ?? []
        }

        var session: SharedSession?
        if let data = dict[WatchTransportKey.session] as? Data {
            session = try? d.decode(SharedSession.self, from: data)
        }

        return WatchTransportPayload(snapshot: snapshot, calendars: calendars, session: session)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchTransportTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd ../CalendarrKit
git add Sources/CalendarrCore/Transport/WatchTransportPayload.swift Tests/CalendarrCoreTests/WatchTransportTests.swift
git commit -m "Add the WatchConnectivity payload format with schema refusal"
```

---

## Task 5: Complication push policy

`transferCurrentComplicationUserInfo` is the only path that wakes the watch app while it is not running, and its daily budget is small. It is therefore spent only when the *next* appointment actually changed.

**Files:**
- Create: `../CalendarrKit/Sources/CalendarrCore/Transport/WatchPushPolicy.swift`
- Test: `../CalendarrKit/Tests/CalendarrCoreTests/WatchPushPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `../CalendarrKit/Tests/CalendarrCoreTests/WatchPushPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarrCore

struct WatchPushPolicyTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, startOffset: TimeInterval,
                              duration: TimeInterval = 3600) -> SnapshotEvent {
        SnapshotEvent(id: id, title: id,
                      start: now.addingTimeInterval(startOffset),
                      end: now.addingTimeInterval(startOffset + duration),
                      isAllDay: false, colorHex: "#4285f4", location: "", calendarKey: "local:1")
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(14 * 86400),
                          isLoggedIn: true, writerVersion: "1.0", events: events,
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("The next event is the first one that has not ended yet")
    func picksFirstUnfinished() {
        let snap = Self.snapshot([Self.event("past", startOffset: -7200),
                                  Self.event("running", startOffset: -600),
                                  Self.event("later", startOffset: 3600)])

        #expect(WatchPushPolicy.nextEventIdentity(in: snap, at: Self.now)?.id == "running")
    }

    @Test("An empty calendar has no next event")
    func emptyHasNoIdentity() {
        #expect(WatchPushPolicy.nextEventIdentity(in: Self.snapshot([]), at: Self.now) == nil)
    }

    @Test("Events are considered in start order regardless of input order")
    func sortsBeforePicking() {
        let snap = Self.snapshot([Self.event("late", startOffset: 7200),
                                  Self.event("soon", startOffset: 1800)])

        #expect(WatchPushPolicy.nextEventIdentity(in: snap, at: Self.now)?.id == "soon")
    }

    @Test("An unchanged next event does not spend a push")
    func unchangedDoesNotPush() {
        let identity = NextEventIdentity(id: "a", start: Self.now)
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: identity, current: identity) == false)
    }

    @Test("A different event, a moved event, or a first event all spend a push")
    func changesPush() {
        let a = NextEventIdentity(id: "a", start: Self.now)
        let b = NextEventIdentity(id: "b", start: Self.now)
        let moved = NextEventIdentity(id: "a", start: Self.now.addingTimeInterval(600))

        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: b))
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: moved))
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: nil, current: a))
    }

    @Test("Losing the last event spends a push, so the watch stops showing it")
    func clearingPushes() {
        let a = NextEventIdentity(id: "a", start: Self.now)
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: a, current: nil))
    }

    @Test("Two empty calendars in a row do not push")
    func stayingEmptyDoesNotPush() {
        #expect(WatchPushPolicy.shouldPushComplicationUpdate(previous: nil, current: nil) == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchPushPolicyTests
```

Expected: FAIL to compile — `cannot find 'WatchPushPolicy' in scope`.

- [ ] **Step 3: Write the implementation**

Create `../CalendarrKit/Sources/CalendarrCore/Transport/WatchPushPolicy.swift`:

```swift
import Foundation

/// Identifies the appointment a complication is currently showing.
///
/// The start date is part of the identity on purpose: a moved event keeps its
/// id, and the complication is wrong until it is told.
public struct NextEventIdentity: Equatable, Sendable, Codable {
    public let id: String
    public let start: Date

    public init(id: String, start: Date) {
        self.id = id
        self.start = start
    }
}

public enum WatchPushPolicy {
    /// The first event that has not ended yet — which is what every "next
    /// appointment" complication renders, including one that is running now.
    public static func nextEventIdentity(in snapshot: CalendarrSnapshot,
                                         at now: Date) -> NextEventIdentity? {
        snapshot.events
            .filter { $0.end > now }
            .min { $0.start < $1.start }
            .map { NextEventIdentity(id: $0.id, start: $0.start) }
    }

    /// Whether this change is worth one of the day's limited complication
    /// pushes. Only a changed next appointment is — everything else reaches the
    /// watch on the next application-context delivery.
    public static func shouldPushComplicationUpdate(previous: NextEventIdentity?,
                                                    current: NextEventIdentity?) -> Bool {
        previous != current
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WatchPushPolicyTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd ../CalendarrKit
git add Sources/CalendarrCore/Transport/WatchPushPolicy.swift Tests/CalendarrCoreTests/WatchPushPolicyTests.swift
git commit -m "Decide complication pushes from the next appointment's identity"
```

---

## Task 6: Complication timeline boundaries

The iOS provider emits 24 hourly entries. On the watch, entries land on event boundaries instead, so the complication flips in the exact minute the next appointment changes — with no network call and no refresh budget spent.

**Files:**
- Create: `../CalendarrKit/Sources/CalendarrCore/Complications/ComplicationTimeline.swift`
- Test: `../CalendarrKit/Tests/CalendarrCoreTests/ComplicationTimelineTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `../CalendarrKit/Tests/CalendarrCoreTests/ComplicationTimelineTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarrCore

struct ComplicationTimelineTests {

    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    private static func event(_ id: String, startOffset: TimeInterval,
                              duration: TimeInterval) -> SnapshotEvent {
        SnapshotEvent(id: id, title: id,
                      start: now.addingTimeInterval(startOffset),
                      end: now.addingTimeInterval(startOffset + duration),
                      isAllDay: false, colorHex: "#4285f4", location: "", calendarKey: "local:1")
    }

    private static func snapshot(_ events: [SnapshotEvent]) -> CalendarrSnapshot {
        CalendarrSnapshot(writtenAt: now,
                          coverageStart: now.addingTimeInterval(-86400),
                          coverageEnd: now.addingTimeInterval(14 * 86400),
                          isLoggedIn: true, writerVersion: "1.0", events: events,
                          theme: SnapshotTheme(today: "#1", text: "#2", background: "#3",
                                               line: "#4", primary: "#5", accent: "#6"),
                          language: "de")
    }

    @Test("The first entry is always now, so the complication renders immediately")
    func startsAtNow() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]))
        #expect(dates.first == Self.now)
    }

    @Test("Entries are sorted and free of duplicates")
    func sortedAndDeduplicated() {
        // Two events that meet exactly: one ends where the next begins.
        let snap = Self.snapshot([Self.event("a", startOffset: 3600, duration: 1800),
                                  Self.event("b", startOffset: 5400, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test("Event starts and ends inside the horizon become entries")
    func includesEventBoundaries() {
        let snap = Self.snapshot([Self.event("a", startOffset: 3600, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates.contains(Self.now.addingTimeInterval(3600)))
        #expect(dates.contains(Self.now.addingTimeInterval(5400)))
    }

    @Test("Boundaries outside the horizon are ignored")
    func ignoresBoundariesBeyondHorizon() {
        let snap = Self.snapshot([Self.event("far", startOffset: 40 * 3600, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap, horizon: 24 * 3600)

        #expect(dates.contains(Self.now.addingTimeInterval(40 * 3600)) == false)
        #expect(dates.allSatisfy { $0 <= Self.now.addingTimeInterval(24 * 3600) })
    }

    @Test("Boundaries already in the past are ignored")
    func ignoresPastBoundaries() {
        let snap = Self.snapshot([Self.event("past", startOffset: -7200, duration: 1800)])
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: snap)

        #expect(dates.allSatisfy { $0 >= Self.now })
    }

    @Test("An empty calendar still gets hourly entries across the horizon")
    func fillsHourlyWhenEmpty() {
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot([]),
                                                    horizon: 24 * 3600)
        #expect(dates.count >= 24)
    }

    @Test("The entry count is capped, keeping the earliest entries")
    func capsEntries() {
        var events: [SnapshotEvent] = []
        for i in 0..<300 {
            events.append(Self.event("e\(i)", startOffset: Double(i) * 60, duration: 30))
        }
        let dates = ComplicationTimeline.entryDates(from: Self.now, in: Self.snapshot(events),
                                                    maxEntries: 50)

        #expect(dates.count == 50)
        #expect(dates.first == Self.now)
        #expect(dates == dates.sorted())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ComplicationTimelineTests
```

Expected: FAIL to compile — `cannot find 'ComplicationTimeline' in scope`.

- [ ] **Step 3: Write the implementation**

Create `../CalendarrKit/Sources/CalendarrCore/Complications/ComplicationTimeline.swift`:

```swift
import Foundation

/// When a complication needs to be redrawn.
///
/// A watch-face complication has a small refresh budget, so the timeline is
/// pre-computed from data the watch already holds instead of being refreshed on
/// a schedule: an entry on every event boundary means the complication changes
/// in the exact minute the next appointment does, without a network call.
public enum ComplicationTimeline {
    /// Dates at which a complication should re-render.
    ///
    /// Always begins with `now` so the first entry renders immediately. Event
    /// starts and ends within `horizon` become entries; hourly marks fill the
    /// rest so a quiet calendar still advances its date and countdown. The
    /// result is sorted, deduplicated to the second, and capped at
    /// `maxEntries`, keeping the earliest.
    public static func entryDates(from now: Date,
                                  in snapshot: CalendarrSnapshot,
                                  horizon: TimeInterval = 24 * 3600,
                                  maxEntries: Int = 100) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var seen: Set<Int> = []
        var dates: [Date] = []

        func add(_ date: Date) {
            guard date >= now, date <= end else { return }
            // Deduplicate to whole seconds: two events that meet exactly would
            // otherwise produce two entries a float apart.
            let key = Int(date.timeIntervalSince1970.rounded())
            guard seen.insert(key).inserted else { return }
            dates.append(date)
        }

        add(now)
        for event in snapshot.events {
            add(event.start)
            add(event.end)
        }
        var hourly = now.addingTimeInterval(3600)
        while hourly <= end {
            add(hourly)
            hourly = hourly.addingTimeInterval(3600)
        }

        return Array(dates.sorted().prefix(maxEntries))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ComplicationTimelineTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Run the whole package suite**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: build succeeds against the native macOS SDK (which proves no UIKit crept in) and every test passes.

- [ ] **Step 6: Commit**

```bash
cd ../CalendarrKit
git add Sources/CalendarrCore/Complications/ComplicationTimeline.swift Tests/CalendarrCoreTests/ComplicationTimelineTests.swift
git commit -m "Compute complication timeline entries from event boundaries"
```

---
## Task 7: iOS background refresh

Independently valuable: the home-screen widgets are currently only as fresh as the last time the app was opened, because `publishWidgetSnapshot()` runs only from `CalendarStore` actions. This task fixes that, and the watch inherits the fix.

`allCachedEvents` is in-memory only, so a `CalendarStore` created in the background starts with no events but with the persisted hidden/banished/reminder sets intact. A forced fetch fills it, and `publishWidgetSnapshot()` then runs exactly as it does in the foreground.

**Files:**
- Create: `Calendarr iOS/Services/BackgroundRefresh.swift`
- Modify: `Calendarr iOS/CalendarrApp.swift:5-13`
- Create: `Calendarr-Info.plist` (project root)
- Modify: `Calendarr iOS.xcodeproj/project.pbxproj` (`INFOPLIST_FILE`, both configurations)

- [ ] **Step 1: Write the refresh service**

Create `Calendarr iOS/Services/BackgroundRefresh.swift`:

```swift
import BackgroundTasks
import Foundation
import CalendarrCore

/// Keeps the shared snapshot fresh while the app is not in the foreground.
///
/// Without this, `publishWidgetSnapshot()` only ever runs from a user action,
/// so an event created on the web or on Android does not reach the widgets — or
/// the watch — until the app is opened again. iOS decides when this actually
/// runs, based on how the user uses the app: it improves freshness, it does not
/// guarantee it.
@MainActor
enum BackgroundRefresh {
    static let taskIdentifier = "com.scarriffleservices.calendarr.ios.refresh"

    /// Minimum gap between runs we ask for. iOS treats this as the earliest
    /// acceptable time, not a promise.
    private static let interval: TimeInterval = 30 * 60

    /// Call once at launch, before the app finishes starting up.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier,
                                        using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in await handle(refresh) }
        }
    }

    /// Ask for the next run. Safe to call repeatedly; a duplicate submission
    /// replaces the pending request rather than queueing a second one.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do { try BGTaskScheduler.shared.submit(request) }
        catch {
            // Submission fails on a simulator and when the user has disabled
            // background refresh. Neither is worth interrupting anyone over.
            print("[BackgroundRefresh] submit failed: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) async {
        // Reschedule first: if the work below throws or is killed, the chain
        // must not end here.
        schedule()

        let work = Task { @MainActor in await refreshSnapshot() }
        task.expirationHandler = { work.cancel() }

        let succeeded = await work.value
        task.setTaskCompleted(success: succeeded)
    }

    /// Fetch the snapshot window and republish. Returns false when there was
    /// nothing to do or the fetch failed.
    private static func refreshSnapshot() async -> Bool {
        let state = AppState()
        guard state.isConfigured, state.isLoggedIn else { return false }

        // An SSO session can lapse while the app is closed; renewing first
        // avoids spending the whole background window on a 401.
        await OIDCSessionRefresher.refreshIfNeeded(state)

        let api = CalendarrAPI(baseURL: state.serverURL, token: state.authToken)
        let store = CalendarStore()

        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -SnapshotCoverage.daysBehind, to: dayStart),
              let to = calendar.date(byAdding: .day, value: SnapshotCoverage.daysAhead, to: dayStart)
        else { return false }

        // force: a freshly created store has an empty in-memory cache, so
        // without this the "already cached" short-circuit would skip the fetch.
        await store.loadEvents(api: api, start: from, end: to, force: true)

        return store.lastError == nil
    }
}
```

- [ ] **Step 2: Register it at launch**

In `Calendarr iOS/CalendarrApp.swift`, replace the struct body so it reads:

```swift
@main
struct CalendarrApp: App {
    @State private var appState = AppState()

    init() {
        // Registration has to happen before the app finishes launching, which
        // is why it is here and not in a .task modifier.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task { BackgroundRefresh.schedule() }
        }
    }
}
```

- [x] **Step 3: Add the Info.plist keys**

Both keys are arrays, and Xcode does **not** expose either as an
`INFOPLIST_KEY_` build setting — verified by setting them, building, and finding
them absent from the result while `INFOPLIST_KEY_UIApplicationSupportsIndirect\
InputEvents` did land. Use a partial Info.plist instead; generation stays on and
merges into it.

Create `Calendarr-Info.plist` at the **project root**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.scarriffleservices.calendarr.ios.refresh</string>
	</array>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
	</array>
</dict>
</plist>
```

Then set `INFOPLIST_FILE = "Calendarr-Info.plist"` on the **Calendarr iOS**
target in both configurations, leaving `GENERATE_INFOPLIST_FILE = YES`.

The root location is load-bearing: `Calendarr iOS/` is a
`PBXFileSystemSynchronizedRootGroup`, so a plist inside it is also copied as a
resource and the build fails with "Multiple commands produce .../Info.plist".

- [x] **Step 4: Build and verify the merge lost nothing**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/calendarr-dd CODE_SIGNING_ALLOWED=NO build
plutil -p "/tmp/calendarr-dd/Build/Products/Release-iphonesimulator/Calendarr iOS.app/Info.plist" | grep -A3 -i "BGTaskScheduler\|UIBackgroundModes"
```

Note the scheme builds **Release**, not Debug. Expected: `** BUILD SUCCEEDED **`
and both keys present. Diff the whole plist against a build without the change
to confirm no generated key was displaced.

- [ ] **Step 5: Commit**

```bash
git add "Calendarr iOS/Services/BackgroundRefresh.swift" "Calendarr iOS/CalendarrApp.swift" "Calendarr iOS.xcodeproj/project.pbxproj"
git commit -m "Refresh the shared snapshot in the background so widgets stop going stale"
git push origin main
```

---

## Task 8: WatchConnectivity sender on the phone

**Files:**
- Create: `Calendarr iOS/Services/WatchSyncService.swift`
- Modify: `Calendarr iOS/Models/CalendarStore.swift:602` and `:623-628`
- Modify: `Calendarr iOS/CalendarrApp.swift` (activate the session)
- Modify: `Calendarr iOS/CalendarrApp.swift` `AppState.logout()`

- [ ] **Step 1: Write the sender**

Create `Calendarr iOS/Services/WatchSyncService.swift`:

```swift
import Foundation
import WatchConnectivity
import CalendarrCore

/// Feeds the watch. App Groups are per-device, so the watch cannot read the
/// file this app just wrote — it has to be handed the data.
///
/// Three delivery paths, because each one alone leaves a gap:
///
/// 1. `updateApplicationContext` carries only the latest state and has no queue
///    to overflow. It is delivered when the watch app next launches or wakes.
/// 2. `transferCurrentComplicationUserInfo` is the only path that wakes the
///    watch app while it is not running. Its daily budget is small, so it is
///    spent only when the *next* appointment changed.
/// 3. A reply to `sendMessage` covers the watch app asking while it is open.
@MainActor
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private let sessions = SharedSessionStore()
    private static let lastIdentityKey = "watchLastPushedNextEvent"
    private static let pushTimesKey = "watchComplicationPushTimes"
    /// The system budget is roughly 50 a day; this keeps a burst of edits from
    /// spending it in an hour.
    private static let maxPushesPerHour = 4

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Call once at launch.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Publish the current calendar to the watch.
    func push(snapshot: CalendarrSnapshot, calendars: [SnapshotCalendar]) {
        guard let session, session.activationState == .activated else { return }

        let trimmed = snapshot.trimmedForWatch()
        let payload = WatchTransportPayload(snapshot: trimmed,
                                            calendars: calendars,
                                            session: sessions.read())
        guard let dict = try? payload.encoded() else { return }

        try? session.updateApplicationContext(dict)

        guard session.isComplicationEnabled else { return }
        let current = WatchPushPolicy.nextEventIdentity(in: trimmed, at: Date())
        guard WatchPushPolicy.shouldPushComplicationUpdate(previous: loadLastIdentity(),
                                                           current: current),
              consumePushBudget()
        else { return }

        session.transferCurrentComplicationUserInfo(dict)
        storeLastIdentity(current)
    }

    /// Tell the watch the user signed out, so it stops showing their calendar.
    /// The watch keeps its own copy of the snapshot, so clearing ours is not
    /// enough.
    func pushSignedOut() {
        guard let session, session.activationState == .activated else { return }

        let now = Date()
        let empty = CalendarrSnapshot(
            writtenAt: now, coverageStart: now, coverageEnd: now,
            isLoggedIn: false, writerVersion: "signout", events: [],
            theme: SnapshotTheme(today: "#4285f4", text: "#FFFFFF", background: "#000000",
                                 line: "#3A3A52", primary: "#4285f4", accent: "#ea4335"),
            language: "system")
        let payload = WatchTransportPayload(snapshot: empty, calendars: [], session: sessions.read())
        guard let dict = try? payload.encoded() else { return }

        try? session.updateApplicationContext(dict)
        if session.isComplicationEnabled, consumePushBudget() {
            session.transferCurrentComplicationUserInfo(dict)
        }
        storeLastIdentity(nil)
    }

    /// The payload for a watch that asked directly. Built from the file we
    /// already wrote, so an on-demand pull cannot disagree with a push.
    fileprivate func currentPayloadDictionary() -> [String: Any]? {
        let store = SnapshotStore()
        guard case .ok(let snapshot) = store.read() else { return nil }
        let payload = WatchTransportPayload(snapshot: snapshot.trimmedForWatch(),
                                            calendars: store.readCalendars(),
                                            session: sessions.read())
        return try? payload.encoded()
    }

    // MARK: – Push budget

    private func consumePushBudget() -> Bool {
        let cutoff = Date().addingTimeInterval(-3600)
        var times = (UserDefaults.standard.array(forKey: Self.pushTimesKey) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .filter { $0 > cutoff }

        guard times.count < Self.maxPushesPerHour else {
            UserDefaults.standard.set(times.map(\.timeIntervalSince1970), forKey: Self.pushTimesKey)
            return false
        }
        times.append(Date())
        UserDefaults.standard.set(times.map(\.timeIntervalSince1970), forKey: Self.pushTimesKey)
        return true
    }

    // MARK: – Last pushed identity

    private func loadLastIdentity() -> NextEventIdentity? {
        guard let data = UserDefaults.standard.data(forKey: Self.lastIdentityKey) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NextEventIdentity.self, from: data)
    }

    private func storeLastIdentity(_ identity: NextEventIdentity?) {
        guard let identity else {
            UserDefaults.standard.removeObject(forKey: Self.lastIdentityKey)
            return
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try? encoder.encode(identity), forKey: Self.lastIdentityKey)
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        if let error {
            print("[WatchSync] activation failed: \(error.localizedDescription)")
        }
    }

    /// The watch asking for the current state, which is what covers "it is open
    /// in front of me and looks stale".
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.currentPayloadDictionary() ?? [:])
        }
    }

    // Required on iOS: the session is torn down and re-activated when the user
    // switches to a different paired watch.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
```

- [ ] **Step 2: Activate the session at launch**

In `Calendarr iOS/CalendarrApp.swift`, extend `init()` so it reads:

```swift
    init() {
        // Registration has to happen before the app finishes launching, which
        // is why it is here and not in a .task modifier.
        BackgroundRefresh.register()
        WatchSyncService.shared.activate()
    }
```

- [ ] **Step 3: Push from the one place that publishes**

In `Calendarr iOS/Models/CalendarStore.swift`, inside `publishWidgetSnapshot()`, replace this line (currently line 602):

```swift
        WidgetStore.writeCalendars(Array(calendarMap.values).sorted { $0.name < $1.name })
```

with:

```swift
        let calendars = Array(calendarMap.values).sorted { $0.name < $1.name }
        WidgetStore.writeCalendars(calendars)
```

Then replace the closing lines of the same method (currently lines 623-628):

```swift
        WidgetStore.write(WidgetStore.makeSnapshot(events: Array(visible),
                                                   coverageStart: from,
                                                   coverageEnd: to))
        WidgetTimelineNotifier.reload()
```

with:

```swift
        let snapshot = WidgetStore.makeSnapshot(events: Array(visible),
                                                coverageStart: from,
                                                coverageEnd: to)
        WidgetStore.write(snapshot)
        WidgetTimelineNotifier.reload()
        // The watch has its own container and cannot read the file we just
        // wrote, so it is handed the data explicitly.
        WatchSyncService.shared.push(snapshot: snapshot, calendars: calendars)
```

- [ ] **Step 4: Tell the watch about sign-out**

In `Calendarr iOS/CalendarrApp.swift`, in `AppState.logout()`, after the existing `publishSession()` call, add:

```swift
        // The watch keeps its own copy of the snapshot, so clearing ours is not
        // enough — it has to be told, or it keeps rendering this user's events.
        WatchSyncService.shared.pushSignedOut()
```

- [ ] **Step 5: Build the iOS app**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add "Calendarr iOS/Services/WatchSyncService.swift" "Calendarr iOS/CalendarrApp.swift" "Calendarr iOS/Models/CalendarStore.swift"
git commit -m "Send the trimmed snapshot to the watch over WatchConnectivity"
git push origin main
```

---

## Task 9: Create the two watchOS targets

This is Xcode project work, not code. Editing `project.pbxproj` by hand to add targets is error-prone; use the UI.

**Files:**
- Create: `CalendarrWatch/CalendarrWatch.entitlements`
- Create: `CalendarrWatchComplications/CalendarrWatchComplications.entitlements`
- Modify: `Calendarr iOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the watch app target**

In Xcode: File → New → Target → watchOS → **App**.

- Product Name: `CalendarrWatch`
- Bundle Identifier: `com.scarriffleservices.calendarr.ios.watchkitapp`
- Interface: SwiftUI, Language: Swift
- **Uncheck** Include Notification Scene
- **Check** "Watch App for Existing iOS App" / set the companion to **Calendarr iOS** so `WKCompanionAppBundleIdentifier` resolves to `com.scarriffleservices.calendarr.ios`

Then in Build Settings for the new target set `WATCHOS_DEPLOYMENT_TARGET = 26.0`.

- [ ] **Step 2: Add the complications target**

File → New → Target → watchOS → **Widget Extension**.

- Product Name: `CalendarrWatchComplications`
- Bundle Identifier: `com.scarriffleservices.calendarr.ios.watchkitapp.complications`
- Embed in Application: `CalendarrWatch`
- **Uncheck** Include Live Activity
- **Check** Include Configuration App Intent

Set `WATCHOS_DEPLOYMENT_TARGET = 26.0`.

Delete the template files Xcode generated in both new target folders; the tasks below create the real ones.

- [ ] **Step 3: Link the shared package to both targets**

For `CalendarrWatch` and `CalendarrWatchComplications`: target → General → "Frameworks, Libraries, and Embedded Content" → **+** → `CalendarrCore` (under the local `CalendarrKit` package).

- [ ] **Step 4: Write the entitlements**

Create `CalendarrWatch/CalendarrWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.scarriffleservices.calendarr</string>
	</array>
</dict>
</plist>
```

Create `CalendarrWatchComplications/CalendarrWatchComplications.entitlements` with **identical** contents.

Set `CODE_SIGN_ENTITLEMENTS` on each target to its own file.

No keychain access group: the watch never holds a token, so there is nothing there to protect.

The App Group identifier carries **no** Team ID prefix. watchOS follows the iOS rule here, and `CalendarrAppGroup.current` already resolves to the unprefixed form because its `#if os(macOS) || targetEnvironment(macCatalyst)` guard falls through. Getting this wrong fails silently: `containerURL(...)` returns nil and every read and write no-ops.

- [ ] **Step 5: Register the identifiers in the developer portal**

For both new bundle IDs, enable the **App Groups** capability and select `group.com.scarriffleservices.calendarr`.

- [ ] **Step 6: Verify both targets build**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` (an empty app at this point).

- [ ] **Step 7: Commit**

```bash
git add "Calendarr iOS.xcodeproj/project.pbxproj" CalendarrWatch CalendarrWatchComplications
git commit -m "Add the watchOS app and complication targets"
git push origin main
```

---
## Task 10: Receive the payload on the watch

**Files:**
- Create: `CalendarrWatch/WatchL10n.swift` (membership: **both** watch targets)
- Create: `CalendarrWatch/WatchFilterStore.swift` (membership: **both** watch targets)
- Create: `CalendarrWatch/WatchSnapshotReceiver.swift`
- Create: `CalendarrWatch/CalendarrWatchApp.swift`

- [ ] **Step 1: Write the strings**

Create `CalendarrWatch/WatchL10n.swift`. Add it to **both** watch targets (the complications need the same strings).

```swift
import Foundation

/// German and English strings for the watch app and its complications.
///
/// A local copy rather than a shared one: `CalendarrCore` is deliberately
/// Foundation-only and holds no presentation concerns, and the iOS `WidgetL10n`
/// belongs to a target the watch cannot link against.
enum WatchL10n {
    static func t(_ key: String, _ stored: String) -> String {
        strings[resolve(stored)]?[key] ?? strings["en"]?[key] ?? key
    }

    static func locale(_ stored: String) -> Locale {
        Locale(identifier: resolve(stored) == "de" ? "de_DE" : "en_US")
    }

    private static func resolve(_ stored: String) -> String {
        if stored == "de" || stored == "en" { return stored }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("de") ? "de" : "en"
    }

    private static let strings: [String: [String: String]] = [
        "de": [
            "watch.title":            "Calendarr",
            "watch.calendars":        "Kalender",
            "watch.allday":           "Ganztägig",
            "watch.no_events":        "Keine Termine",
            "watch.today":            "Heute",
            "watch.tomorrow":         "Morgen",
            "watch.events_today":     "Termine",
            "watch.open_on_iphone":   "Calendarr einmal auf dem iPhone öffnen",
            "watch.sign_in":          "Auf dem iPhone anmelden",
            "watch.update":           "Watch-App aktualisieren",
            "watch.waiting":          "Warte auf Daten vom iPhone",
            "watch.unreadable":       "Daten nicht lesbar",
            "watch.as_of":            "Stand",
            "watch.no_information":   "Keine Daten für diesen Zeitraum",
        ],
        "en": [
            "watch.title":            "Calendarr",
            "watch.calendars":        "Calendars",
            "watch.allday":           "All-day",
            "watch.no_events":        "No events",
            "watch.today":            "Today",
            "watch.tomorrow":         "Tomorrow",
            "watch.events_today":     "events",
            "watch.open_on_iphone":   "Open Calendarr on your iPhone once",
            "watch.sign_in":          "Sign in on your iPhone",
            "watch.update":           "Update the watch app",
            "watch.waiting":          "Waiting for data from your iPhone",
            "watch.unreadable":       "Data unreadable",
            "watch.as_of":            "As of",
            "watch.no_information":   "No data for this range",
        ],
    ]
}
```

- [ ] **Step 2: Write the watch-local filter store**

Create `CalendarrWatch/WatchFilterStore.swift`. Add it to **both** watch targets — the app writes it, the complications read it, and that is exactly why it lives in the App Group rather than in the app's own defaults.

```swift
import Foundation
import CalendarrCore

/// Which calendars this watch hides, on top of what the phone already filtered.
///
/// The snapshot arrives with hidden and banished calendars already removed, so
/// this narrows further and can never contradict the phone. It lives in the App
/// Group so one toggle in the app affects every complication at once.
enum WatchFilterStore {
    private static let key = "watchHiddenCalendarKeys"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CalendarrAppGroup.current)
    }

    static func load() -> Set<String> {
        Set(defaults?.stringArray(forKey: key) ?? [])
    }

    static func save(_ keys: Set<String>) {
        defaults?.set(keys.sorted(), forKey: key)
    }
}
```

- [ ] **Step 3: Write the receiver**

Create `CalendarrWatch/WatchSnapshotReceiver.swift`:

```swift
import Foundation
import WatchConnectivity
import WidgetKit
@_spi(Writer) import CalendarrCore

/// Takes what the phone sends and writes it into this watch's own App Group
/// container, using the same `SnapshotStore` the phone writes with. One wire
/// format, one reader, no drift.
///
/// Only the app runs a `WCSession`; a widget extension cannot. The complications
/// always read what this wrote.
@MainActor
final class WatchSnapshotReceiver: NSObject {
    static let shared = WatchSnapshotReceiver()

    private let store = SnapshotStore()
    private let sessions = SharedSessionStore()

    /// Shown in the agenda footer, because a silent failure here looks exactly
    /// like an empty calendar.
    private(set) var lastError: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the phone for the current state. Covers "the app is open in front of
    /// me and looks stale"; the other two paths are push-driven.
    func requestRefresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        session.sendMessage(["request": "snapshot"],
                            replyHandler: { reply in
                                Task { @MainActor in self.apply(reply) }
                            },
                            errorHandler: { error in
                                Task { @MainActor in self.lastError = error.localizedDescription }
                            })
    }

    func apply(_ dict: [String: Any]) {
        guard !dict.isEmpty else { return }
        do {
            let payload = try WatchTransportPayload.decode(dict)
            // This write posts SnapshotChangeNotifier, which is what the read
            // model listens for — so the UI updates without being told twice.
            try store.write(payload.snapshot)
            try store.writeCalendars(payload.calendars)
            if let session = payload.session { try sessions.write(session) }
            WidgetCenter.shared.reloadAllTimelines()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension WatchSnapshotReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        if let error {
            Task { @MainActor in self.lastError = error.localizedDescription }
        }
    }

    /// The main path: latest state only, delivered when this app launches or wakes.
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    /// The complication push, which is the only path that wakes this app while
    /// it is not running.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
```

- [ ] **Step 4: Write the app entry point**

Create `CalendarrWatch/CalendarrWatchApp.swift`:

```swift
import SwiftUI

@main
struct CalendarrWatchApp: App {
    @State private var model = WatchSnapshotModel()

    init() {
        // The session has to be live before the first payload arrives, and a
        // complication push can wake this app with no UI on screen at all.
        WatchSnapshotReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchAgendaView()
                .environment(model)
        }
    }
}
```

- [ ] **Step 5: Commit (the build is verified in Task 12, once the views exist)**

```bash
git add CalendarrWatch
git commit -m "Receive the phone's snapshot on the watch and store it locally"
```

---

## Task 11: Watch read model and status states

**Files:**
- Create: `CalendarrWatch/WatchSnapshotModel.swift`
- Create: `CalendarrWatch/Views/WatchStatusView.swift`

- [ ] **Step 1: Write the read model**

Create `CalendarrWatch/WatchSnapshotModel.swift`:

```swift
import Foundation
import WidgetKit
import CalendarrCore

/// What the watch views read. Holds the last received snapshot, the calendar
/// list, and this watch's filter.
@MainActor
@Observable
final class WatchSnapshotModel {
    private(set) var result: SnapshotReadResult = .neverWritten
    private(set) var calendars: [SnapshotCalendar] = []
    private(set) var hiddenKeys: Set<String> = WatchFilterStore.load()

    private let store = SnapshotStore()
    private var changeToken: SnapshotChangeNotifier.ObservationToken?

    init() {
        reload()
        // The receiver writes through SnapshotStore, which broadcasts. Listening
        // here means the UI does not have to be notified separately.
        changeToken = SnapshotChangeNotifier.observe { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        result = store.read()
        calendars = store.readCalendars()
    }

    /// The snapshot with this watch's filter applied, or nil when there is
    /// nothing usable to show.
    var visible: CalendarrSnapshot? {
        result.snapshot?.filtered(excludingCalendarKeys: hiddenKeys)
    }

    var language: String { result.snapshot?.language ?? "system" }

    func isHidden(_ key: String) -> Bool { hiddenKeys.contains(key) }

    /// The display name for an event's calendar. Events carry only a
    /// `calendarKey`; the names travel separately, in the calendar list.
    func calendarName(for key: String) -> String? {
        calendars.first { $0.id == key }?.name
    }

    func setHidden(_ key: String, _ hidden: Bool) {
        if hidden { hiddenKeys.insert(key) } else { hiddenKeys.remove(key) }
        WatchFilterStore.save(hiddenKeys)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 2: Write the status view**

Create `CalendarrWatch/Views/WatchStatusView.swift`:

```swift
import SwiftUI
import CalendarrCore

/// Every reason there is nothing to show, named. "Never received", "signed out"
/// and "genuinely empty" call for different sentences, and showing the wrong one
/// sends the user looking in the wrong place.
struct WatchStatusView: View {
    let result: SnapshotReadResult
    let language: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch result {
        case .ok:            return "calendar"
        case .loggedOut:     return "person.crop.circle.badge.xmark"
        case .neverWritten:  return "iphone.and.arrow.forward"
        case .incompatible:  return "arrow.down.circle"
        case .unreadable:    return "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch result {
        case .ok:
            return WatchL10n.t("watch.no_events", language)
        case .loggedOut:
            return WatchL10n.t("watch.sign_in", language)
        case .neverWritten:
            return WatchL10n.t("watch.waiting", language)
        case .incompatible:
            return WatchL10n.t("watch.update", language)
        case .unreadable:
            return WatchL10n.t("watch.unreadable", language)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add CalendarrWatch/WatchSnapshotModel.swift CalendarrWatch/Views/WatchStatusView.swift
git commit -m "Add the watch read model and its named empty states"
```

---

## Task 12: Agenda list

**Files:**
- Create: `CalendarrWatch/Views/WatchEventRow.swift`
- Create: `CalendarrWatch/Views/WatchAgendaView.swift`

- [ ] **Step 1: Write the event row**

Create `CalendarrWatch/Views/WatchEventRow.swift`:

```swift
import SwiftUI
import CalendarrCore

/// One event: a colour bar for the calendar, the time range, the title.
struct WatchEventRow: View {
    let event: SnapshotEvent
    let language: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(watchHex: event.colorHex))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(WatchEventFormat.timeRange(event, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 14))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Color {
    /// Local copy of the hex initialiser: `CalendarrCore` is Foundation-only by
    /// design, so colour parsing cannot live there.
    init(watchHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else { self = .gray; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

enum WatchEventFormat {
    static func timeRange(_ event: SnapshotEvent, language: String) -> String {
        if event.isAllDay { return WatchL10n.t("watch.allday", language) }
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.start)
        guard event.end > event.start else { return start }
        return "\(start) – \(formatter.string(from: event.end))"
    }

    static func time(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "Heute", "Morgen", else "Do 11. Sep".
    static func dayHeader(_ day: Date, language: String,
                          calendar: Calendar, now: Date = Date()) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return WatchL10n.t("watch.today", language)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return WatchL10n.t("watch.tomorrow", language)
        }
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: day)
    }
}
```

- [ ] **Step 2: Write the agenda**

Create `CalendarrWatch/Views/WatchAgendaView.swift`:

```swift
import SwiftUI
import CalendarrCore

/// The whole app: a scrolling agenda grouped by day, plus a way to reach the
/// calendar filter. Read-only by design — the snapshot carries neither
/// recurrence rules nor permissions, so it is deliberately not enough to edit.
///
/// Deliberately does **not** apply `snapshot.theme` to the background. The
/// always-on display and OLED make black the right choice here; the theme only
/// contributes the per-event accent colours.
struct WatchAgendaView: View {
    @Environment(WatchSnapshotModel.self) private var model
    @State private var showingFilter = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = WatchL10n.locale(model.language)
        return calendar
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(WatchL10n.t("watch.title", model.language))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFilter = true } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(WatchL10n.t("watch.calendars", model.language))
                    }
                }
                .sheet(isPresented: $showingFilter) { WatchCalendarFilterView() }
        }
        .onAppear { WatchSnapshotReceiver.shared.requestRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.visible, !groups(in: snapshot).isEmpty {
            List {
                ForEach(groups(in: snapshot), id: \.day) { group in
                    Section(WatchEventFormat.dayHeader(group.day, language: model.language,
                                                       calendar: calendar)) {
                        ForEach(group.events) { event in
                            NavigationLink {
                                WatchEventDetailView(event: event,
                                                     calendarName: model.calendarName(for: event.calendarKey),
                                                     language: model.language)
                            } label: {
                                WatchEventRow(event: event, language: model.language)
                            }
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(WatchL10n.t("watch.as_of", model.language)) \(WatchEventFormat.time(snapshot.writtenAt, language: model.language))")
                        // Beyond the coverage window the snapshot carries no
                        // information, which is not the same as "nothing
                        // scheduled". Saying so is what keeps the empty tail of
                        // the list from reading as a free afternoon.
                        Text(WatchL10n.t("watch.no_information", model.language)
                             + " \u{2192} " + coverageEndLine(snapshot))
                        if let error = WatchSnapshotReceiver.shared.lastError {
                            Text(error).foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.carousel)
        } else {
            WatchStatusView(result: model.result, language: model.language)
        }
    }

    private struct DayGroup {
        let day: Date
        let events: [SnapshotEvent]
    }

    /// The last day the snapshot can speak for, formatted for the footer.
    private func coverageEndLine(_ snapshot: CalendarrSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(model.language)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        let lastCovered = calendar.date(byAdding: .day, value: -1, to: snapshot.coverageEnd)
        return formatter.string(from: lastCovered ?? snapshot.coverageEnd)
    }

    /// Group the covered window by day. Days the snapshot cannot speak for are
    /// simply absent — never rendered as "nothing scheduled", which would look
    /// correct and be false.
    private func groups(in snapshot: CalendarrSnapshot) -> [DayGroup] {
        let calendar = self.calendar
        let from = max(snapshot.coverageStart, calendar.startOfDay(for: Date()))
        var buckets: [Date: [SnapshotEvent]] = [:]

        for event in snapshot.events where event.end > from {
            var day = calendar.startOfDay(for: max(event.start, from))
            // A multi-day event appears on each day it covers.
            while day < event.end && day < snapshot.coverageEnd {
                buckets[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return buckets
            .map { DayGroup(day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add CalendarrWatch/Views/WatchEventRow.swift CalendarrWatch/Views/WatchAgendaView.swift
git commit -m "Add the watch agenda list"
```

---

## Task 13: Event detail

**Files:**
- Create: `CalendarrWatch/Views/WatchEventDetailView.swift`

- [ ] **Step 1: Write the detail view**

Create `CalendarrWatch/Views/WatchEventDetailView.swift`:

```swift
import SwiftUI
import CalendarrCore

/// Everything the snapshot carries about one event, which is deliberately not
/// everything the server knows: notes, recurrence and permissions are dropped
/// on the way out, so there is nothing here to edit.
struct WatchEventDetailView: View {
    let event: SnapshotEvent
    /// Nil when the calendar list has not arrived yet, which is possible right
    /// after a first install.
    let calendarName: String?
    let language: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color(watchHex: event.colorHex))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Text(event.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label(WatchEventFormat.timeRange(event, language: language),
                      systemImage: "clock")
                    .font(.footnote)

                Label(dateLine, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let calendarName {
                    Label(calendarName, systemImage: "list.bullet.rectangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: event.start)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add CalendarrWatch/Views/WatchEventDetailView.swift
git commit -m "Add the read-only event detail on the watch"
```

---

## Task 14: Calendar filter

The rows are `Button`s with an SF Symbol checkbox, deliberately not watchOS `Toggle`s: a switch reads as a state indicator you wait on rather than a control you tap.

**Files:**
- Create: `CalendarrWatch/Views/WatchCalendarFilterView.swift`

- [ ] **Step 1: Write the filter view**

Create `CalendarrWatch/Views/WatchCalendarFilterView.swift`:

```swift
import SwiftUI
import CalendarrCore

/// Narrows what this watch shows, on top of what the phone already filtered.
/// One toggle here affects the agenda and every complication at once.
struct WatchCalendarFilterView: View {
    @Environment(WatchSnapshotModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.calendars.isEmpty {
                    Text(WatchL10n.t("watch.waiting", model.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.calendars) { calendar in
                        row(calendar)
                    }
                }
            }
            .navigationTitle(WatchL10n.t("watch.calendars", model.language))
        }
    }

    private func row(_ calendar: SnapshotCalendar) -> some View {
        let shown = !model.isHidden(calendar.id)
        return Button {
            model.setHidden(calendar.id, shown)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shown ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(shown ? Color.accentColor : Color.secondary)
                Circle()
                    .fill(Color(watchHex: calendar.colorHex))
                    .frame(width: 7, height: 7)
                Text(calendar.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(shown ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: Build the watch app**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add CalendarrWatch/Views/WatchCalendarFilterView.swift
git commit -m "Add the watch calendar filter with tappable checkbox rows"
git push origin main
```

---
## Task 15: Complication data plumbing

**Files:**
- Create: `CalendarrWatchComplications/WatchComplicationSupport.swift`
- Create: `CalendarrWatchComplications/WatchCalendarSelectionIntent.swift`
- Create: `CalendarrWatchComplications/WatchComplicationProvider.swift`

- [ ] **Step 1: Write the shared helpers**

Create `CalendarrWatchComplications/WatchComplicationSupport.swift`:

```swift
import SwiftUI
import CalendarrCore

enum WatchComplicationSupport {
    /// The first event that has not ended yet — including one running now,
    /// which is what "what is next" means when you are already in a meeting.
    /// Matches `WatchPushPolicy.nextEventIdentity`, deliberately.
    static func nextEvent(in snapshot: CalendarrSnapshot?, at now: Date) -> SnapshotEvent? {
        snapshot?.events.filter { $0.end > now }.min { $0.start < $1.start }
    }

    static func upcoming(in snapshot: CalendarrSnapshot?, at now: Date, limit: Int) -> [SnapshotEvent] {
        guard let snapshot else { return [] }
        return Array(snapshot.events.filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(limit))
    }

    static func todayCount(in snapshot: CalendarrSnapshot?, at now: Date,
                           calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        guard let snapshot else { return 0 }
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        return snapshot.events.filter { $0.start < dayEnd && $0.end > dayStart }.count
    }

    /// What a countdown counts to: the start if it has not begun, otherwise the
    /// end. Counting up from a start time that has passed reads as broken.
    static func countdownTarget(_ event: SnapshotEvent, at now: Date) -> Date {
        event.start > now ? event.start : event.end
    }

    /// How full a draining ring should be, over a two-hour lead window.
    static func gaugeFraction(to target: Date, at now: Date) -> Double {
        let window: TimeInterval = 2 * 3600
        return min(1, max(0, target.timeIntervalSince(now) / window))
    }

    static func time(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func monthAbbreviation(_ date: Date, language: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(language)
        formatter.dateFormat = "LLL"
        return formatter.string(from: date).uppercased()
    }

    /// The curved bezel label for a corner complication: time plus title, or a
    /// plain "no events".
    static func cornerLabel(_ event: SnapshotEvent?, at now: Date, language: String) -> String {
        guard let event else { return WatchL10n.t("watch.no_events", language) }
        if event.isAllDay { return event.title }
        return "\(time(event.start, language: language)) \(event.title)"
    }
}
```

- [ ] **Step 2: Write the configuration intent**

Create `CalendarrWatchComplications/WatchCalendarSelectionIntent.swift`:

```swift
import AppIntents
import WidgetKit
import CalendarrCore

/// One calendar option in a complication's configuration.
struct WatchCalendarEntity: AppEntity, Identifiable {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kalender"
    static var defaultQuery = WatchCalendarEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

/// Reads the calendars from this watch's App Group container, so configuration
/// needs no network call and no phone.
struct WatchCalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WatchCalendarEntity] {
        let wanted = Set(identifiers)
        return SnapshotStore().readCalendars()
            .filter { wanted.contains($0.id) }
            .map { WatchCalendarEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [WatchCalendarEntity] {
        SnapshotStore().readCalendars().map { WatchCalendarEntity(id: $0.id, name: $0.name) }
    }
}

/// Per-complication override of the calendar selection. The in-app toggles are
/// the primary path — intent configuration on a watch face is awkward to
/// operate — so an empty selection means "whatever the app is set to".
struct WatchCalendarSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kalender auswählen"
    static var description = IntentDescription("Leer = die Auswahl aus der Watch-App.")

    // Must be optional: WidgetConfigurationIntent requires optional parameter
    // types, and the watchOS SDK enforces it where iOS lets a bare array pass.
    @Parameter(title: "Kalender")
    var selectedCalendars: [WatchCalendarEntity]?
}
```

- [ ] **Step 3: Write the timeline provider**

Create `CalendarrWatchComplications/WatchComplicationProvider.swift`:

```swift
import WidgetKit
import AppIntents
import CalendarrCore

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarrSnapshot?

    var language: String { snapshot?.language ?? "system" }
}

/// Builds every Calendarr complication's timeline.
///
/// Entries land on event boundaries rather than on a fixed schedule, so the
/// complication flips in the exact minute the next appointment changes without
/// a network call and without spending refresh budget. New *data* arrives by
/// push from the phone, which is why the refresh policy is `.atEnd`: when the
/// timeline simply runs out, regenerating from the same snapshot is cheap and
/// correct.
struct WatchComplicationProvider: AppIntentTimelineProvider {
    typealias Entry = WatchComplicationEntry
    typealias Intent = WatchCalendarSelectionIntent

    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: nil)
    }

    func snapshot(for configuration: WatchCalendarSelectionIntent,
                  in context: Context) async -> WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: resolved(configuration))
    }

    func timeline(for configuration: WatchCalendarSelectionIntent,
                  in context: Context) async -> Timeline<WatchComplicationEntry> {
        let snapshot = resolved(configuration)
        let now = Date()
        let dates = snapshot.map { ComplicationTimeline.entryDates(from: now, in: $0) } ?? [now]
        return Timeline(entries: dates.map { WatchComplicationEntry(date: $0, snapshot: snapshot) },
                        policy: .atEnd)
    }

    /// The app-level filter applies first; a per-complication selection narrows
    /// further. An empty selection means "whatever the app is set to".
    private func resolved(_ configuration: WatchCalendarSelectionIntent) -> CalendarrSnapshot? {
        guard case .ok(let snapshot) = SnapshotStore().read() else { return nil }
        return snapshot
            .filtered(excludingCalendarKeys: WatchFilterStore.load())
            .filtered(toCalendarKeys: Set((configuration.selectedCalendars ?? []).map(\.id)))
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add CalendarrWatchComplications
git commit -m "Add complication data plumbing and event-boundary timelines"
```

---

## Task 16: The eight complications

watchOS tints complications monochrome with the watch face's colour, so per-calendar colours are unavailable here and exactly one element per complication is marked `widgetAccentable()`.

**Files:**
- Create: `CalendarrWatchComplications/CornerComplicationViews.swift`
- Create: `CalendarrWatchComplications/RectangularComplicationViews.swift`
- Create: `CalendarrWatchComplications/SmallComplicationViews.swift`
- Create: `CalendarrWatchComplications/CalendarrWatchComplications.swift`

- [ ] **Step 1: Write the corner views**

Create `CalendarrWatchComplications/CornerComplicationViews.swift`:

```swift
import SwiftUI
import WidgetKit
import CalendarrCore

/// A corner holds **one** value plus the curved bezel label. A second inner
/// line runs into the curved text — do not add one. `.widgetLabel` is what
/// makes WidgetKit lay the text along the edge; there is no arc to draw by hand.

/// Value: live countdown. Label: time and title.
struct CornerCountdownComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        Group {
            if let next {
                Text(WatchComplicationSupport.countdownTarget(next, at: entry.date), style: .timer)
                    .widgetAccentable()
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            Text(WatchComplicationSupport.cornerLabel(next, at: entry.date, language: entry.language))
        }
    }
}

/// Value: the appointment's clock time. Label: the title.
struct CornerTimeComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        Group {
            if let next {
                Text(next.isAllDay
                     ? WatchL10n.t("watch.allday", entry.language)
                     : WatchComplicationSupport.time(next.start, language: entry.language))
                    .widgetAccentable()
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            Text(next?.title ?? WatchL10n.t("watch.no_events", entry.language))
        }
    }
}
```

- [ ] **Step 2: Write the rectangular views**

Create `CalendarrWatchComplications/RectangularComplicationViews.swift`:

```swift
import SwiftUI
import WidgetKit
import CalendarrCore

/// Time, title, location. The variant that answers the actual question.
struct NextEventComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        switch family {
        case .accessoryInline:
            inline(next)
        default:
            rectangular(next)
        }
    }

    @ViewBuilder
    private func rectangular(_ next: SnapshotEvent?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next {
                Text(next.isAllDay
                     ? WatchL10n.t("watch.allday", entry.language)
                     : WatchComplicationSupport.time(next.start, language: entry.language))
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text(next.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                if !next.location.isEmpty {
                    Text(next.location)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "calendar").font(.system(size: 13)).widgetAccentable()
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func inline(_ next: SnapshotEvent?) -> some View {
        let text: String = {
            guard let next else { return WatchL10n.t("watch.no_events", entry.language) }
            if next.isAllDay { return next.title }
            return "\(WatchComplicationSupport.time(next.start, language: entry.language)) \(next.title)"
        }()
        return Label(text, systemImage: "calendar")
    }
}

/// The next two, so back-to-back appointments are visible at once.
struct NextTwoComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let events = WatchComplicationSupport.upcoming(in: entry.snapshot, at: entry.date, limit: 2)
        VStack(alignment: .leading, spacing: 3) {
            if events.isEmpty {
                Image(systemName: "calendar").font(.system(size: 13)).widgetAccentable()
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 13))
            } else {
                ForEach(events) { event in
                    HStack(spacing: 5) {
                        Text(event.isAllDay
                             ? WatchL10n.t("watch.allday", entry.language)
                             : WatchComplicationSupport.time(event.start, language: entry.language))
                            .font(.system(size: 12, weight: .semibold))
                            .widgetAccentable()
                        Text(event.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Weekday and date plus the next appointment, so one slot does both jobs.
struct DatePlusEventComplicationView: View {
    let entry: WatchComplicationEntry

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        VStack(alignment: .leading, spacing: 2) {
            Text(dateLine)
                .font(.system(size: 11, weight: .semibold))
                .widgetAccentable()
            if let next {
                Text(next.isAllDay
                     ? next.title
                     : "\(WatchComplicationSupport.time(next.start, language: entry.language)) \(next.title)")
                    .font(.system(size: 14))
                    .lineLimit(1)
            } else {
                Text(WatchL10n.t("watch.no_events", entry.language)).font(.system(size: 14))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = WatchL10n.locale(entry.language)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMMM")
        return formatter.string(from: entry.date).uppercased()
    }
}
```

- [ ] **Step 3: Write the circular and inline views**

Create `CalendarrWatchComplications/SmallComplicationViews.swift`:

```swift
import SwiftUI
import WidgetKit
import CalendarrCore

/// A draining ring plus the remaining time.
struct CountdownComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = WatchComplicationSupport.nextEvent(in: entry.snapshot, at: entry.date)
        switch family {
        case .accessoryInline:
            inline(next)
        default:
            circular(next)
        }
    }

    @ViewBuilder
    private func circular(_ next: SnapshotEvent?) -> some View {
        if let next {
            let target = WatchComplicationSupport.countdownTarget(next, at: entry.date)
            Gauge(value: WatchComplicationSupport.gaugeFraction(to: target, at: entry.date)) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text(target, style: .timer)
                    .font(.system(size: 12))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "calendar").font(.system(size: 18))
            }
        }
    }

    private func inline(_ next: SnapshotEvent?) -> some View {
        guard let next else {
            return Label(WatchL10n.t("watch.no_events", entry.language), systemImage: "calendar")
        }
        let target = WatchComplicationSupport.countdownTarget(next, at: entry.date)
        return Label {
            Text(target, style: .timer)
        } icon: {
            Image(systemName: "timer")
        }
    }
}

/// Day number and month. No appointment information — a date replacement.
struct DateComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var day: Int {
        Calendar(identifier: .gregorian).component(.day, from: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(WatchComplicationSupport.monthAbbreviation(entry.date, language: entry.language)
                  + " \(day)", systemImage: "calendar")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(day)")
                        .font(.system(size: 22, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(WatchComplicationSupport.monthAbbreviation(entry.date, language: entry.language))
                        .font(.system(size: 8, weight: .semibold))
                }
            }
        }
    }
}

/// How many appointments today. Says "busy", not "what".
struct TodayCountComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int {
        WatchComplicationSupport.todayCount(in: entry.snapshot, at: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(count) \(WatchL10n.t("watch.events_today", entry.language))",
                  systemImage: "calendar")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold))
                        .widgetAccentable()
                    Text(WatchL10n.t("watch.events_today", entry.language).uppercased())
                        .font(.system(size: 7, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Write the widget bundle**

Create `CalendarrWatchComplications/CalendarrWatchComplications.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct CalendarrWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        WatchNextEventWidget()
        WatchCornerCountdownWidget()
        WatchCornerTimeWidget()
        WatchCountdownWidget()
        WatchDateWidget()
        WatchTodayCountWidget()
        WatchNextTwoWidget()
        WatchDatePlusEventWidget()
    }
}

private extension View {
    /// Accessory families paint their own background; ours must stay out of
    /// the way so the watch face's tint comes through.
    func complicationChrome(_ language: String) -> some View {
        containerBackground(for: .widget) { Color.clear }
            .environment(\.locale, WatchL10n.locale(language))
    }
}

struct WatchNextEventWidget: Widget {
    let kind = "WatchNextEvent"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            NextEventComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Nächster Termin")
        .description("Zeit, Titel und Ort des nächsten Termins.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct WatchCornerCountdownWidget: Widget {
    let kind = "WatchCornerCountdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CornerCountdownComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Restzeit (Ecke)")
        .description("Restzeit bis zum nächsten Termin, Name am Rand.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct WatchCornerTimeWidget: Widget {
    let kind = "WatchCornerTime"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CornerTimeComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Uhrzeit (Ecke)")
        .description("Uhrzeit des nächsten Termins, Name am Rand.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct WatchCountdownWidget: Widget {
    let kind = "WatchCountdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            CountdownComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Countdown")
        .description("Ring, der bis zum nächsten Termin leerläuft.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchDateWidget: Widget {
    let kind = "WatchDate"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            DateComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Datum")
        .description("Tag und Monat.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchTodayCountWidget: Widget {
    let kind = "WatchTodayCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            TodayCountComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Termine heute")
        .description("Anzahl der heutigen Termine.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WatchNextTwoWidget: Widget {
    let kind = "WatchNextTwo"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            NextTwoComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Die nächsten zwei")
        .description("Die beiden nächsten Termine.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WatchDatePlusEventWidget: Widget {
    let kind = "WatchDatePlusEvent"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchCalendarSelectionIntent.self,
                               provider: WatchComplicationProvider()) { entry in
            DatePlusEventComplicationView(entry: entry).complicationChrome(entry.language)
        }
        .configurationDisplayName("Datum + Termin")
        .description("Datum und nächster Termin in einem Slot.")
        .supportedFamilies([.accessoryRectangular])
    }
}
```

- [ ] **Step 5: Build the complications target**

```bash
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` — the scheme builds the embedded extension too.

- [ ] **Step 6: Commit**

```bash
git add CalendarrWatchComplications
git commit -m "Add the eight watch-face complications"
git push origin main
```

---

## Task 17: Whole-stack verification and handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-apple-watch-app-design.md` (status line)

- [ ] **Step 1: Run the package test suite**

```bash
cd ../CalendarrKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: build succeeds against the native macOS SDK, every test passes.

- [ ] **Step 2: Build every app target**

```bash
cd "../Calendarr iOS"
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Calendarr iOS.xcodeproj" -scheme "Calendarr iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm the package stayed Foundation-only**

```bash
cd ../CalendarrKit
grep -rn "import SwiftUI\|import UIKit\|import AppKit\|import WidgetKit\|import WatchConnectivity" Sources/ || echo "clean"
```

Expected: `clean`. A UIKit import here would compile for Catalyst and break the native macOS consumer.

- [ ] **Step 4: Mark the spec implemented**

In `docs/superpowers/specs/2026-09-11-apple-watch-app-design.md`, change the status line to:

```markdown
Status: implemented — pending on-device verification
```

- [ ] **Step 5: Commit**

```bash
cd "../Calendarr iOS"
git add docs/superpowers/specs/2026-09-11-apple-watch-app-design.md
git commit -m "Mark the watch app spec implemented"
git push origin main
```

- [ ] **Step 6: Hand back with the open items named**

Report these explicitly; none of them can be closed on this machine:

1. **Xcode with watchOS 27 support** must be installed before anything can be installed on the watch. Xcode 26.6 ships the watchOS 26.5 SDK; the device runs watchOS 27 beta.
2. **Developer portal**: both new bundle IDs need the App Groups capability enabled for `group.com.scarriffleservices.calendarr`, or every read on the watch silently returns nothing.
3. **On-device verification** belongs to the user: complication layout on the round face, the curved corner label, whether the agenda's day grouping reads well, and whether a payload actually arrives when the watch app is closed.
4. **App Store Connect**: watch screenshots are required for the version that ships this. The watch app is a new target in the existing app record, not a new app.
5. `CalendarrKit` has **no git remote** — its commits are local only. If the watch app is ever built on another machine, that repo needs a remote first.
