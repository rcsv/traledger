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

    init(trip: Trip, initialActivityID: Activity.ID? = nil) {
        self.trip = trip
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
                            onSelectActivity: selectActivityFromList
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
        .onChange(of: trip) { _, trip in
            interaction.reconcile(with: trip)
        }
    }

    private func selectActivityFromList(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .list, in: trip)
    }

    private func selectActivityFromMap(_ activityID: Activity.ID) {
        interaction.selectActivity(activityID, source: .map, in: trip)
    }
}
#endif
