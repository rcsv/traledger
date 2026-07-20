import Foundation

enum TripLibraryScope: String, CaseIterable, Identifiable, Sendable {
    case upcoming
    case past
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .upcoming: "Upcoming"
        case .past: "Past"
        case .all: "すべて"
        }
    }
}

enum TripTimelineGroup: String, CaseIterable, Identifiable, Sendable {
    case ongoing
    case upcoming
    case past

    var id: Self { self }

    var title: String {
        switch self {
        case .ongoing: "進行中"
        case .upcoming: "Upcoming"
        case .past: "Past"
        }
    }
}

struct TripTimelineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: LocalDate
    let endDate: LocalDate
    let timeZoneIdentifier: String
}

enum TripTimeline {
    static func grouped(
        entries: [TripTimelineEntry],
        now: Date = Date()
    ) -> [TripTimelineGroup: [TripTimelineEntry]] {
        var groups: [TripTimelineGroup: [TripTimelineEntry]] = [:]
        for entry in entries {
            let timeZone = TimeZone(identifier: entry.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
            let today = LocalDate(date: now, timeZone: timeZone)
            let group: TripTimelineGroup
            if entry.endDate.code < today.code {
                group = .past
            } else if entry.startDate.code <= today.code {
                group = .ongoing
            } else {
                group = .upcoming
            }
            groups[group, default: []].append(entry)
        }

        groups[.ongoing]?.sort { $0.endDate.code < $1.endDate.code }
        groups[.upcoming]?.sort { $0.startDate.code < $1.startDate.code }
        groups[.past]?.sort { $0.endDate.code > $1.endDate.code }
        return groups
    }

    static func visibleGroups(for scope: TripLibraryScope) -> [TripTimelineGroup] {
        switch scope {
        case .upcoming: [.ongoing, .upcoming]
        case .past: [.past]
        case .all: [.ongoing, .upcoming, .past]
        }
    }
}
