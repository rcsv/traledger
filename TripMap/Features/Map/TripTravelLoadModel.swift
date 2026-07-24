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

    deinit {
        refreshTask?.cancel()
    }

    func refresh(for trip: Trip) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()

        #if TRIPMAP_QA
        if ProcessInfo.processInfo.arguments.contains("-tripmap-travel-leg-qa") {
            let now = Date()
            let projectedLegs = TravelLegProjection.activeLegs(for: trip, now: now)
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

        refreshTask = Task { [weak self] in
            for request in requests {
                guard !Task.isCancelled else { return }
                let result = await Self.calculate(for: request)
                guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
                self.calculations[request.fingerprint] = result.calculationState
                self.publishLegs(for: trip)
            }
        }
    }

    private func publishLegs(for trip: Trip) {
        legs = TravelLegProjection.activeLegs(
            for: trip,
            calculations: calculations
        )
    }

    private static func calculate(for request: RouteRequest) async -> RouteCalculationResult {
        let directionsRequest = MKDirections.Request()
        directionsRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: request.fromCoordinate))
        directionsRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: request.toCoordinate))
        directionsRequest.transportType = request.transportType.mapKitTransportType

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

private enum RouteCalculationResult {
    case loaded(TravelLegEstimate)
    case unavailable
    case failed

    var calculationState: TravelLegCalculationState {
        switch self {
        case .loaded(let estimate): .loaded(estimate)
        case .unavailable: .unavailable
        case .failed: .failed
        }
    }
}

private struct RouteRequest {
    let fingerprint: TravelLegRoutingFingerprint
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    let transportType: TravelTransportType
}
