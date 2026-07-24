import Foundation

enum TripPlanEditingError: LocalizedError, Equatable {
    case sourceDayNotFound
    case targetDayNotFound
    case activityNotFound
    case activityAlreadyExists
    case activityChangedDay
    case targetIncludesSource
    case sameDay
    case blankActivityTitle
    case invalidActivityDuration
    case invalidTravelLegDuration
    case invalidTravelLegReference
    case invalidReservationTitle
    case invalidReservationURL
    case reminderRequiresStartTime
    case memoryRequiresCompletedActivity
    case invalidReflection
    case invalidTimeZone
    case placeNotFound
    case placeChanged

    var errorDescription: String? {
        switch self {
        case .sourceDayNotFound: "コピー元のDayが見つかりません。"
        case .targetDayNotFound: "コピー先のDayが見つかりません。"
        case .activityNotFound: "予定が見つかりません。"
        case .activityAlreadyExists: "同じ予定がすでに追加されています。"
        case .activityChangedDay: "予定の所属日が変更されたため、操作を中止しました。"
        case .targetIncludesSource: "コピー元と同じDayにはコピーできません。"
        case .sameDay: "同じDay同士は入れ替えできません。"
        case .blankActivityTitle: "予定の名前を入力してください。"
        case .invalidActivityDuration: "所要時間は1分から24時間の範囲で入力してください。"
        case .invalidTravelLegDuration: "移動時間は1分から23時間59分の範囲で入力してください。"
        case .invalidTravelLegReference: "編集対象の移動区間が見つかりません。"
        case .invalidReservationTitle: "予約名を入力してください。"
        case .invalidReservationURL: "予約URLにはHTTPSのリンクを入力してください。"
        case .reminderRequiresStartTime: "リマインダーを設定するには開始時刻が必要です。"
        case .memoryRequiresCompletedActivity: "訪問済みにしてから思い出を記録してください。"
        case .invalidReflection: "感想は500文字以内で入力してください。"
        case .invalidTimeZone: "タイムゾーンを確認してください。"
        case .placeNotFound: "場所が見つかりません。"
        case .placeChanged: "場所が変更されたため、画像の更新を中止しました。"
        }
    }
}

enum ActivityPlaceMutation: Equatable, Sendable {
    case unchanged
    case replace(expectedPlaceID: PlaceSnapshot.ID?, place: PlaceSnapshot?)

    func resolving(current: PlaceSnapshot?) throws -> PlaceSnapshot? {
        switch self {
        case .unchanged:
            return current
        case let .replace(expectedPlaceID, place):
            guard current?.id == expectedPlaceID else {
                throw TripPlanEditingError.placeChanged
            }
            return place
        }
    }
}

struct PlanActivityMutation: Equatable, Sendable {
    let activityID: Activity.ID
    let title: String
    let startTime: Date?
    let category: ActivityCategory?
    let durationMinutes: Int?
    let note: String?
    let place: ActivityPlaceMutation
}

struct GuideActivityMutation: Equatable, Sendable {
    let activityID: Activity.ID
    let startTime: Date?
    let note: String?
    let place: ActivityPlaceMutation
    let progress: ActivityProgress
    let progressChangedAt: Date
    let reservation: ReservationReference?
    let reminderLeadTime: ActivityReminderLeadTime?
}

struct TravelLegPreferenceMutation: Equatable, Sendable {
    let legID: TravelLegID
    let transportType: TravelTransportType
    let manualDurationMinutes: Int?
    let note: String?
}

struct AppendActivityMutation: Equatable, Sendable {
    let dayID: Day.ID
    let activityID: Activity.ID
    let title: String
    let startTime: Date?
    let category: ActivityCategory?
    let durationMinutes: Int?
}

struct DeleteActivityMutation: Equatable, Sendable {
    let dayID: Day.ID
    let activityID: Activity.ID
}

enum ActivityMovePlacement: Equatable, Sendable {
    case before
    case after
}

struct MoveActivityMutation: Equatable, Sendable {
    let dayID: Day.ID
    let activityID: Activity.ID
    let anchorActivityID: Activity.ID
    let placement: ActivityMovePlacement
}

struct DayReplicationTargetMutation: Equatable, Sendable {
    let dayID: Day.ID
    let activityIDs: [Activity.ID]
    let placeIDs: [PlaceSnapshot.ID?]
}

struct ReplicateDayActivitiesMutation: Equatable, Sendable {
    let sourceDayID: Day.ID
    let expectedSourceActivityIDs: [Activity.ID]
    let targets: [DayReplicationTargetMutation]
}

struct SwapDayPlansMutation: Equatable, Sendable {
    let firstDayID: Day.ID
    let expectedFirstActivityIDs: [Activity.ID]
    let secondDayID: Day.ID
    let expectedSecondActivityIDs: [Activity.ID]
}

enum TripMutation: Equatable, Sendable {
    case setCoverImage(Data?)
    case setDefaultCurrencyCode(String)
    case changeTimeZone(String)
    case editPlanActivity(PlanActivityMutation)
    case editGuideActivity(GuideActivityMutation)
    case setTravelLegPreference(TravelLegPreferenceMutation)
    case appendActivity(AppendActivityMutation)
    case deleteActivity(DeleteActivityMutation)
    case moveActivity(MoveActivityMutation)
    case replicateDayActivities(ReplicateDayActivitiesMutation)
    case swapDayPlans(SwapDayPlansMutation)
    case setVenueUserImage(
        activityID: Activity.ID,
        placeID: PlaceSnapshot.ID,
        imageData: Data?
    )
    case setExternalVenueImage(
        activityID: Activity.ID,
        placeID: PlaceSnapshot.ID,
        image: ExternalPlaceImage?
    )
    case setActivityProgress(
        activityID: Activity.ID,
        progress: ActivityProgress,
        changedAt: Date
    )
    case recordActivityMemory(
        activityID: Activity.ID,
        photoData: Data?,
        reflection: String?,
        completedAt: Date
    )

    func applying(to trip: Trip) throws -> Trip {
        switch self {
        case .setCoverImage(let imageData):
            var copy = trip
            copy.coverImageData = imageData
            return copy
        case .setDefaultCurrencyCode(let currencyCode):
            var copy = trip
            copy.defaultCurrencyCode = currencyCode
            return copy
        case .changeTimeZone(let identifier):
            return try TripPlanEditor.changeTimeZone(in: trip, to: identifier)
        case .editPlanActivity(let edit):
            let activity = try activity(in: trip, id: edit.activityID)
            return try TripPlanEditor.updateActivity(
                in: trip,
                activityID: edit.activityID,
                title: edit.title,
                startTime: edit.startTime,
                category: edit.category,
                durationMinutes: edit.durationMinutes,
                note: edit.note,
                place: try edit.place.resolving(current: activity.place)
            )
        case .editGuideActivity(let edit):
            let activity = try activity(in: trip, id: edit.activityID)
            let withDetails = try TripPlanEditor.updateActivity(
                in: trip,
                activityID: edit.activityID,
                title: activity.title,
                startTime: edit.startTime,
                category: activity.category,
                durationMinutes: activity.durationMinutes,
                note: edit.note,
                place: try edit.place.resolving(current: activity.place)
            )
            let withProgress = try TripPlanEditor.setActivityProgress(
                in: withDetails,
                activityID: edit.activityID,
                progress: edit.progress,
                at: edit.progressChangedAt
            )
            let withReservation = try TripPlanEditor.setReservation(
                in: withProgress,
                activityID: edit.activityID,
                reservation: edit.reservation
            )
            return try TripPlanEditor.setActivityReminder(
                in: withReservation,
                activityID: edit.activityID,
                leadTime: edit.reminderLeadTime
            )
        case .setTravelLegPreference(let preference):
            return try TripPlanEditor.setTravelLegPreference(
                in: trip,
                legID: preference.legID,
                transportType: preference.transportType,
                manualDurationMinutes: preference.manualDurationMinutes,
                note: preference.note
            )
        case .appendActivity(let activity):
            return try TripPlanEditor.appendActivity(
                in: trip,
                to: activity.dayID,
                activityID: activity.activityID,
                title: activity.title,
                startTime: activity.startTime,
                category: activity.category,
                durationMinutes: activity.durationMinutes
            )
        case .deleteActivity(let activity):
            guard let currentDay = trip.days.first(
                where: {
                    $0.activities.contains(
                        where: { $0.id == activity.activityID }
                    )
                }
            ) else {
                throw TripPlanEditingError.activityNotFound
            }
            guard currentDay.id == activity.dayID else {
                throw TripPlanEditingError.activityChangedDay
            }
            return try TripPlanEditor.deleteActivity(
                in: trip,
                activityID: activity.activityID
            )
        case .moveActivity(let activity):
            return try TripPlanEditor.positionActivity(
                in: trip,
                dayID: activity.dayID,
                activityID: activity.activityID,
                relativeTo: activity.anchorActivityID,
                placement: activity.placement
            )
        case .replicateDayActivities(let replication):
            return try TripPlanEditor.replicateDayActivities(
                in: trip,
                mutation: replication
            )
        case .swapDayPlans(let swap):
            return try TripPlanEditor.swapDayPlans(
                in: trip,
                mutation: swap
            )
        case let .setVenueUserImage(activityID, placeID, imageData):
            return try updatingPlace(
                in: trip,
                activityID: activityID,
                expectedPlaceID: placeID
            ) { place in
                place.imageData = imageData
            }
        case let .setExternalVenueImage(activityID, placeID, image):
            return try updatingPlace(
                in: trip,
                activityID: activityID,
                expectedPlaceID: placeID
            ) { place in
                place.externalImage = image
            }
        case let .setActivityProgress(activityID, progress, changedAt):
            return try TripPlanEditor.setActivityProgress(
                in: trip,
                activityID: activityID,
                progress: progress,
                at: changedAt
            )
        case let .recordActivityMemory(activityID, photoData, reflection, completedAt):
            let completed = try TripPlanEditor.setActivityProgress(
                in: trip,
                activityID: activityID,
                progress: .completed,
                at: completedAt
            )
            return try TripPlanEditor.setActivityMemory(
                in: completed,
                activityID: activityID,
                photoData: photoData,
                reflection: reflection
            )
        }
    }

    private func activity(in trip: Trip, id activityID: Activity.ID) throws -> Activity {
        guard let activity = trip.days
            .flatMap(\.activities)
            .first(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        return activity
    }

    private func updatingPlace(
        in trip: Trip,
        activityID: Activity.ID,
        expectedPlaceID: PlaceSnapshot.ID,
        update: (inout PlaceSnapshot) -> Void
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(
            where: { $0.id == activityID }
        ) else {
            throw TripPlanEditingError.activityNotFound
        }
        guard var place = trip.days[dayIndex].activities[activityIndex].place else {
            throw TripPlanEditingError.placeNotFound
        }
        guard place.id == expectedPlaceID else {
            throw TripPlanEditingError.placeChanged
        }
        update(&place)
        var copy = trip
        copy.days[dayIndex].activities[activityIndex].place = place
        return copy
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
        activityID: Activity.ID = UUID(),
        title: String,
        startTime: Date?,
        category: ActivityCategory? = nil,
        durationMinutes: Int? = nil
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { $0.id == dayID }) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        guard !trip.days
            .flatMap(\.activities)
            .contains(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityAlreadyExists
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
                id: activityID,
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
        let activity = trip.days[dayIndex].activities[activityIndex]
        guard progress == .completed
            || (activity.memoryPhotoData == nil && activity.reflection == nil) else {
            throw TripPlanEditingError.memoryRequiresCompletedActivity
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].progress = progress
        copy.days[dayIndex].activities[activityIndex].progressUpdatedAt =
            progress == .planned ? nil : changeDate
        return copy
    }

    static func setReservation(
        in trip: Trip,
        activityID: Activity.ID,
        reservation: ReservationReference?
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }

        var normalizedReservation = reservation
        if var reservation {
            reservation.title = reservation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reservation.title.isEmpty else {
                throw TripPlanEditingError.invalidReservationTitle
            }
            reservation.confirmationCode = normalizedOptionalText(reservation.confirmationCode)
            reservation.note = normalizedOptionalText(reservation.note)
            if let url = reservation.url,
               (url.scheme?.lowercased() != "https" || url.host == nil) {
                throw TripPlanEditingError.invalidReservationURL
            }
            normalizedReservation = reservation
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].reservation = normalizedReservation
        return copy
    }

    static func setActivityReminder(
        in trip: Trip,
        activityID: Activity.ID,
        leadTime: ActivityReminderLeadTime?
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        guard leadTime == nil || trip.days[dayIndex].activities[activityIndex].startTime != nil else {
            throw TripPlanEditingError.reminderRequiresStartTime
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].reminderLeadTime = leadTime
        return copy
    }

    static func setActivityMemory(
        in trip: Trip,
        activityID: Activity.ID,
        photoData: Data?,
        reflection: String?
    ) throws -> Trip {
        guard let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activityIndex = trip.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
            throw TripPlanEditingError.activityNotFound
        }

        let normalizedReflection = normalizedOptionalText(reflection)
        guard normalizedReflection.map(\.count) ?? 0 <= 500 else {
            throw TripPlanEditingError.invalidReflection
        }
        guard (photoData == nil && normalizedReflection == nil)
            || trip.days[dayIndex].activities[activityIndex].progress == .completed else {
            throw TripPlanEditingError.memoryRequiresCompletedActivity
        }

        var copy = trip
        copy.days[dayIndex].activities[activityIndex].memoryPhotoData = photoData
        copy.days[dayIndex].activities[activityIndex].reflection = normalizedReflection
        return copy
    }

    static func setTravelLegPreference(
        in trip: Trip,
        legID: TravelLegID,
        transportType: TravelTransportType,
        manualDurationMinutes: Int?,
        note: String?
    ) throws -> Trip {
        let dayIDByActivityID = Dictionary(
            uniqueKeysWithValues: trip.days.flatMap { day in
                day.activities.map { ($0.id, day.id) }
            }
        )
        guard legID.fromActivityID != legID.toActivityID,
              let fromDayID = dayIDByActivityID[legID.fromActivityID],
              fromDayID == dayIDByActivityID[legID.toActivityID] else {
            throw TripPlanEditingError.invalidTravelLegReference
        }
        guard manualDurationMinutes.map({ (1...1_439).contains($0) }) ?? true else {
            throw TripPlanEditingError.invalidTravelLegDuration
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = trimmedNote?.isEmpty == false ? trimmedNote : nil
        var copy = trip
        copy.travelLegPreferences.removeAll { $0.legID == legID }
        if transportType != .automobile || manualDurationMinutes != nil || normalizedNote != nil {
            copy.travelLegPreferences.append(
                TravelLegPreference(
                    legID: legID,
                    transportType: transportType,
                    manualDurationMinutes: manualDurationMinutes,
                    note: normalizedNote
                )
            )
        }
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
        copy.travelLegPreferences.removeAll {
            $0.legID.fromActivityID == activityID || $0.legID.toActivityID == activityID
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
        let placement: ActivityMovePlacement =
            sourceIndex < targetIndex ? .after : .before
        return try positionActivity(
            in: trip,
            dayID: dayID,
            activityID: activityID,
            relativeTo: targetActivityID,
            placement: placement
        )
    }

    static func positionActivity(
        in trip: Trip,
        dayID: Day.ID,
        activityID: Activity.ID,
        relativeTo anchorActivityID: Activity.ID,
        placement: ActivityMovePlacement
    ) throws -> Trip {
        guard activityID != anchorActivityID else { return trip }
        guard let dayIndex = trip.days.firstIndex(where: { $0.id == dayID }) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        let ordered = trip.days[dayIndex].orderedActivities
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == activityID }),
              ordered.contains(where: { $0.id == anchorActivityID }) else {
            throw TripPlanEditingError.activityNotFound
        }
        var reordered = ordered
        let movedActivity = reordered.remove(at: sourceIndex)
        guard let anchorIndex = reordered.firstIndex(
            where: { $0.id == anchorActivityID }
        ) else {
            throw TripPlanEditingError.activityNotFound
        }
        let insertionIndex =
            placement == .before ? anchorIndex : anchorIndex + 1
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

    static func replicateDayActivities(
        in trip: Trip,
        mutation: ReplicateDayActivitiesMutation
    ) throws -> Trip {
        guard let source = trip.days.first(
            where: { $0.id == mutation.sourceDayID }
        ) else {
            throw TripPlanEditingError.sourceDayNotFound
        }
        let sourceActivities = source.orderedActivities
        guard sourceActivities.map(\.id)
            == mutation.expectedSourceActivityIDs else {
            throw TripPlanEditingError.activityNotFound
        }
        let targetIDs = Set(mutation.targets.map(\.dayID))
        guard targetIDs.count == mutation.targets.count,
              !targetIDs.contains(mutation.sourceDayID) else {
            throw TripPlanEditingError.targetIncludesSource
        }
        guard mutation.targets.allSatisfy({
            $0.activityIDs.count == sourceActivities.count
                && $0.placeIDs.count == sourceActivities.count
                && Set($0.activityIDs).count == $0.activityIDs.count
                && zip($0.placeIDs, sourceActivities).allSatisfy {
                    ($0.0 == nil) == ($0.1.place == nil)
                }
        }) else {
            throw TripPersistenceError.invalidModel
        }
        let allGeneratedActivityIDs = mutation.targets.flatMap(\.activityIDs)
        let allGeneratedPlaceIDs = mutation.targets
            .flatMap(\.placeIDs)
            .compactMap { $0 }
        guard Set(allGeneratedActivityIDs).count
            == allGeneratedActivityIDs.count,
              Set(allGeneratedPlaceIDs).count
                == allGeneratedPlaceIDs.count else {
            throw TripPersistenceError.duplicateIdentifier
        }
        let existingActivityIDs = Set(trip.days.flatMap(\.activities).map(\.id))
        let existingPlaceIDs = Set(
            trip.days
                .flatMap(\.activities)
                .compactMap { $0.place?.id }
        )
        guard existingActivityIDs.isDisjoint(
            with: allGeneratedActivityIDs
        ) else {
            throw TripPlanEditingError.activityAlreadyExists
        }
        guard existingPlaceIDs.isDisjoint(
            with: allGeneratedPlaceIDs
        ) else {
            throw TripPersistenceError.duplicateIdentifier
        }

        var copy = trip
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        for target in mutation.targets {
            guard let targetIndex = copy.days.firstIndex(
                where: { $0.id == target.dayID }
            ) else {
                throw TripPlanEditingError.targetDayNotFound
            }
            let firstSequence =
                (copy.days[targetIndex].activities.map(\.sequence).max() ?? 0) + 1
            let replicas = sourceActivities.enumerated().map {
                index, activity in
                Activity(
                    id: target.activityIDs[index],
                    sequence: firstSequence + index,
                    title: activity.title,
                    startTime: time(
                        on: copy.days[targetIndex].date,
                        matching: activity.startTime,
                        timeZone: timeZone
                    ),
                    category: activity.category,
                    durationMinutes: activity.durationMinutes,
                    note: activity.note,
                    place: activity.place.map { place in
                        PlaceSnapshot(
                            id: target.placeIDs[index]!,
                            name: place.name,
                            address: place.address,
                            latitude: place.latitude,
                            longitude: place.longitude,
                            mapKitIdentifier: place.mapKitIdentifier,
                            imageData: place.imageData
                        )
                    }
                )
            }
            copy.days[targetIndex].activities.append(contentsOf: replicas)
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

    static func swapDayPlans(
        in trip: Trip,
        mutation: SwapDayPlansMutation
    ) throws -> Trip {
        guard mutation.firstDayID != mutation.secondDayID else {
            throw TripPlanEditingError.sameDay
        }
        guard let first = trip.days.first(
            where: { $0.id == mutation.firstDayID }
        ), let second = trip.days.first(
            where: { $0.id == mutation.secondDayID }
        ) else {
            throw TripPlanEditingError.targetDayNotFound
        }
        guard first.orderedActivities.map(\.id)
                == mutation.expectedFirstActivityIDs,
              second.orderedActivities.map(\.id)
                == mutation.expectedSecondActivityIDs else {
            throw TripPlanEditingError.activityChangedDay
        }
        return try swapDayPlans(
            in: trip,
            firstDayID: mutation.firstDayID,
            secondDayID: mutation.secondDayID
        )
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

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
