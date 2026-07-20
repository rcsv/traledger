import Combine
import Foundation
import MapKit

/// MapKit の補完候補を解決して、アプリで保持できる会場情報へ変換する検索モデルです。
struct VenueSearchResult: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem

    var name: String { mapItem.name ?? "名称未設定の場所" }
    var address: String { mapItem.placemark.title ?? "住所情報がありません" }
    var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }

    var snapshot: PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(),
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mapKitIdentifier: mapKitIdentifier
        )
    }

    private var mapKitIdentifier: String? {
        if #available(macOS 15.0, iOS 18.0, *) {
            return mapItem.identifier?.rawValue
        }
        return nil
    }
}

@MainActor
final class VenueSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var results: [VenueSearchResult] = []
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?
    private var searchGeneration = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        searchGeneration += 1
        errorMessage = nil
        completions = []
        results = []
        activeSearch?.cancel()
        activeSearch = nil
        completer.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
        } else {
            completer.queryFragment = trimmedQuery
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    func resolve(_ completion: MKLocalSearchCompletion) {
        searchGeneration += 1
        let generation = searchGeneration
        errorMessage = nil
        results = []
        activeSearch?.cancel()

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        activeSearch = search
        search.start { [weak self] response, error in
            guard let self, self.searchGeneration == generation else { return }
            self.results = response?.mapItems.map(VenueSearchResult.init) ?? []
            self.errorMessage = error?.localizedDescription
            self.activeSearch = nil
        }
    }

    func report(error: String?) {
        errorMessage = error
    }
}
