import Foundation
import SwiftData

@Model
final class StoredTrip {
    var id: UUID = UUID()
    var title: String = ""
    var startDateCode: Int = 0
    var endDateCode: Int = 0
    var timeZoneIdentifier: String = "Etc/UTC"
    var defaultCurrencyCode: String = "JPY"
    @Attribute(.externalStorage) var coverImageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \StoredDay.trip)
    var days: [StoredDay] = []
    @Relationship(deleteRule: .cascade, inverse: \StoredTripParticipant.trip)
    var participantAssignments: [StoredTripParticipant] = []
    @Relationship(deleteRule: .cascade, inverse: \StoredChecklistItem.trip)
    var checklistItems: [StoredChecklistItem] = []
    @Relationship(deleteRule: .cascade, inverse: \StoredTravelLegPreference.trip)
    var travelLegPreferences: [StoredTravelLegPreference] = []

    init(
        id: UUID,
        title: String,
        startDateCode: Int,
        endDateCode: Int,
        timeZoneIdentifier: String,
        defaultCurrencyCode: String = "JPY",
        coverImageData: Data? = nil,
        days: [StoredDay] = [],
        travelLegPreferences: [StoredTravelLegPreference] = []
    ) {
        self.id = id
        self.title = title
        self.startDateCode = startDateCode
        self.endDateCode = endDateCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.defaultCurrencyCode = defaultCurrencyCode
        self.coverImageData = coverImageData
        self.days = days
        self.travelLegPreferences = travelLegPreferences
    }
}

@Model
final class StoredDay {
    var id: UUID = UUID()
    var sequence: Int = 0
    var dateCode: Int = 0
    var title: String = ""
    var trip: StoredTrip?
    @Relationship(deleteRule: .cascade, inverse: \StoredActivity.day)
    var activities: [StoredActivity] = []

    init(id: UUID, sequence: Int, dateCode: Int, title: String, activities: [StoredActivity] = []) {
        self.id = id
        self.sequence = sequence
        self.dateCode = dateCode
        self.title = title
        self.activities = activities
    }
}

@Model
final class StoredActivity {
    var id: UUID = UUID()
    var sequence: Int = 0
    var title: String = ""
    var startMinuteOfDay: Int?
    var categoryRawValue: String?
    var durationMinutes: Int?
    var note: String?
    var progressRawValue: String = ActivityProgress.planned.rawValue
    var progressUpdatedAt: Date?
    var reminderLeadTimeMinutes: Int?
    @Attribute(.externalStorage) var memoryPhotoData: Data?
    var reflection: String?
    var day: StoredDay?
    @Relationship(deleteRule: .cascade, inverse: \StoredPlaceSnapshot.activity)
    var place: StoredPlaceSnapshot?
    @Relationship(deleteRule: .cascade, inverse: \StoredReservationReference.activity)
    var reservation: StoredReservationReference?

    init(
        id: UUID,
        sequence: Int,
        title: String,
        startMinuteOfDay: Int?,
        categoryRawValue: String?,
        durationMinutes: Int?,
        note: String?,
        progressRawValue: String = ActivityProgress.planned.rawValue,
        progressUpdatedAt: Date? = nil,
        reminderLeadTimeMinutes: Int? = nil,
        memoryPhotoData: Data? = nil,
        reflection: String? = nil,
        place: StoredPlaceSnapshot?,
        reservation: StoredReservationReference? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.categoryRawValue = categoryRawValue
        self.durationMinutes = durationMinutes
        self.note = note
        self.progressRawValue = progressRawValue
        self.progressUpdatedAt = progressUpdatedAt
        self.reminderLeadTimeMinutes = reminderLeadTimeMinutes
        self.memoryPhotoData = memoryPhotoData
        self.reflection = reflection
        self.place = place
        self.reservation = reservation
    }
}

@Model
final class StoredReservationReference {
    var id: UUID = UUID()
    var kindRawValue: String = ReservationKind.other.rawValue
    var title: String = ""
    var confirmationCode: String?
    var urlString: String?
    var note: String?
    var activity: StoredActivity?

    init(
        id: UUID,
        kindRawValue: String,
        title: String,
        confirmationCode: String?,
        urlString: String?,
        note: String?
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.title = title
        self.confirmationCode = confirmationCode
        self.urlString = urlString
        self.note = note
    }
}

@Model
final class StoredTravelLegPreference {
    var id: UUID = UUID()
    var fromActivityID: UUID = UUID()
    var toActivityID: UUID = UUID()
    var transportTypeRawValue: String = TravelTransportType.automobile.rawValue
    var manualDurationMinutes: Int?
    var note: String?
    var trip: StoredTrip?

    init(
        id: UUID = UUID(),
        fromActivityID: UUID,
        toActivityID: UUID,
        transportTypeRawValue: String,
        manualDurationMinutes: Int?,
        note: String?
    ) {
        self.id = id
        self.fromActivityID = fromActivityID
        self.toActivityID = toActivityID
        self.transportTypeRawValue = transportTypeRawValue
        self.manualDurationMinutes = manualDurationMinutes
        self.note = note
    }
}

@Model
final class StoredPlaceSnapshot {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var mapKitIdentifier: String?
    @Attribute(.externalStorage) var imageData: Data?
    var externalImageProvider: String?
    var externalImageID: String?
    var externalImageURL: String?
    var externalImageSourcePageURL: String?
    var externalImageAuthorName: String?
    var externalImageAuthorURL: String?
    var externalImageLicenseName: String?
    var externalImageLicenseURL: String?
    var externalImageKind: String?
    var externalImageFetchedAt: Date?
    var activity: StoredActivity?

    init(
        id: UUID,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        mapKitIdentifier: String?,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.mapKitIdentifier = mapKitIdentifier
        self.imageData = imageData
    }
}

@Model
final class StoredParticipant {
    var id: UUID = UUID()
    var displayName: String = ""
    var note: String?
    var createdAt: Date = Date()

    init(id: UUID = UUID(), displayName: String, note: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class StoredTripParticipant {
    var id: UUID = UUID()
    var trip: StoredTrip?
    var participant: StoredParticipant?

    init(id: UUID = UUID(), trip: StoredTrip? = nil, participant: StoredParticipant? = nil) {
        self.id = id
        self.trip = trip
        self.participant = participant
    }
}

@Model
final class StoredChecklistItem {
    var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var trip: StoredTrip?

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, trip: StoredTrip? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.trip = trip
    }
}

enum TripMapSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        StoredTrip.self,
        StoredDay.self,
        StoredActivity.self,
        StoredReservationReference.self,
        StoredTravelLegPreference.self,
        StoredPlaceSnapshot.self,
        StoredParticipant.self,
        StoredTripParticipant.self,
        StoredChecklistItem.self
    ]
}

enum TripMapMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        TripMapSchemaV1.self
    ]

    static let stages: [MigrationStage] = []
}

enum TripMapStore {
    static let schema = Schema(versionedSchema: TripMapSchemaV1.self)

    static func makeContainer(inMemoryOnly: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemoryOnly,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: TripMapMigrationPlan.self,
            configurations: configuration
        )
    }
}

enum TripPersistenceError: LocalizedError, Equatable {
    case identityMismatch
    case blankTitle
    case invalidTimeZone
    case invalidModel
    case duplicateIdentifier

    var errorDescription: String? {
        switch self {
        case .identityMismatch:
            "別の旅行として保存することはできません。"
        case .blankTitle:
            "旅行名を入力してください。"
        case .invalidTimeZone:
            "タイムゾーンを確認してください。"
        case .invalidModel:
            "旅行データに不正な日付、順序、時刻、または場所があります。"
        case .duplicateIdentifier:
            "旅行データ内に重複した識別子があります。"
        }
    }
}

extension StoredTrip {
    convenience init(validatingSnapshot trip: Trip) throws {
        let timeZone = try trip.persistenceTimeZone()
        self.init(
            id: trip.id,
            title: trip.title,
            startDateCode: LocalDate(date: trip.dateRange.lowerBound, timeZone: timeZone).code,
            endDateCode: LocalDate(date: trip.dateRange.upperBound, timeZone: timeZone).code,
            timeZoneIdentifier: timeZone.identifier,
            defaultCurrencyCode: trip.defaultCurrencyCode,
            coverImageData: trip.coverImageData,
            days: trip.days.map { StoredDay(snapshot: $0, timeZone: timeZone) },
            travelLegPreferences: trip.travelLegPreferences.map(StoredTravelLegPreference.init(snapshot:))
        )
    }

    var snapshot: Trip? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier),
              let start = LocalDate(code: startDateCode)?.date(in: timeZone),
              let end = LocalDate(code: endDateCode)?.date(in: timeZone),
              start <= end else {
            return nil
        }

        let snapshots = days.compactMap { $0.snapshot(timeZone: timeZone) }
        let preferenceSnapshots = travelLegPreferences.compactMap(\.snapshot)
        guard snapshots.count == days.count,
              preferenceSnapshots.count == travelLegPreferences.count else { return nil }
        let trip = Trip(
            id: id,
            title: title,
            dateRange: start...end,
            timeZoneIdentifier: timeZoneIdentifier,
            defaultCurrencyCode: defaultCurrencyCode,
            coverImageData: coverImageData,
            days: snapshots,
            travelLegPreferences: preferenceSnapshots
        )
        do {
            try trip.validateForPersistence()
            return trip
        } catch {
            return nil
        }
    }

    func applyPlan(_ trip: Trip, in modelContext: ModelContext) throws {
        guard id == trip.id else { throw TripPersistenceError.identityMismatch }
        let timeZone = try trip.persistenceTimeZone()
        let priorDays = days
        let priorActivities = priorDays.flatMap(\.activities)
        let priorTravelLegPreferences = travelLegPreferences
        var existingDays: [UUID: StoredDay] = [:]
        var existingActivities: [UUID: StoredActivity] = [:]
        var originalDayIDByActivityID: [UUID: UUID] = [:]
        for day in priorDays {
            guard existingDays.updateValue(day, forKey: day.id) == nil else {
                throw TripPersistenceError.duplicateIdentifier
            }
            for activity in day.activities {
                guard existingActivities.updateValue(activity, forKey: activity.id) == nil else {
                    throw TripPersistenceError.duplicateIdentifier
                }
                originalDayIDByActivityID[activity.id] = day.id
            }
        }
        let desiredDayIDs = Set(trip.days.map(\.id))
        let desiredActivityIDs = Set(trip.days.flatMap(\.activities).map(\.id))
        var placesToDelete: [StoredPlaceSnapshot] = []
        var reservationsToDelete: [StoredReservationReference] = []

        title = trip.title
        startDateCode = LocalDate(date: trip.dateRange.lowerBound, timeZone: timeZone).code
        endDateCode = LocalDate(date: trip.dateRange.upperBound, timeZone: timeZone).code
        timeZoneIdentifier = timeZone.identifier
        defaultCurrencyCode = trip.defaultCurrencyCode
        coverImageData = trip.coverImageData

        var existingPreferences: [TravelLegID: StoredTravelLegPreference] = [:]
        for preference in priorTravelLegPreferences {
            let legID = TravelLegID(
                fromActivityID: preference.fromActivityID,
                toActivityID: preference.toActivityID
            )
            guard existingPreferences.updateValue(preference, forKey: legID) == nil else {
                throw TripPersistenceError.duplicateIdentifier
            }
        }
        let desiredPreferenceIDs = Set(trip.travelLegPreferences.map(\.legID))
        travelLegPreferences = trip.travelLegPreferences.map { domainPreference in
            let storedPreference = existingPreferences[domainPreference.legID]
                ?? StoredTravelLegPreference(snapshot: domainPreference)
            storedPreference.apply(domainPreference)
            return storedPreference
        }

        days = trip.days.map { domainDay in
            let storedDay = existingDays[domainDay.id] ?? StoredDay(
                id: domainDay.id,
                sequence: domainDay.sequence,
                dateCode: LocalDate(date: domainDay.date, timeZone: timeZone).code,
                title: domainDay.title
            )
            storedDay.sequence = domainDay.sequence
            storedDay.dateCode = LocalDate(date: domainDay.date, timeZone: timeZone).code
            storedDay.title = domainDay.title
            storedDay.activities = domainDay.activities.map { domainActivity in
                if let storedActivity = existingActivities[domainActivity.id] {
                    storedActivity.sequence = domainActivity.sequence
                    storedActivity.title = domainActivity.title
                    storedActivity.note = domainActivity.note
                    storedActivity.startMinuteOfDay = domainActivity.startTime.map {
                        LocalTime(date: $0, timeZone: timeZone).minuteOfDay
                    }
                    storedActivity.categoryRawValue = domainActivity.category?.rawValue
                    storedActivity.durationMinutes = domainActivity.durationMinutes
                    storedActivity.progressRawValue = domainActivity.progress.rawValue
                    storedActivity.progressUpdatedAt = domainActivity.progressUpdatedAt
                    storedActivity.reminderLeadTimeMinutes = domainActivity.reminderLeadTime?.rawValue
                    storedActivity.memoryPhotoData = domainActivity.memoryPhotoData
                    storedActivity.reflection = domainActivity.reflection
                    switch (domainActivity.place, storedActivity.place) {
                    case let (domainPlace?, storedPlace?) where domainPlace.id == storedPlace.id:
                        storedPlace.apply(domainPlace)
                    case let (domainPlace?, storedPlace?):
                        placesToDelete.append(storedPlace)
                        storedActivity.place = StoredPlaceSnapshot(snapshot: domainPlace)
                    case let (domainPlace?, nil):
                        storedActivity.place = StoredPlaceSnapshot(snapshot: domainPlace)
                    case (nil, let storedPlace?):
                        placesToDelete.append(storedPlace)
                        storedActivity.place = nil
                    case (nil, nil):
                        break
                    }
                    switch (domainActivity.reservation, storedActivity.reservation) {
                    case let (domainReservation?, storedReservation?)
                        where domainReservation.id == storedReservation.id:
                        storedReservation.apply(domainReservation)
                    case let (domainReservation?, storedReservation?):
                        reservationsToDelete.append(storedReservation)
                        storedActivity.reservation = StoredReservationReference(snapshot: domainReservation)
                    case let (domainReservation?, nil):
                        storedActivity.reservation = StoredReservationReference(snapshot: domainReservation)
                    case (nil, let storedReservation?):
                        reservationsToDelete.append(storedReservation)
                        storedActivity.reservation = nil
                    case (nil, nil):
                        break
                    }
                    return storedActivity
                }
                return StoredActivity(snapshot: domainActivity, dayDate: domainDay.date, timeZone: timeZone)
            }
            return storedDay
        }

        for day in priorDays where !desiredDayIDs.contains(day.id) {
            modelContext.delete(day)
        }
        for activity in priorActivities
        where desiredDayIDs.contains(originalDayIDByActivityID[activity.id] ?? UUID())
            && !desiredActivityIDs.contains(activity.id) {
            modelContext.delete(activity)
        }
        for place in placesToDelete {
            modelContext.delete(place)
        }
        for reservation in reservationsToDelete {
            modelContext.delete(reservation)
        }
        for preference in priorTravelLegPreferences where !desiredPreferenceIDs.contains(preference.snapshotID) {
            modelContext.delete(preference)
        }
    }

    /// Applies a small user intent to the latest persisted snapshot, then writes
    /// only the fields owned by that intent. This avoids replaying an older
    /// screen snapshot over unrelated changes.
    func applyMutation(_ mutation: TripMutation, in modelContext: ModelContext) throws {
        guard let current = snapshot else {
            throw TripPersistenceError.invalidModel
        }
        let updated = try mutation.applying(to: current)
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw TripPersistenceError.invalidTimeZone
        }

        func storedActivity(_ activityID: Activity.ID) throws -> StoredActivity {
            guard let activity = days
                .flatMap(\.activities)
                .first(where: { $0.id == activityID }) else {
                throw TripPlanEditingError.activityNotFound
            }
            return activity
        }

        func updatedActivity(_ activityID: Activity.ID) throws -> Activity {
            guard let activity = updated.days
                .flatMap(\.activities)
                .first(where: { $0.id == activityID }) else {
                throw TripPlanEditingError.activityNotFound
            }
            return activity
        }

        func applyPlace(
            _ desiredPlace: PlaceSnapshot?,
            to stored: StoredActivity
        ) {
            switch (desiredPlace, stored.place) {
            case let (desired?, existing?) where desired.id == existing.id:
                existing.apply(desired)
            case let (desired?, existing?):
                stored.place = StoredPlaceSnapshot(snapshot: desired)
                modelContext.delete(existing)
            case let (desired?, nil):
                stored.place = StoredPlaceSnapshot(snapshot: desired)
            case (nil, let existing?):
                stored.place = nil
                modelContext.delete(existing)
            case (nil, nil):
                break
            }
        }

        func applyReservation(
            _ desiredReservation: ReservationReference?,
            to stored: StoredActivity
        ) {
            switch (desiredReservation, stored.reservation) {
            case let (desired?, existing?) where desired.id == existing.id:
                existing.apply(desired)
            case let (desired?, existing?):
                stored.reservation = StoredReservationReference(snapshot: desired)
                modelContext.delete(existing)
            case let (desired?, nil):
                stored.reservation = StoredReservationReference(snapshot: desired)
            case (nil, let existing?):
                stored.reservation = nil
                modelContext.delete(existing)
            case (nil, nil):
                break
            }
        }

        switch mutation {
        case .setCoverImage:
            coverImageData = updated.coverImageData
        case .editPlanActivity(let edit):
            let stored = try storedActivity(edit.activityID)
            let desired = try updatedActivity(edit.activityID)
            stored.title = desired.title
            stored.startMinuteOfDay = desired.startTime.map {
                LocalTime(date: $0, timeZone: timeZone).minuteOfDay
            }
            stored.categoryRawValue = desired.category?.rawValue
            stored.durationMinutes = desired.durationMinutes
            stored.note = desired.note
            if case .replace = edit.place {
                applyPlace(desired.place, to: stored)
            }
        case .editGuideActivity(let edit):
            let stored = try storedActivity(edit.activityID)
            let desired = try updatedActivity(edit.activityID)
            stored.startMinuteOfDay = desired.startTime.map {
                LocalTime(date: $0, timeZone: timeZone).minuteOfDay
            }
            stored.note = desired.note
            stored.progressRawValue = desired.progress.rawValue
            stored.progressUpdatedAt = desired.progressUpdatedAt
            stored.reminderLeadTimeMinutes = desired.reminderLeadTime?.rawValue
            applyReservation(desired.reservation, to: stored)
            if case .replace = edit.place {
                applyPlace(desired.place, to: stored)
            }
        case .setTravelLegPreference(let mutation):
            let existing = travelLegPreferences.first(
                where: { $0.snapshotID == mutation.legID }
            )
            let desired = updated.travelLegPreferences.first(
                where: { $0.legID == mutation.legID }
            )
            switch (desired, existing) {
            case let (desired?, existing?):
                existing.apply(desired)
            case let (desired?, nil):
                travelLegPreferences.append(
                    StoredTravelLegPreference(snapshot: desired)
                )
            case (nil, let existing?):
                travelLegPreferences.removeAll {
                    $0.snapshotID == mutation.legID
                }
                modelContext.delete(existing)
            case (nil, nil):
                break
            }
        case .setVenueUserImage(let activityID, _, _):
            let stored = try storedActivity(activityID)
            let desired = try updatedActivity(activityID)
            guard let storedPlace = stored.place, let desiredPlace = desired.place else {
                throw TripPlanEditingError.placeNotFound
            }
            storedPlace.imageData = desiredPlace.imageData
        case .setExternalVenueImage(let activityID, _, _):
            let stored = try storedActivity(activityID)
            let desired = try updatedActivity(activityID)
            guard let storedPlace = stored.place, let desiredPlace = desired.place else {
                throw TripPlanEditingError.placeNotFound
            }
            storedPlace.applyExternalImage(desiredPlace.externalImage)
        case .setActivityProgress(let activityID, _, _):
            let stored = try storedActivity(activityID)
            let desired = try updatedActivity(activityID)
            stored.progressRawValue = desired.progress.rawValue
            stored.progressUpdatedAt = desired.progressUpdatedAt
        case .recordActivityMemory(let activityID, _, _, _):
            let stored = try storedActivity(activityID)
            let desired = try updatedActivity(activityID)
            stored.progressRawValue = desired.progress.rawValue
            stored.progressUpdatedAt = desired.progressUpdatedAt
            stored.memoryPhotoData = desired.memoryPhotoData
            stored.reflection = desired.reflection
        }
    }
}

private extension Trip {
    func persistenceTimeZone() throws -> TimeZone {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TripPersistenceError.blankTitle
        }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw TripPersistenceError.invalidTimeZone
        }
        try validateForPersistence()
        return timeZone
    }

    func validateForPersistence() throws {
        guard validationIssues.isEmpty else {
            throw TripPersistenceError.invalidModel
        }
        let dayIDs = days.map(\.id)
        let activityIDs = days.flatMap(\.activities).map(\.id)
        let placeIDs = days.flatMap(\.activities).compactMap(\.place?.id)
        guard Set(dayIDs).count == dayIDs.count,
              Set(activityIDs).count == activityIDs.count,
              Set(placeIDs).count == placeIDs.count else {
            throw TripPersistenceError.duplicateIdentifier
        }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw TripPersistenceError.invalidTimeZone
        }
        for day in days {
            let localDay = LocalDate(date: day.date, timeZone: timeZone)
            for activity in day.activities {
                guard let startTime = activity.startTime else { continue }
                guard LocalDate(date: startTime, timeZone: timeZone) == localDay else {
                    throw TripPersistenceError.invalidModel
                }
            }
        }
    }
}

private extension StoredTravelLegPreference {
    convenience init(snapshot preference: TravelLegPreference) {
        self.init(
            fromActivityID: preference.legID.fromActivityID,
            toActivityID: preference.legID.toActivityID,
            transportTypeRawValue: preference.transportType.rawValue,
            manualDurationMinutes: preference.manualDurationMinutes,
            note: preference.note
        )
    }

    var snapshotID: TravelLegID {
        TravelLegID(fromActivityID: fromActivityID, toActivityID: toActivityID)
    }

    var snapshot: TravelLegPreference? {
        guard let transportType = TravelTransportType(rawValue: transportTypeRawValue) else {
            return nil
        }
        return TravelLegPreference(
            legID: snapshotID,
            transportType: transportType,
            manualDurationMinutes: manualDurationMinutes,
            note: note
        )
    }

    func apply(_ preference: TravelLegPreference) {
        fromActivityID = preference.legID.fromActivityID
        toActivityID = preference.legID.toActivityID
        transportTypeRawValue = preference.transportType.rawValue
        manualDurationMinutes = preference.manualDurationMinutes
        note = preference.note
    }
}

private extension StoredDay {
    convenience init(snapshot day: Day, timeZone: TimeZone) {
        self.init(
            id: day.id,
            sequence: day.sequence,
            dateCode: LocalDate(date: day.date, timeZone: timeZone).code,
            title: day.title,
            activities: day.activities.map { StoredActivity(snapshot: $0, dayDate: day.date, timeZone: timeZone) }
        )
    }

    func snapshot(timeZone: TimeZone) -> Day? {
        guard let localDate = LocalDate(code: dateCode), let date = localDate.date(in: timeZone) else { return nil }
        let snapshots = activities.compactMap { $0.snapshot(localDate: localDate, timeZone: timeZone) }
        guard snapshots.count == activities.count else { return nil }
        return Day(id: id, sequence: sequence, date: date, title: title, activities: snapshots)
    }
}

private extension StoredActivity {
    convenience init(snapshot activity: Activity, dayDate: Date, timeZone: TimeZone) {
        self.init(
            id: activity.id,
            sequence: activity.sequence,
            title: activity.title,
            startMinuteOfDay: activity.startTime.map { LocalTime(date: $0, timeZone: timeZone).minuteOfDay },
            categoryRawValue: activity.category?.rawValue,
            durationMinutes: activity.durationMinutes,
            note: activity.note,
            progressRawValue: activity.progress.rawValue,
            progressUpdatedAt: activity.progressUpdatedAt,
            reminderLeadTimeMinutes: activity.reminderLeadTime?.rawValue,
            memoryPhotoData: activity.memoryPhotoData,
            reflection: activity.reflection,
            place: activity.place.map(StoredPlaceSnapshot.init(snapshot:)),
            reservation: activity.reservation.map(StoredReservationReference.init(snapshot:))
        )
    }

    func snapshot(localDate: LocalDate, timeZone: TimeZone) -> Activity? {
        guard let progress = ActivityProgress(rawValue: progressRawValue),
              (progress == .planned) == (progressUpdatedAt == nil) else {
            return nil
        }
        let startTime: Date?
        if let startMinuteOfDay {
            guard let localTime = LocalTime(minuteOfDay: startMinuteOfDay),
                  let date = localTime.date(on: localDate, in: timeZone) else { return nil }
            startTime = date
        } else {
            startTime = nil
        }
        let reservationSnapshot: ReservationReference?
        if let reservation {
            guard let snapshot = reservation.snapshot else { return nil }
            reservationSnapshot = snapshot
        } else {
            reservationSnapshot = nil
        }
        let reminderLeadTime: ActivityReminderLeadTime?
        if let reminderLeadTimeMinutes {
            guard let snapshot = ActivityReminderLeadTime(rawValue: reminderLeadTimeMinutes) else {
                return nil
            }
            reminderLeadTime = snapshot
        } else {
            reminderLeadTime = nil
        }
        return Activity(
            id: id,
            sequence: sequence,
            title: title,
            startTime: startTime,
            category: categoryRawValue.flatMap(ActivityCategory.init(rawValue:)),
            durationMinutes: durationMinutes,
            note: note,
            place: place?.snapshot,
            progress: progress,
            progressUpdatedAt: progressUpdatedAt,
            reservation: reservationSnapshot,
            reminderLeadTime: reminderLeadTime,
            memoryPhotoData: memoryPhotoData,
            reflection: reflection
        )
    }
}

private extension StoredReservationReference {
    convenience init(snapshot reservation: ReservationReference) {
        self.init(
            id: reservation.id,
            kindRawValue: reservation.kind.rawValue,
            title: reservation.title,
            confirmationCode: reservation.confirmationCode,
            urlString: reservation.url?.absoluteString,
            note: reservation.note
        )
    }

    var snapshot: ReservationReference? {
        guard let kind = ReservationKind(rawValue: kindRawValue) else { return nil }
        let url: URL?
        if let urlString {
            guard let parsedURL = URL(string: urlString) else { return nil }
            url = parsedURL
        } else {
            url = nil
        }
        return ReservationReference(
            id: id,
            kind: kind,
            title: title,
            confirmationCode: confirmationCode,
            url: url,
            note: note
        )
    }

    func apply(_ reservation: ReservationReference) {
        kindRawValue = reservation.kind.rawValue
        title = reservation.title
        confirmationCode = reservation.confirmationCode
        urlString = reservation.url?.absoluteString
        note = reservation.note
    }
}

private extension StoredPlaceSnapshot {
    convenience init(snapshot place: PlaceSnapshot) {
        self.init(
            id: place.id,
            name: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            mapKitIdentifier: place.mapKitIdentifier,
            imageData: place.imageData
        )
        applyExternalImage(place.externalImage)
    }

    var snapshot: PlaceSnapshot {
        PlaceSnapshot(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            mapKitIdentifier: mapKitIdentifier,
            imageData: imageData,
            externalImage: externalImageSnapshot
        )
    }

    func apply(_ place: PlaceSnapshot) {
        name = place.name
        address = place.address
        latitude = place.latitude
        longitude = place.longitude
        mapKitIdentifier = place.mapKitIdentifier
        imageData = place.imageData
        applyExternalImage(place.externalImage)
    }

    var externalImageSnapshot: ExternalPlaceImage? {
        guard let providerRawValue = externalImageProvider,
              let provider = ExternalPlaceImage.Provider(rawValue: providerRawValue),
              let imageID = externalImageID,
              let imageURLString = externalImageURL,
              let imageURL = URL(string: imageURLString),
              let sourcePageURLString = externalImageSourcePageURL,
              let sourcePageURL = URL(string: sourcePageURLString),
              let authorName = externalImageAuthorName,
              let licenseName = externalImageLicenseName,
              let licenseURLString = externalImageLicenseURL,
              let licenseURL = URL(string: licenseURLString),
              let kindRawValue = externalImageKind,
              let kind = ExternalPlaceImage.Kind(rawValue: kindRawValue),
              let fetchedAt = externalImageFetchedAt else {
            return nil
        }

        return ExternalPlaceImage(
            provider: provider,
            providerImageID: imageID,
            imageURL: imageURL,
            sourcePageURL: sourcePageURL,
            authorName: authorName,
            authorURL: externalImageAuthorURL.flatMap(URL.init(string:)),
            licenseName: licenseName,
            licenseURL: licenseURL,
            kind: kind,
            fetchedAt: fetchedAt
        )
    }

    func applyExternalImage(_ image: ExternalPlaceImage?) {
        externalImageProvider = image?.provider.rawValue
        externalImageID = image?.providerImageID
        externalImageURL = image?.imageURL.absoluteString
        externalImageSourcePageURL = image?.sourcePageURL.absoluteString
        externalImageAuthorName = image?.authorName
        externalImageAuthorURL = image?.authorURL?.absoluteString
        externalImageLicenseName = image?.licenseName
        externalImageLicenseURL = image?.licenseURL.absoluteString
        externalImageKind = image?.kind.rawValue
        externalImageFetchedAt = image?.fetchedAt
    }
}
