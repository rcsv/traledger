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
    private let fixedReferenceDate: Date?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var travelLoad = TripTravelLoadModel()
    @State private var interaction: TripInteractionState
    @State private var mode: Mode = .map
    @State private var quickEditTarget: GuideQuickEditTarget?
    @State private var travelLegEditTarget: TravelLegID?
    @State private var errorMessage: String?
    #if TRIPMAP_QA
    @State private var didOpenQuickEditFromLaunchArgument = false
    @State private var didOpenTravelLegEditFromLaunchArgument = false
    #endif

    init(
        trip: Trip,
        initialActivityID: Activity.ID? = nil,
        onApplyPlan: @escaping (Trip) -> String? = { _ in nil }
    ) {
        self.trip = trip
        self.onApplyPlan = onApplyPlan
        let fixedReferenceDate = Self.qaReferenceDate(for: trip)
        self.fixedReferenceDate = fixedReferenceDate
        var initialInteraction = TripInteractionState(trip: trip)
        if let initialActivityID {
            initialInteraction.selectActivity(initialActivityID, source: .map, in: trip)
        } else if let today = GuideTimelineProjection.todaySummary(
            for: trip,
            now: fixedReferenceDate ?? Date()
        ) {
            initialInteraction.selectDay(today.day.id, in: trip)
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            workspace(at: fixedReferenceDate ?? context.date)
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesRegularWorkspace {
                compactQuickEditButton
            }
        }
        .toolbar {
            if usesRegularWorkspace,
               let selectedActivityID = interaction.selectedActivityID {
                Button("選択した予定を編集", systemImage: "pencil") {
                    presentQuickEdit(selectedActivityID)
                }
                .accessibilityIdentifier("guide-quick-edit-toolbar-button")
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
        .sheet(item: $travelLegEditTarget) { legID in
            if let (leg, fromActivity, toActivity) = legAndActivities(for: legID) {
                TravelLegEditSheet(
                    leg: leg,
                    fromActivityTitle: fromActivity.title,
                    toActivityTitle: toActivity.title,
                    onSave: updateTravelLeg,
                    onRetry: retryTravelLeg
                )
            } else {
                ContentUnavailableView(
                    "移動区間を読み込めません",
                    systemImage: "arrow.trianglehead.swap",
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
        .task(id: travelLoad.legs) {
            let arguments = ProcessInfo.processInfo.arguments
            let targetLeg = arguments.contains("-tripmap-travel-leg-editor-unavailable")
                ? travelLoad.legs.last(where: {
                    if case .unavailable = $0.calculationState { true } else { false }
                })
                : travelLoad.legs.first
            guard !didOpenTravelLegEditFromLaunchArgument,
                  arguments.contains("-tripmap-open-travel-leg-editor"),
                  let legID = targetLeg?.id else {
                return
            }
            didOpenTravelLegEditFromLaunchArgument = true
            mode = .list
            travelLegEditTarget = legID
        }
        #endif
    }

    private var usesRegularWorkspace: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private func workspace(at referenceDate: Date) -> some View {
        if trip.days.isEmpty {
            emptyState
        } else if usesRegularWorkspace {
            regularWorkspace(at: referenceDate)
        } else {
            compactWorkspace(at: referenceDate)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "旅行日程がありません",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("Tripには少なくとも1日が必要です。")
        )
    }

    private func compactWorkspace(at referenceDate: Date) -> some View {
        VStack(spacing: 0) {
            DayPicker(days: trip.orderedDays, selectedDayID: selectedDayBinding)
                .padding(.vertical, 8)

            todaySummary(at: referenceDate)

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
                    map(for: selectedDay)
                        .opacity(mode == .map ? 1 : 0)
                        .allowsHitTesting(mode == .map)
                        .accessibilityHidden(mode != .map)

                    activityList(for: selectedDay, at: referenceDate)
                        .opacity(mode == .list ? 1 : 0)
                        .allowsHitTesting(mode == .list)
                        .accessibilityHidden(mode != .list)
                }
            }
        }
    }

    private func regularWorkspace(at referenceDate: Date) -> some View {
        NavigationSplitView {
            List(selection: selectedDayBinding) {
                ForEach(trip.orderedDays) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Day \(day.sequence)")
                            .font(.headline)
                        Text(day.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(day.id)
                    .accessibilityLabel("Day \(day.sequence)、\(day.title)")
                }
            }
            .navigationTitle(trip.title)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .accessibilityIdentifier("guide-day-sidebar")
        } content: {
            if let selectedDay {
                VStack(spacing: 0) {
                    todaySummary(at: referenceDate)
                    activityList(for: selectedDay, at: referenceDate)
                }
                    .navigationTitle("Day \(selectedDay.sequence)")
                    .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
                    .accessibilityIdentifier("guide-activity-column")
            } else {
                emptyState
            }
        } detail: {
            if let selectedDay {
                map(for: selectedDay)
                    .accessibilityIdentifier("guide-map-column")
            } else {
                emptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var compactQuickEditButton: some View {
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

    private func activityList(for day: Day, at referenceDate: Date) -> some View {
        let summary = GuideTimelineProjection.todaySummary(for: trip, now: referenceDate)
        return ActivityList(
            day: day,
            selectedActivityID: interaction.selectedActivityID,
            travelLegs: travelLoad.legs,
            activityTemporalRoles: summary?.day.id == day.id ? summary?.rolesByActivityID ?? [:] : [:],
            onSelectActivity: selectActivityFromList,
            onEditActivity: presentQuickEdit,
            onEditTravelLeg: { travelLegEditTarget = $0 }
        )
    }

    @ViewBuilder
    private func todaySummary(at referenceDate: Date) -> some View {
        if let summary = GuideTimelineProjection.todaySummary(for: trip, now: referenceDate),
           summary.day.id == selectedDay?.id {
            TodaySummaryCard(
                summary: summary,
                travelLegToNext: travelLegToNext(in: summary),
                timeZoneIdentifier: trip.timeZoneIdentifier,
                onSelectActivity: selectSummaryActivity
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func map(for day: Day) -> some View {
        ActivityMap(
            day: day,
            selectedActivityID: interaction.selectedActivityID,
            cameraRequest: interaction.cameraRequest,
            onSelectMapActivity: selectActivityFromMap
        )
    }

    private func selectActivityFromList(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
    }

    private func selectActivityFromMap(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .map, in: trip)
    }

    private func selectSummaryActivity(_ activityID: Activity.ID) {
        mode = .list
        interaction.selectActivity(activityID, source: .list, in: trip)
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

    private func legAndActivities(
        for legID: TravelLegID
    ) -> (TravelLeg, Activity, Activity)? {
        guard let leg = travelLoad.legs.first(where: { $0.id == legID }),
              let fromActivity = trip.days
                .flatMap(\.activities)
                .first(where: { $0.id == legID.fromActivityID }),
              let toActivity = trip.days
                .flatMap(\.activities)
                .first(where: { $0.id == legID.toActivityID }) else {
            return nil
        }
        return (leg, fromActivity, toActivity)
    }

    private func travelLegToNext(in summary: GuideTodaySummary) -> TravelLeg? {
        guard let nowActivity = summary.nowActivity,
              let nextActivity = summary.nextActivity else {
            return nil
        }
        let legID = TravelLegID(
            fromActivityID: nowActivity.id,
            toActivityID: nextActivity.id
        )
        return travelLoad.legs.first { $0.id == legID }
    }

    private static func qaReferenceDate(for trip: Trip) -> Date? {
        #if TRIPMAP_QA
        guard ProcessInfo.processInfo.arguments.contains("-tripmap-now-next-qa"),
              let startTime = trip.orderedDays.first?.orderedActivities.first?.startTime else {
            return nil
        }
        return startTime.addingTimeInterval(15 * 60)
        #else
        return nil
        #endif
    }

    private func updateActivity(
        activityID: Activity.ID,
        startTime: Date?,
        note: String?,
        place: PlaceSnapshot?,
        progress: ActivityProgress
    ) -> Bool {
        guard let (activity, _) = activityAndDay(for: activityID) else {
            errorMessage = "編集対象の予定が見つかりませんでした。"
            return false
        }

        do {
            let edited = try TripPlanEditor.updateActivity(
                in: trip,
                activityID: activityID,
                title: activity.title,
                startTime: startTime,
                category: activity.category,
                durationMinutes: activity.durationMinutes,
                note: note,
                place: place
            )
            let updated = try TripPlanEditor.setActivityProgress(
                in: edited,
                activityID: activityID,
                progress: progress
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

    private func updateTravelLeg(
        legID: TravelLegID,
        transportType: TravelTransportType,
        manualDurationMinutes: Int?,
        note: String?
    ) -> Bool {
        do {
            let updated = try TripPlanEditor.setTravelLegPreference(
                in: trip,
                legID: legID,
                transportType: transportType,
                manualDurationMinutes: manualDurationMinutes,
                note: note
            )
            if let persistenceError = onApplyPlan(updated) {
                errorMessage = persistenceError
                return false
            }
            travelLoad.refresh(for: updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func retryTravelLeg(
        legID: TravelLegID,
        transportType: TravelTransportType,
        manualDurationMinutes: Int?,
        note: String?
    ) -> Bool {
        do {
            let updated = try TripPlanEditor.setTravelLegPreference(
                in: trip,
                legID: legID,
                transportType: transportType,
                manualDurationMinutes: manualDurationMinutes,
                note: note
            )
            if let persistenceError = onApplyPlan(updated) {
                errorMessage = persistenceError
                return false
            }
            travelLoad.retry(legID, for: updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct TodaySummaryCard: View {
    let summary: GuideTodaySummary
    let travelLegToNext: TravelLeg?
    let timeZoneIdentifier: String
    let onSelectActivity: (Activity.ID) -> Void

    private var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today • Day \(summary.day.sequence)")
                        .font(.headline)
                    Text(summary.day.date, format: .dateTime.month().day().weekday())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("残り \(summary.remainingActivityCount)件")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.12), in: Capsule())
            }

            activityRow(
                role: .now,
                activity: summary.nowActivity,
                emptyText: "現在進行中の予定はありません"
            )

            Divider()

            activityRow(
                role: .next,
                activity: summary.nextActivity,
                emptyText: "次の時刻付き予定はありません"
            )

            if let travelLegToNext,
               let duration = travelLegToNext.effectiveDuration,
               let nextStart = summary.nextActivity?.startTime {
                HStack(spacing: 8) {
                    Image(systemName: travelLegToNext.transportType.systemImage)
                        .accessibilityHidden(true)
                    Text("移動 \(formattedDuration(duration.minutes))")
                    Spacer()
                    Text("出発目安")
                        .foregroundStyle(.secondary)
                    Text(
                        nextStart.addingTimeInterval(TimeInterval(-duration.minutes * 60)),
                        format: .dateTime.hour().minute()
                    )
                    .monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today-summary-travel")
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .environment(\.timeZone, timeZone)
        .accessibilityIdentifier("today-summary")
    }

    @ViewBuilder
    private func activityRow(
        role: GuideActivityTemporalRole,
        activity: Activity?,
        emptyText: String
    ) -> some View {
        if let activity {
            Button {
                onSelectActivity(activity.id)
            } label: {
                HStack(spacing: 10) {
                    Label(role.displayName, systemImage: role.systemImage)
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if let startTime = activity.startTime {
                            Text(startTime, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-summary-\(role.rawValue)")
        } else {
            HStack(spacing: 10) {
                Label(role.displayName, systemImage: role.systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct GuideQuickEditTarget: Identifiable {
    let activityID: Activity.ID
    var id: Activity.ID { activityID }
}

private struct TravelLegEditSheet: View {
    let leg: TravelLeg
    let fromActivityTitle: String
    let toActivityTitle: String
    let onSave: (TravelLegID, TravelTransportType, Int?, String?) -> Bool
    let onRetry: (TravelLegID, TravelTransportType, Int?, String?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var transportType: TravelTransportType
    @State private var hasManualDuration: Bool
    @State private var manualDurationMinutes: Int
    @State private var note: String

    init(
        leg: TravelLeg,
        fromActivityTitle: String,
        toActivityTitle: String,
        onSave: @escaping (TravelLegID, TravelTransportType, Int?, String?) -> Bool,
        onRetry: @escaping (TravelLegID, TravelTransportType, Int?, String?) -> Bool
    ) {
        self.leg = leg
        self.fromActivityTitle = fromActivityTitle
        self.toActivityTitle = toActivityTitle
        self.onSave = onSave
        self.onRetry = onRetry
        _transportType = State(initialValue: leg.transportType)
        _hasManualDuration = State(initialValue: leg.manualDurationMinutes != nil)
        _manualDurationMinutes = State(initialValue: leg.manualDurationMinutes ?? 30)
        _note = State(initialValue: leg.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("出発", value: fromActivityTitle)
                    LabeledContent("到着", value: toActivityTitle)
                }

                Section("移動手段") {
                    Picker("移動手段", selection: $transportType) {
                        ForEach(TravelTransportType.allCases) { transport in
                            Label(transport.displayName, systemImage: transport.systemImage)
                                .tag(transport)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("travel-leg-transport-picker")
                }

                if transportType != .other {
                    Section {
                        Button(retryTitle, systemImage: "arrow.clockwise") {
                            if onRetry(
                                leg.id,
                                transportType,
                                hasManualDuration ? manualDurationMinutes : nil,
                                note
                            ) {
                                dismiss()
                            }
                        }
                        .disabled(isLoading)
                        .accessibilityIdentifier("travel-leg-retry-button")
                    } footer: {
                        Text("再計算しても、手動所要時間は上書きされません。")
                    }
                }

                Section("所要時間") {
                    Toggle("手動で設定", isOn: $hasManualDuration)
                    if hasManualDuration {
                        Stepper(
                            "所要時間 \(formattedDuration(manualDurationMinutes))",
                            value: $manualDurationMinutes,
                            in: 1...1_439,
                            step: 5
                        )
                        .accessibilityIdentifier("travel-leg-manual-duration")
                    } else {
                        Text("MapKitの推定を使用します")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("短いメモ") {
                    TextField("乗り換え、集合場所など", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("移動区間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(
                            leg.id,
                            transportType,
                            hasManualDuration ? manualDurationMinutes : nil,
                            note
                        ) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("travel-leg-save-button")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("travel-leg-editor")
    }

    private var isLoading: Bool {
        if case .loading = leg.calculationState { true } else { false }
    }

    private var retryTitle: String {
        switch leg.calculationState {
        case .failed, .unavailable: "経路取得を再試行"
        case .idle, .loading, .loaded, .stale: "経路を再計算"
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

private struct GuideQuickEditSheet: View {
    let activity: Activity
    let day: Day
    let timeZoneIdentifier: String
    let onSave: (Activity.ID, Date?, String?, PlaceSnapshot?, ActivityProgress) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var note: String
    @State private var place: PlaceSnapshot?
    @State private var progress: ActivityProgress
    @State private var isVenueSearchPresented = false

    init(
        activity: Activity,
        day: Day,
        timeZoneIdentifier: String,
        onSave: @escaping (Activity.ID, Date?, String?, PlaceSnapshot?, ActivityProgress) -> Bool
    ) {
        self.activity = activity
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
        self.onSave = onSave
        _hasStartTime = State(initialValue: activity.startTime != nil)
        _startTime = State(initialValue: activity.startTime ?? day.date)
        _note = State(initialValue: activity.note ?? "")
        _place = State(initialValue: activity.place)
        _progress = State(initialValue: activity.progress)
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
                Section("進行状況") {
                    Picker("進行状況", selection: $progress) {
                        ForEach(ActivityProgress.allCases) { progress in
                            Label(progress.displayName, systemImage: progress.systemImage)
                                .tag(progress)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("guide-activity-progress-picker")
                }

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
                        if onSave(activity.id, editedStartTime, note, place, progress) {
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
