import MapKit
import SwiftUI

struct ActivityList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: Day
    let selectedActivityID: Activity.ID?
    let doctorIssues: [TripDoctorIssue]
    let travelLegs: [TravelLeg]
    let activityTemporalRoles: [Activity.ID: GuideActivityTemporalRole]
    let onSelectActivity: (Activity.ID) -> Void
    let onAddActivity: (() -> Void)?
    let onEditActivity: ((Activity.ID) -> Void)?
    let onDeleteActivity: ((Activity.ID) -> Void)?
    let onMoveActivity: ((Activity.ID, Activity.ID) -> Void)?
    let onEditTravelLeg: ((TravelLegID) -> Void)?
    let onInsertActivity: ((ActivityInsertionAnchor) -> Void)?

    init(
        day: Day,
        selectedActivityID: Activity.ID?,
        doctorIssues: [TripDoctorIssue] = [],
        travelLegs: [TravelLeg] = [],
        activityTemporalRoles: [Activity.ID: GuideActivityTemporalRole] = [:],
        onSelectActivity: @escaping (Activity.ID) -> Void,
        onAddActivity: (() -> Void)? = nil,
        onEditActivity: ((Activity.ID) -> Void)? = nil,
        onDeleteActivity: ((Activity.ID) -> Void)? = nil,
        onMoveActivity: ((Activity.ID, Activity.ID) -> Void)? = nil,
        onEditTravelLeg: ((TravelLegID) -> Void)? = nil,
        onInsertActivity: ((ActivityInsertionAnchor) -> Void)? = nil
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.doctorIssues = doctorIssues
        self.travelLegs = travelLegs
        self.activityTemporalRoles = activityTemporalRoles
        self.onSelectActivity = onSelectActivity
        self.onAddActivity = onAddActivity
        self.onEditActivity = onEditActivity
        self.onDeleteActivity = onDeleteActivity
        self.onMoveActivity = onMoveActivity
        self.onEditTravelLeg = onEditTravelLeg
        self.onInsertActivity = onInsertActivity
    }

    var body: some View {
        if day.activities.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "予定がありません",
                    systemImage: "calendar.badge.plus",
                    description: Text("この日に予定を追加すると、ここに表示されます。")
                )
                if let onAddActivity {
                    Button("予定を追加", systemImage: "plus", action: onAddActivity)
                        .buttonStyle(.borderedProminent)
                }
            }
            .accessibilityIdentifier("empty-activity-list")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let firstActivity = day.orderedActivities.first,
                           let onInsertActivity {
                            ActivityInsertionButton(
                                positionLabel: "先頭",
                                accessibilitySuffix: "start",
                                anchor: ActivityInsertionAnchor(
                                    previousActivityID: nil,
                                    nextActivityID: firstActivity.id
                                ),
                                onInsert: onInsertActivity
                            )
                        }

                        ForEach(Array(day.orderedActivities.enumerated()), id: \.element.id) { index, activity in
                            ActivityCard(
                                activity: activity,
                                isSelected: selectedActivityID == activity.id,
                                temporalRole: activityTemporalRoles[activity.id],
                                doctorIssues: doctorIssues.filter { $0.target.activityID == activity.id },
                                onSelect: { select(activity.id) },
                                onEdit: onEditActivity.map { edit in
                                    { select(activity.id); edit(activity.id) }
                                },
                                onDelete: onDeleteActivity.map { delete in
                                    { select(activity.id); delete(activity.id) }
                                },
                                moveEarlier: moveAction(for: activity, targetIndex: index - 1),
                                moveLater: moveAction(for: activity, targetIndex: index + 1),
                                onDropActivity: onMoveActivity.map { move in
                                    { sourceID in move(sourceID, activity.id) }
                                }
                            )
                            .id(activity.id)
                            .overlay(alignment: .trailing) {
                                if onMoveActivity != nil {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 44)
                                        .contentShape(Rectangle())
                                        .draggable(activity.id.uuidString)
                                        .accessibilityLabel("予定を並べ替え")
                                        .accessibilityIdentifier("activity-drag-\(activity.sequence)")
                                    .padding(.trailing, 8)
                                }
                            }

                            if day.orderedActivities.indices.contains(index + 1) {
                                let nextActivity = day.orderedActivities[index + 1]
                                if let leg = travelLeg(
                                    from: activity.id,
                                    to: nextActivity.id
                                ) {
                                    TravelLegRow(
                                        leg: leg,
                                        fromActivity: activity,
                                        toActivity: nextActivity,
                                        onEdit: onEditTravelLeg.map { edit in
                                            { edit(leg.id) }
                                        }
                                    )
                                }
                            }

                            if let onInsertActivity {
                                let nextActivityID = day.orderedActivities.indices
                                    .contains(index + 1)
                                    ? day.orderedActivities[index + 1].id
                                    : nil
                                ActivityInsertionButton(
                                    positionLabel: nextActivityID == nil
                                        ? "末尾"
                                        : "\(activity.sequence)と\(activity.sequence + 1)の間",
                                    accessibilitySuffix: nextActivityID == nil
                                        ? "end"
                                        : "between-\(activity.sequence)",
                                    anchor: ActivityInsertionAnchor(
                                        previousActivityID: activity.id,
                                        nextActivityID: nextActivityID
                                    ),
                                    onInsert: onInsertActivity
                                )
                            }
                        }
                    }
                    .background(alignment: .leading) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.32))
                            .frame(width: 2)
                            .padding(.leading, 24)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                    .padding()
                }
                .onChange(of: selectedActivityID) { _, activityID in
                    guard let activityID else { return }
                    withAnimation(reduceMotion ? nil : .snappy) {
                        proxy.scrollTo(activityID, anchor: .center)
                    }
                }
            }
            .accessibilityIdentifier("activity-list")
        }
    }

    private func select(_ activityID: Activity.ID) {
        withAnimation(reduceMotion ? nil : .snappy) {
            onSelectActivity(activityID)
        }
    }

    private func moveAction(for activity: Activity, targetIndex: Int) -> (() -> Void)? {
        guard let onMoveActivity,
              day.orderedActivities.indices.contains(targetIndex) else {
            return nil
        }
        let targetID = day.orderedActivities[targetIndex].id
        return {
            select(activity.id)
            onMoveActivity(activity.id, targetID)
        }
    }

    private func travelLeg(
        from fromActivityID: Activity.ID,
        to toActivityID: Activity.ID
    ) -> TravelLeg? {
        let id = TravelLegID(
            fromActivityID: fromActivityID,
            toActivityID: toActivityID
        )
        return travelLegs.first { $0.dayID == day.id && $0.id == id }
    }
}

private struct ActivityInsertionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let positionLabel: String
    let accessibilitySuffix: String
    let anchor: ActivityInsertionAnchor
    let onInsert: (ActivityInsertionAnchor) -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        #if os(macOS)
        let isActive = isHovered || isFocused || isAccessibilityFocused
        #else
        let isActive = true
        #endif
        Button {
            onInsert(anchor)
        } label: {
            HStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            isActive
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.34)
                        )
                        .frame(
                            width: isActive ? 22 : 8,
                            height: isActive ? 22 : 8
                        )

                    Image(systemName: "plus")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .opacity(isActive ? 1 : 0)
                }
                .frame(width: 48, height: 26)
                .overlay {
                    if isActive {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                            .frame(width: 22, height: 22)
                    }
                }

                Text("予定を追加")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    #if os(macOS)
                    .opacity(isActive ? 1 : 0)
                    #endif

                Spacer(minLength: 0)
            }
            #if os(iOS)
            .frame(minHeight: 44)
            #else
            .frame(minHeight: 30)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityFocused($isAccessibilityFocused)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isActive)
        .accessibilityLabel("予定を追加")
        .accessibilityHint("挿入位置: \(positionLabel)")
        .accessibilityIdentifier("activity-insert-\(accessibilitySuffix)")
    }
}

private struct TravelLegRow: View {
    let leg: TravelLeg
    let fromActivity: Activity
    let toActivity: Activity
    let onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint("移動手段、手動所要時間、メモを編集")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: leg.transportType.systemImage)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(statusText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if case .loading = leg.calculationState {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(fromActivity.title)から\(toActivity.title)へ。\(statusText)"
        )
        .accessibilityIdentifier(
            "travel-leg-\(fromActivity.sequence)-\(toActivity.sequence)"
        )
    }

    private var statusText: String {
        if let duration = leg.effectiveDuration {
            let suffix = switch duration.source {
            case .manual: "・手動設定"
            case .mapKit: ""
            case .staleMapKit: "・古い推定"
            }
            return "\(transportLabel) \(formattedDuration(duration.minutes))\(suffix)"
        }

        return switch leg.calculationState {
        case .idle: "\(transportLabel)・未計算"
        case .loading: "\(transportLabel)・計算中"
        case .loaded: "\(transportLabel)・所要時間不明"
        case .unavailable: "\(transportLabel)・経路を利用できません"
        case .failed: "\(transportLabel)・取得に失敗しました"
        case .stale: "\(transportLabel)・古い推定"
        }
    }

    private var transportLabel: String {
        leg.transportType == .other ? "その他の移動" : leg.transportType.displayName
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }
}

private struct ActivityCard: View {
    let activity: Activity
    let isSelected: Bool
    let temporalRole: GuideActivityTemporalRole?
    let doctorIssues: [TripDoctorIssue]
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let moveEarlier: (() -> Void)?
    let moveLater: (() -> Void)?
    let onDropActivity: ((Activity.ID) -> Void)?

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(activity.sequence)")
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    if let startTime = activity.startTime {
                        Text(startTime, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("時刻未定")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(activity.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let temporalRole {
                        Label(temporalRole.displayName, systemImage: temporalRole.systemImage)
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier("activity-temporal-\(temporalRole.rawValue)")
                    }

                    if activity.progress != .planned {
                        Label(activity.progress.displayName, systemImage: activity.progress.systemImage)
                            .font(.caption.bold())
                            .foregroundStyle(activity.progress == .completed ? Color.green : Color.secondary)
                            .accessibilityIdentifier("activity-progress-\(activity.progress.rawValue)")
                    }

                    if activity.category != nil || activity.durationMinutes != nil {
                        HStack(spacing: 10) {
                            if let category = activity.category {
                                Label(category.displayName, systemImage: category.systemImage)
                            }
                            if let durationMinutes = activity.durationMinutes {
                                Label(formattedDuration(durationMinutes), systemImage: "clock")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let place = activity.place {
                        Label(place.name, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let reservation = activity.reservation {
                        Label(reservation.title, systemImage: reservation.kind.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("activity-reservation")
                    }

                    if let reminderLeadTime = activity.reminderLeadTime {
                        Label(
                            "通知: \(reminderLeadTime.displayName)",
                            systemImage: "bell.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("activity-reminder")
                    }

                    if let note = activity.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    ForEach(doctorIssues) { issue in
                        Label(issue.message, systemImage: issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(issue.severity == .warning ? Color.orange : Color.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .padding(.trailing, onDropActivity == nil ? 0 : 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity-\(activity.sequence)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(ActivityDropModifier(activityID: activity.id, onDropActivity: onDropActivity))
        .contextMenu {
            if let moveEarlier {
                Button("前へ移動", systemImage: "arrow.up", action: moveEarlier)
            }
            if let moveLater {
                Button("後へ移動", systemImage: "arrow.down", action: moveLater)
            }
            if moveEarlier != nil || moveLater != nil {
                Divider()
            }
            if let onEdit {
                Button("予定を編集", systemImage: "pencil", action: onEdit)
            }
            if let onDelete {
                Divider()
                Button("予定を削除", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .accessibilityActions {
            if let moveEarlier {
                Button("前へ移動", action: moveEarlier)
            }
            if let moveLater {
                Button("後へ移動", action: moveLater)
            }
            if let onEdit {
                Button("予定を編集", action: onEdit)
            }
            if let onDelete {
                Button("予定を削除", role: .destructive, action: onDelete)
            }
        }
        #if os(macOS)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onEdit?()
            }
        )
        .onKeyPress(.return) {
            guard let onEdit else { return .ignored }
            onEdit()
            return .handled
        }
        .help(onEdit == nil ? "予定を選択" : "ダブルクリックまたはReturnキーで編集")
        #endif
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }
}

struct TravelLegEditSheet: View {
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
                    LabeledContent("出発場所", value: leg.fromPlace.name)
                    LabeledContent("到着場所", value: leg.toPlace.name)
                    LabeledContent("所要時間") {
                        Text(routeDurationText)
                    }
                    LabeledContent("情報源") {
                        Text(routeSourceText)
                    }

                    if let directionsMode {
                        Button("Appleマップで経路を開く", systemImage: "map") {
                            openRouteInMaps(directionsMode: directionsMode)
                        }
                        .accessibilityIdentifier("travel-leg-open-maps-button")
                    }
                } header: {
                    Text("経路概要")
                } footer: {
                    if directionsMode == nil {
                        Text("「その他」の移動は経路モードを決められないため、Appleマップ連携を表示しません。")
                    } else {
                        Text("経路は必要な時だけAppleマップで表示します。TripMap内に経路線は常時表示・保存しません。")
                    }
                }

                Section("移動手段") {
                    Picker("移動手段", selection: $transportType) {
                        ForEach(TravelTransportType.allCases) { transport in
                            Label(transport.displayName, systemImage: transport.systemImage)
                                .tag(transport)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #else
                    .pickerStyle(.menu)
                    #endif
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

    private var routeDurationText: String {
        guard let duration = leg.effectiveDuration else {
            return switch leg.calculationState {
            case .idle: "未計算"
            case .loading: "計算中"
            case .loaded: "不明"
            case .unavailable: "利用できません"
            case .failed: "取得に失敗"
            case .stale: "古い推定"
            }
        }
        return formattedDuration(duration.minutes)
    }

    private var routeSourceText: String {
        if let duration = leg.effectiveDuration {
            return switch duration.source {
            case .manual: "手動設定"
            case .mapKit: "MapKit推定"
            case .staleMapKit: "古いMapKit推定"
            }
        }
        return switch leg.calculationState {
        case .idle: "未取得"
        case .loading: "MapKitへ問い合わせ中"
        case .loaded, .stale: "MapKit推定"
        case .unavailable: "この移動手段では利用不可"
        case .failed: "通信または経路取得エラー"
        }
    }

    private var directionsMode: String? {
        switch leg.transportType {
        case .automobile: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .other: nil
        }
    }

    private func openRouteInMaps(directionsMode: String) {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: leg.fromPlace.coordinate))
        source.name = leg.fromPlace.name
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: leg.toPlace.coordinate))
        destination.name = leg.toPlace.name
        MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: directionsMode]
        )
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }
}

private struct ActivityDropModifier: ViewModifier {
    let activityID: Activity.ID
    let onDropActivity: ((Activity.ID) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDropActivity {
            content
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let identifier = identifiers.first,
                          let sourceID = UUID(uuidString: identifier),
                          sourceID != activityID else {
                        return false
                    }
                    onDropActivity(sourceID)
                    return true
                }
        } else {
            content
        }
    }
}
