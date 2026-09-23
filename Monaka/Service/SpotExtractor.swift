//
//  SpotExtractor.swift
//  Monaka
//
//  Reads a venue's page with the on-device model (Foundation Models, iOS 26)
//  and proposes the title, venue and run. OGP gives a title and an image; the
//  run is baked into prose like 「2026年4月11日(土)〜6月21日(日)」 or `4/11 - 6/21`,
//  and §13-8 rules out a regex for that because a regex that is wrong some of
//  the time silently writes bad data. The model's answer is *not* written
//  silently: the form marks it as suggested (`SpotDraft.isRunSuggested`) and
//  the user confirms both dates.
//
//  Never throws and never blocks the form. No model on this device, no text on
//  the page, a page too long, a nonsensical answer — every one of those means
//  "nothing", and the user types.
//
//  DUPLICATED VERBATIM into MonakaShare/ (§10).
//

import Foundation
import FoundationModels

struct SpotExtractor: Sendable {
    struct Extraction: Equatable, Sendable {
        /// What the text is about. A shop's own name is its venue, so the
        /// form gets the same string in both fields — a café saved from
        /// Google Maps arrives that way too (§3).
        var isShop = false
        var title: String?
        var venue: String?
        /// A street address the text spells out. Not stored on the spot —
        /// it seeds the location picker's search (§8.1).
        var address: String?
        /// A line or two on why you'd go, in the text's own language. Goes to
        /// Notes, which is otherwise empty for a page and a whole caption for
        /// a post — neither of which is what you want to read a month later.
        var summary: String?
        var startDate: Date?
        var endDate: Date?

        var isEmpty: Bool {
            title == nil && venue == nil && address == nil && summary == nil && startDate == nil && endDate == nil
        }
    }

    /// Apple Intelligence is on and the model is ready. Everything else — an
    /// unsupported device, it's switched off, it's still downloading — reads
    /// as unavailable, and the caller skips this step entirely.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// What the model is asked to fill in. Every field is optional and the
    /// guides say so — an invented date is worse than none.
    @Generable
    struct Answer {
        @Guide(description: "True only if this page is dedicated to one specific exhibition, event, pop-up store or shop. False for a homepage, a news or exhibition list, a company site or anything else.")
        var isAboutOneThing: Bool
        @Guide(description: "What the one thing is. shop for a permanent shop, café, restaurant or bakery; popup for a limited-time store; exhibition for a museum or gallery show; event for anything else with a date.")
        var kind: Kind
        @Guide(description: "The exhibition, event, pop-up or shop name, exactly as the page writes it. Null if the page is not about one such thing.")
        var title: String?
        @Guide(description: "The venue: the museum, hall, building, mall or area it is in, as named in the text. A place name, never a street address. Null if not stated.")
        var venue: String?
        @Guide(description: "The street address, if the text spells one out (e.g. after 住所). Null otherwise.")
        var address: String?
        @Guide(description: "One or two short sentences on what this place is and what is worth having or seeing there, written in the same language as the text. Only what the text says. Null if it says nothing beyond the name.")
        var summary: String?
        @Guide(description: "First day of the exhibition, event or pop-up, as yyyy-MM-dd. Null if none is stated, and always null for a permanent shop, café or restaurant.")
        var startDate: String?
        @Guide(description: "Last day of the exhibition, event or pop-up, as yyyy-MM-dd. Null if none is stated, and always null for a permanent shop, café or restaurant.")
        var endDate: String?
    }

    /// The model is far better at naming what a text is about than at
    /// obeying "no dates for a café" — so the kind is asked for, and a shop's
    /// dates are dropped in code.
    @Generable
    enum Kind {
        case exhibition
        case event
        case popup
        case shop
    }

    /// Fetches the page and asks the model. `subject` is what OGP already
    /// called the page — the model reports on that one thing, and a subject
    /// that is a site or company name ends the exercise. `today` anchors a
    /// date the page writes without a year.
    func extract(from url: URL, subject: String? = nil, today: Date = .now) async -> Extraction? {
        guard Self.isAvailable,
              let html = await PageText.fetch(url),
              let text = PageText.digest(html)
        else { return nil }
        return await extract(fromText: text, subject: subject, today: today)
    }

    func extract(fromText text: String, subject: String? = nil, today: Date = .now) async -> Extraction? {
        // Temperature 0: the same page should propose the same dates twice.
        let options = GenerationOptions(temperature: 0)

        // Japanese runs long in tokens; if the digest overflows the window,
        // try once more with the front half, which holds the title. The
        // overflow error was renamed between iOS 26 and 27, so any failure
        // gets the one retry rather than matching either name.
        var candidate = text
        for attempt in 0..<2 {
            // A fresh session each time — the failed turn stays in the old
            // one's transcript and would count against the window again.
            let session = LanguageModelSession(instructions: Self.instructions(today: today))
            var prompt = ""
            if let subject = subject?.cleaned {
                prompt += "The page's own title is “\(subject)”. Report on the exhibition, event, pop-up or shop that title names. If that title is the name of a museum, company, brand, site or a section of one rather than one specific exhibition, event, pop-up or shop, the page is not about one thing.\n\n"
            }
            prompt += "Page text:\n\n\(candidate)"
            do {
                let answer = try await session.respond(
                    to: prompt,
                    generating: Answer.self,
                    options: options
                ).content
                let extraction = Self.validate(answer, today: today)
                return extraction.isEmpty ? nil : extraction
            } catch {
                guard attempt == 0 else { return nil }
                candidate = String(candidate.prefix(candidate.count / 2))
            }
        }
        return nil
    }

    // MARK: - Prompt

    private static func instructions(today: Date) -> String {
        """
        You read a text, usually Japanese — a web page, or a social media post about a place — and report what it states about the one exhibition, event, limited-time pop-up store, or shop it is about. First decide whether the text is about one such thing at all: a homepage, a list of exhibitions or news, a company or brand site, or a text about several things is not, and then every field is null. Report only facts written in the text; when something is not stated, leave it null. Never guess.

        Today is \(isoDate.string(from: today)).

        Dates are only for things that run for a period: an exhibition, an event, a pop-up. Report them as yyyy-MM-dd. Japanese forms such as 2026年4月11日(土)〜6月21日(日), 4/11(土)～6/21(日), 4月11日から6月21日まで all describe a run from the first date to the last. When a date has no year, use the year that makes the run current or upcoming relative to today. 令和N年 is the year 2018 + N. A text that only gives an opening date has no end date. A permanent shop, café or restaurant has no dates at all — a seasonal menu item, opening hours, closed days, a posting date or a ticket sale date are never the run.

        Title: the name of the exhibition, event, pop-up or shop as the text writes it (for a shop, the shop's own name, e.g. what follows 店名), without the site name or slogans. Venue: the place it is in, as a place name. Address: the street address if spelled out.

        Summary: one or two short sentences, in the text's own language, on what the place is and what is worth having or seeing — the signature dish, what the exhibition shows, why the text recommends it. Plain sentences: no emoji, no hashtags, no prices unless they are the point, no "check it out". Say only what the text says.
        """
    }

    // MARK: - Validation

    /// Dates are strings until they survive this. Both are parsed as
    /// Asia/Tokyo calendar days (§6.1), anything outside a sensible window
    /// around today is dropped, and a reversed pair keeps only the start.
    private static func validate(_ answer: Answer, today: Date) -> Extraction {
        var extraction = Extraction()
        // A homepage or a listing yields whatever the model noticed first —
        // "オンライン限定", a one-day news item. Nothing from those.
        guard answer.isAboutOneThing else { return extraction }
        extraction.isShop = answer.kind == .shop
        extraction.title = answer.title?.cleaned
        extraction.venue = extraction.isShop ? extraction.title : answer.venue?.cleaned
        extraction.address = answer.address?.cleaned
        extraction.summary = answer.summary?.cleaned.map { String($0.prefix(maximumSummaryLength)) }

        // A café's "run" is a seasonal menu or the posting date (§13-8).
        guard answer.kind != .shop else { return extraction }

        let start = answer.startDate.flatMap(parseDate)
        let end = answer.endDate.flatMap(parseDate)
        let earliest = calendar.date(byAdding: .year, value: -2, to: today) ?? today
        let latest = calendar.date(byAdding: .year, value: 3, to: today) ?? today
        func plausible(_ date: Date?) -> Date? {
            guard let date, date >= earliest, date <= latest else { return nil }
            return date
        }
        extraction.startDate = plausible(start)
        extraction.endDate = plausible(end)
        if let s = extraction.startDate, let e = extraction.endDate, e < s {
            extraction.endDate = nil
        }
        return extraction
    }

    /// Long enough for two sentences of Japanese, short enough that Notes
    /// stays a note.
    private static let maximumSummaryLength = 160

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        isoDate.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension SpotDraft {
    /// Merge what the model proposed. Title and venue fill only empty
    /// fields, like any other resolver; the run fills only when *neither*
    /// date is set, and is flagged as suggested.
    mutating func fillEmptyFields(from extraction: SpotExtractor.Extraction) {
        if title.isEmpty, let title = extraction.title { self.title = title }
        if venue.isEmpty {
            // A shop is its own venue — even when OGP already named it.
            if extraction.isShop, !title.isEmpty { venue = title }
            else if let venue = extraction.venue { self.venue = venue }
        }
        if suggestedAddress == nil { suggestedAddress = extraction.address }
        if notes.isEmpty, let summary = extraction.summary { notes = summary }
        if startDate == nil, endDate == nil, extraction.startDate != nil || extraction.endDate != nil {
            startDate = extraction.startDate
            endDate = extraction.endDate
            isRunSuggested = true
        }
    }

    /// A shared caption — an Instagram post about a café, say — with no URL
    /// in it. Without the model the whole caption became the title; with it
    /// the shop's name is the title, the caption goes to Notes, and the
    /// address waits for the location picker.
    mutating func adopt(_ extraction: SpotExtractor.Extraction, caption: String) {
        guard let title = extraction.title else { return }
        self.title = title
        venue = extraction.isShop ? title : (extraction.venue ?? "")
        suggestedAddress = extraction.address
        // The summary, not the caption: three screens of emoji and prices is
        // not a note. The post itself is a tap away through the link.
        if notes.isEmpty || notes == caption {
            notes = extraction.summary ?? caption.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if extraction.startDate != nil || extraction.endDate != nil {
            startDate = extraction.startDate
            endDate = extraction.endDate
            isRunSuggested = true
        }
    }
}

private extension String {
    /// Trimmed, or nil when there's nothing left — the model sometimes answers
    /// with whitespace or a lone dash instead of null.
    var cleaned: String? {
        // A title that spans two lines on the page comes back with the break.
        let flat = replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > 1, flat != "null", flat != "-" else { return nil }
        return flat
    }
}

// MARK: - Page text

/// The page as prose. `OGMetadataFetcher` stops at 64 KB because OG tags live
/// in `<head>`; the run lives in the body, so this reads further, then boils
/// the HTML down to the passages a person would read to find the dates.
enum PageText {
    /// Enough for the body of a typical venue page; the streaming cap below
    /// stops a runaway response.
    static let byteLimit = 512 * 1024
    /// What goes to the model. Its context window is 4,096 tokens and Japanese
    /// spends them fast; the instructions and the answer need room too.
    static let characterLimit = 2_400

    static func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-\(byteLimit - 1)", forHTTPHeaderField: "Range")

        guard let (stream, response) = try? await URLSession.shared.bytes(for: request),
              response is HTTPURLResponse
        else { return nil }

        var data = Data()
        data.reserveCapacity(min(byteLimit, 128 * 1024))
        do {
            for try await byte in stream {
                data.append(byte)
                if data.count >= byteLimit { break }
            }
        } catch {
            return nil
        }
        stream.task.cancel()
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// HTML → the parts worth reading, within `characterLimit`. The first
    /// stretch of text (title, lead) always goes in; after that, windows
    /// around anything that looks like a date, in page order, until the
    /// budget runs out.
    static func digest(_ html: String) -> String? {
        let text = plainText(html)
        guard !text.isEmpty else { return nil }
        if text.count <= characterLimit { return text }

        let lead = text.prefix(900)
        var budget = characterLimit - lead.count
        var windows: [Range<String.Index>] = []

        // Hints inside the lead are already covered; only look past it.
        for match in dateHints.matches(in: text, range: NSRange(lead.endIndex..., in: text)) {
            guard budget > 0, let range = Range(match.range, in: text) else { break }
            let from = text.index(range.lowerBound, offsetBy: -160, limitedBy: lead.endIndex) ?? lead.endIndex
            let to = text.index(range.upperBound, offsetBy: 160, limitedBy: text.endIndex) ?? text.endIndex
            if let last = windows.last, last.upperBound >= from {
                // Overlapping the previous window: extend it, and pay only
                // for the part that's new.
                guard to > last.upperBound else { continue }
                budget -= text.distance(from: last.upperBound, to: to)
                windows[windows.count - 1] = last.lowerBound..<to
            } else {
                budget -= text.distance(from: from, to: to)
                windows.append(from..<to)
            }
        }

        let digest = ([String(lead)] + windows.map { String(text[$0]) }).joined(separator: "\n…\n")
        return String(digest.prefix(characterLimit))
    }

    /// 2026年4月11日, 4/11, 4.11, 〜, ～, 会期, 期間, 開催, まで, from, until, through
    private static let dateHints = try! NSRegularExpression(
        pattern: #"\d{4}年|\d{1,2}月\d{1,2}日|\d{1,2}[/.]\d{1,2}|[〜～–]|会期|期間|開催|まで|\buntil\b|\bthrough\b|\bfrom\b"#,
        options: [.caseInsensitive]
    )

    static func plainText(_ html: String) -> String {
        var s = html
        for pattern in [
            #"(?is)<script\b.*?</script>"#, #"(?is)<style\b.*?</style>"#,
            #"(?is)<noscript\b.*?</noscript>"#, #"(?is)<svg\b.*?</svg>"#,
            #"(?is)<head\b.*?</head>"#, #"(?s)<!--.*?-->"#
        ] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Block-level tags become line breaks so headings stay separate.
        s = s.replacingOccurrences(of: #"(?i)</?(p|div|br|li|h[1-6]|tr|td|th|dt|dd|section|article|header|footer|table)\b[^>]*>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: #"[ \t\u{3000}]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*\n\s*"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        var s = s
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        // Numeric references (`&#12316;` is 〜 on more than one venue's site).
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|\d+);"#)
        var out = ""
        var cursor = s.startIndex
        for match in numeric.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let range = Range(match.range, in: s), let code = Range(match.range(at: 1), in: s) else { continue }
            out += s[cursor..<range.lowerBound]
            let body = s[code]
            let value = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) }
            cursor = range.upperBound
        }
        out += s[cursor...]
        return out
    }
}
