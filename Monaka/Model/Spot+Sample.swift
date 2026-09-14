//
//  Spot+Sample.swift
//  Monaka
//
//  Preview fixtures. Dates are relative to now so every §7.2 section is
//  populated whenever a preview runs.
//
//  Images are Wikimedia Commons thumbnails and coordinates come from the
//  venues' Wikipedia entries — real values, so the detail view's header image
//  and map snapshot both render for real instead of falling back to the empty
//  state. Two spots are deliberately left bare (no image, no coordinate) so the
//  missing-data paths stay covered too.
//

#if DEBUG
import Foundation
import SwiftData

extension Spot {
    static func sample(daysFromNow days: Int, calendar: Calendar = .monaka) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now)) ?? .now
    }

    static var samples: [Spot] {
        [
            Spot(
                title: "ミロ展",
                venue: "東京都美術館",
                urlString: "https://www.tobikan.jp",
                notes: "Ueno Park. Closed Mondays — go on the Saturday.",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/c/c1/Toukyoutoartmuseum.jpg",
                startDate: sample(daysFromNow: -10),
                endDate: sample(daysFromNow: 2),          // This Weekend / Ending Soon
                latitude: 35.717186,
                longitude: 139.772776,
                address: "東京都台東区上野公園8-36",
                tags: ["Exhibition", "Ueno"]
            ),
            Spot(
                title: "Cartier and Japan",
                venue: "国立新美術館",
                urlString: "https://www.nact.jp",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/a/af/2018_National_Art_Center%2C_Tokyo_2.jpg/500px-2018_National_Art_Center%2C_Tokyo_2.jpg",
                startDate: sample(daysFromNow: -30),
                endDate: sample(daysFromNow: 9),          // Ending Soon
                latitude: 35.665,
                longitude: 139.726389,
                address: "東京都港区六本木7-22-2",
                tags: ["Exhibition"]
            ),
            Spot(
                title: "The Sky Is Not the Limit",
                venue: "森美術館",
                urlString: "https://www.mori.art.museum",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Mori_Art_Museum_Entrance_2013.jpg/500px-Mori_Art_Museum_Entrance_2013.jpg",
                startDate: sample(daysFromNow: -20),
                endDate: sample(daysFromNow: 60),         // Open Now
                latitude: 35.660506,
                longitude: 139.729067,
                address: "東京都港区六本木6-10-1 六本木ヒルズ森タワー53F",
                tags: ["Exhibition"]
            ),
            Spot(
                title: "モネ 睡蓮のとき",
                venue: "国立西洋美術館",
                urlString: "https://www.nmwa.go.jp",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9d/National_museum_of_western_art05s3200.jpg/500px-National_museum_of_western_art05s3200.jpg",
                startDate: sample(daysFromNow: 21),
                endDate: sample(daysFromNow: 120),        // Upcoming
                latitude: 35.715556,
                longitude: 139.775833,
                address: "東京都台東区上野公園7-7",
                tags: ["Exhibition", "Ueno"]
            ),
            Spot(
                title: "ふげん社",
                venue: "白金高輪",
                urlString: "https://fugensha.jp",
                mapURL: "https://www.google.com/maps/place/fugensha",
                notes: "Photo books and coffee. Small — avoid weekends.",
                latitude: 35.643194,
                longitude: 139.734444,
                address: "東京都港区白金1-14-1",
                tags: ["Café"]                            // Anytime, pinned but no image
            ),
            Spot(
                title: "喫茶 なづな",
                venue: "谷中",
                tags: ["Café"]                            // Anytime, nothing filled in at all
            ),
            Spot(
                title: "ハニワと土偶の近代",
                venue: "東京国立近代美術館",
                urlString: "https://www.momat.go.jp",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/0/00/National_Museum_of_Modern_Art_Tokyo.jpg/500px-National_Museum_of_Modern_Art_Tokyo.jpg",
                startDate: sample(daysFromNow: -80),
                endDate: sample(daysFromNow: -20),
                latitude: 35.690508,
                longitude: 139.754653,
                address: "東京都千代田区北の丸公園3-1",
                isVisited: true,
                visitedAt: sample(daysFromNow: -35),      // Visited
                tags: ["Exhibition"]
            ),
            Spot(
                title: "空想と創造",
                venue: "SOMPO美術館",
                urlString: "https://www.sompo-museum.org",
                imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Sompo_Museum_of_Art_2024-01-25.jpg/500px-Sompo_Museum_of_Art_2024-01-25.jpg",
                startDate: sample(daysFromNow: -100),
                endDate: sample(daysFromNow: -3),         // Ended
                latitude: 35.69264,
                longitude: 139.69652,
                address: "東京都新宿区西新宿1-26-1",
                tags: ["Exhibition"]
            )
        ]
    }

    /// An in-memory container preloaded with `samples`, for `#Preview`.
    @MainActor
    static var previewContainer: ModelContainer {
        let container = try! ModelContainer(
            for: Spot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for spot in samples {
            container.mainContext.insert(spot)
        }
        return container
    }

    /// Puts `samples` into a real store so the simulator shows the same spread
    /// the previews do (§4, `-seed-samples`).
    ///
    /// Deliberately never overwrites: a sample whose title is already there only
    /// fills in fields that are still empty, so a spot you typed in the
    /// simulator by hand survives and just gains an image and a pin.
    @MainActor
    static func seedSamples(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Spot>())) ?? []
        let byTitle = Dictionary(existing.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })

        for sample in samples {
            guard let spot = byTitle[sample.title] else {
                context.insert(sample)
                continue
            }
            spot.venue = spot.venue ?? sample.venue
            spot.urlString = spot.urlString ?? sample.urlString
            spot.mapURL = spot.mapURL ?? sample.mapURL
            spot.notes = spot.notes ?? sample.notes
            spot.imageURL = spot.imageURL ?? sample.imageURL
            spot.latitude = spot.latitude ?? sample.latitude
            spot.longitude = spot.longitude ?? sample.longitude
            spot.address = spot.address ?? sample.address
            if spot.tags.isEmpty { spot.tags = sample.tags }
        }

        try? context.save()
    }
}
#endif
