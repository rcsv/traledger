import Foundation

enum PrototypeEdgeCases {
    static let emptyTrip = Trip(
        id: UUID(),
        title: "空の旅行",
        dateRange: referenceDate...referenceDate,
        days: []
    )

    static let emptyDayTrip = trip(
        title: "予定のない日",
        activities: []
    )

    static let noPlaceTrip = trip(
        title: "場所のない日",
        activities: (1...3).map {
            Activity(id: UUID(), sequence: $0, title: "未設定の予定 \($0)", startTime: nil, note: nil, place: nil)
        }
    )

    static let overlappingPlacesTrip = trip(
        title: "同じ場所の予定",
        activities: (1...3).map {
            Activity(
                id: UUID(), sequence: $0, title: "同一地点の予定 \($0)", startTime: nil, note: nil,
                place: place(name: "東京駅", latitude: 35.6812, longitude: 139.7671)
            )
        }
    )

    static let denseTrip = trip(
        title: "30件の予定",
        activities: (1...30).map { sequence in
            Activity(
                id: UUID(), sequence: sequence, title: "予定 \(sequence)", startTime: nil, note: nil,
                place: place(
                    name: "地点 \(sequence)",
                    latitude: 35.66 + Double(sequence % 6) * 0.008,
                    longitude: 139.72 + Double(sequence / 6) * 0.008
                )
            )
        }
    )

    static let dateLineTrip = trip(
        title: "日付変更線をまたぐ旅行",
        activities: [
            Activity(id: UUID(), sequence: 1, title: "東側", startTime: nil, note: nil,
                     place: place(name: "東側", latitude: -17.7, longitude: 179.6)),
            Activity(id: UUID(), sequence: 2, title: "西側", startTime: nil, note: nil,
                     place: place(name: "西側", latitude: -16.5, longitude: -179.8))
        ]
    )

    static let longContentTrip = trip(
        title: String(repeating: "非常に長い旅行名", count: 8),
        activities: [
            Activity(
                id: UUID(), sequence: 1,
                title: String(repeating: "非常に長いActivity名称", count: 10),
                startTime: nil,
                note: String(repeating: "長いメモでも情報を失わず、スクロール可能であることを確認します。", count: 12),
                place: PlaceSnapshot(
                    id: UUID(),
                    name: String(repeating: "非常に長い場所名", count: 8),
                    address: String(repeating: "非常に長い住所", count: 12),
                    latitude: 35.6812,
                    longitude: 139.7671,
                    mapKitIdentifier: nil
                )
            )
        ]
    )

    private static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    private static func trip(title: String, activities: [Activity]) -> Trip {
        Trip(
            id: UUID(),
            title: title,
            dateRange: referenceDate...referenceDate,
            days: [Day(id: UUID(), sequence: 1, date: referenceDate, title: title, activities: activities)]
        )
    }

    private static func place(name: String, latitude: Double, longitude: Double) -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(), name: name, address: "", latitude: latitude, longitude: longitude, mapKitIdentifier: nil
        )
    }
}
