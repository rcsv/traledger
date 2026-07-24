#if os(macOS)
import AppKit
import Foundation
import MapKit
import PhotosUI
import SwiftData
import SwiftUI

private enum PlanDestination: Hashable {
    case overview
    case day(Day.ID)
}

struct PlanView: View {
    @Query private var participantAssignments: [StoredTripParticipant]
    @Environment(\.undoManager) private var undoManager
    @StateObject private var travelLoad = TripTravelLoadModel()
    @StateObject private var planUndo = PlanUndoCoordinator()
    let trip: Trip
    let onApplyPlan: (Trip) -> String?
    @State private var destination: PlanDestination
    @State private var isMapVisible = true
    @State private var interaction: TripInteractionState
    @State private var operation: DayOperation?
    @State private var coverPickerItem: PhotosPickerItem?
    @State private var isActivityCreationPresented = false
    @State private var activityEditor: ActivityEditorTarget?
    @State private var pendingActivityDeletion: ActivityEditorTarget?
    @State private var pendingVenueFocusActivityID: Activity.ID?
    @State private var isMemoryPresented = false
    @State private var errorMessage: String?

    init(
        trip: Trip,
        initialDayID: Day.ID? = nil,
        initialActivityID: Activity.ID? = nil,
        onApplyPlan: @escaping (Trip) -> String? = { _ in nil }
    ) {
        self.trip = trip
        self.onApplyPlan = onApplyPlan
        var initialInteraction = TripInteractionState(trip: trip)
        if let initialDayID {
            initialInteraction.selectDay(initialDayID, in: trip)
        }
        if let initialActivityID {
            initialInteraction.selectActivity(initialActivityID, source: .list, in: trip)
        }
        _destination = State(
            initialValue: initialDayID.map(PlanDestination.day) ?? .overview
        )
        _interaction = State(initialValue: initialInteraction)
    }

    private var selectedDay: Day? {
        guard case .day = destination else { return nil }
        return interaction.selectedDay(in: trip)
    }

    private var tripParticipantAssignments: [StoredTripParticipant] {
        participantAssignments.filter { $0.trip?.id == trip.id }
    }

    private var doctorReport: TripDoctorReport {
        TripDoctor.inspect(
            trip,
            participantNames: tripParticipantAssignments.compactMap { $0.participant?.displayName },
            travelLegs: travelLoad.legs
        )
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
                Button("思い出", systemImage: "photo.on.rectangle.angled") {
                    isMemoryPresented = true
                }
                .accessibilityIdentifier("plan-memory-button")

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

                    if let selectedActivity {
                        Button("予定を編集", systemImage: "pencil") {
                            activityEditor = ActivityEditorTarget(activityID: selectedActivity.id)
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .help("選択中の予定を編集 (Return)")
                        Menu("予定", systemImage: "ellipsis.circle") {
                            Button("予定を削除", systemImage: "trash", role: .destructive) {
                                pendingActivityDeletion = ActivityEditorTarget(activityID: selectedActivity.id)
                            }
                        }
                    }
                }
            }
        }
        // Keep the map-control in the window toolbar while allowing the map to
        // continue behind it instead of reserving a separate white strip.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: isMapVisible ? 1000 : 760, minHeight: 620)
        .onAppear {
            planUndo.configure(
                undoManager: undoManager,
                applyPlan: onApplyPlan,
                onError: { errorMessage = $0 }
            )
        }
        .onChange(of: trip) { _, trip in
            interaction.reconcile(with: trip)
            focusPendingVenue(in: trip)
            if case .day(let dayID) = destination,
               !trip.days.contains(where: { $0.id == dayID }) {
                destination = .overview
            }
        }
        .task(id: trip) {
            travelLoad.refresh(for: trip)
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
        .sheet(isPresented: $isMemoryPresented) {
            MemoryView(trip: trip, onApplyPlan: onApplyPlan)
        }
        .sheet(isPresented: $isActivityCreationPresented) {
            if let selectedDay {
                ActivityCreationSheet(
                    day: selectedDay,
                    timeZoneIdentifier: trip.timeZoneIdentifier
                ) { title, startTime, category, durationMinutes in
                    addActivity(
                        to: selectedDay.id,
                        title: title,
                        startTime: startTime,
                        category: category,
                        durationMinutes: durationMinutes
                    )
                }
            }
        }
        .sheet(item: $activityEditor) { target in
            if let day = trip.days.first(where: { $0.activities.contains(where: { $0.id == target.activityID }) }),
               let activity = day.activities.first(where: { $0.id == target.activityID }) {
                ActivityEditorSheet(
                    activity: activity,
                    day: day,
                    timeZoneIdentifier: trip.timeZoneIdentifier,
                    onSave: updateActivity
                )
            }
        }
        .confirmationDialog(
            "この予定を削除しますか？",
            isPresented: Binding(
                get: { pendingActivityDeletion != nil },
                set: { if !$0 { pendingActivityDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("予定を削除", role: .destructive) {
                if let activityID = pendingActivityDeletion?.activityID {
                    deleteActivity(activityID)
                }
                pendingActivityDeletion = nil
            }
            Button("キャンセル", role: .cancel) { pendingActivityDeletion = nil }
        } message: {
            Text("場所と画像も削除されます。この操作は取り消せません。")
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
                            let dayIssues = doctorReport.issues(forDay: day.id)
                            if !dayIssues.isEmpty {
                                Label(
                                    "\(dayIssues.count)",
                                    systemImage: dayIssues.contains(where: { $0.severity == .warning })
                                        ? "exclamationmark.triangle.fill"
                                        : "info.circle.fill"
                                )
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    dayIssues.contains(where: { $0.severity == .warning })
                                        ? Color.orange
                                        : Color.secondary
                                )
                                .accessibilityLabel("確認事項が\(dayIssues.count)件あります")
                            }
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
            doctorReport: doctorReport,
            coverPickerItem: $coverPickerItem,
            onSelectCurrency: updateTripCurrency,
            onSelectTimeZone: updateTripTimeZone,
            onSelectDoctorIssue: selectDoctorIssue
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
            let dayIssues = doctorReport.issues(forDay: day.id).filter { $0.target.activityID == nil }
            if !dayIssues.isEmpty {
                DayDoctorBanner(issues: dayIssues)
                Divider()
            }
            ActivityList(
                day: day,
                selectedActivityID: interaction.selectedActivityID,
                doctorIssues: doctorReport.issues(forDay: day.id),
                travelLegs: travelLoad.legs,
                onSelectActivity: selectActivityFromList,
                onAddActivity: { isActivityCreationPresented = true },
                onEditActivity: { activityID in
                    activityEditor = ActivityEditorTarget(activityID: activityID)
                },
                onDeleteActivity: { activityID in
                    pendingActivityDeletion = ActivityEditorTarget(activityID: activityID)
                },
                onMoveActivity: { activityID, targetActivityID in
                    moveActivity(
                        in: day.id,
                        activityID: activityID,
                        relativeTo: targetActivityID
                    )
                }
            )
        }
    }

    private var selectedActivity: Activity? {
        interaction.selectedActivity(in: trip)
    }

    private func mapPanel(day: Day) -> some View {
        ActivityMap(
            day: day,
            selectedActivityID: interaction.selectedActivityID,
            cameraRequest: interaction.cameraRequest,
            onSelectMapActivity: selectActivityFromMap,
            onUpdatePlaceImage: updatePlaceImage,
            onUpdateExternalPlaceImage: updateExternalPlaceImage,
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

    private func selectDoctorIssue(_ issue: TripDoctorIssue) {
        switch issue.target {
        case .day(let dayID):
            destination = .day(dayID)
            interaction.selectDay(dayID, in: trip)
        case .activity(let activityID, let dayID):
            destination = .day(dayID)
            interaction.selectDay(dayID, in: trip)
            interaction.selectActivity(activityID, source: .list, in: trip)
            activityEditor = ActivityEditorTarget(activityID: activityID)
        case .trip, .participants:
            destination = .overview
        }
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

    private func updateExternalPlaceImage(activityID: Activity.ID, image: ExternalPlaceImage?) {
        var updated = trip
        for dayIndex in updated.days.indices {
            guard let activityIndex = updated.days[dayIndex].activities.firstIndex(where: { $0.id == activityID }) else {
                continue
            }
            updated.days[dayIndex].activities[activityIndex].place?.externalImage = image
            apply(updated)
            return
        }
        errorMessage = "外部画像を更新するActivityが見つかりませんでした。"
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

    private func addActivity(
        to dayID: Day.ID,
        title: String,
        startTime: Date?,
        category: ActivityCategory?,
        durationMinutes: Int?
    ) {
        do {
            let updated = try TripPlanEditor.appendActivity(
                in: trip,
                to: dayID,
                title: title,
                startTime: startTime,
                category: category,
                durationMinutes: durationMinutes
            )
            guard apply(updated) else { return }
            if let activity = updated.days.first(where: { $0.id == dayID })?.orderedActivities.last {
                interaction.selectActivity(activity.id, source: .list, in: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateActivity(
        activityID: Activity.ID,
        title: String,
        startTime: Date?,
        category: ActivityCategory?,
        durationMinutes: Int?,
        note: String?,
        place: PlaceSnapshot?
    ) -> Bool {
        do {
            let previousPlace = trip.days
                .flatMap(\.activities)
                .first(where: { $0.id == activityID })?
                .place
            let updated = try TripPlanEditor.updateActivity(
                in: trip,
                activityID: activityID,
                title: title,
                startTime: startTime,
                category: category,
                durationMinutes: durationMinutes,
                note: note,
                place: place
            )
            let shouldFocusVenue = place != nil && previousPlace != place
            if shouldFocusVenue {
                pendingVenueFocusActivityID = activityID
            }
            guard apply(updated) else {
                pendingVenueFocusActivityID = nil
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func deleteActivity(_ activityID: Activity.ID) {
        do {
            let updated = try TripPlanEditor.deleteActivity(in: trip, activityID: activityID)
            if apply(updated) {
                interaction.reconcile(with: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveActivity(
        in dayID: Day.ID,
        activityID: Activity.ID,
        relativeTo targetActivityID: Activity.ID
    ) {
        do {
            let updated = try TripPlanEditor.moveActivity(
                in: trip,
                dayID: dayID,
                activityID: activityID,
                relativeTo: targetActivityID
            )
            guard updated != trip, apply(updated) else { return }
            planUndo.registerTransition(
                from: trip,
                to: updated,
                actionName: "予定の並べ替え"
            )
            interaction.selectActivity(activityID, source: .list, in: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func apply(_ updated: Trip) -> Bool {
        errorMessage = onApplyPlan(updated)
        return errorMessage == nil
    }

    private func focusPendingVenue(in trip: Trip) {
        guard let activityID = pendingVenueFocusActivityID,
              let activity = trip.days.flatMap(\.activities).first(where: { $0.id == activityID }),
              activity.place != nil else {
            return
        }

        interaction.focusActivity(activityID, in: trip)
        pendingVenueFocusActivityID = nil
    }
}

@MainActor
private final class PlanUndoCoordinator: ObservableObject {
    private weak var undoManager: UndoManager?
    private var applyPlan: ((Trip) -> String?)?
    private var onError: ((String) -> Void)?

    func configure(
        undoManager: UndoManager?,
        applyPlan: @escaping (Trip) -> String?,
        onError: @escaping (String) -> Void
    ) {
        self.undoManager = undoManager
        self.applyPlan = applyPlan
        self.onError = onError
    }

    func registerTransition(from previous: Trip, to updated: Trip, actionName: String) {
        registerRestore(
            desired: previous,
            inverse: updated,
            actionName: actionName
        )
    }

    private func registerRestore(desired: Trip, inverse: Trip, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(desired, inverse: inverse, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ desired: Trip, inverse: Trip, actionName: String) {
        guard let applyPlan else { return }
        if let message = applyPlan(desired) {
            onError?(message)
            return
        }
        registerRestore(
            desired: inverse,
            inverse: desired,
            actionName: actionName
        )
    }
}

private struct ActivityEditorTarget: Identifiable {
    let activityID: Activity.ID
    var id: Activity.ID { activityID }
}

private struct ActivityEditorSheet: View {
    let activity: Activity
    let day: Day
    let timeZoneIdentifier: String
    let onSave: (Activity.ID, String, Date?, ActivityCategory?, Int?, String?, PlaceSnapshot?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var category: ActivityCategory?
    @State private var hasDuration: Bool
    @State private var durationMinutes: Int
    @State private var place: PlaceSnapshot?
    @State private var isVenueSearchPresented = false

    init(
        activity: Activity,
        day: Day,
        timeZoneIdentifier: String,
        onSave: @escaping (Activity.ID, String, Date?, ActivityCategory?, Int?, String?, PlaceSnapshot?) -> Bool
    ) {
        self.activity = activity
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.onSave = onSave
        _title = State(initialValue: activity.title)
        _note = State(initialValue: activity.note ?? "")
        _hasStartTime = State(initialValue: activity.startTime != nil)
        _startTime = State(initialValue: activity.startTime ?? day.date)
        _category = State(initialValue: activity.category)
        _hasDuration = State(initialValue: activity.durationMinutes != nil)
        _durationMinutes = State(initialValue: activity.durationMinutes ?? 60)
        _place = State(initialValue: activity.place)
    }

    private var tripTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    private var editedStartTime: Date? {
        guard hasStartTime else { return nil }
        let localDay = LocalDate(date: day.date, timeZone: tripTimeZone)
        return LocalTime(date: startTime, timeZone: tripTimeZone).date(on: localDay, in: tripTimeZone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("予定の名前", text: $title)
                    Toggle("時刻を設定", isOn: $hasStartTime)
                    if hasStartTime {
                        DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, tripTimeZone)
                    }
                    TextField("メモ", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("予定")
                        .accessibilityIdentifier("activity-editor")
                }

                Section("種類と所要時間") {
                    ActivityCategoryDurationFields(
                        category: $category,
                        hasDuration: $hasDuration,
                        durationMinutes: $durationMinutes
                    )
                }

                Section("場所") {
                    if let place {
                        LabeledContent("設定済み") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(place.name)
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("場所を解除", systemImage: "mappin.slash", role: .destructive) {
                            self.place = nil
                        }
                    } else {
                        Text("場所は未設定です")
                            .foregroundStyle(.secondary)
                    }
                    Button(place == nil ? "場所を検索" : "場所を変更", systemImage: "magnifyingglass") {
                        isVenueSearchPresented = true
                    }
                    .accessibilityIdentifier("venue-search-button")
                }
            }
            .navigationTitle("予定を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(
                            activity.id,
                            title,
                            editedStartTime,
                            category,
                            hasDuration ? durationMinutes : nil,
                            note,
                            place
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .sheet(isPresented: $isVenueSearchPresented) {
            VenueSearchSheet { place in
                self.place = place
            }
        }
    }
}

private struct ActivityCategoryDurationFields: View {
    @Binding var category: ActivityCategory?
    @Binding var hasDuration: Bool
    @Binding var durationMinutes: Int

    var body: some View {
        Picker("カテゴリ", selection: $category) {
            Text("未設定").tag(nil as ActivityCategory?)
            ForEach(ActivityCategory.allCases) { category in
                Label(category.displayName, systemImage: category.systemImage)
                    .tag(Optional(category))
            }
        }

        if !hasDuration,
           let suggestedDuration = category?.suggestedDurationMinutes {
            Button {
                durationMinutes = suggestedDuration
                hasDuration = true
            } label: {
                Label(
                    "おすすめの所要時間：\(formattedDuration(suggestedDuration))",
                    systemImage: "sparkles"
                )
            }
            .accessibilityIdentifier("duration-suggestion")
            .accessibilityHint("カテゴリの目安を所要時間として設定します")
        }

        Toggle("所要時間を設定", isOn: $hasDuration)
        if hasDuration {
            Stepper(value: $durationMinutes, in: 5...1_440, step: 5) {
                Text("所要時間 \(formattedDuration(durationMinutes))")
            }
        }
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }
}

private struct ActivityCreationSheet: View {
    let day: Day
    let timeZoneIdentifier: String
    let onCreate: (String, Date?, ActivityCategory?, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasStartTime = false
    @State private var startTime: Date
    @State private var category: ActivityCategory?
    @State private var hasDuration = false
    @State private var durationMinutes = 60

    init(
        day: Day,
        timeZoneIdentifier: String,
        onCreate: @escaping (String, Date?, ActivityCategory?, Int?) -> Void
    ) {
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.onCreate = onCreate
        let tripTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let currentLocalTime = LocalTime(date: Date(), timeZone: .current)
        let selectedDay = LocalDate(date: day.date, timeZone: tripTimeZone)
        _startTime = State(
            initialValue: currentLocalTime.date(on: selectedDay, in: tripTimeZone) ?? day.date
        )
    }

    private var tripTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    private var selectedDayStartTime: Date? {
        guard hasStartTime else { return nil }
        let selectedDay = LocalDate(date: day.date, timeZone: tripTimeZone)
        let selectedTime = LocalTime(date: startTime, timeZone: tripTimeZone)
        return selectedTime.date(on: selectedDay, in: tripTimeZone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("予定") {
                    TextField("予定の名前", text: $title)
                    Toggle("時刻を設定", isOn: $hasStartTime)
                    if hasStartTime {
                        DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, tripTimeZone)
                    }
                }

                Section("種類と所要時間") {
                    ActivityCategoryDurationFields(
                        category: $category,
                        hasDuration: $hasDuration,
                        durationMinutes: $durationMinutes
                    )
                }
            }
            .navigationTitle("Day \(day.sequence)に追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onCreate(
                            title,
                            selectedDayStartTime,
                            category,
                            hasDuration ? durationMinutes : nil
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 340)
    }
}

private struct TripDoctorSummary: View {
    let report: TripDoctorReport
    let onSelectIssue: (TripDoctorIssue) -> Void

    var body: some View {
        GroupBox {
            if report.issues.isEmpty {
                Label("現在の計画に確認事項はありません。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        if report.warningCount > 0 {
                            Label("Warning \(report.warningCount)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if report.infoCount > 0 {
                            Label("Info \(report.infoCount)", systemImage: "info.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline.weight(.semibold))

                    Divider()

                    ForEach(report.issues) { issue in
                        Button {
                            onSelectIssue(issue)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .foregroundStyle(issue.severity == .warning ? Color.orange : Color.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.message)
                                        .foregroundStyle(.primary)
                                    if let suggestion = issue.suggestion {
                                        Text(suggestion)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if issue.target.dayID != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(issueAccessibilityIdentifier(issue))
                        .accessibilityHint(issueAccessibilityHint(issue))
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("旅程チェック", systemImage: "stethoscope")
        }
        .accessibilityIdentifier("trip-doctor-summary")
    }

    private func issueAccessibilityIdentifier(_ issue: TripDoctorIssue) -> String {
        switch issue.target {
        case .activity(let activityID, _):
            "doctor-issue-\(issue.code.rawValue)-activity-\(activityID.uuidString)"
        case .day(let dayID):
            "doctor-issue-\(issue.code.rawValue)-day-\(dayID.uuidString)"
        case .trip:
            "doctor-issue-\(issue.code.rawValue)-trip"
        case .participants:
            "doctor-issue-\(issue.code.rawValue)-participants"
        }
    }

    private func issueAccessibilityHint(_ issue: TripDoctorIssue) -> String {
        switch issue.target {
        case .activity:
            "該当する予定の編集画面を開きます"
        case .day:
            "該当する日を表示します"
        case .trip, .participants:
            ""
        }
    }
}

private struct DayDoctorBanner: View {
    let issues: [TripDoctorIssue]

    private var containsWarning: Bool {
        issues.contains(where: { $0.severity == .warning })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(issues) { issue in
                DoctorIssueLabel(issue: issue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((containsWarning ? Color.orange : Color.blue).opacity(0.09))
        .accessibilityIdentifier("day-doctor-banner")
    }
}

private struct DoctorIssueLabel: View {
    let issue: TripDoctorIssue

    var body: some View {
        Label(
            issue.message,
            systemImage: issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(issue.severity == .warning ? Color.orange : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredParticipant.displayName) private var participants: [StoredParticipant]
    @Query private var storedTrips: [StoredTrip]
    @Query private var participantAssignments: [StoredTripParticipant]
    @Query private var checklistItems: [StoredChecklistItem]
    let trip: Trip
    let doctorReport: TripDoctorReport
    @Binding var coverPickerItem: PhotosPickerItem?
    let onSelectCurrency: (String) -> Void
    let onSelectTimeZone: (String) -> Void
    let onSelectDoctorIssue: (TripDoctorIssue) -> Void
    @State private var isParticipantPickerPresented = false
    @State private var isChecklistEditorPresented = false
    @State private var checklistTitle = ""

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

                TripDoctorSummary(
                    report: doctorReport,
                    onSelectIssue: onSelectDoctorIssue
                )

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
                            LabeledContent("Participants", value: "\(tripAssignments.count)")
                            ForEach(doctorReport.participantIssues) { issue in
                                DoctorIssueLabel(issue: issue)
                            }
                            if tripAssignments.isEmpty {
                                Text("同行者を割り当てると、ここに表示されます。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(tripAssignments) { assignment in
                                    HStack {
                                        Text(assignment.participant?.displayName ?? "削除されたParticipant")
                                        Spacer()
                                        Button("解除", systemImage: "xmark", role: .destructive) {
                                            remove(assignment)
                                        }
                                        .labelStyle(.iconOnly)
                                    }
                                }
                            }
                            Button("Participantを追加", systemImage: "person.badge.plus") {
                                isParticipantPickerPresented = true
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            LabeledContent("Checklist", value: "\(completedChecklistCount) / \(tripChecklistItems.count)")
                            ForEach(tripChecklistItems) { item in
                                Button {
                                    item.isCompleted.toggle()
                                    save()
                                } label: {
                                    Label(item.title, systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                            Button("Checklistを追加", systemImage: "checklist") {
                                checklistTitle = ""
                                isChecklistEditorPresented = true
                            }
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
        .sheet(isPresented: $isParticipantPickerPresented) {
            ParticipantPickerSheet(
                participants: participants.filter { participant in
                    !tripAssignments.contains(where: { $0.participant?.id == participant.id })
                },
                onSelect: assign
            )
        }
        .sheet(isPresented: $isChecklistEditorPresented) {
            NavigationStack {
                Form { TextField("項目", text: $checklistTitle) }
                    .navigationTitle("Checklistを追加")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { isChecklistEditorPresented = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("追加") { addChecklistItem() }
                                .disabled(checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .frame(minWidth: 360, minHeight: 180)
        }
    }

    private var activityCount: Int {
        trip.days.reduce(0) { $0 + $1.activities.count }
    }

    private var placeCount: Int {
        trip.days.reduce(0) { count, day in
            count + day.activities.filter { $0.place != nil }.count
        }
    }

    private var storedTrip: StoredTrip? {
        participantAssignments.first(where: { $0.trip?.id == trip.id })?.trip
            ?? checklistItems.first(where: { $0.trip?.id == trip.id })?.trip
            ?? storedTrips.first(where: { $0.id == trip.id })
    }

    private var tripAssignments: [StoredTripParticipant] {
        participantAssignments.filter { $0.trip?.id == trip.id }
    }

    private var tripChecklistItems: [StoredChecklistItem] {
        checklistItems.filter { $0.trip?.id == trip.id }
    }

    private var completedChecklistCount: Int { tripChecklistItems.filter(\.isCompleted).count }

    private func assign(_ participant: StoredParticipant) {
        guard let storedTrip else { return }
        modelContext.insert(StoredTripParticipant(trip: storedTrip, participant: participant))
        save()
    }

    private func remove(_ assignment: StoredTripParticipant) {
        modelContext.delete(assignment)
        save()
    }

    private func addChecklistItem() {
        guard let storedTrip else { return }
        let title = checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        modelContext.insert(StoredChecklistItem(title: title, trip: storedTrip))
        save()
        isChecklistEditorPresented = false
    }

    private func save() { try? modelContext.save() }
}

private struct ParticipantPickerSheet: View {
    let participants: [StoredParticipant]
    let onSelect: (StoredParticipant) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(participants) { participant in
                Button(participant.displayName) { onSelect(participant); dismiss() }
            }
            .overlay {
                if participants.isEmpty { ContentUnavailableView("追加できるParticipantがいません", systemImage: "person.2") }
            }
            .navigationTitle("Participantを追加")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
        .frame(minWidth: 360, minHeight: 280)
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
