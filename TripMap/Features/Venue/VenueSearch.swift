import Combine
import Foundation
import MapKit
import SwiftUI

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

    var candidate: VenueCandidate {
        VenueCandidate(place: snapshot, mapItem: mapItem)
    }
}

/// A MapKit result that is still outside the Trip domain. It only becomes
/// persisted after the user confirms an Activity draft.
struct VenueCandidate: Identifiable {
    let place: PlaceSnapshot
    let mapItem: MKMapItem

    var id: PlaceSnapshot.ID { place.id }

    var categoryLabel: String? {
        guard let category = mapItem.pointOfInterestCategory else { return nil }
        return switch category {
        case .airport: "空港"
        case .amusementPark: "テーマパーク"
        case .aquarium: "水族館"
        case .bakery: "ベーカリー"
        case .beach: "ビーチ"
        case .brewery: "醸造所"
        case .cafe: "カフェ"
        case .campground: "キャンプ場"
        case .carRental: "レンタカー"
        case .evCharger: "EV充電"
        case .gasStation: "ガソリンスタンド"
        case .hotel: "ホテル"
        case .library: "図書館"
        case .marina: "マリーナ"
        case .movieTheater: "映画館"
        case .museum: "博物館・美術館"
        case .nationalPark: "国立公園"
        case .nightlife: "ナイトライフ"
        case .park: "公園"
        case .parking: "駐車場"
        case .pharmacy: "薬局"
        case .publicTransport: "公共交通"
        case .restaurant: "レストラン"
        case .restroom: "トイレ"
        case .store: "ショップ"
        case .theater: "劇場"
        case .university: "大学"
        case .winery: "ワイナリー"
        case .zoo: "動物園"
        default: nil
        }
    }
}

@MainActor
final class VenueSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var results: [VenueSearchResult] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCompleting = false
    @Published private(set) var isResolving = false
    @Published private(set) var didResolveSearch = false

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
        isCompleting = false
        isResolving = false
        didResolveSearch = false
        activeSearch?.cancel()
        activeSearch = nil
        completer.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isCompleting = true
        completer.queryFragment = trimmedQuery
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isCompleting = false
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isCompleting = false
        errorMessage = error.localizedDescription
    }

    func resolve(_ completion: MKLocalSearchCompletion) {
        searchGeneration += 1
        let generation = searchGeneration
        errorMessage = nil
        completions = []
        results = []
        isCompleting = false
        isResolving = true
        didResolveSearch = false
        activeSearch?.cancel()

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        activeSearch = search
        search.start { [weak self] response, error in
            guard let self, self.searchGeneration == generation else { return }
            self.results = response?.mapItems.map(VenueSearchResult.init) ?? []
            self.errorMessage = error?.localizedDescription
            self.isResolving = false
            self.didResolveSearch = true
            self.activeSearch = nil
        }
    }

    func report(error: String?) {
        errorMessage = error
    }
}

struct VenueSearchSheet: View {
    let onSelect: (VenueCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = VenueSearchModel()
    @State private var query = ""
    @State private var selectedResult: VenueSearchResult?

    var body: some View {
        sheetContent
            .alert("場所を検索できませんでした", isPresented: Binding(
                get: { search.errorMessage != nil },
                set: { if !$0 { search.report(error: nil) } }
            )) {
                Button("OK") { search.report(error: nil) }
            } message: {
                Text(search.errorMessage ?? "不明なエラー")
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(macOS)
        navigationContent
            .frame(minWidth: 740, minHeight: 500)
        #else
        navigationContent
        #endif
    }

    private var navigationContent: some View {
        NavigationStack {
            adaptiveContent
                .navigationTitle("場所を検索")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("この場所を設定") {
                            if let selectedResult { onSelect(selectedResult.candidate) }
                            dismiss()
                        }
                        .disabled(selectedResult == nil)
                    }
                }
        }
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        #if os(macOS)
        HSplitView {
            searchResults
                .frame(minWidth: 290)
            venuePreview
                .frame(minWidth: 360)
        }
        #else
        VStack(spacing: 0) {
            searchResults
            Divider()
            venuePreview
                .frame(minHeight: 220)
        }
        #endif
    }

    private var searchResults: some View {
        List {
            if search.isResolving {
                ProgressView("場所を確認中…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if !search.results.isEmpty {
                Section("検索結果") {
                    ForEach(search.results) { result in
                        resultButton(result)
                    }
                }
            } else if search.didResolveSearch {
                ContentUnavailableView(
                    "場所が見つかりません",
                    systemImage: "mappin.slash",
                    description: Text("別の施設名や住所で検索してください。")
                )
            } else if !search.completions.isEmpty {
                Section("候補") {
                    ForEach(search.completions, id: \.self) { completion in
                        Button {
                            search.resolve(completion)
                        } label: {
                            completionLabel(completion)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if search.isCompleting {
                ProgressView("候補を検索中…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "場所を検索",
                    systemImage: "magnifyingglass",
                    description: Text("施設名または住所を入力してください。")
                )
            } else {
                ContentUnavailableView(
                    "候補がありません",
                    systemImage: "magnifyingglass",
                    description: Text("入力を変えてもう一度検索してください。")
                )
            }
        }
        .searchable(text: $query, prompt: "施設名または住所")
        .onChange(of: query) { _, value in
            selectedResult = nil
            search.update(query: value)
        }
    }

    private func resultButton(_ result: VenueSearchResult) -> some View {
        Button {
            selectedResult = result
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                Text(result.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedResult?.id == result.id ? Color.accentColor.opacity(0.16) : Color.clear)
        .accessibilityAddTraits(selectedResult?.id == result.id ? .isSelected : [])
    }

    private func completionLabel(_ completion: MKLocalSearchCompletion) -> some View {
        let title = completion.title
        let subtitle = completion.subtitle
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !subtitle.isEmpty {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var venuePreview: some View {
        if let selectedResult {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: selectedResult.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ))) {
                    Marker(selectedResult.name, coordinate: selectedResult.coordinate)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(minHeight: 300)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedResult.name).font(.headline)
                    Text(selectedResult.address).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "候補を選択してください",
                systemImage: "mappin.and.ellipse",
                description: Text("選択した場所を地図で確認できます。")
            )
        }
    }
}
