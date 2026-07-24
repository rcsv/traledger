import Foundation

enum TravelTransportType: String, CaseIterable, Hashable, Sendable {
    case automobile
    case walking
    case transit
    case other
}

struct TravelLegID: Hashable, Sendable {
    let fromActivityID: Activity.ID
    let toActivityID: Activity.ID
}

struct TravelLegPreference: Hashable, Sendable {
    let legID: TravelLegID
    var transportType: TravelTransportType
    var manualDurationMinutes: Int?
    var note: String?
}

struct TravelLegRoutingFingerprint: Hashable, Sendable {
    let legID: TravelLegID
    let fromPlaceID: PlaceSnapshot.ID
    let toPlaceID: PlaceSnapshot.ID
    let fromLatitude: Double
    let fromLongitude: Double
    let toLatitude: Double
    let toLongitude: Double
    let transportType: TravelTransportType
}

struct TravelLegEstimate: Hashable, Sendable {
    let durationMinutes: Int
    let calculatedAt: Date
}

enum TravelLegCalculationState: Hashable, Sendable {
    case idle
    case loading
    case loaded(TravelLegEstimate)
    case unavailable
    case failed
    case stale(TravelLegEstimate)
}

struct TravelLeg: Identifiable, Hashable, Sendable {
    enum DurationSource: Hashable, Sendable {
        case manual
        case mapKit
        case staleMapKit
    }

    let id: TravelLegID
    let dayID: Day.ID
    let fromPlace: PlaceSnapshot
    let toPlace: PlaceSnapshot
    let transportType: TravelTransportType
    let manualDurationMinutes: Int?
    let note: String?
    let calculationState: TravelLegCalculationState

    var routingFingerprint: TravelLegRoutingFingerprint {
        TravelLegRoutingFingerprint(
            legID: id,
            fromPlaceID: fromPlace.id,
            toPlaceID: toPlace.id,
            fromLatitude: fromPlace.latitude,
            fromLongitude: fromPlace.longitude,
            toLatitude: toPlace.latitude,
            toLongitude: toPlace.longitude,
            transportType: transportType
        )
    }

    var effectiveDuration: (minutes: Int, source: DurationSource)? {
        if let manualDurationMinutes, Self.isValidDuration(manualDurationMinutes) {
            return (manualDurationMinutes, .manual)
        }

        switch calculationState {
        case .loaded(let estimate) where Self.isValidDuration(estimate.durationMinutes):
            return (estimate.durationMinutes, .mapKit)
        case .stale(let estimate) where Self.isValidDuration(estimate.durationMinutes):
            return (estimate.durationMinutes, .staleMapKit)
        case .idle, .loading, .loaded, .unavailable, .failed, .stale:
            return nil
        }
    }

    private static func isValidDuration(_ minutes: Int) -> Bool {
        (1...1_439).contains(minutes)
    }
}

enum TravelLegProjection {
    static let estimateFreshness: TimeInterval = 24 * 60 * 60

    static func activeLegs(
        for trip: Trip,
        preferences: [TravelLegID: TravelLegPreference] = [:],
        calculations: [TravelLegRoutingFingerprint: TravelLegCalculationState] = [:],
        now: Date = Date()
    ) -> [TravelLeg] {
        trip.orderedDays.flatMap { day in
            zip(day.orderedActivities, day.orderedActivities.dropFirst()).compactMap { from, to in
                guard let fromPlace = from.place, let toPlace = to.place else { return nil }

                let legID = TravelLegID(
                    fromActivityID: from.id,
                    toActivityID: to.id
                )
                let preference = preferences[legID]
                let transportType = preference?.transportType ?? .automobile
                let fingerprint = TravelLegRoutingFingerprint(
                    legID: legID,
                    fromPlaceID: fromPlace.id,
                    toPlaceID: toPlace.id,
                    fromLatitude: fromPlace.latitude,
                    fromLongitude: fromPlace.longitude,
                    toLatitude: toPlace.latitude,
                    toLongitude: toPlace.longitude,
                    transportType: transportType
                )
                let calculationState = normalized(
                    calculations[fingerprint] ?? .idle,
                    now: now
                )

                return TravelLeg(
                    id: legID,
                    dayID: day.id,
                    fromPlace: fromPlace,
                    toPlace: toPlace,
                    transportType: transportType,
                    manualDurationMinutes: preference?.manualDurationMinutes,
                    note: preference?.note,
                    calculationState: calculationState
                )
            }
        }
    }

    private static func normalized(
        _ state: TravelLegCalculationState,
        now: Date
    ) -> TravelLegCalculationState {
        guard case .loaded(let estimate) = state,
              now.timeIntervalSince(estimate.calculatedAt) >= estimateFreshness else {
            return state
        }
        return .stale(estimate)
    }
}
