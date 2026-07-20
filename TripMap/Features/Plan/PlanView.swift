#if os(macOS)
import AppKit
import Foundation
import PhotosUI
import SwiftUI

private enum PlanDestination: Hashable {
    case overview
    case day(Day.ID)
}

struct PlanView: View {
    let trip: Trip
    let onApplyPlan: (Trip) -> String?
    @State private var destination: PlanDestination = .overview
    @State private var isMapVisible = true
    @State private var interaction: TripInteractionState
    @State private var operation: DayOperation?
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var isActivityCreationPresented = false
    @State private var errorMessage: String?

    init(trip: Trip, onApplyPlan: @escaping (Trip) -> String? = { _ in nil }) {
        self.trip = trip
        self.onApplyPlan = onApplyPlan
        _interaction = State(initialValue: TripInteractionState(trip: trip))
    }

    private var selectedDay: Day? {
        guard case .day = destination else { return nil }
        return interaction.selectedDay(in: trip)
    }

    private var destinationBinding: Binding<PlanDestination?> {
        Binding(
            get: { destination },
            set: { newDestination in
                guard let newDestination else { return }
                destination = newDestination
                if case .day(let dayID) = newDestination {
                    interaction.selectDay(dayID, in: trip)
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            destinationsSidebar
        } detail: {
            workspace
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(trip.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isMapVisible.toggle()
                } label: {
                    Label(isMapVisible ? "地図を隠す" : "地図を表示", systemImage: isMapVisible ? "map.fill" : "map")
                }
                .help(isMapVisible ? "地図を隠す" : "地図を表示")

                if let selectedDay {
                    Button("予定を追加", systemImage: "plus") {
                        isActivityCreationPresented = true
                    }

                    Menu("Day", systemImage: "calendar.badge.gearshape") {
                        Button("この日の予定をコピー…", systemImage: "document.on.document") {
                            operation = .replicate(selectedDay.id)
                        }
                        Button("別の日と入れ替え…", systemImage: "arrow.left.arrow.right") {
                            operation = .swap(selectedDay.id)
                        }
                    }
                }
            }
        }
        // Keep the map-control in the window toolbar while allowing the map to
        // continue behind it instead of reserving a separate white strip.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: isMapVisible ? 1000 : 760, minHeight: 620)
        .onChange(of: trip) { _, trip in
            interaction.reconcile(with: trip)
            if case .day(let dayID) = destination,
               !trip.days.contains(where: { $0.id == dayID }) {
                destination = .overview
            }
        }
        .task(id: coverPickerItem) {
            guard let originalData = try? await coverPickerItem?.loadTransferable(type: Data.self),
                  let data = TripImageProcessor.normalizedJPEGData(from: originalData) else {
                if coverPickerItem != nil { errorMessage = "表紙画像を読み込めませんでした。" }
                return
            }
            var updated = trip
            updated.coverImageData = data
            apply(updated)
            coverPickerItem = nil
        }
        .sheet(item: $operation) { operation in
            switch operation {
            case .replicate(let sourceDayID):
                DayReplicationSheet(days: trip.orderedDays, sourceDayID: sourceDayID) { targetDayIDs in
                    applyReplication(from: sourceDayID, to: targetDayIDs)
                }
            case .swap(let sourceDayID):
                DaySwapSheet(days: trip.orderedDays, sourceDayID: sourceDayID) { targetDayID in
                    applySwap(first: sourceDayID, second: targetDayID)
                }
            }
        }
        .sheet(isPresented: $isActivityCreationPresented) {
            if let selectedDay {
                ActivityCreationSheet(day: selectedDay) { title, startTime in
                    addActivity(to: selectedDay.id, title: title, startTime: startTime)
                }
            }
        }
        .alert("予定を更新できませんでした", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    private var destinationsSidebar: some View {
        List(selection: destinationBinding) {
            Label("Overview", systemImage: "rectangle.grid.2x2")
                .font(.headline)
                .padding(.vertical, 7)
                .tag(PlanDestination.overview)
                .accessibilityIdentifier("trip-overview")

            Section("Itinerary") {
                ForEach(trip.orderedDays) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Day \(day.sequence)")
                                .font(.headline)
                            Spacer(minLength: 8)
                            Text("\(day.activities.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .accessibilityLabel("\(day.activities.count) activities")
                        }
                        Text(day.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                            .foregroundStyle(.secondary)
                        if !day.title.isEmpty {
                            Text(day.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(PlanDestination.day(day.id))
                    .contextMenu {
                        Button("この日の予定をコピー…", systemImage: "document.on.document") {
                            operation = .replicate(day.id)
                        }
                        Button("別の日と入れ替え…", systemImage: "arrow.left.arrow.right") {
                            operation = .swap(day.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.title)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }

    @ViewBuilder
    private var workspace: some View {
        switch destination {
        case .overview:
            overviewWorkspace
        case .day:
            dayWorkspace
        }
    }

    @ViewBuilder
    private var overviewWorkspace: some View {
        if isMapVisible {
            HSplitView {
                overviewPanel
                    .frame(minWidth: 440, idealWidth: 560, maxWidth: 760)
                overviewMap
                    .frame(minWidth: 320, idealWidth: 520)
            }
        } else {
            overviewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var dayWorkspace: some View {
        if let selectedDay {
            if isMapVisible {
                HSplitView {
                    schedulePanel(day: selectedDay)
                        .frame(minWidth: 360, idealWidth: 480, maxWidth: 680)
                    mapPanel(day: selectedDay)
                        .frame(minWidth: 320, idealWidth: 520)
                }
            } else {
                schedulePanel(day: selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView(
                "旅行日程がありません",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Tripには少なくとも1日が必要です。")
            )
        }
    }

    private var overviewPanel: some View {
        TripOverviewView(
            trip: trip,
            coverPickerItem: $coverPickerItem,
            onSelectCurrency: updateTripCurrency,
            onSelectTimeZone: updateTripTimeZone
        )
    }

    private var overviewMap: some View {
        ActivityMap(
            day: overviewDay,
            selectedActivityID: nil,
            cameraRequest: nil,
            onSelectMapActivity: selectActivityFromOverviewMap,
            showsPlaceDetailOverlay: false,
            pinLabels: overviewPinLabels
        )
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private var overviewDay: Day {
        Day(
            id: trip.id,
            sequence: 0,
            date: trip.orderedDays.first?.date ?? trip.dateRange.lowerBound,
            title: trip.title,
            activities: trip.orderedDays.flatMap(\.orderedActivities)
        )
    }

    private var overviewPinLabels: [Activity.ID: ActivityMapPinLabel] {
        Dictionary(uniqueKeysWithValues: trip.orderedDays.flatMap { day in
            day.orderedActivities.map { activity in
                (activity.id, ActivityMapPinLabel(daySequence: day.sequence))
            }
        })
    }

    private func schedulePanel(day: Day) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DayHeader(day: day)
            Divider()
            ActivityList(
                day: day,
                selectedActivityID: interaction.selectedActivityID,
                onSelectActivity: selectActivityFromList,
                onAddActivity: { isActivityCreationPresented = true }
            )
        }
    }

    private func mapPanel(day: Day) -> some View {
        ActivityMap(
            day: day,
            selectedActivityID: interaction.selectedActivityID,
            cameraRequest: interaction.cameraRequest,
            onSelectMapActivity: selectActivityFromMap,
            onUpdatePlaceImage: updatePlaceImage,
            allowsPlaceImageEditing: true
        )
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private func selectActivityFromList(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
    }

    private func selectActivityFromMap(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .map, in: trip)
    }

    private func selectActivityFromOverviewMap(_ activityID: Activity.ID) {
        guard let day = trip.days.first(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }) else { return }
        destination = .day(day.id)
        interaction.selectDay(day.id, in: trip)
        interaction.selectActivity(activityID, source: .map, in: trip)
    }

    private func applyReplication(from sourceDayID: Day.ID, to targetDayIDs: Set<Day.ID>) {
        do {
            apply(try TripPlanEditor.replicateDayActivities(in: trip, from: sourceDayID, to: targetDayIDs))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySwap(first: Day.ID, second: Day.ID) {
        do {
            apply(try TripPlanEditor.swapDayPlans(in: trip, firstDayID: first, secondDayID: second))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePlaceImage(activityID: Activity.ID, imageData: Data?) {
        var updated = trip
        for dayIndex in updated.days.indices {
            guard let activityIndex = updated.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
                continue
            }
            updated.days[dayIndex].activities[activityIndex].place?.imageData = imageData
            apply(updated)
            return
        }
        errorMessage = "画像を更新するActivityが見つかりませんでした。"
    }

    private func updateTripCurrency(_ currencyCode: String) {
        guard trip.defaultCurrencyCode != currencyCode else { return }
        var updated = trip
        updated.defaultCurrencyCode = currencyCode
        apply(updated)
    }

    private func updateTripTimeZone(_ identifier: String) {
        do {
            apply(try TripPlanEditor.changeTimeZone(in: trip, to: identifier))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addActivity(to dayID: Day.ID, title: String, startTime: Date?) {
        do {
            let updated = try TripPlanEditor.appendActivity(
                in: trip,
                to: dayID,
                title: title,
                startTime: startTime
            )
            apply(updated)
            if let activity = updated.days.first(where: { $0.id == dayID })?.orderedActivities.last {
                interaction.selectActivity(activity.id, source: .list, in: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ updated: Trip) {
        errorMessage = onApplyPlan(updated)
    }
}

private struct ActivityCreationSheet: View {
    let day: Day
    let onCreate: (String, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasStartTime = false
    @State private var startTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("予定") {
                    TextField("予定の名前", text: $title)
                    Toggle("時刻を設定", isOn: $hasStartTime)
                    if hasStartTime {
                        DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Day \(day.sequence)に追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onCreate(title, hasStartTime ? startTime : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}

private struct TripOverviewView: View {
    let trip: Trip
    @Binding var coverPickerItem: PhotosPickerItem?
    let onSelectCurrency: (String) -> Void
    let onSelectTimeZone: (String) -> Void

    private let timeZones = [
        "Asia/Tokyo", "Asia/Singapore", "Australia/Sydney", "Pacific/Auckland",
        "Europe/London", "Europe/Paris", "America/Los_Angeles", "America/New_York"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(trip.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(trip.dateRange.lowerBound, format: .dateTime.year().month(.abbreviated).day())
                    Text("–")
                    Text(trip.dateRange.upperBound, format: .dateTime.year().month(.abbreviated).day())
                    Text("·")
                    Text("\(trip.orderedDays.count) days")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                ZStack(alignment: .bottomTrailing) {
                    TripCoverArtwork(data: trip.coverImageData)
                        .frame(height: 280)

                    PhotosPicker(selection: $coverPickerItem, matching: .images) {
                        Label(trip.coverImageData == nil ? "表紙画像を追加" : "表紙画像を変更", systemImage: "photo")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 16) {
                    GroupBox("Trip details") {
                        VStack(spacing: 12) {
                            LabeledContent("日程", value: "\(trip.orderedDays.count) days")
                            Divider()
                            LabeledContent("タイムゾーン") {
                                Menu {
                                    ForEach(timeZones, id: \.self) { identifier in
                                        Button(identifier) { onSelectTimeZone(identifier) }
                                    }
                                } label: {
                                    Label(trip.timeZoneIdentifier, systemImage: "globe.asia.australia")
                                }
                                .menuStyle(.borderlessButton)
                            }
                            Divider()
                            LabeledContent("通貨") {
                                Menu {
                                    ForEach(SupportedCurrency.allCases) { currency in
                                        Button(currency.label) { onSelectCurrency(currency.rawValue) }
                                    }
                                } label: {
                                    Label(trip.defaultCurrencyCode, systemImage: "banknote")
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Plan summary") {
                        VStack(spacing: 12) {
                            LabeledContent("Activities", value: "\(activityCount)")
                            Divider()
                            LabeledContent("Venues", value: "\(placeCount)")
                            Divider()
                            LabeledContent("Expenses estimated", value: "—")
                            Divider()
                            LabeledContent("Total distance", value: "—")
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("People & checklist") {
                        VStack(spacing: 12) {
                            LabeledContent("Participants", value: "0")
                            Divider()
                            LabeledContent("Checklist", value: "0 / 0")
                            Divider()
                            Label("Participantを追加（準備中）", systemImage: "person.badge.plus")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("訪問する国") {
                        if trip.venueCountryNames.isEmpty {
                            Text("Venueを追加すると、国をここに表示します。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(trip.venueCountryNames, id: \.self) { country in
                                Label(country, systemImage: "globe")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("trip-overview-content")
    }

    private var activityCount: Int {
        trip.days.reduce(0) { $0 + $1.activities.count }
    }

    private var placeCount: Int {
        trip.days.reduce(0) { count, day in
            count + day.activities.filter { $0.place != nil }.count
        }
    }
}

private struct TripCoverArtwork: View {
    let data: Data?

    var body: some View {
        ZStack {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.7), .blue.opacity(0.45), .teal.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .light))
                    Text("Trip cover")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel(data == nil ? "表紙画像なし" : "旅行の表紙画像")
    }
}

private enum DayOperation: Identifiable {
    case replicate(Day.ID)
    case swap(Day.ID)

    var id: String {
        switch self {
        case .replicate(let id): "replicate-\(id.uuidString)"
        case .swap(let id): "swap-\(id.uuidString)"
        }
    }
}

private struct DayReplicationSheet: View {
    let days: [Day]
    let sourceDayID: Day.ID
    let onConfirm: (Set<Day.ID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var targets: Set<Day.ID> = []

    var body: some View {
        NavigationStack {
            List(days.filter { $0.id != sourceDayID }, selection: $targets) { day in
                Text("Day \(day.sequence) · \(day.title.isEmpty ? "名称未設定" : day.title)")
                    .tag(day.id)
            }
            .safeAreaInset(edge: .bottom) {
                Text("選択したDayの既存予定は残し、コピー元のActivityを末尾へ追加します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
            }
            .navigationTitle("予定をコピー")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("末尾へ追加") { onConfirm(targets); dismiss() }.disabled(targets.isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }
}

private struct DaySwapSheet: View {
    let days: [Day]
    let sourceDayID: Day.ID
    let onConfirm: (Day.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var targetDayID: Day.ID?

    var body: some View {
        NavigationStack {
            List(days.filter { $0.id != sourceDayID }, selection: $targetDayID) { day in
                Text("Day \(day.sequence) · \(day.title.isEmpty ? "名称未設定" : day.title)")
                    .tag(day.id)
            }
            .navigationTitle("別の日と入れ替え")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("入れ替え") {
                        if let targetDayID { onConfirm(targetDayID); dismiss() }
                    }.disabled(targetDayID == nil)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }
}

private struct DayHeader: View {
    let day: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Day \(day.sequence)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if !day.title.isEmpty {
                Text(day.title)
                    .font(.title2.bold())
            }
            Text(day.date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
