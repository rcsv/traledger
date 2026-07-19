#if os(iOS)
import SwiftUI

struct GuideView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"

        var id: Self { self }
    }

    let trip: Trip
    @State private var interaction: TripInteractionState
    @State private var mode: Mode = .map

    init(trip: Trip) {
        self.trip = trip
        _interaction = State(initialValue: TripInteractionState(trip: trip))
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
        NavigationStack {
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
                        switch mode {
                        case .map:
                            ZStack(alignment: .bottom) {
                                ActivityMap(
                                    day: selectedDay,
                                    selectedActivityID: interaction.selectedActivityID,
                                    cameraRequest: interaction.cameraRequest,
                                    onSelectMapActivity: selectActivityFromMap
                                )

                                if let activity = interaction.selectedActivity(in: trip) {
                                    SelectedActivityBar(activity: activity) {
                                        mode = .list
                                    }
                                    .padding()
                                }
                            }
                        case .list:
                            ActivityList(
                                day: selectedDay,
                                selectedActivityID: interaction.selectedActivityID,
                                onSelectActivity: selectActivityFromList
                            )
                        }
                    }
                }
            }
            .navigationTitle(trip.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: trip) { _, trip in
                interaction.reconcile(with: trip)
            }
        }
    }

    private func selectActivityFromList(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
    }

    private func selectActivityFromMap(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .map, in: trip)
    }
}

private struct SelectedActivityBar: View {
    let activity: Activity
    let showInList: () -> Void

    var body: some View {
        Button(action: showInList) {
            HStack(spacing: 12) {
                Image(systemName: activity.place == nil ? "mappin.slash" : "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let place = activity.place {
                        Text(place.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("場所未設定")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "list.bullet")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(activity.title)をリストで表示")
    }
}
#endif
