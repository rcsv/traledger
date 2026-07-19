import Foundation
import SwiftData

@Model
final class StoredTrip {
    var id: UUID = UUID()
    var title: String = ""
    var startDateCode: Int = 0
    var endDateCode: Int = 0
    var timeZoneIdentifier: String = "Etc/UTC"
    @Relationship(deleteRule: .cascade, inverse: \StoredDay.trip)
    var days: [StoredDay] = []

    init(
        id: UUID,
        title: String,
        startDateCode: Int,
        endDateCode: Int,
        timeZoneIdentifier: String,
        days: [StoredDay] = []
    ) {
        self.id = id
        self.title = title
        self.startDateCode = startDateCode
        self.endDateCode = endDateCode
        self.timeZoneIdentifier = timeZoneIdentifier
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
    var note: String?
    var day: StoredDay?
    @Relationship(deleteRule: .cascade, inverse: \StoredPlaceSnapshot.activity)
    var place: StoredPlaceSnapshot?

    init(
        id: UUID,
        sequence: Int,
        title: String,
        startMinuteOfDay: Int?,
        note: String?,
        place: StoredPlaceSnapshot?
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
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
    var activity: StoredActivity?

    init(
        id: UUID,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        mapKitIdentifier: String?
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.mapKitIdentifier = mapKitIdentifier
    }
}

enum TripMapStore {
    static let schema = Schema([
        StoredTrip.self,
        StoredDay.self,
        StoredActivity.self,
        StoredPlaceSnapshot.self
    ])

    static func makeContainer(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

extension StoredTrip {
    convenience init(snapshot trip: Trip) {
        let timeZone = TimeZone(identifier: trip.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        self.init(
            id: trip.id,
            title: trip.title,
            startDateCode: LocalDate(date: trip.dateRange.lowerBound, timeZone: timeZone).code,
            endDateCode: LocalDate(date: trip.dateRange.upperBound, timeZone: timeZone).code,
            timeZoneIdentifier: timeZone.identifier,
            days: trip.days.map { StoredDay(snapshot: $0, timeZone: timeZone) }
        )
    }

    var snapshot: Trip? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier),
              let start = LocalDate(code: startDateCode)?.date(in: timeZone),
              let end = LocalDate(code: endDateCode)?.date(in: timeZone) else {
            return nil
        }

        let snapshots = days.compactMap { $0.snapshot(timeZone: timeZone) }
        guard snapshots.count == days.count else { return nil }
        return Trip(
            id: id,
            title: title,
            dateRange: start...end,
            timeZoneIdentifier: timeZoneIdentifier,
            days: snapshots
        )
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
            mapKitIdentifier: place.mapKitIdentifier
        )
    }

    var snapshot: PlaceSnapshot {
        PlaceSnapshot(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            mapKitIdentifier: mapKitIdentifier
        )
    }
}
