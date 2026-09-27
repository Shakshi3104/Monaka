//
//  OGMetadataFetcher.swift
//  Monaka
//
//  og:title / og:image / og:site_name out of a page's <head>.
//
//  Deliberately NOT a run parser (§13-8): venue sites write the dates as
//  「2026年4月11日(土)〜6月21日(日)」, as `4/11 - 6/21`, as 「会期：令和8年…」, and
//  very often as text baked into an image. A parser that's wrong some of the
//  time writes bad data silently, which is worse than typing two dates.
//

import Foundation

struct OGMetadata: Equatable, Sendable {
    var title: String?
    var imageURL: String?
    var siteName: String?
    /// `og:description`. For most pages it's marketing copy and stays unused;
    /// for a social post it is the caption, which is the whole point.
    var description: String?

    var isEmpty: Bool { title == nil && imageURL == nil && siteName == nil && description == nil }
}

struct OGMetadataFetcher: Sendable {
    enum FetchError: Error {
        case notHTTP
        case unreadable
    }

    /// OG tags are always in `<head>`, so reading stops at `</head>` (§13-9).
    /// This is only the cap for a page that never closes it. A fixed 64 KB
    /// used to be the whole rule, until PR TIMES put 80 KB of monitoring
    /// script ahead of its OG tags and every field came back empty.
    static let byteLimit = 512 * 1024

    private static let headEnd = Data("</head>".utf8)

    /// Throws only on transport failures. A page with no OG tags returns an
    /// empty `OGMetadata`; the caller leaves the fields alone (§13-10).
    func fetch(_ url: URL) async throws -> OGMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // Honoured by many servers; the streaming cap below covers the rest.
        request.setValue("bytes=0-\(Self.byteLimit - 1)", forHTTPHeaderField: "Range")

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard response is HTTPURLResponse else {
            stream.task.cancel()
            throw FetchError.notHTTP
        }

        var data = Data()
        data.reserveCapacity(64 * 1024)
        for try await byte in stream {
            data.append(byte)
            if data.count >= Self.byteLimit { break }
            // Every `>`, look back for `</head>` — the rest of the page is
            // body, and the body has no OG tags.
            if byte == UInt8(ascii: ">"), data.count >= Self.headEnd.count,
               data.suffix(Self.headEnd.count).elementsEqual(Self.headEnd, by: { Self.lowercased($0) == $1 }) {
                break
            }
        }
        stream.task.cancel()

        guard let html = Self.decode(data) else { throw FetchError.unreadable }
        return Self.parse(html, base: url)
    }

    /// `.utf8`, falling back to `.isoLatin1` (§13-9).
    ///
    /// A read cut off at the cap usually ends partway through a character —
    /// Japanese is three bytes in UTF-8 — and a strict UTF-8 decode of that
    /// fails outright, dropping the whole page into Latin-1 mojibake. Up to
    /// three trailing bytes are shed before giving up on UTF-8.
    static func decode(_ data: Data) -> String? {
        for trim in 0...3 where data.count > trim {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    static func parse(_ html: String, base: URL) -> OGMetadata {
        var metadata = OGMetadata()
        metadata.title = metaContent(["og:title", "twitter:title"], in: html)
            ?? firstMatch("<title[^>]*>([^<]*)</title>", in: html)?.decodingHTMLEntities.nilIfBlank
        metadata.siteName = metaContent(["og:site_name"], in: html)
        metadata.description = metaContent(["og:description", "twitter:description", "description"], in: html)
        if let image = metaContent(["og:image", "og:image:url", "twitter:image"], in: html) {
            // OG images are often written as a path, not an absolute URL.
            metadata.imageURL = URL(string: image, relativeTo: base)?.absoluteString ?? image
        }
        return metadata
    }

    // MARK: - Regex

    /// Attribute order varies — `property` may come before or after `content`.
    private static func metaContent(_ names: [String], in html: String) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"<meta[^>]+?(?:property|name)\s*=\s*["']\#(escaped)["'][^>]*?content\s*=\s*["']([^"']*)["']"#,
                #"<meta[^>]+?content\s*=\s*["']([^"']*)["'][^>]*?(?:property|name)\s*=\s*["']\#(escaped)["']"#
            ]
            for pattern in patterns {
                if let value = firstMatch(pattern, in: html)?.decodingHTMLEntities.nilIfBlank {
                    return value
                }
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html)
        else { return nil }

        return String(html[captured])
    }
}

extension String {
    /// Just the handful that actually show up in `<meta>` content.
    var decodingHTMLEntities: String {
        var text = self
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'"
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        // Numeric references — Instagram writes every non-ASCII character
        // of a title as `&#x30e0;`, and so do other sites with Japanese.
        if text.contains("&#") {
            text = text.decodingNumericEntities
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var decodingNumericEntities: String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]{1,6}|[0-9]{1,7});"#) else { return self }
        var out = ""
        var cursor = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self), let code = Range(match.range(at: 1), in: self) else { continue }
            out += self[cursor..<range.lowerBound]
            let body = self[code]
            let value = body.hasPrefix("x") || body.hasPrefix("X") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
            } else {
                out += self[range]
            }
            cursor = range.upperBound
        }
        out += self[cursor...]
        return out
    }
}
