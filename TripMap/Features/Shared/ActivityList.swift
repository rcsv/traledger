import SwiftUI

struct ActivityList: View {
    let day: Day
    let selectedActivityID: Activity.ID?
    let doctorIssues: [TripDoctorIssue]
    let onSelectActivity: (Activity.ID) -> Void
    let onAddActivity: (() -> Void)?

    init(
        day: Day,
        selectedActivityID: Activity.ID?,
        doctorIssues: [TripDoctorIssue] = [],
        onSelectActivity: @escaping (Activity.ID) -> Void,
        onAddActivity: (() -> Void)? = nil
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.doctorIssues = doctorIssues
        self.onSelectActivity = onSelectActivity
        self.onAddActivity = onAddActivity
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
                        ForEach(day.orderedActivities) { activity in
                            ActivityCard(
                                activity: activity,
                                isSelected: selectedActivityID == activity.id,
                                doctorIssues: doctorIssues.filter { $0.target.activityID == activity.id }
                            ) {
                                withAnimation(.snappy) {
                                    onSelectActivity(activity.id)
                                }
                            }
                            .id(activity.id)
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
}

private struct ActivityCard: View {
    let activity: Activity
    let isSelected: Bool
    let doctorIssues: [TripDoctorIssue]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)分" }
        if remainder == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainder)分"
    }
}
