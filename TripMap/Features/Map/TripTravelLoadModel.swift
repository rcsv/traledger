import Combine
import CoreLocation
import Foundation
import MapKit

/// Consecutive Venue pairs are resolved with MapKit driving directions. The
/// results stay in memory because a route is derived data, not part of a Trip.
@MainActor
final class TripTravelLoadModel: ObservableObject {
    @Published private(set) var legs: [TravelLeg] = []

    private var calculations: [TravelLegRoutingFingerprint: TravelLegCalculationState] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private let calculateRoute: @MainActor (
        CLLocationCoordinate2D,
        CLLocationCoordinate2D,
        TravelTransportType
    ) async -> TravelLegCalculationState

    init(
        calculateRoute: @escaping @MainActor (
            CLLocationCoordinate2D,
            CLLocationCoordinate2D,
            TravelTransportType
        ) async -> TravelLegCalculationState = TripTravelLoadModel.calculate
    ) {
        self.calculateRoute = calculateRoute
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh(for trip: Trip) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = nil
        calculations = calculations.mapValues { state in
            if case .loading = state {
                return .idle
            }
            return state
        }

        #if TRIPMAP_QA
        if ProcessInfo.processInfo.arguments.contains("-tripmap-travel-leg-qa") {
            let now = Date()
            let projectedLegs = TravelLegProjection.activeLegs(
                for: trip,
                preferences: preferences(for: trip),
                now: now
            )
            calculations = Dictionary(
                uniqueKeysWithValues: projectedLegs.enumerated().map { index, leg in
                    let state: TravelLegCalculationState = index == 0
                        ? .loaded(TravelLegEstimate(durationMinutes: 25, calculatedAt: now))
                        : .unavailable
                    return (leg.routingFingerprint, state)
                }
            )
            publishLegs(for: trip)
            return
        }
        #endif

        let projectedLegs = TravelLegProjection.activeLegs(
            for: trip,
            preferences: preferences(for: trip),
            calculations: calculations
        )
        let activeFingerprints = Set(projectedLegs.map(\.routingFingerprint))
        calculations = calculations.filter { activeFingerprints.contains($0.key) }

        let requests = projectedLegs.compactMap { leg -> RouteRequest? in
            let shouldRequest: Bool
            switch leg.calculationState {
            case .idle, .stale:
                shouldRequest = true
            case .loading, .loaded, .unavailable, .failed:
                shouldRequest = false
            }
            guard shouldRequest else { return nil }

            if leg.transportType == .other {
                calculations[leg.routingFingerprint] = .unavailable
                return nil
            }

            if case .idle = leg.calculationState {
                calculations[leg.routingFingerprint] = .loading
            }
            return RouteRequest(
                fingerprint: leg.routingFingerprint,
                fromCoordinate: leg.fromPlace.coordinate,
                toCoordinate: leg.toPlace.coordinate,
                transportType: leg.transportType
            )
        }
        publishLegs(for: trip)
        guard !requests.isEmpty else { return }

        let calculateRoute = calculateRoute
        refreshTask = Task { [weak self] in
            for request in requests {
                guard !Task.isCancelled else { return }
                let calculationState = await calculateRoute(
                    request.fromCoordinate,
                    request.toCoordinate,
                    request.transportType
                )
                guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
                self.calculations[request.fingerprint] = calculationState
                self.publishLegs(for: trip)
            }
        }
    }

    func retry(_ legID: TravelLegID, for trip: Trip) {
        guard let leg = TravelLegProjection.activeLegs(
            for: trip,
            preferences: preferences(for: trip),
            calculations: calculations
        ).first(where: { $0.id == legID }) else {
            return
        }
        calculations[leg.routingFingerprint] = .idle
        refresh(for: trip)
    }

    /// Test seam for deterministic cancellation and refresh verification.
    func awaitCurrentRefresh() async {
        await refreshTask?.value
    }

    private func publishLegs(for trip: Trip) {
        legs = TravelLegProjection.activeLegs(
            for: trip,
            preferences: preferences(for: trip),
            calculations: calculations
        )
    }

    private func preferences(for trip: Trip) -> [TravelLegID: TravelLegPreference] {
        Dictionary(
            trip.travelLegPreferences.map { ($0.legID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private static func calculate(
        from fromCoordinate: CLLocationCoordinate2D,
        to toCoordinate: CLLocationCoordinate2D,
        transportType: TravelTransportType
    ) async -> TravelLegCalculationState {
        let directionsRequest = MKDirections.Request()
        directionsRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: fromCoordinate))
        directionsRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: toCoordinate))
        directionsRequest.transportType = transportType.mapKitTransportType

        do {
            let response = try await MKDirections(request: directionsRequest).calculate()
            guard let route = response.routes.first else { return .unavailable }
            return .loaded(
                TravelLegEstimate(
                    durationMinutes: max(1, Int((route.expectedTravelTime / 60).rounded())),
                    calculatedAt: Date()
                )
            )
        } catch {
            return .failed
        }
    }
}

private extension TravelTransportType {
    var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .walking: .walking
        case .transit: .transit
        case .other: .any
        }
    }
}

private struct RouteRequest {
    let fingerprint: TravelLegRoutingFingerprint
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    let transportType: TravelTransportType
}
