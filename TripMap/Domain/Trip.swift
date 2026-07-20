import CoreLocation
import Foundation

struct Trip: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var dateRange: ClosedRange<Date>
    var timeZoneIdentifier: String = "Asia/Tokyo"
    var defaultCurrencyCode: String = "JPY"
    var coverImageData: Data? = nil
    var days: [Day]
}

struct Day: Identifiable, Hashable, Sendable {
    let id: UUID
    var sequence: Int
    var date: Date
    var title: String
    var activities: [Activity]
}

struct Activity: Identifiable, Hashable, Sendable {
    let id: UUID
    var sequence: Int
    var title: String
    var startTime: Date?
    var note: String?
    var place: PlaceSnapshot?
}

struct PlaceSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var mapKitIdentifier: String?
    var imageData: Data? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func == (lhs: PlaceSnapshot, rhs: PlaceSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.address == rhs.address
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
            && lhs.mapKitIdentifier == rhs.mapKitIdentifier
            && lhs.imageData == rhs.imageData
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(latitude)
        hasher.combine(longitude)
        hasher.combine(mapKitIdentifier)
        hasher.combine(imageData)
    }
}

extension Trip {
    /// Temporary country inference until venues persist a geocoded country code.
    var venueCountryNames: [String] {
        Array(Set(days.flatMap(\.activities).compactMap { $0.place?.inferredCountryName })).sorted()
    }
}

private extension PlaceSnapshot {
    var inferredCountryName: String? {
        if address.contains("県") || address.contains("都") || address.contains("府") || address.contains("道") {
            return "Japan"
        }
        if (20...46).contains(latitude), (122...154).contains(longitude) {
            return "Japan"
        }
        return nil
    }
}
