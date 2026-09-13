//
//  Spot+Sample.swift
//  Monaka
//
//  Preview fixtures. Dates are relative to now so every §7.2 section is
//  populated whenever a preview runs.
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
                startDate: sample(daysFromNow: -10),
                endDate: sample(daysFromNow: 2),          // This Weekend / Ending Soon
                tags: ["Exhibition"]
            ),
            Spot(
                title: "Cartier and Japan",
                venue: "国立新美術館",
                startDate: sample(daysFromNow: -30),
                endDate: sample(daysFromNow: 9),          // Ending Soon
                tags: ["Exhibition"]
            ),
            Spot(
                title: "The Sky Is Not the Limit",
                venue: "森美術館",
                startDate: sample(daysFromNow: -20),
                endDate: sample(daysFromNow: 60),         // Open Now
                tags: ["Exhibition"]
            ),
            Spot(
                title: "モネ 睡蓮のとき",
                venue: "国立西洋美術館",
                startDate: sample(daysFromNow: 21),
                endDate: sample(daysFromNow: 120),        // Upcoming
                tags: ["Exhibition"]
            ),
            Spot(
                title: "ふげん社",
                venue: "白金高輪",
                mapURL: "https://www.google.com/maps/place/fugensha",
                tags: ["Café"]                          // Anytime
            ),
            Spot(
                title: "喫茶 なづな",
                venue: "谷中",
                tags: ["Café"]                          // Anytime
            ),
            Spot(
                title: "ハニワと土偶の近代",
                venue: "東京国立近代美術館",
                startDate: sample(daysFromNow: -80),
                endDate: sample(daysFromNow: -20),
                isVisited: true,
                visitedAt: sample(daysFromNow: -35)       // Visited
            ),
            Spot(
                title: "空想と創造",
                venue: "SOMPO美術館",
                startDate: sample(daysFromNow: -100),
                endDate: sample(daysFromNow: -3)          // Ended
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
}
#endif
