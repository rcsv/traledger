#if os(iOS)
import MapKit
import SwiftUI
import UIKit
import UserNotifications

struct GuideView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"

        var id: Self { self }
    }

    let trip: Trip
    let onApplyPlan: (Trip) -> String?
    let onApplyMutation: ((TripMutation) -> String?)?
    private let fixedReferenceDate: Date?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var travelLoad = TripTravelLoadModel()
    @State private var interaction: TripInteractionState
    @State private var mode: Mode = .map
    @State private var quickEditTarget: GuideQuickEditTarget?
    @State private var travelLegEditTarget: TravelLegID?
    @State private var reservationTarget: GuideReservationTarget?
    @State private var isOfflineReviewPresented = false
    @State private var isMemoryPresented = false
    @State private var isTripRenamePresented = false
    @State private var isDateRangeEditorPresented = false
    @State private var errorMessage: String?
    #if TRIPMAP_QA
    @State private var didOpenQuickEditFromLaunchArgument = false
    @State private var didOpenTravelLegEditFromLaunchArgument = false
    #endif

    init(
        trip: Trip,
        initialActivityID: Activity.ID? = nil,
        onApplyPlan: @escaping (Trip) -> String? = { _ in nil },
        onApplyMutation: ((TripMutation) -> String?)? = nil
    ) {
        self.trip = trip
        self.onApplyPlan = onApplyPlan
        self.onApplyMutation = onApplyMutation
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
                compactActionBar
            }
        }
        .toolbar {
            Button("オフライン確認", systemImage: "checkmark.icloud") {
                isOfflineReviewPresented = true
            }
            .accessibilityIdentifier("guide-offline-review-button")

            Button("思い出", systemImage: "photo.on.rectangle.angled") {
                isMemoryPresented = true
            }
            .accessibilityIdentifier("guide-memory-button")

            Menu("Trip", systemImage: "ellipsis.circle") {
                Button("旅行名を変更", systemImage: "square.and.pencil") {
                    isTripRenamePresented = true
                }
                .accessibilityIdentifier("guide-trip-rename-button")

                Button("日程を変更", systemImage: "calendar.badge.clock") {
                    isDateRangeEditorPresented = true
                }
                .accessibilityIdentifier("guide-date-range-edit-button")
            }

            if let selectedActivityID = interaction.selectedActivityID,
               activityAndDay(for: selectedActivityID)?.0.reservation != nil {
                Button("予約を表示", systemImage: "ticket") {
                    reservationTarget = GuideReservationTarget(activityID: selectedActivityID)
                }
                .accessibilityIdentifier("guide-reservation-toolbar-button")
            }

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
        .sheet(item: $reservationTarget) { target in
            if let reservation = activityAndDay(for: target.activityID)?.0.reservation {
                GuideReservationSheet(reservation: reservation)
            } else {
                ContentUnavailableView(
                    "予約参照を読み込めません",
                    systemImage: "ticket",
                    description: Text("シートを閉じて、もう一度お試しください。")
                )
            }
        }
        .sheet(isPresented: $isOfflineReviewPresented) {
            GuideOfflineReviewSheet(report: GuideOfflineReview.report(for: trip))
        }
        .sheet(isPresented: $isMemoryPresented) {
            MemoryView(
                trip: trip,
                onApplyPlan: { updated in
                    let result = onApplyPlan(updated)
                    if result == nil {
                        Task {
                            try? await GuideReminderScheduler.sync(
                                trip: updated,
                                requestingAuthorization: false
                            )
                        }
                    }
                    return result
                },
                onApplyMutation: onApplyMutation
            )
        }
        .sheet(isPresented: $isTripRenamePresented) {
            GuideTripRenameSheet(title: trip.title) { title in
                updateTripTitle(title)
            }
        }
        .sheet(isPresented: $isDateRangeEditorPresented) {
            TripDateRangeSheet(
                startDate: trip.dateRange.lowerBound,
                endDate: trip.dateRange.upperBound,
                timeZoneIdentifier: trip.timeZoneIdentifier,
                onSave: updateTripDateRange
            )
        }
        .alert("操作を完了できませんでした", isPresented: Binding(
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
    private var compactActionBar: some View {
        if let selectedActivityID = interaction.selectedActivityID {
            HStack {
                if activityAndDay(for: selectedActivityID)?.0.reservation != nil {
                    Button {
                        reservationTarget = GuideReservationTarget(activityID: selectedActivityID)
                    } label: {
                        Label("予約", systemImage: "ticket")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("guide-reservation-button")
                }

                Button {
                    presentQuickEdit(selectedActivityID)
                } label: {
                    Label("クイック編集", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("guide-quick-edit-button")
            }
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
        progress: ActivityProgress,
        reservation: ReservationReference?,
        reminderLeadTime: ActivityReminderLeadTime?
    ) -> Bool {
        guard let (activity, _) = activityAndDay(for: activityID) else {
            errorMessage = "編集対象の予定が見つかりませんでした。"
            return false
        }

        do {
            let placeMutation: ActivityPlaceMutation = activity.place == place
                ? .unchanged
                : .replace(expectedPlaceID: activity.place?.id, place: place)
            let mutation = TripMutation.editGuideActivity(
                GuideActivityMutation(
                    activityID: activityID,
                    startTime: startTime,
                    note: note,
                    place: placeMutation,
                    progress: progress,
                    progressChangedAt: Date(),
                    reservation: reservation,
                    reminderLeadTime: reminderLeadTime
                )
            )
            if let onApplyMutation {
                let updated = try mutation.applying(to: trip)
                if let persistenceError = onApplyMutation(mutation) {
                    errorMessage = persistenceError
                    return false
                }
                interaction.selectActivity(activityID, source: .list, in: updated)
                let shouldRequestAuthorization = activity.reminderLeadTime == nil
                    && reminderLeadTime != nil
                Task {
                    do {
                        try await GuideReminderScheduler.sync(
                            trip: updated,
                            requestingAuthorization: shouldRequestAuthorization
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                return true
            }

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
            let withProgress = try TripPlanEditor.setActivityProgress(
                in: edited,
                activityID: activityID,
                progress: progress
            )
            let withReservation = try TripPlanEditor.setReservation(
                in: withProgress,
                activityID: activityID,
                reservation: reservation
            )
            let updated = try TripPlanEditor.setActivityReminder(
                in: withReservation,
                activityID: activityID,
                leadTime: reminderLeadTime
            )
            if let persistenceError = onApplyPlan(updated) {
                errorMessage = persistenceError
                return false
            }
            interaction.selectActivity(activityID, source: .list, in: updated)
            let shouldRequestAuthorization = activity.reminderLeadTime == nil
                && reminderLeadTime != nil
            Task {
                do {
                    try await GuideReminderScheduler.sync(
                        trip: updated,
                        requestingAuthorization: shouldRequestAuthorization
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateTripTitle(_ title: String) -> Bool {
        do {
            let mutation = TripMutation.renameTrip(title)
            let persistenceError: String?
            if let onApplyMutation {
                persistenceError = onApplyMutation(mutation)
            } else {
                persistenceError = onApplyPlan(
                    try mutation.applying(to: trip)
                )
            }
            if let persistenceError {
                errorMessage = persistenceError
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateTripDateRange(
        startDate: Date,
        endDate: Date
    ) -> Bool {
        do {
            guard let timeZone = TimeZone(
                identifier: trip.timeZoneIdentifier
            ) else {
                throw TripPlanEditingError.invalidTimeZone
            }
            let mutation = TripMutation.changeTripDateRange(
                try TripPlanEditor.makeDateRangeMutation(
                    in: trip,
                    startDate: LocalDate(
                        date: startDate,
                        timeZone: timeZone
                    ),
                    endDate: LocalDate(
                        date: endDate,
                        timeZone: timeZone
                    )
                )
            )
            let persistenceError: String?
            if let onApplyMutation {
                persistenceError = onApplyMutation(mutation)
            } else {
                persistenceError = onApplyPlan(
                    try mutation.applying(to: trip)
                )
            }
            if let persistenceError {
                errorMessage = persistenceError
                return false
            }
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
            let mutation = TripMutation.setTravelLegPreference(
                TravelLegPreferenceMutation(
                    legID: legID,
                    transportType: transportType,
                    manualDurationMinutes: manualDurationMinutes,
                    note: note
                )
            )
            let updated = try mutation.applying(to: trip)
            let persistenceError: String?
            if let onApplyMutation {
                persistenceError = onApplyMutation(mutation)
            } else {
                persistenceError = onApplyPlan(updated)
            }
            if let persistenceError {
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
            let mutation = TripMutation.setTravelLegPreference(
                TravelLegPreferenceMutation(
                    legID: legID,
                    transportType: transportType,
                    manualDurationMinutes: manualDurationMinutes,
                    note: note
                )
            )
            let updated = try mutation.applying(to: trip)
            let persistenceError: String?
            if let onApplyMutation {
                persistenceError = onApplyMutation(mutation)
            } else {
                persistenceError = onApplyPlan(updated)
            }
            if let persistenceError {
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

private struct GuideTripRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let onSave: (String) -> Bool

    init(title: String, onSave: @escaping (String) -> Bool) {
        _title = State(initialValue: title)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("旅行名", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("guide-trip-title-field")
            }
            .navigationTitle("旅行名を変更")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(title) {
                            dismiss()
                        }
                    }
                    .disabled(
                        title
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GuideOfflineReviewSheet: View {
    let report: GuideOfflineReviewReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("旅程本体はオフラインで閲覧できます", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Activity", value: "\(report.activityCount)")
                    LabeledContent("保存済み場所", value: "\(report.venueSnapshotCount)")
                    LabeledContent("ユーザー画像", value: "\(report.userImageCount)")
                    LabeledContent("予約参照", value: "\(report.reservationCount)")
                } header: {
                    Text("端末内に保存済み")
                }

                Section {
                    dependencyRow("移動時間の再取得", count: travelEstimateCount, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    dependencyRow("外部Venue画像", count: externalImageCount, systemImage: "photo.badge.arrow.down")
                    dependencyRow("予約Webリンク", count: reservationLinkCount, systemImage: "link")
                } header: {
                    Text("通信が必要な付加情報")
                } footer: {
                    Text("通信できなくても、保存済みの旅程、場所、確認番号、メモは消えません。")
                }
            }
            .navigationTitle("オフライン確認")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("guide-offline-review")
    }

    private var travelEstimateCount: Int {
        report.onlineDependencies.filter {
            if case .travelEstimate = $0 { true } else { false }
        }.count
    }

    private var externalImageCount: Int {
        report.onlineDependencies.filter {
            if case .externalVenueImage = $0 { true } else { false }
        }.count
    }

    private var reservationLinkCount: Int {
        report.onlineDependencies.filter {
            if case .reservationLink = $0 { true } else { false }
        }.count
    }

    @ViewBuilder
    private func dependencyRow(_ title: String, count: Int, systemImage: String) -> some View {
        if count > 0 {
            LabeledContent {
                Text("\(count)件")
            } label: {
                Label(title, systemImage: systemImage)
            }
        } else {
            Label("\(title)は準備済み", systemImage: "checkmark")
                .foregroundStyle(.secondary)
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

private struct GuideReservationTarget: Identifiable {
    let activityID: Activity.ID
    var id: Activity.ID { activityID }
}

private struct GuideReservationSheet: View {
    let reservation: ReservationReference

    @Environment(\.dismiss) private var dismiss
    @State private var didCopyConfirmationCode = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(reservation.title, systemImage: reservation.kind.systemImage)
                        .font(.headline)
                    LabeledContent("種類", value: reservation.kind.displayName)
                }

                if let confirmationCode = reservation.confirmationCode {
                    Section("確認番号") {
                        Text(confirmationCode)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button(
                            didCopyConfirmationCode ? "コピーしました" : "確認番号をコピー",
                            systemImage: didCopyConfirmationCode ? "checkmark" : "doc.on.doc"
                        ) {
                            UIPasteboard.general.string = confirmationCode
                            didCopyConfirmationCode = true
                        }
                        .accessibilityIdentifier("reservation-copy-confirmation-code")
                    }
                }

                if let url = reservation.url {
                    Section {
                        Link(destination: url) {
                            Label("予約ページを開く", systemImage: "safari")
                        }
                        .accessibilityIdentifier("reservation-open-url")
                    } footer: {
                        Text("TripMapを離れてWebサイトを開きます。")
                    }
                }

                if let note = reservation.note {
                    Section("メモ") {
                        Text(note)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Text("確認番号はこの画面を開いた時だけ表示します。コピーした内容はシステムのクリップボードに残ります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("予約")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("guide-reservation-sheet")
    }
}

private struct GuideQuickEditSheet: View {
    let activity: Activity
    let day: Day
    let timeZoneIdentifier: String
    let onSave: (
        Activity.ID,
        Date?,
        String?,
        PlaceSnapshot?,
        ActivityProgress,
        ReservationReference?,
        ActivityReminderLeadTime?
    ) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var note: String
    @State private var place: PlaceSnapshot?
    @State private var progress: ActivityProgress
    @State private var hasReminder: Bool
    @State private var reminderLeadTime: ActivityReminderLeadTime
    @State private var hasReservation: Bool
    @State private var reservationKind: ReservationKind
    @State private var reservationTitle: String
    @State private var confirmationCode: String
    @State private var reservationURL: String
    @State private var reservationNote: String
    @State private var isVenueSearchPresented = false

    init(
        activity: Activity,
        day: Day,
        timeZoneIdentifier: String,
        onSave: @escaping (
            Activity.ID,
            Date?,
            String?,
            PlaceSnapshot?,
            ActivityProgress,
            ReservationReference?,
            ActivityReminderLeadTime?
        ) -> Bool
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
        _hasReminder = State(initialValue: activity.reminderLeadTime != nil)
        _reminderLeadTime = State(initialValue: activity.reminderLeadTime ?? .fifteenMinutes)
        _hasReservation = State(initialValue: activity.reservation != nil)
        _reservationKind = State(initialValue: activity.reservation?.kind ?? .other)
        _reservationTitle = State(initialValue: activity.reservation?.title ?? "")
        _confirmationCode = State(initialValue: activity.reservation?.confirmationCode ?? "")
        _reservationURL = State(initialValue: activity.reservation?.url?.absoluteString ?? "")
        _reservationNote = State(initialValue: activity.reservation?.note ?? "")
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

                Section {
                    Toggle("通知を設定", isOn: $hasReminder)
                        .disabled(!hasStartTime)
                    if hasReminder, hasStartTime {
                        Picker("通知時刻", selection: $reminderLeadTime) {
                            ForEach(ActivityReminderLeadTime.allCases) { leadTime in
                                Text(leadTime.displayName).tag(leadTime)
                            }
                        }
                    }
                } header: {
                    Text("リマインダー")
                } footer: {
                    if hasStartTime {
                        Text("保存後に通知の許可を確認します。通知には予定名だけを使用し、予約番号や場所は表示しません。")
                    } else {
                        Text("開始時刻を設定すると通知を利用できます。")
                    }
                }

                Section("短いメモ") {
                    TextField("待ち合わせ場所、予約名など", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("予約") {
                    Toggle("予約参照を保存", isOn: $hasReservation)
                    if hasReservation {
                        Picker("種類", selection: $reservationKind) {
                            ForEach(ReservationKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.systemImage)
                                    .tag(kind)
                            }
                        }
                        TextField("予約名", text: $reservationTitle)
                        TextField("確認番号", text: $confirmationCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField("https://", text: $reservationURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if hasInvalidReservationURL {
                            Label("HTTPSのWebリンクを入力してください", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        TextField("予約に関するメモ", text: $reservationNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
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
                        let reservation = hasReservation ? ReservationReference(
                            id: activity.reservation?.id ?? UUID(),
                            kind: reservationKind,
                            title: reservationTitle,
                            confirmationCode: confirmationCode,
                            url: parsedReservationURL,
                            note: reservationNote
                        ) : nil
                        let reminder = hasStartTime && hasReminder ? reminderLeadTime : nil
                        if onSave(
                            activity.id,
                            editedStartTime,
                            note,
                            place,
                            progress,
                            reservation,
                            reminder
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(hasReservation && (
                        reservationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || hasInvalidReservationURL
                    ))
                    .accessibilityIdentifier("guide-quick-edit-save")
                }
            }
        }
        .accessibilityIdentifier("guide-quick-editor")
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isVenueSearchPresented) {
            VenueSearchSheet { candidate in
                place = candidate.place
            }
        }
    }

    private var parsedReservationURL: URL? {
        let value = reservationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private var hasInvalidReservationURL: Bool {
        !reservationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedReservationURL == nil
    }
}

private enum GuideReminderSchedulingError: LocalizedError {
    case notificationsDenied

    var errorDescription: String? {
        "予定は保存しました。通知を受け取るには、システム設定でTripMapの通知を許可してください。"
    }
}

@MainActor
enum GuideReminderScheduler {
    static func sync(
        trip: Trip,
        requestingAuthorization: Bool,
        now: Date = Date()
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let prefix = ActivityReminderProjection.identifierPrefix(for: trip.id)
        let schedules = ActivityReminderProjection.pendingSchedules(for: trip, now: now)
        let desiredIdentifiers = Set(schedules.map(\.id))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter {
                $0.hasPrefix(prefix) && !desiredIdentifiers.contains($0)
            }
        )

        guard !schedules.isEmpty else { return }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, requestingAuthorization {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                throw GuideReminderSchedulingError.notificationsDenied
            }
            settings = await center.notificationSettings()
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied where requestingAuthorization:
            throw GuideReminderSchedulingError.notificationsDenied
        case .notDetermined, .denied:
            return
        @unknown default:
            return
        }

        for schedule in schedules {
            let content = UNMutableNotificationContent()
            content.title = "予定のリマインダー"
            content.body = schedule.activityTitle
            content.sound = .default
            let interval = schedule.fireDate.timeIntervalSince(now)
            guard interval >= 1 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
            try await center.add(
                UNNotificationRequest(
                    identifier: schedule.id,
                    content: content,
                    trigger: trigger
                )
            )
        }
    }
}
#endif
