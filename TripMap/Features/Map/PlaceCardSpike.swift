import Combine
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
            Button {
                isPresented = true
            } label: {
                Label("場所の詳細", systemImage: "info.circle")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $isPresented) {
                NativePlaceCardSheet(place: place, isPresented: $isPresented)
            }
            .accessibilityIdentifier("native-place-card-button")
        }
    }
}

struct ResolvedMapsButton: View {
    let place: PlaceSnapshot
    @StateObject private var resolution = PlaceResolutionModel()

    var body: some View {
        Button {
            resolution.load(place) { mapItem in
                mapItem.openInMaps()
            }
        } label: {
            HStack(spacing: 5) {
                if resolution.phase == .loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "map")
                }
                Text(resolution.phase == .loading ? "検索中" : "Mapsで開く")
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .disabled(resolution.phase == .loading)
        .accessibilityIdentifier("resolved-maps-button")
        .alert("Apple Mapsで場所を開けませんでした", isPresented: errorAlert) {
            Button("OK") { resolution.dismissError() }
        } message: {
            Text(resolution.errorMessage ?? "一致する場所が見つかりませんでした。")
        }
        .onDisappear {
            resolution.cancel()
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { resolution.phase == .failed },
            set: { if !$0 { resolution.dismissError() } }
        )
    }
}

@available(macOS 15.0, iOS 18.0, *)
private struct NativePlaceCardSheet: View {
    let place: PlaceSnapshot
    @Binding var isPresented: Bool
    @StateObject private var resolution = PlaceResolutionModel()

    var body: some View {
        Group {
            switch resolution.phase {
            case .idle, .loading:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Apple Mapsから場所を取得中…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("native-place-card-loading")

            case .loaded:
                if let mapItem = resolution.mapItem {
                    NativePlaceCard(mapItem: mapItem, isPresented: $isPresented)
                }

            case .failed:
                ContentUnavailableView {
                    Label("場所の詳細を取得できません", systemImage: "mappin.slash")
                } description: {
                    Text(resolution.errorMessage ?? "Apple Mapsで一致する場所が見つかりませんでした。")
                } actions: {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
                .padding()
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 520, idealHeight: 640)
        #endif
        .task(id: place.id) {
            resolution.load(place)
        }
        .onDisappear {
            resolution.cancel()
        }
    }
}

@MainActor
final class PlaceResolutionModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mapItem: MKMapItem?
    @Published private(set) var errorMessage: String?

    private var resolutionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func load(_ place: PlaceSnapshot, onSuccess: @escaping @MainActor (MKMapItem) -> Void = { _ in }) {
        cancel()
        phase = .loading
        mapItem = nil
        errorMessage = nil

        resolutionTask = Task { [weak self] in
            do {
                let item = try await PlaceMapItemResolver.resolve(place)
                guard let self, !Task.isCancelled, self.phase == .loading else { return }
                self.timeoutTask?.cancel()
                self.mapItem = item
                self.phase = .loaded
                onSuccess(item)
            } catch is CancellationError {
            } catch {
                guard let self, self.phase == .loading else { return }
                self.timeoutTask?.cancel()
                self.errorMessage = error.localizedDescription
                self.phase = .failed
            }
        }

        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let self, self.phase == .loading else { return }
            self.resolutionTask?.cancel()
            self.errorMessage = PlaceCardError.timedOut.localizedDescription
            self.phase = .failed
        }
    }

    func cancel() {
        resolutionTask?.cancel()
        timeoutTask?.cancel()
        resolutionTask = nil
        timeoutTask = nil
    }

    func dismissError() {
        errorMessage = nil
        if phase == .failed {
            phase = .idle
        }
    }
}

@MainActor
enum PlaceMapItemResolver {
    static func resolve(_ place: PlaceSnapshot) async throws -> MKMapItem {
        if #available(macOS 15.0, iOS 18.0, *),
           let rawIdentifier = place.mapKitIdentifier,
           let identifier = MKMapItem.Identifier(rawValue: rawIdentifier),
           let identifiedItem = try? await item(for: identifier) {
            return identifiedItem
        }

        return try await search(for: place)
    }

    static func bestMatch(in mapItems: [MKMapItem], for place: PlaceSnapshot) -> MKMapItem? {
        let origin = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let targetName = normalized(place.name)
        let ranked = mapItems.map { item in
            let itemName = normalized(item.name ?? "")
            let nameRank: Int
            if !targetName.isEmpty, itemName == targetName {
                nameRank = 0
            } else if !targetName.isEmpty,
                      !itemName.isEmpty,
                      (itemName.contains(targetName) || targetName.contains(itemName)) {
                nameRank = 1
            } else {
                nameRank = 2
            }
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            return (item: item, nameRank: nameRank, distance: distance)
        }

        guard let best = ranked.min(by: { lhs, rhs in
            lhs.nameRank == rhs.nameRank ? lhs.distance < rhs.distance : lhs.nameRank < rhs.nameRank
        }), best.nameRank < 2 || best.distance <= 500 else {
            return nil
        }
        return best.item
    }

    @available(macOS 15.0, iOS 18.0, *)
    private static func item(for identifier: MKMapItem.Identifier) async throws -> MKMapItem {
        let request = MKMapItemRequest(mapItemIdentifier: identifier)
        return try await request.mapItem
    }

    private static func search(for place: PlaceSnapshot) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.name
        request.region = MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
        request.resultTypes = .pointOfInterest

        let response = try await MKLocalSearch(request: request).start()
        guard let match = bestMatch(in: response.mapItems, for: place) else {
            throw PlaceCardError.placeNotFound
        }
        return match
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }
}

enum PlaceCardError: LocalizedError {
    case placeNotFound
    case timedOut

    var errorDescription: String? {
        switch self {
        case .placeNotFound:
            "Apple Mapsで一致するPOIが見つかりませんでした。"
        case .timedOut:
            "Apple Mapsからの取得がタイムアウトしました。通信状況を確認して、もう一度お試しください。"
        }
    }
}

#if os(macOS)
@available(macOS 15.0, iOS 18.0, *)
private struct NativePlaceCard: NSViewControllerRepresentable {
    let mapItem: MKMapItem
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
    let mapItem: MKMapItem
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
