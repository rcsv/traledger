import Foundation

enum ActivitySelectionSource: Equatable, Sendable {
    case list
    case map
}

struct MapCameraRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case day(Day.ID)
        case activity(Activity.ID)
    }

    let target: Target
    let generation: Int
}

struct TripInteractionState: Equatable, Sendable {
    private(set) var selectedDayID: Day.ID?
    private(set) var selectedActivityID: Activity.ID?
    private(set) var cameraRequest: MapCameraRequest?
    private var cameraGeneration = 0
    private var lastSelectedActivitySequence: Int?

    init(trip: Trip) {
        let initialDay = trip.orderedDays.dropFirst().first ?? trip.orderedDays.first
        selectedDayID = initialDay?.id
        selectedActivityID = initialDay?.orderedActivities.first?.id
        lastSelectedActivitySequence = initialDay?.orderedActivities.first?.sequence
        cameraRequest = initialDay.map {
            MapCameraRequest(target: .day($0.id), generation: cameraGeneration)
        }
    }

    func selectedDay(in trip: Trip) -> Day? {
        trip.days.first(where: { $0.id == selectedDayID })
    }

    func selectedActivity(in trip: Trip) -> Activity? {
        selectedDay(in: trip)?.activities.first(where: { $0.id == selectedActivityID })
    }

    mutating func selectDay(_ dayID: Day.ID?, in trip: Trip) {
        guard let dayID, let day = trip.days.first(where: { $0.id == dayID }) else {
            selectedDayID = nil
            selectedActivityID = nil
            cameraRequest = nil
            lastSelectedActivitySequence = nil
            return
        }

        selectedDayID = day.id
        selectedActivityID = day.orderedActivities.first?.id
        lastSelectedActivitySequence = day.orderedActivities.first?.sequence
        requestCamera(.day(day.id))
    }

    mutating func selectActivity(
        _ activityID: Activity.ID?,
        source: ActivitySelectionSource,
        in trip: Trip
    ) {
        guard let day = selectedDay(in: trip) else {
            selectedActivityID = nil
            lastSelectedActivitySequence = nil
            return
        }

        guard let activityID else {
            selectedActivityID = nil
            lastSelectedActivitySequence = nil
            return
        }

        guard let activity = day.activities.first(where: { $0.id == activityID }) else {
            return
        }

        selectedActivityID = activity.id
        lastSelectedActivitySequence = activity.sequence
        if source == .list, activity.place != nil {
            requestCamera(.activity(activity.id))
        }
    }

    mutating func reconcile(with trip: Trip) {
        guard let selectedDay = selectedDay(in: trip) else {
            let firstDay = trip.orderedDays.first
            selectedDayID = firstDay?.id
            selectedActivityID = firstDay?.orderedActivities.first?.id
            lastSelectedActivitySequence = firstDay?.orderedActivities.first?.sequence
            cameraRequest = firstDay.map {
                MapCameraRequest(target: .day($0.id), generation: cameraGeneration)
            }
            return
        }

        if !selectedDay.activities.contains(where: { $0.id == selectedActivityID }) {
            let orderedActivities = selectedDay.orderedActivities
            let replacement = lastSelectedActivitySequence.flatMap { sequence in
                orderedActivities.first(where: { $0.sequence >= sequence }) ?? orderedActivities.last
            } ?? orderedActivities.first
            selectedActivityID = replacement?.id
            lastSelectedActivitySequence = replacement?.sequence
        }
    }

    private mutating func requestCamera(_ target: MapCameraRequest.Target) {
        cameraGeneration += 1
        cameraRequest = MapCameraRequest(target: target, generation: cameraGeneration)
    }
}
