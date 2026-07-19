#if os(macOS)
import SwiftUI

struct PlanView: View {
    let trip: Trip
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var interaction: TripInteractionState

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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(trip.orderedDays, selection: selectedDayBinding) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(day.sequence)")
                        .font(.headline)
                    Text(day.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                        .foregroundStyle(.secondary)
                    Text(day.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .tag(day.id)
            }
            .navigationTitle(trip.title)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            if let selectedDay {
                VStack(alignment: .leading, spacing: 0) {
                    DayHeader(day: selectedDay)
                    Divider()
                    ActivityList(
                        day: selectedDay,
                        selectedActivityID: interaction.selectedActivityID,
                        onSelectActivity: selectActivityFromList
                    )
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
            } else {
                ContentUnavailableView(
                    "旅行日程がありません",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Tripには少なくとも1日が必要です。")
                )
            }
        } detail: {
            if let selectedDay {
                ActivityMap(
                    day: selectedDay,
                    selectedActivityID: interaction.selectedActivityID,
                    cameraRequest: interaction.cameraRequest,
                    onSelectMapActivity: selectActivityFromMap
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("地図に表示する日がありません", systemImage: "map")
            }
        }
        .frame(minWidth: 1100, minHeight: 620)
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

private struct DayHeader: View {
    let day: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Day \(day.sequence)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(day.title)
                .font(.title2.bold())
            Text(day.date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
