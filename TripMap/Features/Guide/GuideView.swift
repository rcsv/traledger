#if os(iOS)
import SwiftUI

struct GuideView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"

        var id: Self { self }
    }

    let trip: Trip
    let onApplyPlan: (Trip) -> String?
    @StateObject private var travelLoad = TripTravelLoadModel()
    @State private var interaction: TripInteractionState
    @State private var mode: Mode = .map
    @State private var quickEditTarget: GuideQuickEditTarget?
    @State private var errorMessage: String?
    #if TRIPMAP_QA
    @State private var didOpenQuickEditFromLaunchArgument = false
    #endif

    init(
        trip: Trip,
        initialActivityID: Activity.ID? = nil,
        onApplyPlan: @escaping (Trip) -> String? = { _ in nil }
    ) {
        self.trip = trip
        self.onApplyPlan = onApplyPlan
        var initialInteraction = TripInteractionState(trip: trip)
        if let initialActivityID {
            initialInteraction.selectActivity(initialActivityID, source: .map, in: trip)
        }
        _interaction = State(initialValue: initialInteraction)
    }

    private var selectedDay: Day? {
        interaction.selectedDay(in: trip)
    }

    private var selectedDayBinding: Binding<Day.ID?> {
        Binding(
            get: { interaction.selectedDayID },
            set: { interaction.selectDay($0, in: trip) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if trip.days.isEmpty {
                ContentUnavailableView(
                    "旅行日程がありません",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Tripには少なくとも1日が必要です。")
                )
            } else {
                DayPicker(days: trip.orderedDays, selectedDayID: selectedDayBinding)
                    .padding(.vertical, 8)

                Picker("表示", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if let selectedDay {
                    ZStack {
                        ActivityMap(
                            day: selectedDay,
                            selectedActivityID: interaction.selectedActivityID,
                            cameraRequest: interaction.cameraRequest,
                            onSelectMapActivity: selectActivityFromMap
                        )
                        .opacity(mode == .map ? 1 : 0)
                        .allowsHitTesting(mode == .map)
                        .accessibilityHidden(mode != .map)

                        ActivityList(
                            day: selectedDay,
                            selectedActivityID: interaction.selectedActivityID,
                            travelLegs: travelLoad.legs,
                            onSelectActivity: selectActivityFromList,
                            onEditActivity: presentQuickEdit
                        )
                        .opacity(mode == .list ? 1 : 0)
                        .allowsHitTesting(mode == .list)
                        .accessibilityHidden(mode != .list)
                    }
                }
            }
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selectedActivityID = interaction.selectedActivityID {
                Button {
                    presentQuickEdit(selectedActivityID)
                } label: {
                    Label("クイック編集", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("guide-quick-edit-button")
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .sheet(item: $quickEditTarget) { target in
            if let (activity, day) = activityAndDay(for: target.activityID) {
                GuideQuickEditSheet(
                    activity: activity,
                    day: day,
                    timeZoneIdentifier: trip.timeZoneIdentifier,
                    onSave: updateActivity
                )
            } else {
                ContentUnavailableView(
                    "予定を読み込めません",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("シートを閉じて、もう一度お試しください。")
                )
            }
        }
        .alert("変更を保存できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
        .onChange(of: trip) { _, trip in
            interaction.reconcile(with: trip)
        }
        .task(id: trip) {
            travelLoad.refresh(for: trip)
        }
        #if TRIPMAP_QA
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-tripmap-open-guide-list") {
                mode = .list
            }
            guard !didOpenQuickEditFromLaunchArgument,
                  arguments.contains("-tripmap-open-guide-quick-edit"),
                  let selectedActivityID = interaction.selectedActivityID else {
                return
            }
            didOpenQuickEditFromLaunchArgument = true
            presentQuickEdit(selectedActivityID)
        }
        #endif
    }

    private func selectActivityFromList(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
    }

    private func selectActivityFromMap(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .map, in: trip)
    }

    private func presentQuickEdit(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
        quickEditTarget = GuideQuickEditTarget(activityID: activityID)
    }

    private func activityAndDay(for activityID: Activity.ID) -> (Activity, Day)? {
        guard let day = trip.days.first(where: { day in
            day.activities.contains(where: { $0.id == activityID })
        }), let activity = day.activities.first(where: { $0.id == activityID }) else {
            return nil
        }
        return (activity, day)
    }

    private func updateActivity(
        activityID: Activity.ID,
        startTime: Date?,
        note: String?,
        place: PlaceSnapshot?
    ) -> Bool {
        guard let (activity, _) = activityAndDay(for: activityID) else {
            errorMessage = "編集対象の予定が見つかりませんでした。"
            return false
        }

        do {
            let updated = try TripPlanEditor.updateActivity(
                in: trip,
                activityID: activityID,
                title: activity.title,
                startTime: startTime,
                category: activity.category,
                durationMinutes: activity.durationMinutes,
                note: note,
                place: place
            )
            if let persistenceError = onApplyPlan(updated) {
                errorMessage = persistenceError
                return false
            }
            interaction.selectActivity(activityID, source: .list, in: updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct GuideQuickEditTarget: Identifiable {
    let activityID: Activity.ID
    var id: Activity.ID { activityID }
}

private struct GuideQuickEditSheet: View {
    let activity: Activity
    let day: Day
    let timeZoneIdentifier: String
    let onSave: (Activity.ID, Date?, String?, PlaceSnapshot?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var note: String
    @State private var place: PlaceSnapshot?
    @State private var isVenueSearchPresented = false

    init(
        activity: Activity,
        day: Day,
        timeZoneIdentifier: String,
        onSave: @escaping (Activity.ID, Date?, String?, PlaceSnapshot?) -> Bool
    ) {
        self.activity = activity
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.onSave = onSave
        _hasStartTime = State(initialValue: activity.startTime != nil)
        _startTime = State(initialValue: activity.startTime ?? day.date)
        _note = State(initialValue: activity.note ?? "")
        _place = State(initialValue: activity.place)
        #if TRIPMAP_QA
        _isVenueSearchPresented = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-tripmap-open-guide-venue-search")
        )
        #endif
    }

    private var tripTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    private var editedStartTime: Date? {
        guard hasStartTime else { return nil }
        let localDay = LocalDate(date: day.date, timeZone: tripTimeZone)
        return LocalTime(date: startTime, timeZone: tripTimeZone)
            .date(on: localDay, in: tripTimeZone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("時刻") {
                    Toggle("開始時刻を設定", isOn: $hasStartTime)
                    if hasStartTime {
                        DatePicker(
                            "開始時刻",
                            selection: $startTime,
                            displayedComponents: .hourAndMinute
                        )
                        .environment(\.timeZone, tripTimeZone)
                    }
                }

                Section("短いメモ") {
                    TextField("待ち合わせ場所、予約名など", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("場所") {
                    if let place {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(.headline)
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    .accessibilityIdentifier("guide-venue-search-button")
                }
            }
            .navigationTitle("クイック編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(activity.id, editedStartTime, note, place) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("guide-quick-edit-save")
                }
            }
        }
        .accessibilityIdentifier("guide-quick-editor")
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isVenueSearchPresented) {
            VenueSearchSheet { selectedPlace in
                place = selectedPlace
            }
        }
    }
}
#endif
