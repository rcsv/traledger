import Combine
import CoreLocation
import Foundation
import MapKit

/// Consecutive Venue pairs are resolved with MapKit driving directions. The
/// results stay in memory because a route is derived data, not part of a Trip.
@MainActor
final class TripTravelLoadModel: ObservableObject {
    @Published private(set) var estimates: [TripTravelEstimate] = []

    private var estimatesByKey: [RouteKey: TripTravelEstimate] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    deinit {
        refreshTask?.cancel()
    }

    func refresh(for trip: Trip) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()

        let requests = routeRequests(for: trip)
        let requestKeys = Set(requests.map(\.key))
        estimatesByKey = estimatesByKey.filter { requestKeys.contains($0.key) }
        publishEstimates()

        let missingRequests = requests.filter { estimatesByKey[$0.key] == nil }
        guard !missingRequests.isEmpty else { return }

        refreshTask = Task { [weak self] in
            for request in missingRequests {
                guard !Task.isCancelled else { return }
                guard let minutes = await Self.calculateDrivingMinutes(for: request) else { continue }
                guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
                self.estimatesByKey[request.key] = TripTravelEstimate(
                    dayID: request.dayID,
                    fromActivityID: request.key.fromActivityID,
                    toActivityID: request.key.toActivityID,
                    expectedTravelMinutes: minutes
                )
                self.publishEstimates()
            }
        }
    }

    private func publishEstimates() {
        estimates = estimatesByKey.values.sorted {
            if $0.dayID != $1.dayID {
                return $0.dayID.uuidString < $1.dayID.uuidString
            }
            return $0.fromActivityID.uuidString < $1.fromActivityID.uuidString
        }
    }

    private func routeRequests(for trip: Trip) -> [RouteRequest] {
        trip.orderedDays.flatMap { day in
            zip(day.orderedActivities, day.orderedActivities.dropFirst()).compactMap { from, to in
                guard let fromPlace = from.place, let toPlace = to.place else { return nil }
                return RouteRequest(
                    key: RouteKey(
                        fromActivityID: from.id,
                        toActivityID: to.id,
                        fromPlaceID: fromPlace.id,
                        toPlaceID: toPlace.id
                    ),
                    dayID: day.id,
                    fromCoordinate: fromPlace.coordinate,
                    toCoordinate: toPlace.coordinate
                )
            }
        }
    }

    private static func calculateDrivingMinutes(for request: RouteRequest) async -> Int? {
        let directionsRequest = MKDirections.Request()
        directionsRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: request.fromCoordinate))
        directionsRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: request.toCoordinate))
        directionsRequest.transportType = .automobile

        do {
            let response = try await MKDirections(request: directionsRequest).calculate()
            guard let route = response.routes.first else { return nil }
            return max(1, Int((route.expectedTravelTime / 60).rounded()))
        } catch {
            return nil
        }
    }
}

private struct RouteKey: Hashable {
    let fromActivityID: Activity.ID
    let toActivityID: Activity.ID
    let fromPlaceID: PlaceSnapshot.ID
    let toPlaceID: PlaceSnapshot.ID
}

private struct RouteRequest {
    let key: RouteKey
    let dayID: Day.ID
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
}
