import Foundation

enum TripDoctorSeverity: Int, Comparable, Hashable, Sendable {
    case info
    case warning

    static func < (lhs: TripDoctorSeverity, rhs: TripDoctorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TripDoctorIssueCode: String, Hashable, Sendable {
    case emptyItinerary
    case emptyDay
    case overloadedDay
    case noRestaurant
    case missingActivityDuration
    case highTravelTime
    case activityTimeOutOfOrder
    case duplicateActivityStartTime
    case participantsNotAssigned
    case duplicateParticipantNames
}

enum TripDoctorIssueTarget: Hashable, Sendable {
    case trip
    case day(Day.ID)
    case activity(Activity.ID, dayID: Day.ID)
    case participants

    var dayID: Day.ID? {
        switch self {
        case .day(let dayID), .activity(_, let dayID):
            dayID
        case .trip, .participants:
            nil
        }
    }

    var activityID: Activity.ID? {
        guard case .activity(let activityID, _) = self else { return nil }
        return activityID
    }
}

struct TripDoctorIssue: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let code: TripDoctorIssueCode
        let target: TripDoctorIssueTarget
    }

    let code: TripDoctorIssueCode
    let severity: TripDoctorSeverity
    let target: TripDoctorIssueTarget
    let message: String
    let suggestion: String?

    var id: ID { ID(code: code, target: target) }
}

struct TripDoctorReport: Equatable, Sendable {
    let issues: [TripDoctorIssue]

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    var infoCount: Int {
        issues.filter { $0.severity == .info }.count
    }

    func issues(forDay dayID: Day.ID) -> [TripDoctorIssue] {
        issues.filter { $0.target.dayID == dayID }
    }

    func issues(forActivity activityID: Activity.ID) -> [TripDoctorIssue] {
        issues.filter { $0.target.activityID == activityID }
    }

    var participantIssues: [TripDoctorIssue] {
        issues.filter { $0.target == .participants }
    }
}

enum TripDoctor {
    static let maximumActivitiesPerDay = 7
    static let maximumTravelMinutesPerDay = 180

    static func inspect(
        _ trip: Trip,
        participantNames: [String] = [],
        travelLegs: [TravelLeg] = []
    ) -> TripDoctorReport {
        var issues: [TripDoctorIssue] = []
        let orderedDays = trip.orderedDays
        let activityCount = orderedDays.reduce(0) { $0 + $1.activities.count }

        if activityCount == 0 {
            issues.append(
                TripDoctorIssue(
                    code: .emptyItinerary,
                    severity: .info,
                    target: .trip,
                    message: "旅行に予定がまだありません。",
                    suggestion: "最初のActivityを追加すると、旅程を確認できるようになります。"
                )
            )
        } else {
            for day in orderedDays where day.activities.isEmpty {
                issues.append(
                    TripDoctorIssue(
                        code: .emptyDay,
                        severity: .info,
                        target: .day(day.id),
                        message: "Day \(day.sequence)に予定がありません。",
                        suggestion: "予定がない日でなければ、Activityを追加してください。"
                    )
                )
            }
        }

        for day in orderedDays where !day.activities.isEmpty {
            let activities = day.orderedActivities
            if activities.count >= maximumActivitiesPerDay {
                issues.append(
                    TripDoctorIssue(
                        code: .overloadedDay,
                        severity: .warning,
                        target: .day(day.id),
                        message: "Day \(day.sequence)に予定が\(activities.count)件あります。",
                        suggestion: "移動や休憩の余裕があるか確認してください。"
                    )
                )
            }

            if activities.contains(where: { $0.category != nil }),
               !activities.contains(where: { $0.category == .restaurant }) {
                issues.append(
                    TripDoctorIssue(
                        code: .noRestaurant,
                        severity: .warning,
                        target: .day(day.id),
                        message: "Day \(day.sequence)に食事カテゴリの予定がありません。",
                        suggestion: "食事の予定を追加するか、食事にあたるActivityへカテゴリを設定してください。"
                    )
                )
            }

            for activity in activities where activity.category != nil && activity.durationMinutes == nil {
                issues.append(
                    TripDoctorIssue(
                        code: .missingActivityDuration,
                        severity: .warning,
                        target: .activity(activity.id, dayID: day.id),
                        message: "「\(activity.title)」に所要時間が設定されていません。",
                        suggestion: "滞在時間の目安を設定してください。"
                    )
                )
            }

            appendTravelLoadIssue(
                for: day,
                activities: activities,
                travelLegs: travelLegs,
                to: &issues
            )

            var previousTimedActivity: Activity?
            var activitiesByStartTime: [Date: [Activity]] = [:]

            for activity in activities {
                guard let startTime = activity.startTime else { continue }

                if let previousTimedActivity,
                   let previousStartTime = previousTimedActivity.startTime,
                   startTime < previousStartTime {
                    issues.append(
                        TripDoctorIssue(
                            code: .activityTimeOutOfOrder,
                            severity: .warning,
                            target: .activity(activity.id, dayID: day.id),
                            message: "「\(activity.title)」の開始時刻が表示順と一致していません。",
                            suggestion: "Activityの順序か開始時刻を確認してください。"
                        )
                    )
                }

                previousTimedActivity = activity
                activitiesByStartTime[startTime, default: []].append(activity)
            }

            for sameTimeActivities in activitiesByStartTime.values where sameTimeActivities.count > 1 {
                for activity in sameTimeActivities {
                    issues.append(
                        TripDoctorIssue(
                            code: .duplicateActivityStartTime,
                            severity: .warning,
                            target: .activity(activity.id, dayID: day.id),
                            message: "「\(activity.title)」は別のActivityと同じ開始時刻です。",
                            suggestion: "同時に行う予定でなければ、開始時刻を調整してください。"
                        )
                    )
                }
            }
        }

        if participantNames.isEmpty {
            issues.append(
                TripDoctorIssue(
                    code: .participantsNotAssigned,
                    severity: .info,
                    target: .participants,
                    message: "Participantが割り当てられていません。",
                    suggestion: "一人旅の場合も、自分をParticipantとして追加できます。"
                )
            )
        } else if containsDuplicateParticipantNames(participantNames) {
            issues.append(
                TripDoctorIssue(
                    code: .duplicateParticipantNames,
                    severity: .warning,
                    target: .participants,
                    message: "同じ名前のParticipantが複数割り当てられています。",
                    suggestion: "見分けられる表示名に変更してください。"
                )
            )
        }

        return TripDoctorReport(
            issues: issues.sorted {
                if $0.severity != $1.severity {
                    return $0.severity > $1.severity
                }
                return issueOrder($0, in: trip) < issueOrder($1, in: trip)
            }
        )
    }

    private static func containsDuplicateParticipantNames(_ names: [String]) -> Bool {
        var seen: Set<String> = []
        for name in names {
            let normalized = name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !normalized.isEmpty else { continue }
            if !seen.insert(normalized).inserted { return true }
        }
        return false
    }

    private static func appendTravelLoadIssue(
        for day: Day,
        activities: [Activity],
        travelLegs: [TravelLeg],
        to issues: inout [TripDoctorIssue]
    ) {
        let routeLegIDs = zip(activities, activities.dropFirst()).compactMap { from, to -> TravelLegID? in
            guard from.place != nil, to.place != nil else { return nil }
            return TravelLegID(fromActivityID: from.id, toActivityID: to.id)
        }
        guard !routeLegIDs.isEmpty else { return }

        let durationsByLeg = travelLegs
            .filter { $0.dayID == day.id }
            .reduce(into: [TravelLegID: Int]()) { result, leg in
                result[leg.id] = leg.effectiveDuration?.minutes
            }
        guard routeLegIDs.allSatisfy({ durationsByLeg[$0] != nil }) else { return }

        let total = routeLegIDs.reduce(0) { $0 + (durationsByLeg[$1] ?? 0) }
        guard total >= maximumTravelMinutesPerDay else { return }

        issues.append(
            TripDoctorIssue(
                code: .highTravelTime,
                severity: .warning,
                target: .day(day.id),
                message: "Day \(day.sequence)の移動見込みは\(formattedDuration(total))です。",
                suggestion: "移動順や滞在時間を見直して、余裕を確保してください。"
            )
        )
    }

    private static func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }

    private static func issueOrder(_ issue: TripDoctorIssue, in trip: Trip) -> Int {
        guard let dayID = issue.target.dayID,
              let dayIndex = trip.orderedDays.firstIndex(where: { $0.id == dayID }) else {
            return issue.target == .participants ? Int.max : -1
        }
        let activityOffset: Int
        if let activityID = issue.target.activityID,
           let activityIndex = trip.orderedDays[dayIndex].orderedActivities.firstIndex(where: { $0.id == activityID }) {
            activityOffset = activityIndex + 1
        } else {
            activityOffset = 0
        }
        return (dayIndex + 1) * 1_000 + activityOffset
    }
}
