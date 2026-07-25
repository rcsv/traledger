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

struct TripSystemExperienceSummary: Hashable, Sendable {
    let tripID: Trip.ID
    let tripTitle: String
    let timeZoneIdentifier: String
    let daySequence: Int
    let nowActivity: Activity?
    let nextActivity: Activity?

    var spokenSummary: String {
        let nowText = nowActivity.map { "現在は \(activityDescription($0))" }
        let nextText = nextActivity.map { "次は \(activityDescription($0))" }
        switch (nowText, nextText) {
        case let (.some(nowText), .some(nextText)):
            return "\(tripTitle)。\(nowText)。\(nextText)です。"
        case let (.some(nowText), .none):
            return "\(tripTitle)。\(nowText)です。"
        case let (.none, .some(nextText)):
            return "\(tripTitle)。\(nextText)です。"
        case (.none, .none):
            return "\(tripTitle)の今日の予定は終了しています。"
        }
    }

    private func activityDescription(_ activity: Activity) -> String {
        var components: [String] = []
        if let startTime = activity.startTime {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
            formatter.dateFormat = "H時mm分"
            components.append(formatter.string(from: startTime))
        }
        components.append(activity.title)
        if let venueName = activity.place?.name {
            components.append(venueName)
        }
        return components.joined(separator: "、")
    }
}

enum TripSystemExperienceProjection {
    static func currentSummary(
        for trips: [Trip],
        now: Date = Date()
    ) -> TripSystemExperienceSummary? {
        trips.compactMap { trip -> TripSystemExperienceSummary? in
            guard let today = GuideTimelineProjection.todaySummary(for: trip, now: now),
                  today.nowActivity != nil || today.nextActivity != nil else {
                return nil
            }
            return TripSystemExperienceSummary(
                tripID: trip.id,
                tripTitle: trip.title,
                timeZoneIdentifier: trip.timeZoneIdentifier,
                daySequence: today.day.sequence,
                nowActivity: today.nowActivity,
                nextActivity: today.nextActivity
            )
        }
        .sorted(by: summaryOrder)
        .first
    }

    private static func summaryOrder(
        _ lhs: TripSystemExperienceSummary,
        _ rhs: TripSystemExperienceSummary
    ) -> Bool {
        if (lhs.nowActivity != nil) != (rhs.nowActivity != nil) {
            return lhs.nowActivity != nil
        }
        let lhsTime = lhs.nowActivity?.startTime ?? lhs.nextActivity?.startTime ?? .distantFuture
        let rhsTime = rhs.nowActivity?.startTime ?? rhs.nextActivity?.startTime ?? .distantFuture
        if lhsTime != rhsTime {
            return lhsTime < rhsTime
        }
        return lhs.tripID.uuidString < rhs.tripID.uuidString
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

struct MemoryActivityEntry: Identifiable, Hashable, Sendable {
    let dayID: Day.ID
    let daySequence: Int
    let activity: Activity

    var id: Activity.ID { activity.id }
    var hasRecord: Bool {
        activity.memoryPhotoData != nil || activity.reflection != nil
    }
}

struct MemoryTripSummary: Hashable, Sendable {
    let totalActivityCount: Int
    let visitedCount: Int
    let skippedCount: Int
    let recordedCount: Int
    let entries: [MemoryActivityEntry]
}

enum MemoryProjection {
    static func summary(for trip: Trip) -> MemoryTripSummary {
        let allEntries = trip.orderedDays.flatMap { day in
            day.orderedActivities.map {
                MemoryActivityEntry(
                    dayID: day.id,
                    daySequence: day.sequence,
                    activity: $0
                )
            }
        }
        let visited = allEntries.filter { $0.activity.progress == .completed }
        return MemoryTripSummary(
            totalActivityCount: allEntries.count,
            visitedCount: visited.count,
            skippedCount: allEntries.filter { $0.activity.progress == .skipped }.count,
            recordedCount: visited.filter(\.hasRecord).count,
            entries: visited
        )
    }
}

struct ActivityCategoryAnalysis: Identifiable, Hashable, Sendable {
    let category: ActivityCategory
    let count: Int
    let fraction: Double

    var id: ActivityCategory { category }
}

struct ActivityAnalysisSummary: Hashable, Sendable {
    let totalActivityCount: Int
    let unclassifiedCount: Int
    let unclassifiedFraction: Double
    let categories: [ActivityCategoryAnalysis]
}

enum ActivityAnalysisProjection {
    static func summary(for trip: Trip) -> ActivityAnalysisSummary {
        summary(for: [trip])
    }

    static func summary(for trips: [Trip]) -> ActivityAnalysisSummary {
        let activities = trips
            .flatMap(\.orderedDays)
            .flatMap(\.orderedActivities)
            .filter { $0.progress != .skipped }
        let total = activities.count
        let counts = Dictionary(
            grouping: activities.compactMap(\.category),
            by: { $0 }
        )
        .mapValues(\.count)
        let categoryOrder = Dictionary(
            uniqueKeysWithValues: ActivityCategory.allCases.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let categories = counts
            .map { category, count in
                ActivityCategoryAnalysis(
                    category: category,
                    count: count,
                    fraction: fraction(count, of: total)
                )
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return categoryOrder[$0.category, default: .max]
                    < categoryOrder[$1.category, default: .max]
            }
        let unclassifiedCount = activities.filter {
            $0.category == nil
        }.count
        return ActivityAnalysisSummary(
            totalActivityCount: total,
            unclassifiedCount: unclassifiedCount,
            unclassifiedFraction: fraction(unclassifiedCount, of: total),
            categories: categories
        )
    }

    private static func fraction(_ count: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }
}

struct LibraryUpcomingReservationSummary: Identifiable, Hashable, Sendable {
    let tripID: Trip.ID
    let tripTitle: String
    let timeZoneIdentifier: String
    let reservation: UpcomingReservationSummary

    var id: ReservationReference.ID { reservation.id }
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
    }
}

struct LibraryDashboardSummary: Hashable, Sendable {
    let readableTripCount: Int
    let assignedParticipantCount: Int
    let activityAnalysis: ActivityAnalysisSummary
    let reservationCount: Int
    let reservationKinds: [ReservationKindSummary]
    let unscheduledReservationCount: Int
    let nextReservation: LibraryUpcomingReservationSummary?

    var leadingActivityCategory: LibraryActivityCategoryLeader? {
        let categorized = activityAnalysis.categories.first.map {
            LibraryActivityCategoryLeader(
                category: $0.category,
                count: $0.count,
                fraction: $0.fraction
            )
        }
        let unclassified = activityAnalysis.unclassifiedCount > 0
            ? LibraryActivityCategoryLeader(
                category: nil,
                count: activityAnalysis.unclassifiedCount,
                fraction: activityAnalysis.unclassifiedFraction
            )
            : nil
        guard let unclassified else { return categorized }
        guard let categorized else { return unclassified }
        return categorized.count >= unclassified.count
            ? categorized
            : unclassified
    }
}

struct LibraryActivityCategoryLeader: Hashable, Sendable {
    let category: ActivityCategory?
    let count: Int
    let fraction: Double

    var displayName: String { category?.displayName ?? "未分類" }
    var systemImage: String { category?.systemImage ?? "questionmark.circle" }
}

enum LibraryDashboardProjection {
    static func summary(
        for trips: [Trip],
        assignedParticipantIDs: [UUID],
        now: Date = Date()
    ) -> LibraryDashboardSummary {
        let reservationSummaries = trips.map {
            (
                trip: $0,
                summary: ReservationSummaryProjection.summary(
                    for: $0,
                    now: now
                )
            )
        }
        let kindCounts = reservationSummaries
            .flatMap(\.summary.kinds)
            .reduce(into: [ReservationKind: Int]()) { counts, item in
                counts[item.kind, default: 0] += item.count
            }
        let nextReservation = reservationSummaries
            .compactMap { item -> LibraryUpcomingReservationSummary? in
                item.summary.nextReservation.map {
                    LibraryUpcomingReservationSummary(
                        tripID: item.trip.id,
                        tripTitle: item.trip.title,
                        timeZoneIdentifier: item.trip.timeZoneIdentifier,
                        reservation: $0
                    )
                }
            }
            .sorted(by: nextReservationOrder)
            .first

        return LibraryDashboardSummary(
            readableTripCount: trips.count,
            assignedParticipantCount: Set(assignedParticipantIDs).count,
            activityAnalysis: ActivityAnalysisProjection.summary(for: trips),
            reservationCount: reservationSummaries.reduce(0) {
                $0 + $1.summary.totalCount
            },
            reservationKinds: ReservationKind.allCases.compactMap { kind in
                kindCounts[kind].map {
                    ReservationKindSummary(kind: kind, count: $0)
                }
            },
            unscheduledReservationCount: reservationSummaries.reduce(0) {
                $0 + $1.summary.unscheduledCount
            },
            nextReservation: nextReservation
        )
    }

    private static func nextReservationOrder(
        _ lhs: LibraryUpcomingReservationSummary,
        _ rhs: LibraryUpcomingReservationSummary
    ) -> Bool {
        if lhs.reservation.startTime != rhs.reservation.startTime {
            return lhs.reservation.startTime < rhs.reservation.startTime
        }
        if lhs.tripTitle != rhs.tripTitle {
            return lhs.tripTitle.localizedStandardCompare(rhs.tripTitle)
                == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct ReservationKindSummary: Identifiable, Hashable, Sendable {
    let kind: ReservationKind
    let count: Int

    var id: ReservationKind { kind }
}

struct UpcomingReservationSummary: Identifiable, Hashable, Sendable {
    let reservationID: ReservationReference.ID
    let activityID: Activity.ID
    let dayID: Day.ID
    let daySequence: Int
    let activityTitle: String
    let reservationTitle: String
    let kind: ReservationKind
    let startTime: Date

    var id: ReservationReference.ID { reservationID }
}

struct ReservationSummary: Hashable, Sendable {
    let totalCount: Int
    let unscheduledCount: Int
    let kinds: [ReservationKindSummary]
    let nextReservation: UpcomingReservationSummary?
}

enum ReservationSummaryProjection {
    static func summary(
        for trip: Trip,
        now: Date = Date()
    ) -> ReservationSummary {
        let entries = trip.orderedDays.flatMap { day in
            day.orderedActivities.compactMap { activity in
                activity.reservation.map {
                    (
                        day: day,
                        activity: activity,
                        reservation: $0
                    )
                }
            }
        }
        let counts = Dictionary(
            grouping: entries.map(\.reservation.kind),
            by: { $0 }
        )
        .mapValues(\.count)
        let kinds = ReservationKind.allCases.compactMap { kind in
            counts[kind].map {
                ReservationKindSummary(kind: kind, count: $0)
            }
        }
        let next = entries
            .filter {
                $0.activity.progress == .planned
                    && ($0.activity.startTime ?? .distantPast) >= now
            }
            .sorted(by: upcomingOrder)
            .first
            .flatMap { entry -> UpcomingReservationSummary? in
                guard let startTime = entry.activity.startTime else {
                    return nil
                }
                return UpcomingReservationSummary(
                    reservationID: entry.reservation.id,
                    activityID: entry.activity.id,
                    dayID: entry.day.id,
                    daySequence: entry.day.sequence,
                    activityTitle: entry.activity.title,
                    reservationTitle: entry.reservation.title,
                    kind: entry.reservation.kind,
                    startTime: startTime
                )
            }
        return ReservationSummary(
            totalCount: entries.count,
            unscheduledCount: entries.filter {
                $0.activity.startTime == nil
            }.count,
            kinds: kinds,
            nextReservation: next
        )
    }

    private static func upcomingOrder(
        _ lhs: (
            day: Day,
            activity: Activity,
            reservation: ReservationReference
        ),
        _ rhs: (
            day: Day,
            activity: Activity,
            reservation: ReservationReference
        )
    ) -> Bool {
        let lhsStart = lhs.activity.startTime ?? .distantFuture
        let rhsStart = rhs.activity.startTime ?? .distantFuture
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }
        if lhs.day.sequence != rhs.day.sequence {
            return lhs.day.sequence < rhs.day.sequence
        }
        if lhs.activity.sequence != rhs.activity.sequence {
            return lhs.activity.sequence < rhs.activity.sequence
        }
        return lhs.activity.id.uuidString < rhs.activity.id.uuidString
    }
}
