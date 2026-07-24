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
    let onUpdateExternalPlaceImage: (Activity.ID, ExternalPlaceImage?) -> Void
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
        onUpdateExternalPlaceImage: @escaping (Activity.ID, ExternalPlaceImage?) -> Void = { _, _ in },
        allowsPlaceImageEditing: Bool = false,
        showsPlaceDetailOverlay: Bool = true,
        pinLabels: [Activity.ID: ActivityMapPinLabel] = [:]
    ) {
        self.day = day
        self.selectedActivityID = selectedActivityID
        self.cameraRequest = cameraRequest
        self.onSelectMapActivity = onSelectMapActivity
        self.onUpdatePlaceImage = onUpdatePlaceImage
        self.onUpdateExternalPlaceImage = onUpdateExternalPlaceImage
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
                            onUpdateExternalImage: { image in onUpdateExternalPlaceImage(selectedActivity.id, image) },
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
    let onUpdateExternalImage: (ExternalPlaceImage?) -> Void
    let allowsImageEditing: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageError: String?
    @StateObject private var venueResolution = PlaceResolutionModel()
    @StateObject private var imageResolution = VenueImageResolutionModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                venueSummary(imageSize: CGSize(width: 72, height: 72))
            } else {
                ViewThatFits(in: .horizontal) {
                    venueSummary(imageSize: CGSize(width: 176, height: 99))
                        .frame(minWidth: 400, alignment: .leading)
                    venueSummary(imageSize: CGSize(width: 88, height: 88))
                }
            }

            imageAttribution

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityActions
            } else {
                ViewThatFits(in: .horizontal) {
                    regularActions
                        .frame(minWidth: allowsImageEditing ? 400 : 270)
                    compactActions
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 12, y: 4)
        .task(id: place.id) {
            venueResolution.load(place)
        }
        .task(id: VenueImageResolutionRequestID(placeID: place.id, hasUserImage: place.imageData != nil)) {
            imageResolution.load(place) { image in
                onUpdateExternalImage(image)
            }
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
        .onDisappear {
            venueResolution.cancel()
            imageResolution.cancel()
        }
    }

    private func venueSummary(imageSize: CGSize) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PlaceIllustration(
                data: place.imageData,
                externalImage: imageResolution.externalImage,
                scene: imageResolution.lookAroundScene,
                source: imageResolution.source
            )
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("venue-image")
                .accessibilityLabel(imageAccessibilityLabel)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(activity.sequence)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())
                        .accessibilityLabel("予定 \(activity.sequence)")

                    if let startTime = activity.startTime {
                        Text(startTime, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(place.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                if let category = venueCategory {
                    Label(category, systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var imageAttribution: some View {
        if imageResolution.source == .wikimedia, let image = imageResolution.externalImage {
            Link(destination: image.sourcePageURL) {
                Text("Wikimedia Commons · \(image.authorName) · \(image.licenseName)")
                    .font(.caption2)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .focusable()
            .accessibilityIdentifier("wikimedia-attribution")
            .accessibilityLabel("Wikimedia Commons の画像。作者 \(image.authorName)、ライセンス \(image.licenseName)")
        }
    }

    private var regularActions: some View {
        HStack(spacing: 8) {
            if allowsImageEditing {
                imagePicker
            }
            ResolvedMapsButton(place: place, resolvedMapItem: venueResolution.mapItem)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private var compactActions: some View {
        HStack(spacing: 8) {
            if allowsImageEditing {
                imagePicker
            }
            ResolvedMapsButton(place: place, resolvedMapItem: venueResolution.mapItem)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private var accessibilityActions: some View {
        VStack(spacing: 8) {
            if allowsImageEditing {
                imagePicker
            }
            ResolvedMapsButton(place: place, resolvedMapItem: venueResolution.mapItem)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private var imagePicker: some View {
        let titleLineLimit: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 1

        return PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("画像を変更", systemImage: "photo")
                .lineLimit(titleLineLimit)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var imageAccessibilityLabel: String {
        switch imageResolution.source {
        case .user:
            return "\(place.name) の選択された画像"
        case .lookAround:
            return "\(place.name) 周辺の Look Around 画像"
        case .wikimedia:
            return "\(place.name) の Wikimedia Commons 画像"
        case .loading, .placeholder:
            return "\(place.name) の場所を示す画像"
        }
    }

    private var venueCategory: String? {
        guard let category = venueResolution.mapItem?.pointOfInterestCategory else { return nil }

        switch category {
        case .aquarium: return "水族館"
        case .amusementPark: return "テーマパーク"
        case .bakery: return "ベーカリー"
        case .beach: return "ビーチ"
        case .cafe: return "カフェ"
        case .campground: return "キャンプ場"
        case .hotel: return "ホテル"
        case .marina: return "マリーナ"
        case .museum: return "博物館"
        case .nationalPark: return "国立公園"
        case .park: return "公園"
        case .restaurant: return "レストラン"
        case .theater: return "劇場"
        case .zoo: return "動物園"
        default: return nil
        }
    }
}

private struct PlaceIllustration: View {
    let data: Data?
    let externalImage: ExternalPlaceImage?
    let scene: MKLookAroundScene?
    let source: VenueImageSource

    var body: some View {
        switch source {
        case .user:
            userImage
        case .lookAround:
            if let scene {
                LookAroundPreview(initialScene: scene)
            } else {
                placeholder
            }
        case .wikimedia:
            wikimediaImage
        case .loading:
            placeholder.overlay { ProgressView().controlSize(.small) }
        case .placeholder:
            placeholder
        }
    }

    @ViewBuilder
    private var userImage: some View {
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
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private var wikimediaImage: some View {
        if let externalImage {
            AsyncImage(url: externalImage.imageURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    placeholder.overlay { ProgressView().controlSize(.small) }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [.teal.opacity(0.7), .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "mappin.and.ellipse").font(.title).foregroundStyle(.white.opacity(0.9)))
    }
}
