import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct TripLibraryHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\StoredTrip.startDateCode),
        SortDescriptor(\StoredTrip.endDateCode),
        SortDescriptor(\StoredTrip.title)
    ]) private var storedTrips: [StoredTrip]
    @Binding private var scope: TripLibraryScope
    private let showsScopePicker: Bool
    private let creationRequestID: UUID?
    private let onOpenTrip: (UUID) -> Void
    private let onDeleteTrip: (UUID) -> Void
    @State private var searchText = ""
    @State private var isNewTripPresented = false
    @State private var pendingDeletionID: UUID?
    @State private var errorMessage: String?
    @State private var handledCreationRequestID: UUID?
    @AppStorage("planning.baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.jpy.rawValue

    init(
        scope: Binding<TripLibraryScope>,
        showsScopePicker: Bool,
        creationRequestID: UUID? = nil,
        onOpenTrip: @escaping (UUID) -> Void,
        onDeleteTrip: @escaping (UUID) -> Void = { _ in }
    ) {
        _scope = scope
        self.showsScopePicker = showsScopePicker
        self.creationRequestID = creationRequestID
        self.onOpenTrip = onOpenTrip
        self.onDeleteTrip = onDeleteTrip
    }

    var body: some View {
        List {
            if showsScopePicker {
                Section {
                    Picker("表示", selection: $scope) {
                        ForEach(TripLibraryScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            ForEach(visibleGroups, id: \.self) { group in
                let trips = trips(in: group)
                if !trips.isEmpty {
                    Section(group.title) {
                        ForEach(trips) { trip in
                            Button {
                                onOpenTrip(trip.id)
                            } label: {
                                TripLibraryRow(trip: trip, group: group)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("trip-\(trip.id.uuidString)")
                            .swipeActions {
                                Button("削除", role: .destructive) {
                                    pendingDeletionID = trip.id
                                }
                            }
                            .contextMenu {
                                Button("削除", systemImage: "trash", role: .destructive) {
                                    pendingDeletionID = trip.id
                                }
                            }
                        }
                    }
                }
            }

            if !unreadableTrips.isEmpty {
                Section("読み込めない旅行") {
                    ForEach(unreadableTrips) { trip in
                        UnreadableTripRow(trip: trip)
                            .swipeActions {
                                Button("削除", role: .destructive) {
                                    pendingDeletionID = trip.id
                                }
                            }
                            .contextMenu {
                                Button("削除", systemImage: "trash", role: .destructive) {
                                    pendingDeletionID = trip.id
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if visibleGroups.allSatisfy({ trips(in: $0).isEmpty }) && unreadableTrips.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "suitcase.rolling")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button("新しい旅行", systemImage: "plus") {
                        isNewTripPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(scope.title)
        .searchable(text: $searchText, prompt: "旅行を検索")
        .onAppear { handleCreationRequest(creationRequestID) }
        .onChange(of: creationRequestID) { _, requestID in
            handleCreationRequest(requestID)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新しい旅行", systemImage: "plus") {
                    isNewTripPresented = true
                }
                .accessibilityIdentifier("new-trip")
            }
        }
        .sheet(isPresented: $isNewTripPresented) {
            NewTripView(onCreate: createTrip, defaultCurrencyCode: baseCurrencyCode)
        }
        .confirmationDialog(
            "\(pendingDeletionTrip?.title ?? "この旅行")を削除しますか？",
            isPresented: deletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("旅行を削除", role: .destructive) { deletePendingTrip() }
            Button("キャンセル", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("DayとActivityも削除されます。この操作は取り消せません。")
        }
        .alert("保存できませんでした", isPresented: errorAlert) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    private var entriesByID: [UUID: TripTimelineEntry] {
        Dictionary(uniqueKeysWithValues: storedTrips.compactMap { trip in
            guard let startDate = LocalDate(code: trip.startDateCode),
                  let endDate = LocalDate(code: trip.endDateCode),
                  TimeZone(identifier: trip.timeZoneIdentifier) != nil else { return nil }
            return (
                trip.id,
                TripTimelineEntry(
                    id: trip.id,
                    startDate: startDate,
                    endDate: endDate,
                    timeZoneIdentifier: trip.timeZoneIdentifier
                )
            )
        })
    }

    private var groupedTripIDs: [TripTimelineGroup: [UUID]] {
        let groups = TripTimeline.grouped(entries: Array(entriesByID.values))
        return groups.mapValues { $0.map(\.id) }
    }

    private var storedTripsByID: [UUID: StoredTrip] {
        Dictionary(uniqueKeysWithValues: storedTrips.map { ($0.id, $0) })
    }

    private var unreadableTrips: [StoredTrip] {
        storedTrips.filter { trip in
            guard searchText.isEmpty || trip.title.localizedCaseInsensitiveContains(searchText) else {
                return false
            }
            return entriesByID[trip.id] == nil || trip.snapshot == nil
        }
    }

    private var visibleGroups: [TripTimelineGroup] {
        TripTimeline.visibleGroups(for: scope)
    }

    private var pendingDeletionTrip: StoredTrip? {
        storedTrips.first(where: { $0.id == pendingDeletionID })
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletionID != nil },
            set: { if !$0 { pendingDeletionID = nil } }
        )
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var emptyTitle: String {
        switch scope {
        case .upcoming: "Upcomingの旅行はありません"
        case .past: "Pastの旅行はありません"
        case .all: "旅行がありません"
        }
    }

    private var emptyDescription: String {
        scope == .past ? "過去の旅行はここに表示されます。" : "旅行を作成すると、ここから計画を開けます。"
    }

    private func trips(in group: TripTimelineGroup) -> [StoredTrip] {
        (groupedTripIDs[group] ?? []).compactMap { id in
            guard let trip = storedTripsByID[id],
                  searchText.isEmpty || trip.title.localizedCaseInsensitiveContains(searchText) else {
                return nil
            }
            return trip
        }
    }

    private func createTrip(_ draft: NewTripDraft) -> String? {
        guard let timeZone = TimeZone(identifier: draft.timeZoneIdentifier) else {
            return TripCreationError.invalidTimeZone.localizedDescription
        }
        let request = TripCreationRequest(
            title: draft.title,
            startDate: LocalDate(date: draft.startDate, timeZone: timeZone),
            endDate: LocalDate(date: draft.endDate, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier,
            defaultCurrencyCode: draft.defaultCurrencyCode
        )

        do {
            let trip = try TripFactory.makeTrip(from: request)
            modelContext.insert(try StoredTrip(validatingSnapshot: trip))
            try modelContext.save()
            onOpenTrip(trip.id)
            return nil
        } catch {
            modelContext.rollback()
            return error.localizedDescription
        }
    }

    private func handleCreationRequest(_ requestID: UUID?) {
        guard let requestID,
              requestID != handledCreationRequestID else {
            return
        }
        handledCreationRequestID = requestID
        isNewTripPresented = true
    }

    private func deletePendingTrip() {
        guard let pendingDeletionTrip else { return }
        let tripID = pendingDeletionTrip.id
        modelContext.delete(pendingDeletionTrip)
        do {
            try modelContext.save()
            pendingDeletionID = nil
            onDeleteTrip(tripID)
        } catch {
            modelContext.rollback()
            pendingDeletionID = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnreadableTripRow: View {
    let trip: StoredTrip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 54, height: 54)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title.isEmpty ? "名称未設定" : trip.title)
                    .font(.headline)
                Text("この旅行データを読み込めません。削除できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("unreadable-trip-\(trip.id.uuidString)")
    }
}

private struct TripLibraryRow: View {
    let trip: StoredTrip
    let group: TripTimelineGroup

    var body: some View {
        HStack(spacing: 12) {
            TripCoverThumbnail(data: trip.coverImageData, isOngoing: group == .ongoing)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.title.isEmpty ? "名称未設定" : trip.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(dateRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let memoryText {
                    Label(memoryText, systemImage: "photo.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var dateRangeText: String {
        guard let start = LocalDate(code: trip.startDateCode),
              let end = LocalDate(code: trip.endDateCode) else {
            return "日付を読み取れません"
        }
        let startText = String(format: "%04d/%02d/%02d", start.year, start.month, start.day)
        let endText = String(format: "%04d/%02d/%02d", end.year, end.month, end.day)
        return start == end ? startText : "\(startText) – \(endText)"
    }

    private var memoryText: String? {
        guard group == .past, let snapshot = trip.snapshot else { return nil }
        let summary = MemoryProjection.summary(for: snapshot)
        guard summary.visitedCount > 0 else { return nil }
        return "訪問 \(summary.visitedCount) · 記録 \(summary.recordedCount)"
    }
}

private struct TripCoverThumbnail: View {
    let data: Data?
    let isOngoing: Bool

    var body: some View {
        Group {
            #if os(macOS)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #elseif os(iOS)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: isOngoing ? [.green.opacity(0.75), .mint.opacity(0.65)] : [.blue.opacity(0.75), .mint.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: isOngoing ? "location.circle.fill" : "suitcase.rolling.fill")
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
