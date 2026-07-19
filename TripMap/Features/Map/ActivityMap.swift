import MapKit
import SwiftUI

struct ActivityMap: View {
    let day: Day
    let selectedActivityID: Activity.ID?
    let cameraRequest: MapCameraRequest?
    let onSelectMapActivity: (Activity.ID) -> Void
    @State private var cameraPosition: MapCameraPosition

    init(
        day: Day,
        selectedActivityID: Activity.ID?,
        cameraRequest: MapCameraRequest?,
        onSelectMapActivity: @escaping (Activity.ID) -> Void
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.cameraRequest = cameraRequest
        self.onSelectMapActivity = onSelectMapActivity
        _cameraPosition = State(initialValue: Self.region(for: day).map(MapCameraPosition.region) ?? .automatic)
    }

    private var placedActivities: [Activity] {
        day.orderedActivities.filter { $0.place != nil }
    }

    private var selectedActivity: Activity? {
        day.activities.first(where: { $0.id == selectedActivityID })
    }

    private var mapSelection: Binding<Activity.ID?> {
        Binding(
            get: {
                guard selectedActivity?.place != nil else { return nil }
                return selectedActivityID
            },
            set: { activityID in
                guard let activityID else { return }
                onSelectMapActivity(activityID)
            }
        )
    }

    var body: some View {
        Group {
            if placedActivities.isEmpty {
                ContentUnavailableView(
                    "地図に表示できる場所がありません",
                    systemImage: "mappin.slash",
                    description: Text("Activityに場所を追加するとピンが表示されます。")
                )
                .accessibilityIdentifier("empty-activity-map")
            } else {
                ZStack(alignment: .top) {
                    Map(position: $cameraPosition, selection: mapSelection) {
                        ForEach(placedActivities) { activity in
                            if let place = activity.place {
                                Marker(activity.title, coordinate: place.coordinate)
                                    .tag(activity.id)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapPitchToggle()
                    }
                    .accessibilityIdentifier("activity-map")

                    if let selectedActivity, selectedActivity.place == nil {
                        Label("このActivityには場所が設定されていません", systemImage: "mappin.slash")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding()
                            .accessibilityIdentifier("activity-without-place")
                    }
                }
            }
        }
        .onChange(of: cameraRequest) { _, request in
            apply(request)
        }
        .onChange(of: day.id) { _, _ in
            showWholeDay()
        }
    }

    private func apply(_ request: MapCameraRequest?) {
        guard let request else { return }

        switch request.target {
        case .day(let dayID):
            guard dayID == day.id else { return }
            showWholeDay()
        case .activity(let activityID):
            guard let place = day.activities.first(where: { $0.id == activityID })?.place else { return }
            withAnimation(.easeInOut) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
                    )
                )
            }
        }
    }

    private func showWholeDay() {
        guard let region = Self.region(for: day) else { return }
        withAnimation(.easeInOut) {
            cameraPosition = .region(region)
        }
    }

    nonisolated static func region(for day: Day) -> MKCoordinateRegion? {
        let coordinates = day.activities.compactMap(\.place?.coordinate)
        guard let first = coordinates.first else { return nil }

        let latitudeBounds = coordinates.reduce((minimum: first.latitude, maximum: first.latitude)) {
            (min($0.minimum, $1.latitude), max($0.maximum, $1.latitude))
        }
        let longitudeBounds = minimalLongitudeBounds(coordinates.map(\.longitude))

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (latitudeBounds.minimum + latitudeBounds.maximum) / 2,
                longitude: normalizedLongitude((longitudeBounds.start + longitudeBounds.end) / 2)
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((latitudeBounds.maximum - latitudeBounds.minimum) * 1.8, 0.04),
                longitudeDelta: max((longitudeBounds.end - longitudeBounds.start) * 1.8, 0.04)
            )
        )
    }

    nonisolated private static func minimalLongitudeBounds(_ longitudes: [Double]) -> (start: Double, end: Double) {
        let sorted = longitudes.map { longitude in
            let value = longitude.truncatingRemainder(dividingBy: 360)
            return value < 0 ? value + 360 : value
        }.sorted()

        guard sorted.count > 1 else {
            let longitude = sorted[0]
            return (longitude, longitude)
        }

        var largestGapIndex = 0
        var largestGap = -Double.infinity
        for index in sorted.indices {
            let next = index == sorted.count - 1 ? sorted[0] + 360 : sorted[index + 1]
            let gap = next - sorted[index]
            if gap > largestGap {
                largestGap = gap
                largestGapIndex = index
            }
        }

        let nextIndex = (largestGapIndex + 1) % sorted.count
        let start = sorted[nextIndex]
        var end = sorted[largestGapIndex]
        if end < start {
            end += 360
        }
        return (start, end)
    }

    nonisolated private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
