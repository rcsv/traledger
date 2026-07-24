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

enum GuideActivityTemporalRole: String, Hashable, Sendable {
    case now
    case next

    var displayName: String {
        switch self {
        case .now: "Now"
        case .next: "Next"
        }
    }

    var systemImage: String {
        switch self {
        case .now: "location.fill"
        case .next: "arrow.forward.circle.fill"
        }
    }
}

struct GuideTodaySummary: Hashable, Sendable {
    let day: Day
    let nowActivity: Activity?
    let nextActivity: Activity?
    let remainingActivityCount: Int

    var rolesByActivityID: [Activity.ID: GuideActivityTemporalRole] {
        var roles: [Activity.ID: GuideActivityTemporalRole] = [:]
        if let nowActivity {
            roles[nowActivity.id] = .now
        }
        if let nextActivity {
            roles[nextActivity.id] = .next
        }
        return roles
    }
}

enum GuideTimelineProjection {
    static func todaySummary(
        for trip: Trip,
        now: Date = Date()
    ) -> GuideTodaySummary? {
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        let today = LocalDate(date: now, timeZone: timeZone)
        guard let day = trip.orderedDays.first(where: {
            LocalDate(date: $0.date, timeZone: timeZone) == today
        }) else {
            return nil
        }

        let planned = day.orderedActivities.filter { $0.progress == .planned }
        let current = planned
            .compactMap { activity -> (activity: Activity, start: Date)? in
                guard let start = activity.startTime,
                      let durationMinutes = activity.durationMinutes,
                      durationMinutes > 0,
                      start <= now,
                      now < start.addingTimeInterval(TimeInterval(durationMinutes * 60)) else {
                    return nil
                }
                return (activity, start)
            }
            .sorted(by: temporalOrder)
            .first?
            .activity

        let next = planned
            .compactMap { activity -> (activity: Activity, start: Date)? in
                guard activity.id != current?.id,
                      let start = activity.startTime,
                      start > now else {
                    return nil
                }
                return (activity, start)
            }
            .sorted(by: temporalOrder)
            .first?
            .activity

        return GuideTodaySummary(
            day: day,
            nowActivity: current,
            nextActivity: next,
            remainingActivityCount: planned.count
        )
    }

    private static func temporalOrder(
        _ lhs: (activity: Activity, start: Date),
        _ rhs: (activity: Activity, start: Date)
    ) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        return lhs.activity.sequence < rhs.activity.sequence
    }
}
