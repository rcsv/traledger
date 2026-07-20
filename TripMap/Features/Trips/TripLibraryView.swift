import SwiftUI

enum SupportedCurrency: String, CaseIterable, Identifiable {
    case jpy = "JPY"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpy: "日本円（JPY）"
        case .usd: "米ドル（USD）"
        case .eur: "ユーロ（EUR）"
        case .gbp: "英ポンド（GBP）"
        }
    }
}

struct NewTripDraft {
    var title = ""
    var startDate = Date()
    var endDate = Date()
    var timeZoneIdentifier = TimeZone.current.identifier
    var defaultCurrencyCode = SupportedCurrency.jpy.rawValue
}

struct NewTripView: View {
    let onCreate: (NewTripDraft) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewTripDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(onCreate: @escaping (NewTripDraft) -> String?, defaultCurrencyCode: String = SupportedCurrency.jpy.rawValue) {
        self.onCreate = onCreate
        _draft = State(initialValue: NewTripDraft(defaultCurrencyCode: defaultCurrencyCode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("旅行") {
                    TextField("旅行名", text: $draft.title, prompt: Text("沖縄・瀬底 4日間"))
                        .accessibilityIdentifier("new-trip-title")
                    DatePicker("開始日", selection: $draft.startDate, displayedComponents: .date)
                        .accessibilityIdentifier("new-trip-start-date")
                    DatePicker("終了日", selection: $draft.endDate, displayedComponents: .date)
                        .accessibilityIdentifier("new-trip-end-date")
                }

                Section("時刻の基準") {
                    LabeledContent("タイムゾーン", value: timeZoneName)
                    Text("現在の端末設定を使用します。旅行先のタイムゾーン変更は後続で追加します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("予算の基準") {
                    Picker("旅行の通貨", selection: $draft.defaultCurrencyCode) {
                        ForEach(SupportedCurrency.allCases) { currency in
                            Text(currency.label).tag(currency.rawValue)
                        }
                    }
                    Text("明細ごとに異なる通貨を使えるようになる予定です。この値は旅行の既定値です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("new-trip-error")
                    }
                }
            }
            .navigationTitle("新しい旅行")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 360)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { create() }
                        .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("create-trip")
                }
            }
            .onChange(of: draft.startDate) { _, startDate in
                if draft.endDate < startDate {
                    draft.endDate = startDate
                }
            }
        }
    }

    private var timeZoneName: String {
        TimeZone(identifier: draft.timeZoneIdentifier)?
            .localizedName(for: .standard, locale: .current) ?? draft.timeZoneIdentifier
    }

    private func create() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = onCreate(draft)
        isSaving = false
        if errorMessage == nil {
            dismiss()
        }
    }
}

struct TripLibraryView: View {
    let trips: [StoredTrip]
    let selectedTripID: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletionID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(trips) { trip in
                    Button {
                        onSelect(trip.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedTripID == trip.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTripID == trip.id ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.title.isEmpty ? "名称未設定" : trip.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(dateRangeText(for: trip))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView("旅行がありません", systemImage: "suitcase.rolling")
                }
            }
            .navigationTitle("旅行")
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 420)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("選択中の旅行を削除", systemImage: "trash") {
                        pendingDeletionID = selectedTripID
                    }
                    .disabled(selectedTripID == nil)
                }
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
            .alert("削除できませんでした", isPresented: errorAlert) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "不明なエラー")
            }
        }
    }

    private var pendingDeletionTrip: StoredTrip? {
        trips.first(where: { $0.id == pendingDeletionID })
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

    private func deletePendingTrip() {
        guard let pendingDeletionID else { return }
        let deletionError = onDelete(pendingDeletionID)
        self.pendingDeletionID = nil
        errorMessage = deletionError
    }

    private func dateRangeText(for trip: StoredTrip) -> String {
        guard let start = LocalDate(code: trip.startDateCode),
              let end = LocalDate(code: trip.endDateCode) else {
            return "日付を読み取れません"
        }
        if start == end {
            return localDateText(start)
        }
        return "\(localDateText(start)) – \(localDateText(end))"
    }

    private func localDateText(_ date: LocalDate) -> String {
        String(format: "%04d/%02d/%02d", date.year, date.month, date.day)
    }
}
