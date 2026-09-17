# Monaka — Project Rules for Claude Code

This document tells Claude Code how to work inside this repo. Read it before making changes.

---

## 1. Overview

**Monaka** 🥮 is an iOS app for keeping the places you want to go on your days off — museum exhibitions, events, shops — and checking them off once you've been.

The name is the Japanese sweet 最中 (*monaka*), read the other way: 最中 (*sanaka*) means "in the middle of". The app exists to catch an exhibition **while its run is still on**. The wafer itself comes from 「水の面に照る月の最中」 (*Shūi Wakashū*) — the round shell was likened to a full moon, which is where the app icon comes from.

This project follows the naming convention of Shakshi3104's other apps: a dessert name tied to the feature (Waffle 🧇 = wafer, Shortcake 🍰 = screenshot, Mille 🥞 = layer, Madeleine 🥧 = a sensory cue that revives a memory).

### What problem it solves

Reminders is not missing a feature — it has the wrong **type** of date. A reminder's date is a **point** ("do it by this day"); an exhibition's date is an **interval** ("you can go during this period"). Enter "until 5/18" in Reminders and the 4/11 opening is unrepresentable. Calendar apps hold intervals but can't be completed, and aren't a place for candidates you haven't committed to.

Monaka owns exactly that gap: **a ToDo that has a run**. Anything that doesn't need an interval belongs in Reminders, not here.

---

## 2. Tech Stack

| Item | Choice |
|---|---|
| UI | SwiftUI with Liquid Glass |
| State | `@Observable` macro (NOT `ObservableObject`) |
| Persistence | SwiftData (single-device, no CloudKit sync) |
| Web metadata | `OGMetadataFetcher` (regex over the first 64 KB of `<head>`), no third-party package |
| Map links | `MapLinkResolver` — follows the `maps.app.goo.gl` redirect and parses the resolved URL |
| Location | CoreLocation (When In Use, requested lazily) + MapKit for the detail snapshot |
| Share Extension | Inserts into the shared store in the App Group container |
| Widget | WidgetKit, data shared via App Group + JSON file (Phase 3) |
| Minimum iOS | **26.0** |
| Bundle ID | `com.shakshi.Monaka` |
| App Group | `group.com.shakshi.Monaka` |
| Xcode | 26.0+ |
| Swift | 6.1+ |
| Accent Color | Azuki `#A9414E` (Dark variant ~`#C85C68`) |

No SPM dependencies. Everything the app needs is in the standard library + SwiftUI + SwiftData.

---

## 3. Data Strategy

- **One model: `Spot`.** There is no separate `Event` / `Place` distinction — a spot with a run is an exhibition, a spot without one is "somewhere I want to go eventually". Keeping them in one model is what lets a single list serve both.
- **A café saved in Google Maps is a spot with no run.** That's the entire difference. It's why §7.1 treats a missing run as a first-class case rather than incomplete data, and why the `Anytime` section exists.
- **The run is two Optionals** (`startDate`, `endDate`), not a required range. See §7 for how the four combinations are interpreted.
- **Coordinates are stored; nothing else about the place is.** `latitude` / `longitude` / `address` / `mapURL`. No Google API key, no Place ID, no cached tiles, no geocoding at import time.
- **Tags are a plain `[String]`** on `Spot`, not a relationship and not a single category — an exhibition can be `Exhibition` + `Ends soon` + `Ueno` at once. Unlike `Feed.category` in yomy, there is no tag entity: the Add form suggests tags already in use so the vocabulary converges without a tag table, and `TagsView` rewrites every spot when one is renamed.
- **A tag's name and icon live in `TagVocabulary`** (`@AppStorage`, JSON), not SwiftData. Without a tag entity there is nowhere else for a zero-spot tag or an SF Symbol to exist, and setting a vocabulary up in advance is worth having. It stays strictly vocabulary: `Spot.tags` remains the only answer to *which* spots carry a tag. A tag typed straight into a spot's form has no entry and falls back to `TagVocabulary.defaultIcon` until one is chosen in Settings.
- **No sync.** Single-device only. The `@Model` still follows the CloudKit constraints in §9 so the option stays open.

```swift
@Model
final class Spot {
    var id: UUID = UUID()
    var title: String = ""          // exhibition / event / shop name
    var venue: String?              // venue or area
    var urlString: String?          // official page
    var mapURL: String?             // Google / Apple Maps link, kept verbatim
    var notes: String?
    var imageURL: String?           // filled from OGP

    // The run. Both nil means "anytime".
    var startDate: Date?
    var endDate: Date?

    var latitude: Double?
    var longitude: Double?
    var address: String?

    var isVisited: Bool = false
    var visitedAt: Date?
    var addedAt: Date = .now
    var tags: [String] = []
}
```

`urlString` and `mapURL` are separate on purpose: a museum has an official page and may have neither coordinates nor a map link; a café from Google Maps has a map link and usually no official page. One field would make "which kind of link is this" a guess based on the host.

---

## 4. Build & Test Commands

Prefer these over opening Xcode. Use them to verify your changes compile.

### Build for simulator

```bash
xcodebuild -scheme Monaka \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build
```

### Clean build

```bash
xcodebuild -scheme Monaka clean
```

### List available simulators

```bash
xcrun simctl list devices available
```

### Screenshot a specific tab

Nothing outside the app can tap the tab bar, so `ContentView` reads a DEBUG-only launch argument to open straight into a tab. Use it to verify a screen you can't reach from the launch state:

```bash
xcrun simctl launch booted com.shakshi.Monaka -tab-map    # or -tab-all
xcrun simctl io booted screenshot /tmp/monaka.png
```

Most screens sit behind a tap nothing outside the app can make. Every DEBUG launch argument that opens one is declared in `DebugLaunchArguments.swift` — add new ones there rather than reaching for `ProcessInfo` inline.

| Argument | Opens |
|---|---|
| `-tab-all` / `-tab-map` | that tab |
| `-add-first` | the Add sheet |
| `-detail-first` | the Today tab's featured spot |
| `-edit-first` | that spot's Edit sheet |
| `-tags-first` | Settings → Tags |
| `-new-tag-first` | Settings → Tags → New Tag |
| `-icon-picker-first` | …→ its icon grid |
| `-seed-samples` | nothing; fills the store first |

`-seed-samples` fills the simulator's store with `Spot.samples`, which carry real Wikimedia images and real coordinates so the header image and map snapshot render. It is additive: a spot already in the store keeps everything it has and only gains the fields it was missing, so nothing you typed in the simulator is overwritten.

```bash
xcrun simctl launch booted com.shakshi.Monaka -seed-samples -edit-first
```

The share extension's form is the one screen none of this reaches — it needs a real share sheet, so changes to `ShareFormView` can only be verified by hand.

If a build fails, read the output carefully and fix the errors before reporting back. Do not stop at the first error — fix as many as you can in one pass.

### Release to TestFlight

Releases go through `asc` (App Store Connect CLI) with the workflows in `.asc/workflow.json` — see `RELEASE.md`. App ID `6813017923`, external group `Monaka Testers`.

```bash
asc workflow run testflight_internal VERSION:1.0
asc workflow run testflight_external VERSION:1.0 GROUP:"Monaka Testers"
```

- **Build numbers are the git commit count**, stamped by the `Set Build Number` Run Script phase on both targets. Never bump `CURRENT_PROJECT_VERSION` by hand, and never re-run a workflow without a new commit — the number collides with the build already uploaded.
- **Never pass `SUBMIT_BETA:false` for an external release.** Every build must go through Beta App Review individually or it stalls at "Ready to Submit".
- `#Preview` bodies compile in Release too. Anything that touches `Spot.samples` / `Spot.previewContainer` must sit inside `#if DEBUG`, or the archive fails where the simulator build passed.

---

## 5. Code Style

- **SwiftUI + `@Observable`**. Never use `ObservableObject` / `@Published`.
- **iOS 26+ only**. Use new APIs freely: `#Preview`, `.glassEffect()`, `GlassEffectContainer`, the latest `Calendar` / `FormatStyle` APIs.
- **async/await everywhere** for networking and the SwiftData writes that follow.
- **`throws` for errors**, not `Result`. Define a nested `enum ...Error: Error` on the type that throws.
- **One screen per file.** A View and its `@Observable` ViewModel can share a file.
- **No force-unwrap** in production code paths. Especially URLs from user-typed strings — guard them.
- **Prefer `struct` and `actor` over `class`.** Use `class` only for `@Model`.

### Naming

- Views end with `View` (e.g. `SpotListView`)
- ViewModels end with `ViewModel`
- Services are nouns (`OGMetadataFetcher`, `SharedStore`)

---

## 6. UI Guidelines

### 6.1 Conventions

- **English UI.** Every user-facing string is English. Data fetched from a venue's page (venue names, exhibition titles in Japanese) stays as-is — that's source data.
- **Dates: `yyyy/MM/dd`, `en_US_POSIX` locale, `Asia/Tokyo` timezone.** Always set **both** `locale` and `timeZone` on a `DateFormatter`. The TZ pin matters when the user is travelling.
- **System colors only.** `.primary` / `.secondary` / `.tertiary` for text, `Color(.systemGroupedBackground)` / `Color(.secondarySystemGroupedBackground)` for surfaces, `Color.accentColor` for the azuki tint. Never hardcode `Color.white` / `Color.black` / `.preferredColorScheme(.dark)`.
- **Three tabs.** `ContentView` is a `TabView`: **Today** (where to go today), **All** (the full §7.2 sectioned list), **Map**. Each tab owns its own `NavigationStack`. Settings is a gear in the nav bar opening a sheet (Madeleine / yomy style).
  - `Today` carries only `This Weekend` / `Ending Soon` / `Open Now`, led by one featured spot. `Upcoming`, `Anytime`, `Visited` and `Ended` live in `All`.
  - The featured spot is **also** listed in the section below it. The card is a highlight, not a removal.
  - **Add lives in the tab bar's detached capsule at the right end** — `role: .prominent` on iOS 27, falling back to `role: .search` on 26. `.search` was the only trailing-separated slot on iOS 26 and Add borrowed it; iOS 27 gave the separation its own role and draws a borrowed `.search` inline with the other tabs, so the role is picked behind an `#available`. It is not a real tab either way: selecting it bounces the selection back and presents the Add sheet. No FAB.
- **Destructive actions in the detail view confirm via `.alert`**, not `.confirmationDialog`. List swipe-to-delete is the deliberate exception and deletes immediately.

### 6.2 Liquid Glass

- Use `.glassEffect()` only for floating controls over content (the FAB area / bottom controls).
- **No nesting.** A `.glassEffect()` inside another breaks visually.
- **No glass on content itself** (images, long text).
- **Valid variants**: `.regular`, `.clear`, `.identity`. `.prominent` does NOT exist — do not hallucinate it.
- **Don't override sheet backgrounds.** No `.presentationBackground(.clear)`.

### 6.3 List rows

`[thumbnail] [title (lineLimit 1) + venue · run] [trailing tag]`. The trailing tag is the countdown (`12 days left`), tinted `.accentColor` while open, `.orange` when ending soon, `.green` when visited. Title is struck through and `.secondary` once visited.

---

## 7. The run, and how the list is sectioned

This is the core domain logic. Get it wrong and the app is just a worse Reminders.

### 7.1 Interpreting `startDate` / `endDate`

| `startDate` | `endDate` | Meaning |
|---|---|---|
| set | set | a normal run (`2026/04/11 – 06/21`) |
| nil | set | "until 6/21" |
| set | nil | "from 10/03", open-ended |
| nil | nil | **Anytime** — no run, always available |

These interpretations live as computed properties in `Spot+Period.swift`, **not** in `Spot.swift`. `Spot.swift` stays a bare `@Model` of plain value types so it can be compiled into the share extension target unchanged (same split as `TrackedParcel` / `TrackedParcel+Tracking` in LangueDeChat).

### 7.2 Sections

Evaluated top to bottom; a spot lands in the **first** section it matches and appears only there.

`isVisited` is checked **before** every dated section: once a spot is checked off it leaves the active list, whatever its run says. That's also what `Ended`'s "never visited" condition implies.

| Section | Condition | Sort |
|---|---|---|
| This Weekend | the upcoming weekend intersects the run — see `Spot.WeekendRule` below (no-run spots excluded) | `endDate` ascending |
| Ending Soon | currently open and `endDate` within 14 days | `endDate` ascending |
| Open Now | currently open, everything else | `endDate` ascending |
| Upcoming | `startDate` is in the future | `startDate` ascending |
| Anytime | no run | `addedAt` descending |
| Visited | `isVisited == true` | `visitedAt` descending |
| Ended | the run is over and it was never visited | `endDate` descending |

`Ended` is the "missed it" bucket — make it hideable from Settings.

**`Spot.WeekendRule` — "This Weekend" means two different things.** Exhibition runs are months long, so a plain intersection test puts nearly every open spot in `This Weekend` and leaves `Ending Soon` and `Open Now` empty. The rule is therefore per-screen:

| Screen | Rule | Meaning |
|---|---|---|
| Today tab | `.intersecting` | anything whose run covers the upcoming weekend — the whole point of that tab |
| All tab | `.lastChance` | it is the run's **last** weekend, or the weekend the run **opens** on |

The upcoming weekend is the one we're currently inside if today is Sat/Sun, otherwise the next one (`Calendar.upcomingWeekend(from:)`).

**"Last weekend" is not "ends by Sunday".** A run closing on the following Tuesday still makes this weekend the last one you can go on a day off, and days off are when people actually go. So test that the *following* weekend no longer intersects the run — never compare `endDate` against the weekend's end.

### 7.3 Anytime is the big one

Once Google Maps places are imported, `Anytime` will hold an order of magnitude more rows than every dated section combined, and a naive list buries the exhibitions — the thing the app exists for — under a hundred cafés. Two rules keep that from happening:

- **Collapse it.** Above 8 items the `Anytime` section renders as a header row with a count and a disclosure. Expanded state is `@AppStorage`, not SwiftData.
- **Sort by distance when that's possible.** This is what makes the imported places actually useful — "I'm here, what did I want to try nearby" is how that list gets read, and it is never read by date.

### Distance sort

A single **Sort by Distance** toggle in Settings (`@AppStorage("sortsByDistance")`), off by default.

It reorders **within** each section, never across them — `Anytime` is where it matters most, but a nearby exhibition beats a far one in `Open Now` too, and the sections themselves still mean "how much run is left", which distance can't replace. Spots with no coordinate keep to the back of their section in their existing order. With the toggle off, or with no fix yet, every section falls back to its §7.2 order.

While it's on, a row shows the distance under the countdown — both, since one says how long you've got and the other how far it is.

**Request location only when the user turns that toggle on.** Never at launch, never on first import, never on opening the Map tab. `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` explains it in those terms. The app is fully usable with location denied — `LocationProvider.access` becomes `.denied`, Settings says so, and the lists keep their usual order.

---

## 8. Getting spots in

Typing a spot by hand is the fallback, not the path. Three capture routes, all landing on the same `SpotDraft` struct which the Add form is prefilled from and which the user can always correct before saving.

### 8.1 The dispatcher

The share extension and the in-app URL field both hand their input to `ShareInputResolver`, which branches on the URL's host:

| Input | Handler | Fills |
|---|---|---|
| `maps.app.goo.gl`, `goo.gl/maps`, `google.com/maps`, `maps.google.*` | `MapLinkResolver` | `title`, `latitude`, `longitude`, `mapURL` |
| `maps.apple.com` | `MapLinkResolver` | `title` (`q=`), `latitude`, `longitude` (`ll=`), `mapURL` |
| any other URL | `OGMetadataFetcher` | `title`, `imageURL`, `venue` (`og:site_name`), `urlString` |
| plain text | — | `title` |

A resolver that fails fills nothing and is not an error (§13). The form opens either way.

**Every spot gets a location at add time — in the app.** The dispatcher only produces coordinates for map links, so the Add form carries a location picker (`LocationPickerView`, `MKLocalSearch`) and it is part of the normal add flow, not an afterthought — an exhibition shared from a museum's own page would otherwise never reach the Map tab. Seed the search field with whatever `venue` the OGP fetch produced. User-initiated only: this is not the bulk geocoding §3 rules out.

**The share extension is the exception.** A share should be two taps, so `ShareFormView` has no map picker and only requires a title; it says so in the form. A spot captured that way can arrive without coordinates and gets pinned later in the app.

### 8.2 Google Maps links

A share from the Google Maps app gives a short `https://maps.app.goo.gl/…` link, sometimes with the place name as a separate text item. `MapLinkResolver` follows the redirect with a `HEAD`-then-`GET` `URLSession` request and reads the resolved URL, which has the shape:

```
https://www.google.com/maps/place/<name>/@<lat>,<lng>,17z/data=…!3d<lat>!4d<lng>…
```

Take the name from the `/place/` path segment (percent-decoded, `+` → space) and the coordinates from `!3d` / `!4d` when present, falling back to the `/@lat,lng` centre. Store the **resolved** URL in `mapURL`, not the short link — short links are opaque and can expire.

**This is not a public API.** The redirect behaviour and the path shape can change without notice, so the parser is a convenience and never load-bearing: on any mismatch, leave the fields empty, keep the URL, and let the user type the name. Never throw, never alert.

Opening a spot's `mapURL` from the detail view just opens the URL — Google Maps claims it as a universal link when installed, Safari handles it when not. No `LSApplicationQueriesSchemes`, no `comgooglemaps://`.

### 8.3 Bulk import from Google Takeout

For the existing backlog, one-at-a-time sharing is too slow. Google Takeout exports each Maps saved list as a CSV (`Title`, `Note`, `URL` — verify against a real export before writing the parser; Google has changed this before). `SavedPlacesImporter`:

1. `.fileImporter` in Settings → Import, accepting `UTType.commaSeparatedText`.
2. Parse rows into `Spot`s with no run, `notes` from `Note`, `mapURL` from `URL`, `category` defaulted to the list's filename.
3. Show a **preview list with per-row toggles** before inserting anything. An import that silently adds 200 rows is not undoable.
4. Resolve coordinates **afterwards, in the background**, at most 3 concurrent and skippable. Never block the import on it, and never resolve hundreds of short links in a burst — that reads as abuse and gets rate-limited.

A row whose coordinates never resolve is still a perfectly good spot. Title alone is enough.

---

## 9. SwiftData + CloudKit Rules

CloudKit sync is not enabled, but the `@Model` follows the three constraints below so it stays possible. Treat all three as mandatory.

### 9.1 Every property must have a default value or be Optional

```swift
// GOOD
var id: UUID = UUID()
var title: String = ""
var endDate: Date?

// BAD — CloudKit will refuse to initialize the container
var id: UUID
var title: String
```

### 9.2 `@Relationship` must be defined on both sides with `inverse:`

Not needed yet (`Spot` is standalone), but applies to anything added later.

### 9.3 Do NOT use `@Attribute(.unique)`

CloudKit does not enforce uniqueness. Handle it at the application level if ever needed.

---

## 10. File Creation Rules

**`Monaka/` is a synchronized folder reference** (Xcode 16+). Anything you `Write` into it, including subdirectories, is picked up by the target automatically — **no `project.pbxproj` editing required.** Create new `.swift` files freely.

This is deliberately different from Madeleine and yomy, whose `.pbxproj` files are maintained by hand. Do not copy their "stop and ask the user to create the file" rule into this repo.

Two things still need Xcode's GUI and must be handed back to the user:

- New **targets** (the share extension, the widget extension)
- **Capabilities** (App Groups) and asset catalog entries created through the asset editor

Also: a synchronized folder can only belong to one target. These six files are therefore **duplicated verbatim** into `MonakaShare/`:

`Spot.swift`, `SpotDraft.swift`, `SharedStore.swift`, `OGMetadataFetcher.swift`, `MapLinkResolver.swift`, `ShareInputResolver.swift`

**Edit both copies together**, and keep them byte-identical — `diff` them after touching any of them. Only files with no app-only dependency belong on this list; anything that interprets a spot (`Spot+Period.swift`) stays app-only.

---

## 11. Project Structure

```
AppIcon.icon/                       Icon Composer bundle, referenced from the project root
Monaka/
├── MonakaApp.swift                 entry point, ModelContainer from SharedStore
├── ContentView.swift               TabView root — Today / All / Map
├── DebugLaunchArguments.swift      #if DEBUG, every -flag in §4
├── Info.plist
├── Monaka.entitlements             App Group
├── SharedStore.swift               App Group SwiftData container (duplicated in MonakaShare/)
├── Model/
│   ├── Spot.swift                  @Model, plain value types only (duplicated in MonakaShare/)
│   ├── Spot+Period.swift           run interpretation, section assignment, countdown
│   ├── Spot+Location.swift         coordinate accessors, distance
│   ├── SpotDraft.swift             what every capture route produces, + PickedLocation
│   ├── TagVocabulary.swift         @AppStorage tag names + icons, §3
│   └── Spot+Sample.swift           #if DEBUG preview fixtures
├── Service/
│   ├── OGMetadataFetcher.swift     og:title / og:image / og:site_name
│   ├── MapLinkResolver.swift       Google / Apple Maps link → name + coordinates
│   ├── ShareInputResolver.swift    dispatches a shared item to the right resolver
│   ├── SavedPlacesImporter.swift   Google Takeout CSV → [SpotDraft]
│   └── LocationProvider.swift      CoreLocation, When In Use, requested lazily
└── View/
    ├── Today/
    │   └── TodayView.swift         featured pick + This Weekend / Ending Soon / Open Now
    ├── Spots/
    │   ├── SpotListView.swift      the full sectioned list (All tab)
    │   ├── SpotDetailView.swift    header image, run pills, notes, link, Visited button
    │   ├── SpotFormView.swift      the form Add and Edit share, + TagChip / SpotMapSnapshot
    │   ├── AddSpotView.swift       form + PasteButton + OGP autofill + location picker
    │   ├── EditSpotView.swift
    │   ├── LocationPickerView.swift  MKLocalSearch + pin, §8.1
    │   └── SpotRowView.swift       row + spotSwipeActions
    ├── Map/
    │   └── SpotMapView.swift       all spots with coordinates, pins tinted by countdown
    ├── Calendar/
    │   └── CalendarView.swift      month grid with run bars (Phase 4)
    └── Settings/
        ├── SettingsView.swift          sheet off the gear in the All tab, + SettingsRoute
        ├── TagsView.swift              the vocabulary: counts, rename, delete
        ├── TagEditView.swift           name a tag and pick its icon
        ├── IconPickerView.swift        SF Symbol grid, ported from yomy
        ├── ImportView.swift            Takeout CSV picker + per-row preview
        └── AboutView.swift
MonakaShare/                        share extension target (Phase 2)
├── ShareViewController.swift
├── ShareFormView.swift
├── Spot.swift                      verbatim copy
└── SharedStore.swift               verbatim copy
```

---

## 12. Implementation Status

### Phase 0 — Bootstrap (user, in Xcode)
- [x] New iOS App project `Monaka`, SwiftUI + SwiftData, Team `WHBF4Z49B6`
- [x] Deployment Target iOS 26.0
- [x] `Monaka/` added as a **synchronized folder**
- [x] AccentColor `#A9414E` (Any) / `#C85C68` (Dark) in the asset catalog
- [x] App Group `group.com.shakshi.Monaka`
- [x] `Shakshi3104/Monaka` created on GitHub (public)

### Phase 1 — Foundation
- [x] `Model/Spot.swift`
- [x] `Model/Spot+Period.swift` (run interpretation, sections, countdown)
- [x] `ContentView` TabView — Today / All / Map
- [x] `TodayView` — featured pick + the three open sections
- [x] `SpotListView` with the §7.2 sections + `SpotRowView`
- [x] `AddSpotView` + `LocationPickerView` (§8.1) + tags
- [x] `EditSpotView` (shares `SpotFormView` with Add)
- [x] `SpotDetailView` + Visited toggle
- [x] Swipe to toggle Visited / delete

**Phase 1 is done.**

### Phase 2 — Capture
- [x] `SharedStore.swift` + App Group container (moves a pre-App-Group `default.store` across once)
- [x] `MonakaShare` extension target (SwiftUI, `ShareFormView`)
- [x] `OGMetadataFetcher` + autofill on URL entry (Fetch Info / PasteButton in `SpotFormView`)
- [x] `ShareInputResolver` dispatch (§8.1) — also used by the in-app URL field
- [x] `MapLinkResolver` — share a place from Google Maps (§8.2)
- [x] `Anytime` collapsing (§7.3)
- [x] Distance sort + `LocationProvider` (§7.3) — applies within every section
- [x] `SpotMapView` — pins tinted by countdown, selection card, unpinned-spots sheet
- [x] Tag management — `SettingsView` + `TagsView` (rename / delete across spots), tag filter in the All tab
- [x] Hide Ended from Settings (§7.2)

### Phase 3 — Reminding
- [ ] `SavedPlacesImporter` — Takeout CSV import with preview (§8.3)
- [ ] Widget (ending soon / this weekend)
- [ ] Local notification 3 days before a run ends

### Phase 4 — Beyond
- [ ] `CalendarView` (month grid with run bars)
- [ ] Photos taken on the visit
- [x] App icon — `AppIcon.icon` (Icon Composer): a warm-tinted full moon on a night sky, the moon the wafer was likened to
- [ ] About with the name's origin

Update this section as you complete items.

---

## 13. Common Pitfalls

### Dates

1. **Count "N days left" on day boundaries.** Passing `Date()` straight into `Calendar.dateComponents([.day], from:to:)` gives a result skewed by the time of day. Round **both** ends with `startOfDay(for:)` first, or the countdown is off by one for most of the day.
2. **Use `Calendar.nextWeekend(startingAfter:)` for "This Weekend"**, not a `weekday` comparison. Opening the app on Friday night should already show the weekend that starts tomorrow.
3. **A run is inclusive of `endDate`.** "Open until 6/21" means 6/21 still counts. Compare against `endOfDay(endDate)`, not `endDate` itself, or the last day silently drops into `Ended`.
4. **`yyyy/MM/dd` with `en_US_POSIX` and `Asia/Tokyo`** — both, always (§6.1).

### Data

5. Every `@Model` property needs a default or must be Optional (§9.1).
6. Do not use `@Attribute(.unique)` (§9.3).
7. **`@Model` types are not `Sendable`.** Pull values out before crossing an isolation boundary and match results back by `id` on the main actor.
7b. **Types nested in a `@Model` inherit its main-actor isolation.** `Spot.Run` needs `nonisolated enum Run: Equatable`, or the synthesized conformance can't be used from a nonisolated context — a warning today, an error in the Swift 6 language mode.

### Web metadata

8. **Do not try to parse the run out of a page.** Venue sites write it as 「2026年4月11日(土)〜6月21日(日)」, `4/11 - 6/21`, 「会期：令和8年…」, and very often as text baked into an image. A parser that's wrong some of the time silently writes bad data, which is worse than typing two dates. Autofill the **title and image only**; the run is always hand-entered.
9. **Read at most the first 64 KB** of the response — OG tags are always in `<head>`. Decode `.utf8` with an `.isoLatin1` fallback.
10. **Fall back silently.** A page with no OG tags is normal; leave the fields empty and let the user type. Never surface a fetch failure as an error alert. Same for `MapLinkResolver` — an unparsed link still produces a usable spot.

### Maps

11. **Google's short-link format is not an API** (§8.2). Treat every field the resolver produces as optional and keep the raw URL regardless. A parser change on Google's side must degrade to "the user types the name", never to a crash or an empty save.
12. **Store the resolved URL, not the short link.** `maps.app.goo.gl` links are opaque and can stop resolving.
13. **Never resolve links in a burst.** Bulk import caps concurrency at 3 and runs after the rows are already saved.
14. **Ask for location only when distance sort is switched on** (§7.3). Not at launch, not during import. Everything works with location denied — the `Anytime` section just falls back to `addedAt`.
15. **`Anytime` will dwarf every other section** once the Google Maps backlog is in. Keep it collapsed above 8 rows, or the exhibitions the app exists for get buried.

### Share extension

16. **Both copies of `Spot.swift` and `SharedStore.swift` must stay identical** (§10). A drift between them is a store schema mismatch at runtime, not a compile error.
17. **Keep TsuiseKit-style heavy dependencies out of `Spot.swift`** — anything that interprets a spot goes in `Spot+Period.swift`, which is app-only.

### Liquid Glass

18. Do not nest `.glassEffect()`.
19. Do not apply glass to content itself.
20. `.prominent` is not a valid variant.
21. Do not override sheet backgrounds.

---

## 14. How to Work With the User

- When the user describes a feature, confirm the scope first, then implement one layer at a time (model → service → view).
- After each file change, run the build command (§4) before declaring success.
- If a build fails, fix errors yourself — do not ask the user to fix Swift compile errors unless you genuinely cannot.
- New **files** you can create yourself (§10). New **targets** and **capabilities** need Xcode — stop and tell the user exactly what to do there.
- Keep PRs focused. The user prefers squash-merging one logical change at a time.
- The user's other apps (LangueDeChat, yomy, Madeleine) are the reference for conventions. When in doubt, look at how the same problem was solved there.
