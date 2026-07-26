import Combine
import Foundation
import MapKit
import SwiftUI

private enum VenueSearchKeyboardSelection: Equatable {
    case completion(Int)
    case result(Int)
}

struct VenueSearchCompletion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let mapKitCompletion: MKLocalSearchCompletion?

    init(_ completion: MKLocalSearchCompletion) {
        title = completion.title
        subtitle = completion.subtitle
        mapKitCompletion = completion
    }

    #if TRIPMAP_QA
    init(qaTitle: String, subtitle: String) {
        title = qaTitle
        self.subtitle = subtitle
        mapKitCompletion = nil
    }
    #endif
}

/// MapKit の補完候補を解決して、アプリで保持できる会場情報へ変換する検索モデルです。
struct VenueSearchResult: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    private let addressOverride: String?

    var name: String { mapItem.name ?? "名称未設定の場所" }
    var address: String {
        addressOverride ?? mapItem.placemark.title ?? "住所情報がありません"
    }
    var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        addressOverride = nil
    }

    #if TRIPMAP_QA
    init(
        qaName: String,
        address: String,
        coordinate: CLLocationCoordinate2D
    ) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = qaName
        self.mapItem = mapItem
        addressOverride = address
    }
    #endif

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
    @Published private(set) var completions: [VenueSearchCompletion] = []
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
        #if TRIPMAP_QA
        seedQAFixtureIfRequested()
        #endif
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
        completions = completer.results.map(VenueSearchCompletion.init)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isCompleting = false
        errorMessage = error.localizedDescription
    }

    func resolve(_ completion: VenueSearchCompletion) {
        searchGeneration += 1
        let generation = searchGeneration
        errorMessage = nil
        completions = []
        results = []
        isCompleting = false
        isResolving = true
        didResolveSearch = false
        activeSearch?.cancel()

        guard let mapKitCompletion = completion.mapKitCompletion else {
            #if TRIPMAP_QA
            seedResolvedQAFixture()
            #else
            isResolving = false
            errorMessage = "検索候補を解決できませんでした。"
            #endif
            return
        }

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: mapKitCompletion))
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

    #if TRIPMAP_QA
    private func seedQAFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-tripmap-venue-search-qa-state"),
              arguments.indices.contains(flagIndex + 1) else {
            return
        }

        switch arguments[flagIndex + 1] {
        case "completion-list":
            completions = [
                VenueSearchCompletion(
                    qaTitle: "沖縄美ら海水族館",
                    subtitle: "沖縄県国頭郡本部町"
                ),
                VenueSearchCompletion(
                    qaTitle: "首里城公園",
                    subtitle: "沖縄県那覇市"
                )
            ]
        case "completion-loading":
            isCompleting = true
        case "result-resolving":
            isResolving = true
        case "result-list":
            results = [Self.qaResult]
            didResolveSearch = true
        case "no-result":
            didResolveSearch = true
        case "failure":
            errorMessage = "QA fixture: 場所を検索できません。"
        default:
            break
        }
    }

    private func seedResolvedQAFixture() {
        results = [Self.qaResult]
        isResolving = false
        didResolveSearch = true
    }

    private static var qaResult: VenueSearchResult {
        VenueSearchResult(
            qaName: "沖縄美ら海水族館",
            address: "沖縄県国頭郡本部町",
            coordinate: CLLocationCoordinate2D(
                latitude: 26.6943,
                longitude: 127.8779
            )
        )
    }
    #endif
}

struct VenueSearchSheet: View {
    let onSelect: (VenueCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = VenueSearchModel()
    @State private var query = ""
    @State private var selectedResult: VenueSearchResult?
    @State private var keyboardSelection: VenueSearchKeyboardSelection?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        sheetContent
            .preferredColorScheme(qaPreferredColorScheme)
            .onChange(of: query) { _, value in
                selectedResult = nil
                keyboardSelection = nil
                search.update(query: value)
            }
            .alert("場所を検索できませんでした", isPresented: Binding(
                get: { search.errorMessage != nil },
                set: { if !$0 { search.report(error: nil) } }
            )) {
                Button("OK") { search.report(error: nil) }
            } message: {
                Text(search.errorMessage ?? "不明なエラー")
            }
    }

    private var qaPreferredColorScheme: ColorScheme? {
        #if TRIPMAP_QA
        ProcessInfo.processInfo.arguments.contains("-tripmap-qa-dark-appearance")
            ? .dark
            : nil
        #else
        nil
        #endif
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(macOS)
        macOSContent
        #else
        navigationContent
        #endif
    }

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            macOSHeader
            Divider()
            HSplitView {
                macOSSearchPane
                    .frame(minWidth: 320, idealWidth: 340)
                venuePreview
                    .frame(minWidth: 400, idealWidth: 500)
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("venue-search-preview")
            }
            .frame(maxHeight: .infinity)
            Divider()
            macOSFooter
        }
        .frame(
            minWidth: 760,
            idealWidth: 840,
            minHeight: 520,
            idealHeight: 600
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("venue-search-sheet")
        .onAppear {
            isSearchFocused = true
        }
    }

    private var macOSHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("場所を検索")
                .font(.title2.bold())
            Text("施設名または住所から、予定に設定する場所を選択します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("venue-search-header")
    }

    private var macOSSearchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("施設名または住所", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("施設名または住所")
                    .accessibilityIdentifier("venue-search-field")
                    .onKeyPress(.downArrow) {
                        moveKeyboardSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveKeyboardSelection(by: -1)
                        return .handled
                    }
                    .onSubmit {
                        activateKeyboardSelection()
                    }

                if !query.isEmpty {
                    Button("検索文字列を消去", systemImage: "xmark.circle.fill") {
                        query = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("venue-search-clear")
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSearchFocused ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: isSearchFocused ? 2 : 1
                    )
            }
            .padding(12)

            Divider()

            searchResults
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("venue-search-results")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var macOSFooter: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("キャンセル") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("venue-search-cancel")

            Button("この場所を設定") {
                confirmSelection()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedResult == nil)
            .accessibilityIdentifier("venue-search-confirm")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("venue-search-footer")
    }
    #endif

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
                            confirmSelection()
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
                .searchable(text: $query, prompt: "施設名または住所")
            Divider()
            venuePreview
                .frame(minHeight: 220)
        }
        #endif
    }

    @ViewBuilder
    private var searchResults: some View {
        if search.isResolving {
            centeredState {
                ProgressView("場所を確認中…")
                    .accessibilityIdentifier("venue-search-result-resolving")
            }
        } else if !search.results.isEmpty {
            List {
                Section("検索結果") {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { index, result in
                        resultButton(result, index: index)
                    }
                }
            }
        } else if search.didResolveSearch {
            ContentUnavailableView(
                "場所が見つかりません",
                systemImage: "mappin.slash",
                description: Text("別の施設名や住所で検索してください。")
            )
            .accessibilityIdentifier("venue-search-no-result")
        } else if !search.completions.isEmpty {
            List {
                Section("候補") {
                    ForEach(Array(search.completions.enumerated()), id: \.element.id) { index, completion in
                        completionButton(completion, index: index)
                    }
                }
            }
        } else if search.isCompleting {
            centeredState {
                ProgressView("候補を検索中…")
                    .accessibilityIdentifier("venue-search-completion-loading")
            }
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "場所を検索",
                systemImage: "magnifyingglass",
                description: Text("施設名または住所を入力してください。")
            )
            .accessibilityIdentifier("venue-search-idle")
        } else {
            ContentUnavailableView(
                "候補がありません",
                systemImage: "magnifyingglass",
                description: Text("入力を変えてもう一度検索してください。")
            )
            .accessibilityIdentifier("venue-search-no-completion")
        }
    }

    private func resultButton(_ result: VenueSearchResult, index: Int) -> some View {
        Button {
            selectedResult = result
            keyboardSelection = .result(index)
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
        .listRowBackground(
            selectedResult?.id == result.id || keyboardSelection == .result(index)
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
        .accessibilityAddTraits(selectedResult?.id == result.id ? .isSelected : [])
        .accessibilityIdentifier("venue-search-result-\(index)")
    }

    private func completionButton(
        _ completion: VenueSearchCompletion,
        index: Int
    ) -> some View {
        Button {
            keyboardSelection = .completion(index)
            search.resolve(completion)
        } label: {
            completionLabel(completion)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            keyboardSelection == .completion(index)
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
        .accessibilityIdentifier("venue-search-completion-\(index)")
    }

    private func completionLabel(_ completion: VenueSearchCompletion) -> some View {
        let title = completion.title
        let subtitle = completion.subtitle
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !subtitle.isEmpty {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private func centeredState<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func confirmSelection() {
        guard let selectedResult else { return }
        onSelect(selectedResult.candidate)
        dismiss()
    }

    private func moveKeyboardSelection(by offset: Int) {
        let count: Int
        let currentIndex: Int?
        let makesSelection: (Int) -> VenueSearchKeyboardSelection

        if !search.results.isEmpty {
            count = search.results.count
            if case .result(let index) = keyboardSelection {
                currentIndex = index
            } else {
                currentIndex = nil
            }
            makesSelection = VenueSearchKeyboardSelection.result
        } else if !search.completions.isEmpty {
            count = search.completions.count
            if case .completion(let index) = keyboardSelection {
                currentIndex = index
            } else {
                currentIndex = nil
            }
            makesSelection = VenueSearchKeyboardSelection.completion
        } else {
            return
        }

        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + offset, 0), count - 1)
        } else {
            nextIndex = offset < 0 ? count - 1 : 0
        }
        keyboardSelection = makesSelection(nextIndex)
    }

    private func activateKeyboardSelection() {
        switch keyboardSelection {
        case .completion(let index) where search.completions.indices.contains(index):
            search.resolve(search.completions[index])
        case .result(let index) where search.results.indices.contains(index):
            selectedResult = search.results[index]
        default:
            if search.results.count == 1 {
                selectedResult = search.results[0]
                keyboardSelection = .result(0)
            } else if search.completions.count == 1 {
                keyboardSelection = .completion(0)
                search.resolve(search.completions[0])
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
