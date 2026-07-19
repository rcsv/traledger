import SwiftUI

struct ActivityList: View {
    let day: Day
    let selectedActivityID: Activity.ID?
    let onSelectActivity: (Activity.ID) -> Void

    var body: some View {
        if day.activities.isEmpty {
            ContentUnavailableView(
                "予定がありません",
                systemImage: "calendar.badge.plus",
                description: Text("この日にActivityを追加すると、ここに表示されます。")
            )
            .accessibilityIdentifier("empty-activity-list")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(day.orderedActivities) { activity in
                            ActivityCard(
                                activity: activity,
                                isSelected: selectedActivityID == activity.id
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
}
