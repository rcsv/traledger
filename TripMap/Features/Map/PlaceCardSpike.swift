import CoreLocation
import MapKit
import SwiftUI

/// Research Gate 0: keep TripMap's activity context and open Apple's native
/// place details only on the OS versions that provide them.
struct PlaceCardSpikeButton: View {
    let place: PlaceSnapshot
    @State private var isPresented = false

    var body: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            Button("場所の詳細", systemImage: "info.circle") {
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                NativePlaceCardSheet(place: place, isPresented: $isPresented)
            }
            .accessibilityIdentifier("native-place-card-button")
        }
    }
}

@available(macOS 15.0, iOS 18.0, *)
private struct NativePlaceCardSheet: View {
    let place: PlaceSnapshot
    @Binding var isPresented: Bool
    @State private var mapItem: MKMapItem?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            NativePlaceCard(mapItem: mapItem, isPresented: $isPresented)

            if let errorMessage {
                ContentUnavailableView {
                    Label("場所の詳細を取得できません", systemImage: "mappin.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Mapsで開く", systemImage: "map") {
                        openInMaps()
                    }
                    Button("閉じる") {
                        isPresented = false
                    }
                }
                .padding()
                .background(.background)
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 520, idealHeight: 640)
        #endif
        .task(id: place.id) {
            mapItem = nil
            errorMessage = nil
            do {
                mapItem = try await PlaceMapItemResolver.resolve(place)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps()
    }
}

@available(macOS 15.0, iOS 18.0, *)
@MainActor
private enum PlaceMapItemResolver {
    static func resolve(_ place: PlaceSnapshot) async throws -> MKMapItem {
        if let rawIdentifier = place.mapKitIdentifier,
           let identifier = MKMapItem.Identifier(rawValue: rawIdentifier),
           let identifiedItem = try? await item(for: identifier) {
            return identifiedItem
        }

        return try await search(for: place)
    }

    private static func item(for identifier: MKMapItem.Identifier) async throws -> MKMapItem {
        let request = MKMapItemRequest(mapItemIdentifier: identifier)
        return try await request.mapItem
    }

    private static func search(for place: PlaceSnapshot) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [place.name, place.address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        request.region = MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: 8_000,
            longitudinalMeters: 8_000
        )
        request.resultTypes = [.pointOfInterest, .address]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        let origin = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let nearest = response.mapItems.min(by: { lhs, rhs in
            origin.distance(from: CLLocation(latitude: lhs.placemark.coordinate.latitude, longitude: lhs.placemark.coordinate.longitude))
                < origin.distance(from: CLLocation(latitude: rhs.placemark.coordinate.latitude, longitude: rhs.placemark.coordinate.longitude))
        }) else {
            throw PlaceCardError.placeNotFound
        }
        return nearest
    }
}

private enum PlaceCardError: LocalizedError {
    case placeNotFound

    var errorDescription: String? {
        "Apple Mapsで一致する場所が見つかりませんでした。"
    }
}

#if os(macOS)
@available(macOS 15.0, iOS 18.0, *)
private struct NativePlaceCard: NSViewControllerRepresentable {
    let mapItem: MKMapItem?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSViewController(context: Context) -> MKMapItemDetailViewController {
        let controller = MKMapItemDetailViewController(mapItem: mapItem, displaysMap: false)
        controller.delegate = context.coordinator
        return controller
    }

    func updateNSViewController(_ controller: MKMapItemDetailViewController, context: Context) {
        controller.mapItem = mapItem
    }

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        @Binding private var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
            isPresented = false
        }
    }
}
#else
@available(macOS 15.0, iOS 18.0, *)
private struct NativePlaceCard: UIViewControllerRepresentable {
    let mapItem: MKMapItem?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        let controller = MKMapItemDetailViewController(mapItem: mapItem, displaysMap: false)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MKMapItemDetailViewController, context: Context) {
        controller.mapItem = mapItem
    }

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        @Binding private var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
            isPresented = false
        }
    }
}
#endif
