import SwiftUI

struct ActivityList: View {
    let day: Day
    let selectedActivityID: Activity.ID?
    let doctorIssues: [TripDoctorIssue]
    let onSelectActivity: (Activity.ID) -> Void
    let onAddActivity: (() -> Void)?
    let onEditActivity: ((Activity.ID) -> Void)?
    let onDeleteActivity: ((Activity.ID) -> Void)?
    let onMoveActivity: ((Activity.ID, Activity.ID) -> Void)?

    init(
        day: Day,
        selectedActivityID: Activity.ID?,
        doctorIssues: [TripDoctorIssue] = [],
        onSelectActivity: @escaping (Activity.ID) -> Void,
        onAddActivity: (() -> Void)? = nil,
        onEditActivity: ((Activity.ID) -> Void)? = nil,
        onDeleteActivity: ((Activity.ID) -> Void)? = nil,
        onMoveActivity: ((Activity.ID, Activity.ID) -> Void)? = nil
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.doctorIssues = doctorIssues
        self.onSelectActivity = onSelectActivity
        self.onAddActivity = onAddActivity
        self.onEditActivity = onEditActivity
        self.onDeleteActivity = onDeleteActivity
        self.onMoveActivity = onMoveActivity
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
                        ForEach(Array(day.orderedActivities.enumerated()), id: \.element.id) { index, activity in
                            ActivityCard(
                                activity: activity,
                                isSelected: selectedActivityID == activity.id,
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
                        }
                    }
                    .padding()
                }
                .onChange(of: selectedActivityID) { _, activityID in
                    guard let activityID else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(activityID, anchor: .center)
                    }
                }
            }
            .accessibilityIdentifier("activity-list")
        }
    }

    private func select(_ activityID: Activity.ID) {
        withAnimation(.snappy) {
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
}

private struct ActivityCard: View {
    let activity: Activity
    let isSelected: Bool
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
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
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
