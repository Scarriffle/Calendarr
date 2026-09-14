# Design contract (Web / iOS / Android)

> For the user-configurable **colours**, see [../THEME.md](../THEME.md). Colours come from
> the server and are already consistent across clients — this document covers everything
> below the colour level, which is not.

The three clients should read as one product. That means the same structure and the same
measurements, **not** the same pixels: each app keeps its platform's navigation, system font
and controls. A Material button on iOS would feel wrong, and a swipe-back gesture on Android
would feel broken.

This document is the reference the clients are checked against. When a value here and a value
in the code disagree, the code is wrong.

---

## Why this exists

Nothing below the colour level was ever decided once. Counted across the clients today:

| | Web | Android | iOS |
|---|---|---|---|
| Distinct spacing values | 8 | **40** | not audited |
| Distinct font sizes | 8 | **9** | system styles |
| Distinct corner radii | 8 | **9** | mixed |
| Screen gutters | — | **4** (12/16/20/28) | — |

The result is that the left text edge visibly jumps between screens, the same event pill has
four different radii, and nine list rows were each built separately with five different
paddings. That is what makes an app look hand-made.

---

## Spacing

A four-step ladder. Every margin, padding and gap is one of these — no other value is allowed
without a comment saying why.

| Token | Value | Use |
|---|---|---|
| `xs` | 4 | Inside a control; gap between an icon and its label |
| `sm` | 8 | Between related items in a list; vertical padding of a compact row |
| `md` | 12 | Vertical padding of a standard row |
| `lg` | **16** | **Screen gutter**, section spacing, dialog padding |
| `xl` | 24 | Between major sections |
| `xxl` | 32 | Above a primary action, around empty states |

**One screen gutter: `lg` (16).** Every screen, every sheet, every dialog. This is the single
change with the most visible effect — it is what stops the text edge from jumping.

| Platform | How |
|---|---|
| Web | `--space-xs … --space-xxl` in `:root`; existing `6px`/`10px` paddings collapse to `xs`/`sm` |
| Android | `ui/theme/Spacing.kt`, reached as `MaterialTheme.spacing.lg` |
| iOS | `enum Spacing { static let lg: CGFloat = 16 }` in the shared design file |

---

## Corner radii

Defined by role, not by number, so the same object cannot drift apart between views.

| Token | Value | Applies to |
|---|---|---|
| `event` | 4 | Event pills in month, week, day, agenda, all-day strip — **all of them** |
| `field` | 8 | Text fields, list rows, small cards, popovers |
| `sheet` | 20 | Modals, bottom sheets, day preview |
| `full` | pill | Buttons, chips, FAB |

Today the event pill is 3 in month view, 4 in week view, 3 in the all-day strip and 10 in the
agenda on Android; the web uses 3. All become `event`.

---

## Type scale

Six steps. **Nothing below 11.**

| Token | Size | Use | Material | iOS |
|---|---|---|---|---|
| `caption` | 11 | Timestamps, metadata, hints | `labelSmall` | `.caption2` |
| `label` | 12 | Field labels, chips, tab labels | `labelMedium` | `.caption` |
| `body` | 13 | Default reading size | `bodySmall` | `.footnote` |
| `bodyLarge` | 14 | Primary list text, input text | `bodyMedium` | `.subheadline` |
| `title` | 18 | Screen and section titles | `titleMedium` | `.headline` |
| `headline` | 22 | Page headline, month name | `headlineSmall` | `.title2` |

**Android must configure `Typography()`** — today it is the raw Material default
(`ui/theme/Theme.kt:68`), which is why every text size in the app is an ad-hoc `fontSize = N.sp`
override at the call site.

**The one documented exception:** the month grid's overflow counter (`+N`) and week-number
label may use **10**. They sit in a dense grid where 11 does not fit at the current row height.
The 8 and 9 values used today (five places) are removed outright. If the month grid is ever
made height-adaptive, this exception goes away too.

---

## Hit targets

Minimum **48 × 48** for anything tappable, on every platform. A smaller icon is fine; the
touch area around it is not.

The top app bar is **64** tall with 48 targets. Android currently uses 50 with 40 targets,
which is the first thing a user sees and reads as cramped.

Every actionable icon has an accessibility label. Decorative icons — and only those — get
none. Android has 30 `contentDescription = null` today, several of them on buttons
(month back/forward, calendar visibility toggle, remove-reminder, password reveal).

---

## Component inventory

Every client implements these, named the same way, with the same anatomy. If a screen needs
something that is not on this list, it goes on the list first.

### `ListRow`
`[leading icon or colour dot] [title, one line, ellipsised] [optional subtitle] [trailing control]`
Vertical padding `md`, horizontal `lg`, full-width tap area, `field` radius when it sits on a
surface. Android should build this on `ListItem`; today the app has **zero** `Card` and **zero**
`ListItem` — nine separate hand-rolled variants instead.

### `SettingsRow`
A `ListRow` whose trailing control is a switch, a dropdown or a colour swatch. One
implementation, not four.

### `EmptyState`
`[title] [one sentence of body] [optional action]`, centred, `xxl` above. Every list has one.
Today only the agenda does it properly (`AgendaView.kt:49-62`) — copy that.

### `LoadingState`
One spinner, centred, same size everywhere. Never a different shape per screen. The keys
`settings.loading`, `profile.loading` and `accounts.loading` already exist in the translation
tables and are never rendered.

### `Feedback`
**Success and failure appear in one place per platform** — a snackbar on Android, a toast on
web, a transient banner on iOS. Never as loose text in the page flow, and never as the last
item of a scrolling list, where the user who caused the error cannot see it.

---

## States

Every list and every screen defines all four. A missing state is a bug, not an omission.

| State | Rule |
|---|---|
| **Loading** | Shown from the first frame, never a blank screen |
| **Empty** | Title plus one sentence; an action when there is a sensible one |
| **Error** | In the feedback slot above, with what failed and what to do |
| **Partial** | Stale data stays visible. Never replace loaded content with an empty list because one source failed — see `CalendarViewModel.kt:377-416` |

---

## Event rendering

The one object all three clients draw, and the one most likely to drift.

| | Rule |
|---|---|
| Radius | `event` (4) everywhere |
| All-day | Own strip above the time grid, packed into lanes |
| Timed, overlapping | **Side by side, never stacked.** Android's week and day views currently draw every event at full column width, so one of two 10:00 meetings is completely invisible (`TimeGridView.kt:156-169`) |
| Overflow | `+N` when the lane count is exceeded, with a way to see the rest |
| Colour | Per-event colour, else calendar colour; the group view's server-resolved colour wins |
| Title | The server-decorated title (birthday age, group prefix) wins over the raw one |

---

## Widgets

Home-screen widgets are **always native**: iOS requires WidgetKit with SwiftUI views, Android
requires Glance or RemoteViews. No cross-platform framework changes this. What is shared is
the **selection and the content**, defined here once.

| Widget | Shows | iOS | Android |
|---|---|---|---|
| `today` | Today's events | small | 2×2 |
| `upNext` | The next few events | medium | 4×2 |
| `month` | Month grid with event dots | medium | 4×4 |

iOS ships 13 widgets today; these three are the ones Android mirrors. The rest stay
iOS-only — that is fine, as long as the three above look and behave the same.

**Data path, both platforms:** the app writes a snapshot into shared storage; the widget reads
it and performs **no networking of its own**. The snapshot format is defined by `CalendarrCore`
on iOS and is the reference for Android's equivalent.

---

## Wording

The translation keys in `android/…/ui/L10n.kt` and `ios/…/Models/Localization.swift` are
deliberately kept identical — Android even converts `%@` to `%s` so the same table works. That
is a contract: **a key means the same thing on every platform**, and a new key is added to all
of them.

Nothing user-visible is hard-coded. Current violations, all of which show a German string to
an English user:

- `ColorPickerDialog.kt` — `"Abbrechen"`, `"OK"`, `"Hex"`
- `NotificationScheduler.kt` / `.swift` — every notification body
- The nine watch complication names on iOS
- Date patterns built without a `Locale`, and `is24HourView = true` forced

---

## Deliberately not unified

| | Why |
|---|---|
| Navigation | Bottom sheets and a drawer on Android, navigation stack and sheets on iOS |
| System font | Roboto / SF — using one font on both would look wrong on one of them |
| Controls | Switches, pickers, date entry stay platform-native |
| Gestures | Swipe-back on iOS, system back on Android |
| Widget families | Each platform has its own sizes; only the three above must correspond |

---

## How to check

There is no automated check — both apps have **zero tests**. So it is done by eye, and these
are the questions that catch real drift:

1. Open every screen in turn. Does the **left text edge** stay put?
2. Put the two apps side by side on the same screen. Same order, same words, same rows?
3. System font size to maximum. Does anything clip? Do icons grow with their text?
4. Device language to English. Any German left? Trigger a reminder and read it.
5. Two events at the same time, week view. Are **both** visible?
6. Turn the server off and save something. Does the message appear in the feedback slot?
7. Every list: force it empty. Is there an empty state, or just nothing?
