import MapKit
import PhotosUI
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ActivityMapPinLabel: Hashable {
    let primary: String
    private let representsDay: Bool

    init(activitySequence: Int) {
        primary = "\(activitySequence)"
        representsDay = false
    }

    init(daySequence: Int) {
        primary = "\(daySequence)"
        representsDay = true
    }

    var accessibilityDescription: String {
        representsDay ? "Day \(primary)" : "予定 \(primary)"
    }
}

struct ActivityMap: View {
    let day: Day
    let selectedActivityID: Activity.ID?
    let cameraRequest: MapCameraRequest?
    let onSelectMapActivity: (Activity.ID) -> Void
    let onUpdatePlaceImage: (Activity.ID, Data?) -> Void
    let allowsPlaceImageEditing: Bool
    let showsPlaceDetailOverlay: Bool
    let pinLabels: [Activity.ID: ActivityMapPinLabel]
    @State private var cameraPosition: MapCameraPosition

    init(
        day: Day,
        selectedActivityID: Activity.ID?,
        cameraRequest: MapCameraRequest?,
        onSelectMapActivity: @escaping (Activity.ID) -> Void,
        onUpdatePlaceImage: @escaping (Activity.ID, Data?) -> Void = { _, _ in },
        allowsPlaceImageEditing: Bool = false,
        showsPlaceDetailOverlay: Bool = true,
        pinLabels: [Activity.ID: ActivityMapPinLabel] = [:]
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.cameraRequest = cameraRequest
        self.onSelectMapActivity = onSelectMapActivity
        self.onUpdatePlaceImage = onUpdatePlaceImage
        self.allowsPlaceImageEditing = allowsPlaceImageEditing
        self.showsPlaceDetailOverlay = showsPlaceDetailOverlay
        self.pinLabels = pinLabels
        _cameraPosition = State(initialValue: Self.region(for: day).map(MapCameraPosition.region) ?? .automatic)
    }

    private var placedActivities: [Activity] {
        Self.activitiesWithPlaces(in: day)
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
                                let pinLabel = pinLabels[activity.id] ?? ActivityMapPinLabel(activitySequence: activity.sequence)
                                Annotation(activity.title, coordinate: place.coordinate, anchor: .bottom) {
                                    Button {
                                        onSelectMapActivity(activity.id)
                                    } label: {
                                        ActivitySequencePin(
                                            label: pinLabel,
                                            isSelected: activity.id == selectedActivityID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 44, height: 44, alignment: .bottom)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("\(activity.title)、\(pinLabel.accessibilityDescription)")
                                }
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
                    } else if showsPlaceDetailOverlay, let selectedActivity, let place = selectedActivity.place {
                        PlaceDetailOverlay(
                            activity: selectedActivity,
                            place: place,
                            onUpdateImage: { imageData in onUpdatePlaceImage(selectedActivity.id, imageData) },
                            allowsImageEditing: allowsPlaceImageEditing
                        )
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
        let coordinates = activitiesWithPlaces(in: day).compactMap(\.place?.coordinate)
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

    nonisolated static func activitiesWithPlaces(in day: Day) -> [Activity] {
        day.orderedActivities.filter { $0.place != nil }
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

private struct ActivitySequencePin: View {
    let label: ActivityMapPinLabel
    let isSelected: Bool

    private var color: Color {
        isSelected ? .accentColor : Color(red: 0.82, green: 0.27, blue: 0.33)
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapPinTip()
                .fill(color)
                .overlay {
                    MapPinTip().stroke(.white.opacity(0.92), lineWidth: 1.25)
                }
                .frame(width: 9, height: 9)
                .offset(y: 22)

            ZStack {
                Text(label.primary)
                    .font(.system(size: label.primary.count == 1 ? 14 : 12, weight: .bold, design: .rounded))
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.95), lineWidth: isSelected ? 2 : 1.25)
            }
        }
        .frame(width: 28, height: 31, alignment: .top)
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct MapPinTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

private struct PlaceDetailOverlay: View {
    let activity: Activity
    let place: PlaceSnapshot
    let onUpdateImage: (Data?) -> Void
    let allowsImageEditing: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var imageError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceIllustration(data: place.imageData, scene: lookAroundScene)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .top, spacing: 8) {
                Text("\(activity.sequence)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.headline).lineLimit(2)
                    if let startTime = activity.startTime {
                        Text(startTime, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text(place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                if allowsImageEditing {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(place.imageData == nil ? "画像" : "画像を変更", systemImage: "photo")
                    }
                }
                PlaceCardSpikeButton(place: place)
                Button("Mapsで開く", systemImage: "map") { place.openInMaps() }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 12, y: 4)
        .task(id: place.id) {
            let request = MKLookAroundSceneRequest(coordinate: place.coordinate)
            lookAroundScene = try? await request.scene
        }
        .task(id: pickerItem) {
            guard let originalData = try? await pickerItem?.loadTransferable(type: Data.self),
                  let data = TripImageProcessor.normalizedJPEGData(from: originalData) else {
                if pickerItem != nil { imageError = "画像を読み込めませんでした。" }
                return
            }
            onUpdateImage(data)
            pickerItem = nil
        }
        .alert("画像を更新できませんでした", isPresented: Binding(
            get: { imageError != nil }, set: { if !$0 { imageError = nil } }
        )) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "不明なエラー")
        }
    }
}

private struct PlaceIllustration: View {
    let data: Data?
    let scene: MKLookAroundScene?

    var body: some View {
        if let data {
            #if os(macOS)
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else { placeholder }
            #else
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { placeholder }
            #endif
        } else if let scene {
            LookAroundPreview(initialScene: scene)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [.teal.opacity(0.7), .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "mappin.and.ellipse").font(.title).foregroundStyle(.white.opacity(0.9)))
    }
}

private extension PlaceSnapshot {
    func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps()
    }
}
