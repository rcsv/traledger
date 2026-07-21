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

    init(
        id: UUID,
        title: String,
        startDateCode: Int,
        endDateCode: Int,
        timeZoneIdentifier: String,
        defaultCurrencyCode: String = "JPY",
        coverImageData: Data? = nil,
        days: [StoredDay] = []
    ) {
        self.id = id
        self.title = title
        self.startDateCode = startDateCode
        self.endDateCode = endDateCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.defaultCurrencyCode = defaultCurrencyCode
        self.coverImageData = coverImageData
        self.days = days
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
    var day: StoredDay?
    @Relationship(deleteRule: .cascade, inverse: \StoredPlaceSnapshot.activity)
    var place: StoredPlaceSnapshot?

    init(
        id: UUID,
        sequence: Int,
        title: String,
        startMinuteOfDay: Int?,
        categoryRawValue: String?,
        durationMinutes: Int?,
        note: String?,
        place: StoredPlaceSnapshot?
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.categoryRawValue = categoryRawValue
        self.durationMinutes = durationMinutes
        self.note = note
        self.place = place
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

enum TripMapStore {
    static let schema = Schema([
        StoredTrip.self,
        StoredDay.self,
        StoredActivity.self,
        StoredPlaceSnapshot.self,
        StoredParticipant.self,
        StoredTripParticipant.self,
        StoredChecklistItem.self
    ])

    static func makeContainer(inMemoryOnly: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryOnly)
        }
        return try ModelContainer(for: schema, configurations: configuration)
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
            days: trip.days.map { StoredDay(snapshot: $0, timeZone: timeZone) }
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
        guard snapshots.count == days.count else { return nil }
        let trip = Trip(
            id: id,
            title: title,
            dateRange: start...end,
            timeZoneIdentifier: timeZoneIdentifier,
            defaultCurrencyCode: defaultCurrencyCode,
            coverImageData: coverImageData,
            days: snapshots
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

        title = trip.title
        startDateCode = LocalDate(date: trip.dateRange.lowerBound, timeZone: timeZone).code
        endDateCode = LocalDate(date: trip.dateRange.upperBound, timeZone: timeZone).code
        timeZoneIdentifier = timeZone.identifier
        defaultCurrencyCode = trip.defaultCurrencyCode
        coverImageData = trip.coverImageData

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
            place: activity.place.map(StoredPlaceSnapshot.init(snapshot:))
        )
    }

    func snapshot(localDate: LocalDate, timeZone: TimeZone) -> Activity? {
        let startTime: Date?
        if let startMinuteOfDay {
            guard let localTime = LocalTime(minuteOfDay: startMinuteOfDay),
                  let date = localTime.date(on: localDate, in: timeZone) else { return nil }
            startTime = date
        } else {
            startTime = nil
        }
        return Activity(
            id: id,
            sequence: sequence,
            title: title,
            startTime: startTime,
            category: categoryRawValue.flatMap(ActivityCategory.init(rawValue:)),
            durationMinutes: durationMinutes,
            note: note,
            place: place?.snapshot
        )
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
