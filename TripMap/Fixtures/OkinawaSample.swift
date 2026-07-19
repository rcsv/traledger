import Foundation

enum OkinawaSample {
    static let trip: Trip = {
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: "Asia/Tokyo")!

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = timeZone
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            return components.date!
        }

        func place(_ name: String, _ address: String, _ latitude: Double, _ longitude: Double) -> PlaceSnapshot {
            PlaceSnapshot(
                id: UUID(),
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                mapKitIdentifier: nil
            )
        }

        let days = [
            Day(
                id: UUID(), sequence: 1, date: date(2026, 10, 9), title: "那覇から瀬底へ",
                activities: [
                    Activity(id: UUID(), sequence: 1, title: "那覇空港に到着", startTime: date(2026, 10, 9, 11, 30), note: nil,
                             place: place("那覇空港", "沖縄県那覇市鏡水150", 26.2064, 127.6460)),
                    Activity(id: UUID(), sequence: 2, title: "瀬底島へ移動", startTime: date(2026, 10, 9, 13, 0), note: "海沿いを北へ", place: nil),
                    Activity(id: UUID(), sequence: 3, title: "瀬底の宿にチェックイン", startTime: date(2026, 10, 9, 16, 0), note: nil,
                             place: place("瀬底島", "沖縄県国頭郡本部町瀬底", 26.6426, 127.8677))
                ]
            ),
            Day(
                id: UUID(), sequence: 2, date: date(2026, 10, 10), title: "海洋博公園と備瀬",
                activities: [
                    Activity(id: UUID(), sequence: 1, title: "沖縄美ら海水族館", startTime: date(2026, 10, 10, 9, 0), note: "朝一番に黒潮の海へ",
                             place: place("沖縄美ら海水族館", "沖縄県国頭郡本部町石川424", 26.6943, 127.8779)),
                    Activity(id: UUID(), sequence: 2, title: "備瀬のフクギ並木を歩く", startTime: date(2026, 10, 10, 13, 30), note: nil,
                             place: place("備瀬のフクギ並木", "沖縄県国頭郡本部町備瀬", 26.7054, 127.8807)),
                    Activity(id: UUID(), sequence: 3, title: "エメラルドビーチで夕方を過ごす", startTime: date(2026, 10, 10, 16, 0), note: nil,
                             place: place("エメラルドビーチ", "沖縄県国頭郡本部町石川424", 26.7019, 127.8750))
                ]
            ),
            Day(
                id: UUID(), sequence: 3, date: date(2026, 10, 11), title: "古宇利島ドライブ",
                activities: [
                    Activity(id: UUID(), sequence: 1, title: "古宇利大橋を渡る", startTime: date(2026, 10, 11, 10, 0), note: nil,
                             place: place("古宇利大橋", "沖縄県国頭郡今帰仁村古宇利", 26.6967, 128.0183)),
                    Activity(id: UUID(), sequence: 2, title: "ハートロックを見る", startTime: date(2026, 10, 11, 12, 0), note: nil,
                             place: place("ハートロック", "沖縄県国頭郡今帰仁村古宇利", 26.7142, 128.0157))
                ]
            ),
            Day(
                id: UUID(), sequence: 4, date: date(2026, 10, 12), title: "那覇へ戻る",
                activities: [
                    Activity(id: UUID(), sequence: 1, title: "瀬底を出発", startTime: date(2026, 10, 12, 9, 30), note: nil, place: nil),
                    Activity(id: UUID(), sequence: 2, title: "国際通りを散策", startTime: date(2026, 10, 12, 13, 0), note: nil,
                             place: place("国際通り", "沖縄県那覇市牧志", 26.2150, 127.6847))
                ]
            )
        ]

        return Trip(
            id: UUID(),
            title: "沖縄・瀬底 4日間",
            dateRange: date(2026, 10, 9)...date(2026, 10, 12),
            days: days
        )
    }()
}
