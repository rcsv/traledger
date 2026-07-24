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

#if TRIPMAP_QA
enum VenueImageQAFixture {
    static let tripID = UUID(uuidString: "A11E0000-0000-4000-8000-000000000000")!
    static let dayID = UUID(uuidString: "A11E0000-0000-4000-8000-000000000001")!
    static let lookAroundActivityID = UUID(uuidString: "A11E0000-0000-4000-8000-000000000011")!
    static let wikimediaActivityID = UUID(uuidString: "A11E0000-0000-4000-8000-000000000012")!
    static let userImageActivityID = UUID(uuidString: "A11E0000-0000-4000-8000-000000000013")!

    // A deterministic copy of the app icon used only to make user-image rendering
    // visually unambiguous on platforms where Venue Card editing is unavailable.
    static let preseededUserImageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAHgAAAB4CAYAAAA5ZDbSAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAeKADAAQAAAABAAAAeAAAAAArKnfUAAAEQ0lEQVR4Ae2dMWsUQRSA5w4l2lvYCBFSCIdBMbH2D6SwsEqXnyDkB6QW7NPYWaVMkU4UbfQiomDlgVFbrTUYL2Z3SdjM7g253cfbd+++K/Tmze3Me9+3uyxkhu1tbe8dBz5uCfTdVkZhOQEEOz8REIxg5wScl8cVjGDnBJyXxxWMYOcEnJfHFexc8CXr9fXHR2H1025YOtjPUx0troTh8loY982nbgKteUqrH3fDYPT6DNbgS/H97Z2HZzG+TCZg/ha99K24csslnF7N5Rjf6wmYF7zw93cl87pY5UcEcgLmBeOpHQEEt+Nn/mi1h6x+vxce3L0RBjevhSsLF5/21049w831+/UdhqN/Do/C568/w8sPP8J4rPNn+IuTbgkuk3vv1vWWo8z24dmJfcrgxfvvKsWo3aKzK5dPQUCThZrgaW7L3k8ETRZqgr1Ls1ofgq2aEcoLwUIgrQ6DYKtmhPJCsBBIq8Mg2KoZobwQLATS6jAItmpGKC8EC4G0OgyCrZoRygvBQiCtDoNgq2aE8kKwEEirwyDYqhmhvBAsBNLqMAi2akYoLwQLgbQ6DIKtmhHKC8FCIK0OoyY4WzLKpyCgyUJNcLYemE9BQJOF2rroVyeLvbPPtAvfCyQ+/i0vfNeqSE3wv5OV/Nli72kXfG9MIPHk+bsJPYTLBNRu0eVJ+a5HAMF6rDuZCcGdYNebFMF6rDuZSe0hq+n20bD+phbMZm3UdrD8FM32UduuGmXH9tFG2GbvILaPzp6zqTJm++hUuPhxigBP0Sk6DvoQ7EBiqgQEp+g46EOwA4mpEhCcouOgD8EOJKZKQHCKjoM+BDuQmCoBwSk6DvoQ7EBiqgQEp+g46EOwA4mpEhCcouOgD8EOJKZKQHCKjoM+BDuQmCoBwSk6DvoQ7EBiqgQ1wZpbJlMFW+jTZKEmWHPLpAWJqRw0WagtfGf7aAjlhe+pE0CyT01w4+2jO49r63326GltnOB5Amq36PPT0tIigGAt0h3Ng+COwGtNi2At0h3No/aQ1XT7KG8fbXdmqAnm7aMhf60ubx9td8LOxNFsH50JTc2TZPtoc3YcGRHgKToC4q2JYG9Go3oQHAHx1kSwN6NRPQiOgHhrItib0ageBEdAvDUR7M1oVA+CIyDemgj2ZjSqB8EREG9NBHszGtWD4AiItyaCvRmN6kFwBMRbE8HejEb1IDgC4q2JYG9Go3rUBGtumYxqNNfUZKEmWHPLpDmjUUKaLNTWRbN9lO2j0XleNDdqoyHw9tEJYKKw2i06mpemEgEEK4Huahrzgg8vX62wqYtVfkQgJ2Be8GhxpaKqLlb5EYGcgNpTdFPew9tr+aFLB/v5/5nc4XIRazrmPB3X29reO56nguetVvO36HkTIl0vgqWJGhsPwcaESKeDYGmixsZDsDEh0ukgWJqosfEQbEyIdDoIliZqbDwEGxMinc5/DX3CXn1YKHkAAAAASUVORK5CYII="
    )!

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

        func place(
            id: String,
            name: String,
            address: String,
            latitude: Double,
            longitude: Double
        ) -> PlaceSnapshot {
            PlaceSnapshot(
                id: UUID(uuidString: id)!,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                mapKitIdentifier: nil
            )
        }

        let day = Day(
            id: dayID,
            sequence: 1,
            date: date(2026, 11, 1),
            title: "Venue image QA",
            activities: [
                Activity(
                    id: lookAroundActivityID,
                    sequence: 1,
                    title: "Look Aroundを確認",
                    startTime: date(2026, 11, 1, 9, 0),
                    note: nil,
                    place: place(
                        id: "A11E0000-0000-4000-8000-000000000021",
                        name: "渋谷スクランブル交差点",
                        address: "東京都渋谷区道玄坂2丁目",
                        latitude: 35.6595,
                        longitude: 139.7005
                    )
                ),
                Activity(
                    id: wikimediaActivityID,
                    sequence: 2,
                    title: "Wikimediaを確認",
                    startTime: date(2026, 11, 1, 11, 0),
                    note: nil,
                    place: place(
                        id: "A11E0000-0000-4000-8000-000000000022",
                        name: "那覇空港",
                        address: "沖縄県那覇市鏡水150",
                        latitude: 26.2064,
                        longitude: 127.6460
                    )
                ),
                Activity(
                    id: userImageActivityID,
                    sequence: 3,
                    title: "ユーザー画像を確認",
                    startTime: date(2026, 11, 1, 13, 0),
                    note: nil,
                    place: place(
                        id: "A11E0000-0000-4000-8000-000000000023",
                        name: "沖縄美ら海水族館",
                        address: "沖縄県国頭郡本部町石川424",
                        latitude: 26.6943,
                        longitude: 127.8779
                    )
                )
            ]
        )

        return Trip(
            id: tripID,
            title: "Venue Image QA",
            dateRange: date(2026, 11, 1)...date(2026, 11, 1),
            timeZoneIdentifier: timeZone.identifier,
            days: [day]
        )
    }()
}
#endif
