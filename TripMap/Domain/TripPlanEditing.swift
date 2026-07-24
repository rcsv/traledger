import Foundation

enum TripPlanEditingError: LocalizedError, Equatable {
    case sourceDayNotFound
    case targetDayNotFound
    case activityNotFound
    case targetIncludesSource
    case sameDay
    case blankActivityTitle
    case invalidActivityDuration
    case invalidTimeZone

    var errorDescription: String? {
        switch self {
        case .sourceDayNotFound: "コピー元のDayが見つかりません。"
        case .targetDayNotFound: "コピー先のDayが見つかりません。"
        case .activityNotFound: "予定が見つかりません。"
        case .targetIncludesSource: "コピー元と同じDayにはコピーできません。"
        case .sameDay: "同じDay同士は入れ替えできません。"
        case .blankActivityTitle: "予定の名前を入力してください。"
        case .invalidActivityDuration: "所要時間は1分から24時間の範囲で入力してください。"
        case .invalidTimeZone: "タイムゾーンを確認してください。"
        }
    }
}

enum TripPlanEditor {
    static func changeTimeZone(in trip: Trip, to identifier: String) throws -> Trip {
        guard let currentTimeZone = TimeZone(identifier: trip.timeZoneIdentifier),
              let newTimeZone = TimeZone(identifier: identifier) else {
            throw TripPlanEditingError.invalidTimeZone
        }
        guard currentTimeZone.identifier != newTimeZone.identifier else { return trip }

        func rebasedDate(_ date: Date) -> Date? {
            LocalDate(date: date, timeZone: currentTimeZone).date(in: newTimeZone)
        }
        guard let startDate = rebasedDate(trip.dateRange.lowerBound),
              let endDate = rebasedDate(trip.dateRange.upperBound) else {
            throw TripPlanEditingError.invalidTimeZone
        }

        var copy = trip
        copy.timeZoneIdentifier = newTimeZone.identifier
        copy.dateRange = startDate...endDate
        copy.days = trip.days.compactMap { day in
            guard let localDay = LocalDate(date: day.date, timeZone: currentTimeZone).date(in: newTimeZone) else {
                return nil
            }
            var updatedDay = day
            updatedDay.date = localDay
            updatedDay.activities = day.activities.map { activity in
                var updatedActivity = activity
                if let startTime = activity.startTime {
                    let localTime = LocalTime(date: startTime, timeZone: currentTimeZone)
                    updatedActivity.startTime = localTime.date(
                        on: LocalDate(date: day.date, timeZone: currentTimeZone),
                        in: newTimeZone
                    )
                }
                return updatedActivity
            }
            return updatedDay
        }
        guard copy.days.count == trip.days.count else { throw TripPlanEditingError.invalidTimeZone }
        return copy
    }

    static func appendActivity(
        in trip: Trip,
        to dayID: Day.ID,
        title: String,
        startTime: Date?,
        category: ActivityCategory? = nil,
        durationMinutes: Int? = nil
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { $0.id == dayID }) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw TripPlanEditingError.blankActivityTitle }

        var copy = trip
        let sequence = (copy.days[dayIndex].activities.map(\.sequence).max() ?? 0) + 1
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let normalizedStartTime = time(
            on: copy.days[dayIndex].date,
            matching: startTime,
            timeZone: timeZone
        )
        try validate(durationMinutes: durationMinutes)
        copy.days[dayIndex].activities.append(
            Activity(
                id: UUID(),
                sequence: sequence,
                title: trimmedTitle,
                startTime: normalizedStartTime,
                category: category,
                durationMinutes: durationMinutes,
                note: nil,
                place: nil
            )
        )
        return copy
    }

    static func updateActivity(
        in trip: Trip,
        activityID: Activity.ID,
        title: String,
        startTime: Date?,
        category: ActivityCategory? = nil,
        durationMinutes: Int? = nil,
        note: String?,
        place: PlaceSnapshot?
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw TripPlanEditingError.blankActivityTitle }
        try validate(durationMinutes: durationMinutes)

        var copy = trip
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        copy.days[dayIndex].activities[activityIndex].title = trimmedTitle
        copy.days[dayIndex].activities[activityIndex].startTime = time(
            on: copy.days[dayIndex].date,
            matching: startTime,
            timeZone: timeZone
        )
        copy.days[dayIndex].activities[activityIndex].category = category
        copy.days[dayIndex].activities[activityIndex].durationMinutes = durationMinutes
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.days[dayIndex].activities[activityIndex].note = trimmedNote?.isEmpty == false ? trimmedNote : nil
        copy.days[dayIndex].activities[activityIndex].place = place
        return copy
    }

    static func setPlace(
        in trip: Trip,
        for activityID: Activity.ID,
        place: PlaceSnapshot?
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].place = place
        return copy
    }

    static func setActivityProgress(
        in trip: Trip,
        activityID: Activity.ID,
        progress: ActivityProgress,
        at changeDate: Date = Date()
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        guard trip.days[dayIndex].activities[activityIndex].progress != progress else {
            return trip
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].progress = progress
        copy.days[dayIndex].activities[activityIndex].progressUpdatedAt =
            progress == .planned ? nil : changeDate
        return copy
    }

    static func deleteActivity(in trip: Trip, activityID: Activity.ID) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }) else {
            throw TripPlanEditingError.activityNotFound
        }

        var copy = trip
        copy.days[dayIndex].activities.removeAll { $0.id == activityID }
        copy.days[dayIndex].activities = copy.days[dayIndex].orderedActivities.enumerated().map { index, activity in
            var updated = activity
            updated.sequence = index + 1
            return updated
        }
        return copy
    }

    static func moveActivity(
        in trip: Trip,
        dayID: Day.ID,
        activityID: Activity.ID,
        relativeTo targetActivityID: Activity.ID
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { $0.id == dayID }) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        let ordered = trip.days[dayIndex].orderedActivities
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == activityID }),
              let targetIndex = ordered.firstIndex(where: { $0.id == targetActivityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        guard sourceIndex != targetIndex else { return trip }

        var reordered = ordered
        let movedActivity = reordered.remove(at: sourceIndex)
        guard let adjustedTargetIndex = reordered.firstIndex(where: { $0.id == targetActivityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        let insertionIndex = sourceIndex < targetIndex
            ? adjustedTargetIndex + 1
            : adjustedTargetIndex
        reordered.insert(movedActivity, at: insertionIndex)

        var copy = trip
        copy.days[dayIndex].activities = reordered.enumerated().map { index, activity in
            var updated = activity
            updated.sequence = index + 1
            return updated
        }
        return copy
    }

    static func replicateDayActivities(
        in trip: Trip,
        from sourceDayID: Day.ID,
        to targetDayIDs: Set<Day.ID>
    ) throws -> Trip {
        guard let source = trip.days.first(where: { $0.id == sourceDayID }) else {
            throw TripPlanEditingError.sourceDayNotFound
        }
        guard !targetDayIDs.contains(sourceDayID) else {
            throw TripPlanEditingError.targetIncludesSource
        }
        guard targetDayIDs.allSatisfy({ id in trip.days.contains(where: { $0.id == id }) }) else {
            throw TripPlanEditingError.targetDayNotFound
        }

        var copy = trip
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        for index in copy.days.indices where targetDayIDs.contains(copy.days[index].id) {
            let firstSequence = (copy.days[index].activities.map(\.sequence).max() ?? 0) + 1
            let replicas = source.orderedActivities.enumerated().map { offset, activity in
                Activity(
                    id: UUID(),
                    sequence: firstSequence + offset,
                    title: activity.title,
                    startTime: time(on: copy.days[index].date, matching: activity.startTime, timeZone: timeZone),
                    category: activity.category,
                    durationMinutes: activity.durationMinutes,
                    note: activity.note,
                    place: activity.place.map {
                        PlaceSnapshot(
                            id: UUID(),
                            name: $0.name,
                            address: $0.address,
                            latitude: $0.latitude,
                            longitude: $0.longitude,
                            mapKitIdentifier: $0.mapKitIdentifier,
                            imageData: $0.imageData
                        )
                    }
                )
            }
            copy.days[index].activities.append(contentsOf: replicas)
        }
        return copy
    }

    static func swapDayPlans(in trip: Trip, firstDayID: Day.ID, secondDayID: Day.ID) throws -> Trip {
        guard firstDayID != secondDayID else { throw TripPlanEditingError.sameDay }
        guard let firstIndex = trip.days.firstIndex(where: { $0.id == firstDayID }),
              let secondIndex = trip.days.firstIndex(where: { $0.id == secondDayID }) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        var copy = trip
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let firstPayload = (copy.days[firstIndex].title, copy.days[firstIndex].activities)
        copy.days[firstIndex].title = copy.days[secondIndex].title
        copy.days[firstIndex].activities = copy.days[secondIndex].activities.map {
            activity(on: copy.days[firstIndex].date, matching: $0, timeZone: timeZone)
        }
        copy.days[secondIndex].title = firstPayload.0
        copy.days[secondIndex].activities = firstPayload.1.map {
            activity(on: copy.days[secondIndex].date, matching: $0, timeZone: timeZone)
        }
        return copy
    }

    private static func activity(on dayDate: Date, matching activity: Activity, timeZone: TimeZone) -> Activity {
        var copy = activity
        copy.startTime = time(on: dayDate, matching: activity.startTime, timeZone: timeZone)
        return copy
    }

    private static func time(on dayDate: Date, matching sourceTime: Date?, timeZone: TimeZone) -> Date? {
        guard let sourceTime else {
            return sourceTime
        }
        let localDate = LocalDate(date: dayDate, timeZone: timeZone)
        let localTime = LocalTime(date: sourceTime, timeZone: timeZone)
        return localTime.date(on: localDate, in: timeZone)
    }

    private static func validate(durationMinutes: Int?) throws {
        guard durationMinutes.map({ (1...1_440).contains($0) }) ?? true else {
            throw TripPlanEditingError.invalidActivityDuration
        }
    }
}
