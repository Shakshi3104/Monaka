//
//  Spot+Period.swift
//  Monaka
//
//  How a spot's run is interpreted, which section it lands in, and what the
//  trailing countdown says. App-only — never compiled into the share extension.
//  See CLAUDE.md §7.
//

import Foundation

// MARK: - Calendar

extension Calendar {
    /// Pinned to `Asia/Tokyo` / `en_US_POSIX` so the sections don't shift while
    /// the user is travelling (CLAUDE.md §6.1).
    static let monaka: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// The last instant of `date`'s day. A run is inclusive of `endDate` (§13-3).
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
    }

    /// Whole days between two instants, counted on day boundaries (§13-1).
    func dayCount(from: Date, to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }

    /// The weekend the user means by "this weekend": the one we're inside if
    /// today is Sat/Sun, otherwise the next one — so Friday night already
    /// shows tomorrow (§13-2).
    func upcomingWeekend(from date: Date) -> DateInterval? {
        dateIntervalOfWeekend(containing: date) ?? nextWeekend(startingAfter: date)
    }
}

// MARK: - The run

extension Spot {
    /// The four ways `startDate` / `endDate` combine (§7.1).
    ///
    /// `nonisolated`: `Spot` is main-actor isolated, and without this the
    /// synthesized `Equatable` conformance is too — an error in Swift 6 mode.
    nonisolated enum Run: Equatable {
        case period(start: Date, end: Date)   // 2026/04/11 – 06/21
        case until(Date)                      // "until 6/21"
        case from(Date)                       // "from 10/03", open-ended
        case anytime                          // no run, always available
    }

    var run: Run {
        switch (startDate, endDate) {
        case let (start?, end?): .period(start: start, end: end)
        case let (nil, end?): .until(end)
        case let (start?, nil): .from(start)
        case (nil, nil): .anytime
        }
    }

    var hasRun: Bool { run != .anytime }

    /// The run as an interval, inclusive of both ends' days. `nil` when anytime.
    ///
    /// Reversed dates (a user typo) are normalized rather than trapped —
    /// `DateInterval` requires `end >= start`.
    func runInterval(calendar: Calendar = .monaka) -> DateInterval? {
        switch run {
        case .anytime:
            return nil
        case let .period(start, end):
            let from = calendar.startOfDay(for: start)
            let to = calendar.endOfDay(for: end)
            return DateInterval(start: min(from, to), end: max(from, to))
        case let .until(end):
            return DateInterval(start: .distantPast, end: calendar.endOfDay(for: end))
        case let .from(start):
            return DateInterval(start: calendar.startOfDay(for: start), end: .distantFuture)
        }
    }

    /// Currently within the run. An anytime spot is *not* "open" — it belongs
    /// to the `Anytime` section, not `Open Now`.
    func isOpen(on date: Date = .now, calendar: Calendar = .monaka) -> Bool {
        guard let interval = runInterval(calendar: calendar) else { return false }
        return interval.contains(date)
    }

    /// The run is over. An open-ended run (`from`, no `endDate`) never ends.
    func hasEnded(on date: Date = .now, calendar: Calendar = .monaka) -> Bool {
        guard let end = endDate else { return false }
        return date > calendar.endOfDay(for: end)
    }

    /// The run hasn't started yet.
    func isUpcoming(on date: Date = .now, calendar: Calendar = .monaka) -> Bool {
        guard let start = startDate else { return false }
        return calendar.startOfDay(for: start) > date
    }

    /// Days until the last day of the run, inclusive: `0` on the final day.
    func daysUntilEnd(on date: Date = .now, calendar: Calendar = .monaka) -> Int? {
        guard let end = endDate else { return nil }
        return calendar.dayCount(from: date, to: end)
    }

    /// Days until the run opens: `0` on opening day.
    func daysUntilStart(on date: Date = .now, calendar: Calendar = .monaka) -> Int? {
        guard let start = startDate else { return nil }
        return calendar.dayCount(from: date, to: start)
    }

    /// What "This Weekend" means, which differs by screen.
    ///
    /// Exhibition runs are months long, so `.intersecting` catches nearly every
    /// open spot — which is what the Today tab wants (everything you could go
    /// to this weekend) and what the full list must not do, or `Ending Soon`
    /// and `Open Now` end up empty.
    enum WeekendRule {
        /// The run overlaps the weekend at all.
        case intersecting
        /// The last weekend of the run, or the weekend it opens on.
        case lastChance
    }

    /// Whether the upcoming weekend intersects the run (§7.2). No-run spots excluded.
    func isOnUpcomingWeekend(on date: Date = .now, calendar: Calendar = .monaka) -> Bool {
        guard let interval = runInterval(calendar: calendar),
              let weekend = calendar.upcomingWeekend(from: date)
        else { return false }
        return interval.intersects(weekend)
    }

    /// The run's **last weekend** — or the weekend it opens on.
    ///
    /// Deliberately not "the run ends by Sunday": a run closing on the Tuesday
    /// after still makes this the last weekend you could go, and days off are
    /// when people actually go. So the test is that the *following* weekend no
    /// longer falls inside the run.
    func isLastChanceThisWeekend(on date: Date = .now, calendar: Calendar = .monaka) -> Bool {
        guard let interval = runInterval(calendar: calendar),
              let weekend = calendar.upcomingWeekend(from: date),
              interval.intersects(weekend)
        else { return false }

        if let start = startDate {
            let opening = calendar.startOfDay(for: start)
            if opening >= weekend.start && opening < weekend.end { return true }
        }

        guard let following = calendar.nextWeekend(startingAfter: weekend.end) else { return false }
        return !interval.intersects(following)
    }

    func isOnUpcomingWeekend(
        rule: WeekendRule,
        on date: Date = .now,
        calendar: Calendar = .monaka
    ) -> Bool {
        switch rule {
        case .intersecting: isOnUpcomingWeekend(on: date, calendar: calendar)
        case .lastChance: isLastChanceThisWeekend(on: date, calendar: calendar)
        }
    }
}

// MARK: - Countdown

extension Spot {
    /// The trailing tag on a list row (§6.3).
    enum Countdown: Equatable {
        case visited
        case endsToday
        case daysLeft(Int)
        case startsToday
        case startsIn(Int)
        case ended
        /// Anytime, or open now with no end in sight — no tag.
        case none

        var text: String? {
            switch self {
            case .visited: "Visited"
            case .endsToday: "Ends today"
            case let .daysLeft(days): "\(days) \(days == 1 ? "day" : "days") left"
            case .startsToday: "Starts today"
            case let .startsIn(days): "In \(days) \(days == 1 ? "day" : "days")"
            case .ended: "Ended"
            case .none: nil
            }
        }

        /// How the view should tint the tag. Colors live in the view layer.
        var emphasis: Emphasis {
            switch self {
            case .visited: .done
            case .endsToday: .soon
            case let .daysLeft(days): days <= Spot.endingSoonWindow ? .soon : .normal
            // Not open yet: nothing to act on, so it doesn't compete with a
            // run you could go to today. The map keeps its pins tinted —
            // a grey pin reads as missing rather than early.
            case .startsToday, .startsIn: .muted
            case .ended, .none: .muted
            }
        }

        enum Emphasis: Equatable {
            case normal   // .accentColor
            case soon     // .orange
            case done     // .green
            case muted    // .secondary
        }
    }

    func countdown(on date: Date = .now, calendar: Calendar = .monaka) -> Countdown {
        if isVisited { return .visited }
        if hasEnded(on: date, calendar: calendar) { return .ended }

        if isUpcoming(on: date, calendar: calendar) {
            guard let days = daysUntilStart(on: date, calendar: calendar) else { return .none }
            return days <= 0 ? .startsToday : .startsIn(days)
        }

        guard let days = daysUntilEnd(on: date, calendar: calendar) else { return .none }
        return days <= 0 ? .endsToday : .daysLeft(days)
    }
}

// MARK: - Sections

/// The list's sections, in display order (§7.2).
enum SpotSection: Int, CaseIterable, Identifiable, Hashable {
    case thisWeekend
    case endingSoon
    case openNow
    case upcoming
    case anytime
    case visited
    case ended

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thisWeekend: "This Weekend"
        case .endingSoon: "Ending Soon"
        case .openNow: "Open Now"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .visited: "Visited"
        case .ended: "Ended"
        }
    }
}

extension Spot {
    /// A run ending within this many days is "Ending Soon".
    static let endingSoonWindow = 14

    /// The first section the spot matches (§7.2).
    ///
    /// `isVisited` is checked before every dated section: once it's checked off
    /// it leaves the active list, which is also what `Ended`'s "never visited"
    /// condition implies.
    func section(
        on date: Date = .now,
        weekend rule: WeekendRule = .intersecting,
        calendar: Calendar = .monaka
    ) -> SpotSection {
        if isVisited { return .visited }
        guard hasRun else { return .anytime }

        if isOnUpcomingWeekend(rule: rule, on: date, calendar: calendar) { return .thisWeekend }

        if isOpen(on: date, calendar: calendar) {
            if let days = daysUntilEnd(on: date, calendar: calendar), days <= Self.endingSoonWindow {
                return .endingSoon
            }
            return .openNow
        }

        if isUpcoming(on: date, calendar: calendar) { return .upcoming }
        return .ended
    }
}

extension SpotSection {
    /// The section's own sort (§7.2). `Anytime`'s distance sort is layered on
    /// top of this later (§7.3) — without coordinates it stays `addedAt` desc.
    func sorted(_ spots: [Spot]) -> [Spot] {
        switch self {
        case .thisWeekend, .endingSoon, .openNow:
            spots.sorted { Self.ascending($0.endDate, $1.endDate, tie: $0, $1) }
        case .upcoming:
            spots.sorted { Self.ascending($0.startDate, $1.startDate, tie: $0, $1) }
        case .anytime:
            spots.sorted { $0.addedAt > $1.addedAt }
        case .visited:
            spots.sorted { Self.descending($0.visitedAt, $1.visitedAt, tie: $0, $1) }
        case .ended:
            spots.sorted { Self.descending($0.endDate, $1.endDate, tie: $0, $1) }
        }
    }

    /// Spots grouped into their sections, empty sections dropped.
    static func grouped(
        _ spots: [Spot],
        on date: Date = .now,
        weekend rule: Spot.WeekendRule = .intersecting,
        only wanted: [SpotSection]? = nil,
        calendar: Calendar = .monaka
    ) -> [(section: SpotSection, spots: [Spot])] {
        let buckets = Dictionary(grouping: spots) {
            $0.section(on: date, weekend: rule, calendar: calendar)
        }
        // Always in §7.2 order, whatever order `wanted` came in.
        return allCases.filter { wanted?.contains($0) ?? true }.compactMap { section in
            guard let bucket = buckets[section], !bucket.isEmpty else { return nil }
            return (section, section.sorted(bucket))
        }
    }

    // A missing date sorts last either way; `addedAt` breaks the tie so the
    // order is stable across redraws.
    private static func ascending(_ lhs: Date?, _ rhs: Date?, tie l: Spot, _ r: Spot) -> Bool {
        switch (lhs, rhs) {
        case let (a?, b?): a == b ? l.addedAt > r.addedAt : a < b
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): l.addedAt > r.addedAt
        }
    }

    private static func descending(_ lhs: Date?, _ rhs: Date?, tie l: Spot, _ r: Spot) -> Bool {
        switch (lhs, rhs) {
        case let (a?, b?): a == b ? l.addedAt > r.addedAt : a > b
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): l.addedAt > r.addedAt
        }
    }
}

// MARK: - Formatting

extension DateFormatter {
    /// Both `locale` and `timeZone` are always pinned — §6.1.
    private static func monaka(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = format
        return formatter
    }

    /// `2026/04/11`
    static let monakaDate = monaka("yyyy/MM/dd")
    /// `2026/04/11 (Sat)` — the §6.1 format plus the day of the week, which is
    /// what you actually plan a visit around.
    static let monakaDateWithWeekday = monaka("yyyy/MM/dd (E)")
    /// `04/11 (Sat)` — only for *today*, where the year is never in question.
    /// Anything describing a run keeps the full §6.1 format.
    static let monakaTodayDate = monaka("MM/dd (E)")
    /// `4/11` — for a list row, where the year is dropped when it's this
    /// year and the zero padding goes too (see `Spot.compactRunText`).
    static let monakaMonthDay = monaka("M/d")
    /// `2027/1/10` — the row form for a date outside the current year.
    static let monakaCompactDate = monaka("yyyy/M/d")
}

extension Spot {
    /// `2026/04/11 – 2026/06/21`, `Until 2026/06/21`, `From 2026/10/03`, `Anytime`.
    var runText: String {
        let format = DateFormatter.monakaDate.string(from:)
        switch run {
        case let .period(start, end):
            return "\(format(start)) – \(format(end))"
        case let .until(end):
            return "Until \(format(end))"
        case let .from(start):
            return "From \(format(start))"
        case .anytime:
            return "Anytime"
        }
    }

    /// `4/11 – 6/21` — the row form. A full `yyyy/MM/dd – yyyy/MM/dd` never
    /// fit beside a venue name and the end date, the half that matters, was
    /// the half that got truncated. The year appears only on a date outside
    /// the current year (`12/20 – 2027/1/10`), so a run that crosses New
    /// Year still says so.
    func compactRunText(on today: Date = .now, calendar: Calendar = .monaka) -> String {
        let thisYear = calendar.component(.year, from: today)
        func format(_ date: Date) -> String {
            calendar.component(.year, from: date) == thisYear
                ? DateFormatter.monakaMonthDay.string(from: date)
                : DateFormatter.monakaCompactDate.string(from: date)
        }
        switch run {
        case let .period(start, end):
            return "\(format(start)) – \(format(end))"
        case let .until(end):
            return "Until \(format(end))"
        case let .from(start):
            return "From \(format(start))"
        case .anytime:
            return "Anytime"
        }
    }
}

// MARK: - Search

extension Spot {
    /// Title, venue, tags, address and notes, matched the way the system
    /// does (case- and diacritic-insensitive, so `cafe` finds `Café`).
    func matches(_ query: String) -> Bool {
        let fields = [title, venue, address, notes].compactMap { $0 } + tags
        return fields.contains { $0.localizedStandardContains(query) }
    }
}
