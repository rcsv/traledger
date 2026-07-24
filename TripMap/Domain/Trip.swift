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

enum ActivityCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case transport
    case restaurant
    case accommodation
    case sightseeing
    case activity
    case shopping
    case other

    var id: Self { self }

    var displayName: String {
        switch self {
        case .transport: "移動"
        case .restaurant: "食事"
        case .accommodation: "宿泊"
        case .sightseeing: "観光"
        case .activity: "体験"
        case .shopping: "買い物"
        case .other: "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .transport: "car"
        case .restaurant: "fork.knife"
        case .accommodation: "bed.double"
        case .sightseeing: "camera"
        case .activity: "figure.hiking"
        case .shopping: "bag"
        case .other: "ellipsis.circle"
        }
    }

    var suggestedDurationMinutes: Int? {
        switch self {
        case .transport: 30
        case .restaurant: 60
        case .accommodation: 30
        case .sightseeing: 90
        case .activity: 120
        case .shopping: 60
        case .other: nil
        }
    }
}

enum ActivityProgress: String, CaseIterable, Identifiable, Codable, Sendable {
    case planned
    case completed
    case skipped

    var id: Self { self }

    var displayName: String {
        switch self {
        case .planned: "未着手"
        case .completed: "完了"
        case .skipped: "スキップ"
        }
    }

    var systemImage: String {
        switch self {
        case .planned: "circle"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.circle.fill"
        }
    }
}

struct Activity: Identifiable, Hashable, Sendable {
    let id: UUID
    var sequence: Int
    var title: String
    var startTime: Date?
    var category: ActivityCategory? = nil
    var durationMinutes: Int? = nil
    var note: String?
    var place: PlaceSnapshot?
    var progress: ActivityProgress = .planned
    var progressUpdatedAt: Date? = nil
}

struct ExternalPlaceImage: Hashable, Sendable {
    enum Provider: String, Sendable {
        case wikimediaCommons
    }

    enum Kind: String, Sendable {
        case exactVenue
        case regional
    }

    var provider: Provider
    var providerImageID: String
    var imageURL: URL
    var sourcePageURL: URL
    var authorName: String
    var authorURL: URL?
    var licenseName: String
    var licenseURL: URL
    var kind: Kind
    var fetchedAt: Date
}

struct PlaceSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var mapKitIdentifier: String?
    var imageData: Data? = nil
    var externalImage: ExternalPlaceImage? = nil

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
            && lhs.externalImage == rhs.externalImage
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(latitude)
        hasher.combine(longitude)
        hasher.combine(mapKitIdentifier)
        hasher.combine(imageData)
        hasher.combine(externalImage)
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
