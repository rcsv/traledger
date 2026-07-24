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

enum GuideOnlineDependency: Hashable, Sendable {
    case reservationLink(activityID: Activity.ID, reservationID: ReservationReference.ID)
    case travelEstimate(TravelLegID)
    case externalVenueImage(activityID: Activity.ID)
}

struct GuideOfflineReviewReport: Hashable, Sendable {
    let activityCount: Int
    let venueSnapshotCount: Int
    let userImageCount: Int
    let reservationCount: Int
    let onlineDependencies: [GuideOnlineDependency]
}

enum GuideOfflineReview {
    static func report(for trip: Trip) -> GuideOfflineReviewReport {
        let activities = trip.orderedDays.flatMap(\.orderedActivities)
        var dependencies: [GuideOnlineDependency] = []

        for activity in activities {
            if let reservation = activity.reservation, reservation.url != nil {
                dependencies.append(
                    .reservationLink(activityID: activity.id, reservationID: reservation.id)
                )
            }
            if activity.place?.imageData == nil, activity.place?.externalImage != nil {
                dependencies.append(.externalVenueImage(activityID: activity.id))
            }
        }

        let preferences = Dictionary(
            trip.travelLegPreferences.map { ($0.legID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let legs = TravelLegProjection.activeLegs(for: trip, preferences: preferences)
        dependencies.append(contentsOf: legs.compactMap { leg in
            leg.manualDurationMinutes == nil ? .travelEstimate(leg.id) : nil
        })

        return GuideOfflineReviewReport(
            activityCount: activities.count,
            venueSnapshotCount: activities.compactMap(\.place).count,
            userImageCount: activities.compactMap(\.place?.imageData).count,
            reservationCount: activities.compactMap(\.reservation).count,
            onlineDependencies: dependencies
        )
    }
}

struct ActivityReminderSchedule: Identifiable, Hashable, Sendable {
    let id: String
    let activityID: Activity.ID
    let fireDate: Date
    let activityTitle: String
}

enum ActivityReminderProjection {
    static func identifierPrefix(for tripID: Trip.ID) -> String {
        "tripmap.activity-reminder.\(tripID.uuidString)."
    }

    static func pendingSchedules(
        for trip: Trip,
        now: Date = Date()
    ) -> [ActivityReminderSchedule] {
        let prefix = identifierPrefix(for: trip.id)
        return trip.orderedDays
            .flatMap(\.orderedActivities)
            .compactMap { activity in
                guard activity.progress == .planned,
                      let startTime = activity.startTime,
                      let leadTime = activity.reminderLeadTime else {
                    return nil
                }
                let fireDate = startTime.addingTimeInterval(
                    -TimeInterval(leadTime.rawValue * 60)
                )
                guard fireDate > now else { return nil }
                return ActivityReminderSchedule(
                    id: prefix + activity.id.uuidString,
                    activityID: activity.id,
                    fireDate: fireDate,
                    activityTitle: activity.title
                )
            }
    }
}
