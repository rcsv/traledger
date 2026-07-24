import AppKit
import ImageIO
import MapKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import TripMap

final class TripModelTests: XCTestCase {
    @available(macOS 26.0, *)
    @MainActor
    func testOptionalToManyRelationshipSupportsLightweightMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("OptionalRelationship.store")

        do {
            let schema = Schema(versionedSchema: OptionalRelationshipSchemaV1.self)
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: OptionalRelationshipMigrationPlan.self,
                configurations: configuration
            )
            let root = OptionalRelationshipSchemaV1.Root(
                id: UUID(uuidString: "A11E0000-0000-4000-8000-00000000AA01")!,
                title: "Migration fixture"
            )
            root.children = [
                OptionalRelationshipSchemaV1.Child(
                    id: UUID(uuidString: "A11E0000-0000-4000-8000-00000000AA02")!,
                    sequence: 1
                )
            ]
            container.mainContext.insert(root)
            try container.mainContext.save()
        }

        let schema = Schema(versionedSchema: OptionalRelationshipSchemaV2.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: OptionalRelationshipMigrationPlan.self,
            configurations: configuration
        )
        let roots = try container.mainContext.fetch(
            FetchDescriptor<OptionalRelationshipSchemaV2.Root>()
        )
        let root = try XCTUnwrap(roots.first)
        let child = try XCTUnwrap(root.children?.first)

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(root.title, "Migration fixture")
        XCTAssertEqual(root.id, UUID(uuidString: "A11E0000-0000-4000-8000-00000000AA01"))
        XCTAssertEqual(child.id, UUID(uuidString: "A11E0000-0000-4000-8000-00000000AA02"))
        XCTAssertEqual(child.sequence, 1)
        XCTAssertEqual(child.root?.id, root.id)
    }

    @MainActor
    func testImageNormalizationEnforcesPixelAndEncodedByteCeilings() throws {
        let image = NSImage(size: NSSize(width: 3_200, height: 2_400))
        image.lockFocus()
        NSColor.systemIndigo.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 3_200, height: 2_400))
        NSColor.systemOrange.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 320, y: 240, width: 2_560, height: 1_920),
            xRadius: 320,
            yRadius: 320
        ).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let normalized = try XCTUnwrap(TripImageProcessor.normalizedJPEGData(from: sourceData))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalized as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)

        XCTAssertLessThanOrEqual(max(width, height), TripImageProcessor.maximumPixelDimension)
        XCTAssertLessThanOrEqual(normalized.count, TripImageProcessor.maximumEncodedByteCount)
        XCTAssertEqual(CGImageSourceGetType(source), UTType.jpeg.identifier as CFString)
        XCTAssertNil(TripImageProcessor.normalizedJPEGData(from: Data([0x00, 0x01])))
    }

    func testTripImageStorageInventorySeparatesUserOwnedImageKinds() {
        var trip = OkinawaSample.trip
        trip.coverImageData = Data(repeating: 0x01, count: 10)
        trip.days[0].activities[0].place?.imageData = Data(repeating: 0x02, count: 20)
        trip.days[0].activities[2].place?.imageData = Data(repeating: 0x03, count: 30)
        trip.days[0].activities[0].memoryPhotoData = Data(repeating: 0x04, count: 40)

        let inventory = trip.imageStorageInventory

        XCTAssertEqual(inventory.coverByteCount, 10)
        XCTAssertEqual(inventory.venueUserImageByteCount, 50)
        XCTAssertEqual(inventory.memoryPhotoByteCount, 40)
        XCTAssertEqual(inventory.totalByteCount, 100)
        XCTAssertEqual(inventory.coverCount, 1)
        XCTAssertEqual(inventory.venueUserImageCount, 2)
        XCTAssertEqual(inventory.memoryPhotoCount, 1)
        XCTAssertEqual(inventory.totalImageCount, 4)
        XCTAssertFalse(inventory.exceedsSoftLimit)
    }

    func testTripImageSoftBudgetOnlyConfirmsGrowthAboveTheLimit() {
        let limit = TripImageStorageInventory.softLimitByteCount
        let inventory = TripImageStorageInventory(
            coverByteCount: limit - 10,
            venueUserImageByteCount: 0,
            memoryPhotoByteCount: 0,
            coverCount: 1,
            venueUserImageCount: 0,
            memoryPhotoCount: 0
        )

        let crossing = inventory.proposal(
            replacing: Data(repeating: 0, count: limit - 10),
            with: Data(repeating: 0, count: limit + 1)
        )
        XCTAssertTrue(crossing.requiresConfirmation)
        XCTAssertEqual(crossing.proposedTotalByteCount, limit + 1)

        let alreadyOver = TripImageStorageInventory(
            coverByteCount: limit + 100,
            venueUserImageByteCount: 0,
            memoryPhotoByteCount: 0,
            coverCount: 1,
            venueUserImageCount: 0,
            memoryPhotoCount: 0
        )
        let shrinking = alreadyOver.proposal(
            replacing: Data(repeating: 0, count: limit + 100),
            with: Data(repeating: 0, count: limit)
        )
        XCTAssertFalse(shrinking.requiresConfirmation)
        XCTAssertEqual(shrinking.proposedTotalByteCount, limit)

        let removal = alreadyOver.proposal(
            replacing: Data(repeating: 0, count: limit + 100),
            with: nil
        )
        XCTAssertFalse(removal.requiresConfirmation)
        XCTAssertEqual(removal.proposedTotalByteCount, 0)
    }

    @MainActor
    func testVenueImageResolutionUsesUserImageWithoutAutomaticRequests() async {
        var lookAroundCalls = 0
        var wikimediaCalls = 0

        let result: VenueImageResolution<String> = await VenueImageResolutionCoordinator.resolve(
            hasUserImage: true,
            existingExternalImage: nil,
            resolveLookAround: {
                lookAroundCalls += 1
                return "look around"
            },
            resolveWikimedia: {
                wikimediaCalls += 1
                return self.externalPlaceImage()
            }
        )

        XCTAssertEqual(result.source, .user)
        XCTAssertEqual(lookAroundCalls, 0)
        XCTAssertEqual(wikimediaCalls, 0)
    }

    @MainActor
    func testVenueImageResolutionPrefersLookAroundOverWikimedia() async {
        var lookAroundCalls = 0
        var wikimediaCalls = 0

        let result: VenueImageResolution<String> = await VenueImageResolutionCoordinator.resolve(
            hasUserImage: false,
            existingExternalImage: externalPlaceImage(),
            resolveLookAround: {
                lookAroundCalls += 1
                return "look around"
            },
            resolveWikimedia: {
                wikimediaCalls += 1
                return self.externalPlaceImage()
            }
        )

        XCTAssertEqual(result.source, .lookAround)
        XCTAssertEqual(lookAroundCalls, 1)
        XCTAssertEqual(wikimediaCalls, 0)
    }

    @MainActor
    func testVenueImageResolutionUsesStoredWikimediaImageWhenLookAroundIsUnavailable() async {
        var wikimediaCalls = 0
        let storedImage = externalPlaceImage()

        let result: VenueImageResolution<String> = await VenueImageResolutionCoordinator.resolve(
            hasUserImage: false,
            existingExternalImage: storedImage,
            resolveLookAround: { nil },
            resolveWikimedia: {
                wikimediaCalls += 1
                return nil
            }
        )

        XCTAssertEqual(result.source, .wikimedia)
        XCTAssertEqual(wikimediaCalls, 0)
    }

    @MainActor
    func testVenueImageResolutionFallsBackToWikimediaWhenLookAroundIsUnavailable() async {
        var wikimediaCalls = 0
        let image = externalPlaceImage()

        let result: VenueImageResolution<String> = await VenueImageResolutionCoordinator.resolve(
            hasUserImage: false,
            existingExternalImage: nil,
            resolveLookAround: { nil },
            resolveWikimedia: {
                wikimediaCalls += 1
                return image
            }
        )

        XCTAssertEqual(result.source, .wikimedia)
        XCTAssertEqual(wikimediaCalls, 1)
    }

    @MainActor
    func testVenueImageResolutionUsesPlaceholderWhenAllAutomaticSourcesFail() async {
        let result: VenueImageResolution<String> = await VenueImageResolutionCoordinator.resolve(
            hasUserImage: false,
            existingExternalImage: nil,
            resolveLookAround: { nil },
            resolveWikimedia: { nil }
        )

        XCTAssertEqual(result.source, .placeholder)
    }

    func testVenueImageResolutionRequestIDChangesWhenUserImageIsSet() throws {
        let place = try XCTUnwrap(OkinawaSample.trip.days[1].activities[0].place)
        XCTAssertNotEqual(
            VenueImageResolutionRequestID(placeID: place.id, hasUserImage: false),
            VenueImageResolutionRequestID(placeID: place.id, hasUserImage: true)
        )
    }

    @MainActor
    func testVenueImageResolutionModelDoesNotRestartTheSameRequest() async throws {
        let place = try XCTUnwrap(OkinawaSample.trip.days[0].activities[0].place)
        let image = externalPlaceImage()
        var lookAroundCalls = 0
        var wikimediaCalls = 0
        var storedImages: [ExternalPlaceImage] = []
        let model = VenueImageResolutionModel(dependencies: VenueImageResolutionDependencies(
            resolveLookAround: { _ in
                lookAroundCalls += 1
                return nil
            },
            resolveWikimedia: { _ in
                wikimediaCalls += 1
                return image
            }
        ))

        model.load(place) { storedImages.append($0) }
        model.load(place) { storedImages.append($0) }
        await model.awaitCurrentResolution()

        XCTAssertEqual(model.source, .wikimedia)
        XCTAssertEqual(model.externalImage, image)
        XCTAssertEqual(lookAroundCalls, 1)
        XCTAssertEqual(wikimediaCalls, 1)
        XCTAssertEqual(storedImages, [image])
    }

    @MainActor
    func testVenueImageResolutionModelSkipsAutomaticRequestsForUserImage() async throws {
        var place = try XCTUnwrap(OkinawaSample.trip.days[0].activities[0].place)
        place.imageData = Data([0x01])
        var lookAroundCalls = 0
        var wikimediaCalls = 0
        let model = VenueImageResolutionModel(dependencies: VenueImageResolutionDependencies(
            resolveLookAround: { _ in
                lookAroundCalls += 1
                return nil
            },
            resolveWikimedia: { _ in
                wikimediaCalls += 1
                return nil
            }
        ))

        model.load(place) { _ in
            XCTFail("User images must not persist an automatic image.")
        }
        await model.awaitCurrentResolution()

        XCTAssertEqual(model.source, .user)
        XCTAssertEqual(lookAroundCalls, 0)
        XCTAssertEqual(wikimediaCalls, 0)
    }

    @MainActor
    func testVenueImageResolutionModelRejectsAStaleResultAfterPlaceChanges() async throws {
        let firstPlace = try XCTUnwrap(OkinawaSample.trip.days[0].activities[0].place)
        let secondPlace = try XCTUnwrap(OkinawaSample.trip.days[1].activities[0].place)
        let staleImage = externalPlaceImage(providerImageID: "stale")
        let currentImage = externalPlaceImage(providerImageID: "current")
        var storedImages: [ExternalPlaceImage] = []
        let model = VenueImageResolutionModel(dependencies: VenueImageResolutionDependencies(
            resolveLookAround: { _ in nil },
            resolveWikimedia: { place in
                if place.id == firstPlace.id {
                    try? await Task.sleep(for: .milliseconds(100))
                    return staleImage
                }
                return currentImage
            }
        ))

        model.load(firstPlace) { storedImages.append($0) }
        model.load(secondPlace) { storedImages.append($0) }
        await model.awaitCurrentResolution()
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.source, .wikimedia)
        XCTAssertEqual(model.externalImage, currentImage)
        XCTAssertEqual(storedImages, [currentImage])
    }

    #if TRIPMAP_LIVE_VENUE_IMAGE_QA
    @MainActor
    func testLiveShibuyaCrossingResolvesLookAroundBeforeWikimedia() async throws {
        let place = livePlace(
            name: "渋谷スクランブル交差点",
            address: "東京都渋谷区道玄坂2丁目",
            latitude: 35.6595,
            longitude: 139.7005
        )
        var wikimediaCalls = 0
        let model = VenueImageResolutionModel(dependencies: VenueImageResolutionDependencies(
            resolveLookAround: VenueImageResolutionDependencies.live.resolveLookAround,
            resolveWikimedia: { place in
                wikimediaCalls += 1
                return await VenueImageResolutionDependencies.live.resolveWikimedia(place)
            }
        ))

        model.load(place) { _ in
            XCTFail("Look Around success must not persist a Wikimedia image.")
        }
        await model.awaitCurrentResolution()

        XCTAssertEqual(model.source, .lookAround)
        XCTAssertNotNil(model.lookAroundScene)
        XCTAssertNil(model.externalImage)
        XCTAssertEqual(wikimediaCalls, 0)
    }

    @MainActor
    func testLiveNahaAirportFallsBackToWikimedia() async throws {
        let place = livePlace(
            name: "那覇空港",
            address: "沖縄県那覇市鏡水150",
            latitude: 26.2064,
            longitude: 127.6460
        )
        var storedImages: [ExternalPlaceImage] = []
        let model = VenueImageResolutionModel()

        model.load(place) { storedImages.append($0) }
        await model.awaitCurrentResolution()

        XCTAssertEqual(model.source, .wikimedia)
        XCTAssertNil(model.lookAroundScene)
        XCTAssertNotNil(model.externalImage)
        XCTAssertEqual(storedImages, model.externalImage.map { [$0] } ?? [])
    }
    #endif

    func testOkinawaSamplePreservesSequenceFirstOrdering() {
        let trip = OkinawaSample.trip

        XCTAssertEqual(trip.title, "沖縄・瀬底 4日間")
        XCTAssertEqual(trip.days.map(\.sequence), [1, 2, 3, 4])
        XCTAssertTrue(trip.days.allSatisfy { day in
            day.activities.map(\.sequence) == Array(1...day.activities.count)
        })
    }

    func testDayTwoStartsWithChuraumiAndEveryActivityHasAtMostOnePlace() {
        let dayTwo = OkinawaSample.trip.days[1]

        XCTAssertEqual(dayTwo.title, "海洋博公園と備瀬")
        XCTAssertEqual(dayTwo.activities.first?.place?.name, "沖縄美ら海水族館")
        XCTAssertEqual(dayTwo.activities.compactMap(\.place).count, dayTwo.activities.count)
    }

    func testPlaceSnapshotKeepsExchangeFriendlyMapFields() throws {
        let place = try XCTUnwrap(OkinawaSample.trip.days[1].activities[0].place)

        XCTAssertFalse(place.name.isEmpty)
        XCTAssertFalse(place.address.isEmpty)
        XCTAssertEqual(place.coordinate.latitude, place.latitude)
        XCTAssertEqual(place.coordinate.longitude, place.longitude)
    }

    @MainActor
    func testPlaceResolverPrefersTheMatchingAppleMapsPOI() throws {
        let place = try XCTUnwrap(OkinawaSample.trip.days[1].activities[0].place)
        let nearbyUnrelated = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: place.latitude + 0.0001,
            longitude: place.longitude
        )))
        nearbyUnrelated.name = "海洋博公園"
        let matchingPOI = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: place.latitude + 0.0003,
            longitude: place.longitude
        )))
        matchingPOI.name = "沖縄美ら海水族館"

        let match = PlaceMapItemResolver.bestMatch(in: [nearbyUnrelated, matchingPOI], for: place)

        XCTAssertTrue(match === matchingPOI)
    }

    @MainActor
    func testPlaceResolverRejectsAnUnrelatedDistantResult() throws {
        let place = try XCTUnwrap(OkinawaSample.trip.days[1].activities[0].place)
        let unrelated = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: place.latitude + 0.2,
            longitude: place.longitude
        )))
        unrelated.name = "別の観光施設"

        XCTAssertNil(PlaceMapItemResolver.bestMatch(in: [unrelated], for: place))
    }

    func testEmptyTripIsReportedWithoutCreatingASelection() {
        let trip = PrototypeEdgeCases.emptyTrip
        let interaction = TripInteractionState(trip: trip)

        XCTAssertEqual(trip.validationIssues, [.noDays])
        XCTAssertNil(interaction.selectedDayID)
        XCTAssertNil(interaction.selectedActivityID)
        XCTAssertNil(interaction.cameraRequest)
    }

    func testDaySelectionUsesFirstSequenceAndRequestsWholeDayCamera() {
        let trip = OkinawaSample.trip
        let dayOne = trip.orderedDays[0]
        var interaction = TripInteractionState(trip: trip)

        interaction.selectDay(dayOne.id, in: trip)

        XCTAssertEqual(interaction.selectedDayID, dayOne.id)
        XCTAssertEqual(interaction.selectedActivityID, dayOne.orderedActivities[0].id)
        XCTAssertEqual(interaction.cameraRequest?.target, .day(dayOne.id))
    }

    func testListSelectionRequestsFocusButMapSelectionPreservesCamera() {
        let trip = OkinawaSample.trip
        let dayTwo = trip.orderedDays[1]
        var interaction = TripInteractionState(trip: trip)
        let second = dayTwo.orderedActivities[1]
        let third = dayTwo.orderedActivities[2]

        interaction.selectDay(dayTwo.id, in: trip)
        interaction.selectActivity(second.id, source: .list, in: trip)
        XCTAssertEqual(interaction.cameraRequest?.target, .activity(second.id))
        let listCameraRequest = interaction.cameraRequest

        interaction.selectActivity(third.id, source: .map, in: trip)
        XCTAssertEqual(interaction.selectedActivityID, third.id)
        XCTAssertEqual(interaction.cameraRequest, listCameraRequest)
    }

    func testPlaceLessActivitySelectionPreservesCamera() {
        let trip = OkinawaSample.trip
        let dayOne = trip.orderedDays[0]
        let placeLessActivity = dayOne.orderedActivities[1]
        var interaction = TripInteractionState(trip: trip)
        interaction.selectDay(dayOne.id, in: trip)
        let wholeDayCameraRequest = interaction.cameraRequest

        interaction.selectActivity(placeLessActivity.id, source: .list, in: trip)

        XCTAssertEqual(interaction.selectedActivityID, placeLessActivity.id)
        XCTAssertEqual(interaction.cameraRequest, wholeDayCameraRequest)
    }

    func testFocusingActivityAfterVenueIsSetRequestsItsCamera() throws {
        var trip = OkinawaSample.trip
        let day = trip.orderedDays[0]
        let activity = day.orderedActivities[1]
        var interaction = TripInteractionState(trip: trip)

        interaction.selectDay(day.id, in: trip)
        interaction.selectActivity(activity.id, source: .list, in: trip)
        let cameraBeforeSettingVenue = interaction.cameraRequest

        trip = try TripPlanEditor.setPlace(
            in: trip,
            for: activity.id,
            place: PlaceSnapshot(
                id: UUID(),
                name: "瀬底ビーチ",
                address: "沖縄県国頭郡本部町",
                latitude: 26.653,
                longitude: 127.861,
                mapKitIdentifier: "mapkit-place"
            )
        )
        interaction.focusActivity(activity.id, in: trip)

        XCTAssertEqual(interaction.selectedActivityID, activity.id)
        XCTAssertEqual(interaction.cameraRequest?.target, .activity(activity.id))
        XCTAssertNotEqual(interaction.cameraRequest, cameraBeforeSettingVenue)
    }

    func testPlacedActivitiesBecomePinsInSequenceOrder() {
        let day = OkinawaSample.trip.orderedDays[0]

        let pinActivities = ActivityMap.activitiesWithPlaces(in: day)

        XCTAssertEqual(pinActivities.map(\.id), day.orderedActivities.filter { $0.place != nil }.map(\.id))
        XCTAssertEqual(pinActivities.map(\.sequence), [1, 3])
    }

    func testReplacingAndClearingVenueKeepsCameraBehaviorConsistent() throws {
        var trip = OkinawaSample.trip
        let day = trip.orderedDays[1]
        let activity = day.orderedActivities[0]
        var interaction = TripInteractionState(trip: trip)

        interaction.selectDay(day.id, in: trip)
        interaction.selectActivity(activity.id, source: .list, in: trip)
        let cameraBeforeReplacement = interaction.cameraRequest

        trip = try TripPlanEditor.setPlace(
            in: trip,
            for: activity.id,
            place: PlaceSnapshot(
                id: UUID(),
                name: "新しい会場",
                address: "沖縄県国頭郡本部町",
                latitude: 26.701,
                longitude: 127.878,
                mapKitIdentifier: "replacement"
            )
        )
        interaction.focusActivity(activity.id, in: trip)
        let cameraAfterReplacement = interaction.cameraRequest

        XCTAssertEqual(cameraAfterReplacement?.target, .activity(activity.id))
        XCTAssertNotEqual(cameraAfterReplacement, cameraBeforeReplacement)

        trip = try TripPlanEditor.setPlace(in: trip, for: activity.id, place: nil)
        interaction.focusActivity(activity.id, in: trip)

        XCTAssertEqual(interaction.selectedActivityID, activity.id)
        XCTAssertEqual(interaction.cameraRequest, cameraAfterReplacement)
    }

    func testReconcileSelectsNextThenPreviousAfterDeletion() {
        var trip = OkinawaSample.trip
        let dayTwo = trip.orderedDays[1]
        let second = dayTwo.orderedActivities[1]
        let third = dayTwo.orderedActivities[2]
        var interaction = TripInteractionState(trip: trip)
        interaction.selectDay(dayTwo.id, in: trip)
        interaction.selectActivity(second.id, source: .list, in: trip)

        trip.days[1].activities.removeAll(where: { $0.id == second.id })
        interaction.reconcile(with: trip)
        XCTAssertEqual(interaction.selectedActivityID, third.id)
        XCTAssertEqual(interaction.cameraRequest?.target, .activity(third.id))

        trip.days[1].activities.removeAll(where: { $0.id == third.id })
        interaction.reconcile(with: trip)
        XCTAssertEqual(interaction.selectedActivityID, dayTwo.orderedActivities[0].id)
        XCTAssertEqual(interaction.cameraRequest?.target, .activity(dayTwo.orderedActivities[0].id))
    }

    func testReconcilePreservesCameraWhenDeletionSelectsPlaceLessActivity() {
        var trip = OkinawaSample.trip
        let dayOne = trip.orderedDays[0]
        let first = dayOne.orderedActivities[0]
        let placeLessSecond = dayOne.orderedActivities[1]
        var interaction = TripInteractionState(trip: trip)
        interaction.selectDay(dayOne.id, in: trip)
        interaction.selectActivity(first.id, source: .list, in: trip)
        let focusedCameraRequest = interaction.cameraRequest

        trip.days[0].activities.removeAll(where: { $0.id == first.id })
        interaction.reconcile(with: trip)

        XCTAssertEqual(interaction.selectedActivityID, placeLessSecond.id)
        XCTAssertEqual(interaction.cameraRequest, focusedCameraRequest)
    }

    func testValidationFindsSequenceAndCoordinateProblems() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = Activity(
            id: UUID(), sequence: 2, title: "Invalid", startTime: nil, note: nil,
            place: PlaceSnapshot(
                id: UUID(), name: "Invalid", address: "", latitude: 100, longitude: 200, mapKitIdentifier: nil
            )
        )
        let day = Day(id: UUID(), sequence: 2, date: referenceDate, title: "Invalid", activities: [activity])
        let trip = Trip(
            id: UUID(), title: "Invalid", dateRange: referenceDate...referenceDate, days: [day]
        )

        XCTAssertTrue(trip.validationIssues.contains(.invalidDaySequence))
        XCTAssertTrue(trip.validationIssues.contains(.invalidActivitySequence(day.id)))
        XCTAssertTrue(trip.validationIssues.contains(.invalidCoordinate(activity.id)))
    }

    func testDoctorReportsAnEmptyItineraryWithoutFlaggingEveryDay() {
        let trip = PrototypeEdgeCases.emptyDayTrip

        let report = TripDoctor.inspect(trip)

        XCTAssertEqual(report.issues.map(\.code), [.emptyItinerary, .participantsNotAssigned])
        XCTAssertFalse(report.issues.contains(where: { $0.code == .emptyDay }))
        XCTAssertEqual(report.warningCount, 0)
        XCTAssertEqual(report.infoCount, 2)
    }

    func testDoctorFlagsOnlyAnEmptyDayWhenOtherDaysHaveActivities() {
        var trip = OkinawaSample.trip
        let emptyDayID = trip.days[1].id
        trip.days[1].activities = []

        let report = TripDoctor.inspect(trip, participantNames: ["John"])

        let issue = report.issues.first(where: { $0.code == .emptyDay })
        XCTAssertEqual(issue?.target, .day(emptyDayID))
        XCTAssertFalse(report.issues.contains(where: { $0.code == .emptyItinerary }))
    }

    func testDoctorUsesSevenActivitiesAsTheOverloadedDayThreshold() {
        var trip = OkinawaSample.trip
        let dayID = trip.days[0].id
        trip.days[0].activities = (1...7).map {
            Activity(id: UUID(), sequence: $0, title: "予定\($0)", startTime: nil, note: nil, place: nil)
        }

        let report = TripDoctor.inspect(trip, participantNames: ["John"])

        let issue = report.issues.first(where: { $0.code == .overloadedDay })
        XCTAssertEqual(issue?.severity, .warning)
        XCTAssertEqual(issue?.target, .day(dayID))
    }

    func testDoctorTargetsTheActivityWhoseTimeIsOutOfOrder() throws {
        var trip = OkinawaSample.trip
        let firstStartTime = try XCTUnwrap(trip.days[0].activities[0].startTime)
        let activityID = trip.days[0].activities[1].id
        let dayID = trip.days[0].id
        trip.days[0].activities[1].startTime = firstStartTime.addingTimeInterval(-3_600)

        let report = TripDoctor.inspect(trip, participantNames: ["John"])

        let issue = try XCTUnwrap(report.issues.first(where: { $0.code == .activityTimeOutOfOrder }))
        XCTAssertEqual(issue.target, .activity(activityID, dayID: dayID))
        XCTAssertEqual(report.issues(forActivity: activityID), [issue])
    }

    func testDoctorTargetsEveryActivityWithTheSameStartTime() throws {
        var trip = OkinawaSample.trip
        let first = trip.days[0].activities[0]
        let secondID = trip.days[0].activities[1].id
        trip.days[0].activities[1].startTime = try XCTUnwrap(first.startTime)

        let report = TripDoctor.inspect(trip, participantNames: ["John"])
        let duplicateIssues = report.issues.filter { $0.code == .duplicateActivityStartTime }

        XCTAssertEqual(Set(duplicateIssues.compactMap(\.target.activityID)), Set([first.id, secondID]))
        XCTAssertFalse(report.issues.contains(where: { $0.code == .activityTimeOutOfOrder }))
    }

    func testDoctorNormalizesParticipantNamesBeforeFindingDuplicates() {
        let report = TripDoctor.inspect(
            OkinawaSample.trip,
            participantNames: [" Aiko ", "aiko"]
        )

        XCTAssertEqual(report.participantIssues.map(\.code), [.duplicateParticipantNames])
        XCTAssertEqual(report.participantIssues.first?.severity, .warning)
    }

    func testDoctorChecksForRestaurantsAfterCategoriesAreUsed() {
        var trip = OkinawaSample.trip
        let day = trip.days[0]
        trip.days[0].activities[0].category = .transport
        trip.days[0].activities[0].durationMinutes = 30

        var report = TripDoctor.inspect(trip, participantNames: ["John"])
        XCTAssertTrue(report.issues.contains(where: {
            $0.code == .noRestaurant && $0.target == .day(day.id)
        }))

        trip.days[0].activities[1].category = .restaurant
        trip.days[0].activities[1].durationMinutes = 60
        report = TripDoctor.inspect(trip, participantNames: ["John"])
        XCTAssertFalse(report.issues.contains(where: {
            $0.code == .noRestaurant && $0.target == .day(day.id)
        }))
    }

    func testActivityCategoryDurationSuggestionsUseTravelPlanningDefaults() {
        XCTAssertEqual(ActivityCategory.transport.suggestedDurationMinutes, 30)
        XCTAssertEqual(ActivityCategory.restaurant.suggestedDurationMinutes, 60)
        XCTAssertEqual(ActivityCategory.accommodation.suggestedDurationMinutes, 30)
        XCTAssertEqual(ActivityCategory.sightseeing.suggestedDurationMinutes, 90)
        XCTAssertEqual(ActivityCategory.activity.suggestedDurationMinutes, 120)
        XCTAssertEqual(ActivityCategory.shopping.suggestedDurationMinutes, 60)
        XCTAssertNil(ActivityCategory.other.suggestedDurationMinutes)
    }

    func testDoctorTargetsCategorizedActivityMissingDuration() {
        var trip = OkinawaSample.trip
        let day = trip.days[1]
        let activity = trip.days[1].activities[0]
        trip.days[1].activities[0].category = .sightseeing

        let report = TripDoctor.inspect(trip, participantNames: ["John"])

        XCTAssertTrue(report.issues.contains(where: {
            $0.code == .missingActivityDuration && $0.target == .activity(activity.id, dayID: day.id)
        }))
    }

    func testDoctorChecksCompleteMapKitTravelEstimatesPerDay() {
        let trip = OkinawaSample.trip
        let day = trip.days[1]
        let now = Date()
        let idleLegs = TravelLegProjection.activeLegs(for: trip, now: now)
        let dayLegs = idleLegs.filter { $0.dayID == day.id }
        let calculations = Dictionary(
            uniqueKeysWithValues: zip(dayLegs, [100, 85]).map { leg, minutes in
                (
                    leg.routingFingerprint,
                    TravelLegCalculationState.loaded(
                        TravelLegEstimate(durationMinutes: minutes, calculatedAt: now)
                    )
                )
            }
        )
        let loadedLegs = TravelLegProjection.activeLegs(
            for: trip,
            calculations: calculations,
            now: now
        )

        var report = TripDoctor.inspect(
            trip,
            participantNames: ["John"],
            travelLegs: loadedLegs
        )
        XCTAssertTrue(report.issues.contains(where: {
            $0.code == .highTravelTime && $0.target == .day(day.id)
        }))

        report = TripDoctor.inspect(
            trip,
            participantNames: ["John"],
            travelLegs: loadedLegs.filter { $0.id != dayLegs.last?.id }
        )
        XCTAssertFalse(report.issues.contains(where: { $0.code == .highTravelTime }))
    }

    func testTravelLegProjectionUsesOnlyAdjacentActivitiesWithTwoVenues() {
        var trip = OkinawaSample.trip
        let dayIndex = 1
        let activities = trip.days[dayIndex].orderedActivities
        trip.days[dayIndex].activities[1].place = nil

        let legs = TravelLegProjection.activeLegs(for: trip)

        XCTAssertFalse(legs.contains(where: {
            $0.id == TravelLegID(
                fromActivityID: activities[0].id,
                toActivityID: activities[2].id
            )
        }))
        XCTAssertTrue(legs.allSatisfy {
            $0.id.fromActivityID != activities[1].id
                && $0.id.toActivityID != activities[1].id
        })
    }

    func testTravelLegIdentityIsDirectionalAndSurvivesUnrelatedActivityEdits() {
        var trip = OkinawaSample.trip
        let originalLegs = TravelLegProjection.activeLegs(for: trip)
        let original = originalLegs[0]

        trip.days[0].activities[0].title = "Edited title"
        trip.days[0].activities[0].note = "Edited note"
        let edited = TravelLegProjection.activeLegs(for: trip)[0]

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.routingFingerprint, original.routingFingerprint)
        XCTAssertNotEqual(
            original.id,
            TravelLegID(
                fromActivityID: original.id.toActivityID,
                toActivityID: original.id.fromActivityID
            )
        )
    }

    func testTravelLegFingerprintChangesForVenueAndTransportEdits() {
        var trip = OkinawaSample.trip
        let initial = TravelLegProjection.activeLegs(for: trip)[0]
        let dayIndex = trip.days.firstIndex(where: { day in
            day.activities.contains(where: { $0.id == initial.id.fromActivityID })
        })!
        let activityIndex = trip.days[dayIndex].activities.firstIndex(where: {
            $0.id == initial.id.fromActivityID
        })!

        trip.days[dayIndex].activities[activityIndex].place?.latitude += 0.01
        let venueEdited = TravelLegProjection.activeLegs(for: trip).first(where: {
            $0.id == initial.id
        })!
        XCTAssertNotEqual(venueEdited.routingFingerprint, initial.routingFingerprint)

        let preference = TravelLegPreference(
            legID: venueEdited.id,
            transportType: .walking,
            manualDurationMinutes: nil,
            note: nil
        )
        let transportEdited = TravelLegProjection.activeLegs(
            for: trip,
            preferences: [preference.legID: preference]
        )[0]
        XCTAssertNotEqual(transportEdited.routingFingerprint, venueEdited.routingFingerprint)
    }

    func testTravelLegManualDurationWinsAndLoadedEstimateBecomesStale() throws {
        let trip = OkinawaSample.trip
        let now = Date()
        let idleLeg = try XCTUnwrap(TravelLegProjection.activeLegs(for: trip, now: now).first)
        let estimate = TravelLegEstimate(durationMinutes: 30, calculatedAt: now)
        let preference = TravelLegPreference(
            legID: idleLeg.id,
            transportType: .automobile,
            manualDurationMinutes: 45,
            note: "Meet at the north exit"
        )

        let manualLeg = try XCTUnwrap(
            TravelLegProjection.activeLegs(
                for: trip,
                preferences: [preference.legID: preference],
                calculations: [idleLeg.routingFingerprint: .loaded(estimate)],
                now: now
            ).first
        )
        XCTAssertEqual(manualLeg.effectiveDuration?.minutes, 45)
        XCTAssertEqual(manualLeg.effectiveDuration?.source, .manual)

        let staleLeg = try XCTUnwrap(
            TravelLegProjection.activeLegs(
                for: trip,
                calculations: [idleLeg.routingFingerprint: .loaded(estimate)],
                now: now.addingTimeInterval(TravelLegProjection.estimateFreshness)
            ).first
        )
        XCTAssertEqual(staleLeg.calculationState, .stale(estimate))
        XCTAssertEqual(staleLeg.effectiveDuration?.minutes, 30)
        XCTAssertEqual(staleLeg.effectiveDuration?.source, .staleMapKit)
    }

    func testTravelLegPreferenceEditingNormalizesAndClearsDefaultIntent() throws {
        let trip = OkinawaSample.trip
        let legID = try XCTUnwrap(TravelLegProjection.activeLegs(for: trip).first?.id)

        let edited = try TripPlanEditor.setTravelLegPreference(
            in: trip,
            legID: legID,
            transportType: .walking,
            manualDurationMinutes: 18,
            note: "  北口で集合  "
        )
        XCTAssertEqual(
            edited.travelLegPreferences,
            [
                TravelLegPreference(
                    legID: legID,
                    transportType: .walking,
                    manualDurationMinutes: 18,
                    note: "北口で集合"
                )
            ]
        )

        let cleared = try TripPlanEditor.setTravelLegPreference(
            in: edited,
            legID: legID,
            transportType: .automobile,
            manualDurationMinutes: nil,
            note: "  "
        )
        XCTAssertTrue(cleared.travelLegPreferences.isEmpty)
    }

    func testTravelLegPreferenceRejectsCrossDayAndInvalidDuration() throws {
        let trip = OkinawaSample.trip
        let crossDayID = TravelLegID(
            fromActivityID: trip.orderedDays[0].orderedActivities[0].id,
            toActivityID: trip.orderedDays[1].orderedActivities[0].id
        )
        XCTAssertThrowsError(
            try TripPlanEditor.setTravelLegPreference(
                in: trip,
                legID: crossDayID,
                transportType: .transit,
                manualDurationMinutes: nil,
                note: nil
            )
        ) {
            XCTAssertEqual($0 as? TripPlanEditingError, .invalidTravelLegReference)
        }

        let legID = try XCTUnwrap(TravelLegProjection.activeLegs(for: trip).first?.id)
        XCTAssertThrowsError(
            try TripPlanEditor.setTravelLegPreference(
                in: trip,
                legID: legID,
                transportType: .other,
                manualDurationMinutes: 1_440,
                note: nil
            )
        ) {
            XCTAssertEqual($0 as? TripPlanEditingError, .invalidTravelLegDuration)
        }
    }

    func testDeletingActivityDeletesReferencingTravelLegPreferences() throws {
        let trip = OkinawaSample.trip
        let legID = try XCTUnwrap(TravelLegProjection.activeLegs(for: trip).first?.id)
        let edited = try TripPlanEditor.setTravelLegPreference(
            in: trip,
            legID: legID,
            transportType: .transit,
            manualDurationMinutes: nil,
            note: nil
        )

        let deleted = try TripPlanEditor.deleteActivity(
            in: edited,
            activityID: legID.toActivityID
        )

        XCTAssertTrue(deleted.travelLegPreferences.isEmpty)
    }

    func testAdversarialFixturesCoverEmptyOverlapAndDensity() {
        XCTAssertTrue(PrototypeEdgeCases.emptyDayTrip.days[0].activities.isEmpty)
        XCTAssertTrue(PrototypeEdgeCases.noPlaceTrip.days[0].activities.allSatisfy { $0.place == nil })

        let overlappingCoordinates = PrototypeEdgeCases.overlappingPlacesTrip.days[0].activities
            .compactMap(\.place?.coordinate)
        XCTAssertEqual(Set(overlappingCoordinates.map(\.latitude)).count, 1)
        XCTAssertEqual(Set(overlappingCoordinates.map(\.longitude)).count, 1)
        XCTAssertEqual(PrototypeEdgeCases.denseTrip.days[0].activities.count, 30)
        XCTAssertGreaterThan(PrototypeEdgeCases.longContentTrip.title.count, 50)
        XCTAssertGreaterThan(PrototypeEdgeCases.longContentTrip.days[0].activities[0].note?.count ?? 0, 100)
    }

    func testDateLineRegionUsesTheShortLongitudeArc() throws {
        let day = try XCTUnwrap(PrototypeEdgeCases.dateLineTrip.days.first)
        let region = try XCTUnwrap(ActivityMap.region(for: day))

        XCTAssertLessThan(region.span.longitudeDelta, 5)
        XCTAssertTrue(abs(region.center.longitude) > 170)
    }

    func testLocalDateAndTimeRejectInvalidValues() {
        XCTAssertNil(LocalDate(year: 2026, month: 2, day: 29))
        XCTAssertNil(LocalDate(code: 20261301))
        XCTAssertNil(LocalTime(hour: 24, minute: 0))
        XCTAssertNil(LocalTime(minuteOfDay: 1_440))
        XCTAssertEqual(LocalDate(year: 2028, month: 2, day: 29)?.code, 20280229)
        XCTAssertEqual(LocalTime(hour: 9, minute: 30)?.minuteOfDay, 570)
    }

    func testTripCreationGeneratesInclusiveContiguousDays() throws {
        let start = try XCTUnwrap(LocalDate(year: 2026, month: 10, day: 9))
        let end = try XCTUnwrap(LocalDate(year: 2026, month: 10, day: 12))
        let trip = try TripFactory.makeTrip(
            from: TripCreationRequest(
                title: "  沖縄旅行  ",
                startDate: start,
                endDate: end,
                timeZoneIdentifier: "Asia/Tokyo"
            )
        )
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))

        XCTAssertEqual(trip.title, "沖縄旅行")
        XCTAssertEqual(trip.days.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(trip.days.map { LocalDate(date: $0.date, timeZone: timeZone).code }, [
            20261009, 20261010, 20261011, 20261012
        ])
        XCTAssertTrue(trip.days.allSatisfy { $0.activities.isEmpty })
        XCTAssertTrue(trip.validationIssues.isEmpty)
    }

    func testTripCreationRejectsInvalidDrafts() throws {
        let start = try XCTUnwrap(LocalDate(year: 2026, month: 10, day: 12))
        let end = try XCTUnwrap(LocalDate(year: 2026, month: 10, day: 9))

        XCTAssertThrowsError(
            try TripFactory.makeTrip(
                from: TripCreationRequest(
                    title: "   ", startDate: start, endDate: start, timeZoneIdentifier: "Asia/Tokyo"
                )
            )
        ) { error in
            XCTAssertEqual(error as? TripCreationError, .blankTitle)
        }
        XCTAssertThrowsError(
            try TripFactory.makeTrip(
                from: TripCreationRequest(
                    title: "逆転", startDate: start, endDate: end, timeZoneIdentifier: "Asia/Tokyo"
                )
            )
        ) { error in
            XCTAssertEqual(error as? TripCreationError, .endBeforeStart)
        }
    }

    func testTripCreationKeepsCalendarDaysAcrossDSTBoundary() throws {
        let start = try XCTUnwrap(LocalDate(year: 2026, month: 3, day: 7))
        let end = try XCTUnwrap(LocalDate(year: 2026, month: 3, day: 9))
        let trip = try TripFactory.makeTrip(
            from: TripCreationRequest(
                title: "New York",
                startDate: start,
                endDate: end,
                timeZoneIdentifier: "America/New_York"
            )
        )
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))

        XCTAssertEqual(trip.days.map { LocalDate(date: $0.date, timeZone: timeZone).code }, [
            20260307, 20260308, 20260309
        ])
    }

    func testReplicatingDayPlansCreatesIndependentActivityAndPlaceSnapshots() throws {
        let trip = OkinawaSample.trip
        let source = trip.orderedDays[1]
        let target = trip.orderedDays[2]

        let updated = try TripPlanEditor.replicateDayActivities(
            in: trip,
            from: source.id,
            to: [target.id]
        )
        let updatedTarget = try XCTUnwrap(updated.days.first(where: { $0.id == target.id }))
        let replicas = Array(updatedTarget.orderedActivities.suffix(source.activities.count))

        XCTAssertEqual(updatedTarget.activities.count, target.activities.count + source.activities.count)
        XCTAssertEqual(replicas.map(\.title), source.orderedActivities.map(\.title))
        XCTAssertEqual(replicas.map(\.sequence), Array((target.activities.count + 1)...updatedTarget.activities.count))
        XCTAssertNotEqual(replicas.first?.id, source.orderedActivities.first?.id)
        XCTAssertNotEqual(replicas.first?.place?.id, source.orderedActivities.first?.place?.id)
    }

    func testAppendingActivityUsesNextSequenceAndTrimsTitle() throws {
        let trip = OkinawaSample.trip
        let day = trip.orderedDays[0]

        let updated = try TripPlanEditor.appendActivity(
            in: trip,
            to: day.id,
            title: "  夕食  ",
            startTime: nil
        )

        let added = try XCTUnwrap(updated.days.first(where: { $0.id == day.id })?.orderedActivities.last)
        XCTAssertEqual(added.title, "夕食")
        XCTAssertEqual(added.sequence, (day.activities.map(\.sequence).max() ?? 0) + 1)
        XCTAssertNil(added.place)
    }

    @MainActor
    func testAppendingTimedActivityUsesTheSelectedDayDate() throws {
        let trip = OkinawaSample.trip
        let day = trip.orderedDays[2]
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = 2026
        components.month = 7
        components.day = 20
        components.hour = 18
        components.minute = 45
        let pickerValue = try XCTUnwrap(components.date)

        let updated = try TripPlanEditor.appendActivity(
            in: trip,
            to: day.id,
            title: "夕食",
            startTime: pickerValue
        )

        let added = try XCTUnwrap(updated.days.first(where: { $0.id == day.id })?.orderedActivities.last)
        let addedTime = try XCTUnwrap(added.startTime)
        XCTAssertEqual(LocalDate(date: addedTime, timeZone: timeZone), LocalDate(date: day.date, timeZone: timeZone))
        XCTAssertEqual(LocalTime(date: addedTime, timeZone: timeZone).minuteOfDay, 18 * 60 + 45)
        XCTAssertNoThrow(try StoredTrip(validatingSnapshot: updated))
    }

    func testAppendingActivityRejectsBlankTitle() {
        let trip = OkinawaSample.trip
        XCTAssertThrowsError(
            try TripPlanEditor.appendActivity(
                in: trip,
                to: trip.orderedDays[0].id,
                title: "   ",
                startTime: nil
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .blankActivityTitle)
        }
    }

    func testUpdatingActivityNormalizesTimeAndTrimsFields() throws {
        let trip = OkinawaSample.trip
        let day = trip.orderedDays[1]
        let activity = try XCTUnwrap(day.orderedActivities.first)
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))
        let localTime = try XCTUnwrap(LocalTime(hour: 18, minute: 45))
        let inputDate = try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 20))
        let input = try XCTUnwrap(localTime.date(on: inputDate, in: timeZone))

        let updated = try TripPlanEditor.updateActivity(
            in: trip,
            activityID: activity.id,
            title: "  夕食  ",
            startTime: input,
            category: .restaurant,
            durationMinutes: 90,
            note: "  海が見える席を予約  ",
            place: activity.place
        )
        let edited = try XCTUnwrap(updated.days.first(where: { $0.id == day.id })?.activities.first(where: { $0.id == activity.id }))

        XCTAssertEqual(edited.title, "夕食")
        XCTAssertEqual(edited.category, .restaurant)
        XCTAssertEqual(edited.durationMinutes, 90)
        XCTAssertEqual(edited.note, "海が見える席を予約")
        let editedStartTime = try XCTUnwrap(edited.startTime)
        XCTAssertEqual(LocalDate(date: editedStartTime, timeZone: timeZone), LocalDate(date: day.date, timeZone: timeZone))
        XCTAssertEqual(LocalTime(date: editedStartTime, timeZone: timeZone).minuteOfDay, 18 * 60 + 45)
    }

    func testSettingAndClearingActivityPlacePreservesActivityIdentity() throws {
        let trip = OkinawaSample.trip
        let activity = trip.orderedDays[0].orderedActivities[1]
        let place = PlaceSnapshot(
            id: UUID(), name: "瀬底ビーチ", address: "沖縄県国頭郡本部町", latitude: 26.653, longitude: 127.861,
            mapKitIdentifier: "mapkit-place"
        )

        let withPlace = try TripPlanEditor.setPlace(in: trip, for: activity.id, place: place)
        XCTAssertEqual(withPlace.days[0].activities[1].id, activity.id)
        XCTAssertEqual(withPlace.days[0].activities[1].place, place)

        let withoutPlace = try TripPlanEditor.setPlace(in: withPlace, for: activity.id, place: nil)
        XCTAssertNil(withoutPlace.days[0].activities[1].place)
    }

    func testActivityProgressIsExplicitIdempotentAndReversible() throws {
        let trip = OkinawaSample.trip
        let activity = trip.orderedDays[0].orderedActivities[0]
        let completionDate = Date(timeIntervalSince1970: 1_800_000_000)

        let completed = try TripPlanEditor.setActivityProgress(
            in: trip,
            activityID: activity.id,
            progress: .completed,
            at: completionDate
        )
        let completedActivity = try XCTUnwrap(
            completed.orderedDays[0].orderedActivities.first(where: { $0.id == activity.id })
        )
        XCTAssertEqual(completedActivity.progress, .completed)
        XCTAssertEqual(completedActivity.progressUpdatedAt, completionDate)

        let repeated = try TripPlanEditor.setActivityProgress(
            in: completed,
            activityID: activity.id,
            progress: .completed,
            at: completionDate.addingTimeInterval(60)
        )
        XCTAssertEqual(
            repeated.orderedDays[0].orderedActivities.first(where: { $0.id == activity.id })?.progressUpdatedAt,
            completionDate
        )

        let planned = try TripPlanEditor.setActivityProgress(
            in: repeated,
            activityID: activity.id,
            progress: .planned
        )
        let plannedActivity = try XCTUnwrap(
            planned.orderedDays[0].orderedActivities.first(where: { $0.id == activity.id })
        )
        XCTAssertEqual(plannedActivity.progress, .planned)
        XCTAssertNil(plannedActivity.progressUpdatedAt)
    }

    func testReplicatedActivitiesResetExecutionProgress() throws {
        var trip = OkinawaSample.trip
        let sourceDay = trip.orderedDays[0]
        let targetDay = trip.orderedDays[1]
        trip.days[0].activities[0].progress = .skipped
        trip.days[0].activities[0].progressUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let replicated = try TripPlanEditor.replicateDayActivities(
            in: trip,
            from: sourceDay.id,
            to: [targetDay.id]
        )
        let firstReplicaSequence = targetDay.activities.count + 1
        let replica = try XCTUnwrap(
            replicated.days.first(where: { $0.id == targetDay.id })?
                .activities.first(where: { $0.sequence == firstReplicaSequence })
        )

        XCTAssertEqual(replica.progress, .planned)
        XCTAssertNil(replica.progressUpdatedAt)
    }

    func testDeletingActivityRenumbersRemainingActivities() throws {
        let trip = OkinawaSample.trip
        let day = trip.orderedDays[1]
        let deleted = day.orderedActivities[1]

        let updated = try TripPlanEditor.deleteActivity(in: trip, activityID: deleted.id)
        let remaining = try XCTUnwrap(updated.days.first(where: { $0.id == day.id }))

        XCTAssertFalse(remaining.activities.contains(where: { $0.id == deleted.id }))
        XCTAssertEqual(remaining.orderedActivities.map(\.sequence), Array(1...remaining.activities.count))
        XCTAssertNoThrow(try StoredTrip(validatingSnapshot: updated))
    }

    func testMovingActivityAcrossTargetRenumbersTheWholeDay() throws {
        let trip = OkinawaSample.trip
        let day = trip.orderedDays[1]
        let originalIDs = day.orderedActivities.map(\.id)

        let movedLater = try TripPlanEditor.moveActivity(
            in: trip,
            dayID: day.id,
            activityID: originalIDs[0],
            relativeTo: originalIDs[2]
        )
        let laterIDs = try XCTUnwrap(
            movedLater.days.first(where: { $0.id == day.id })
        ).orderedActivities.map(\.id)
        XCTAssertEqual(laterIDs, [originalIDs[1], originalIDs[2], originalIDs[0]])

        let restored = try TripPlanEditor.moveActivity(
            in: movedLater,
            dayID: day.id,
            activityID: originalIDs[0],
            relativeTo: originalIDs[1]
        )
        let restoredDay = try XCTUnwrap(
            restored.days.first(where: { $0.id == day.id })
        )
        XCTAssertEqual(restoredDay.orderedActivities.map(\.id), originalIDs)
        XCTAssertEqual(
            restoredDay.orderedActivities.map(\.sequence),
            Array(1...restoredDay.activities.count)
        )
        XCTAssertNoThrow(try StoredTrip(validatingSnapshot: restored))
    }

    func testChangingTimeZonePreservesLocalDatesAndActivityTimes() throws {
        let trip = OkinawaSample.trip
        let updated = try TripPlanEditor.changeTimeZone(in: trip, to: "America/Los_Angeles")
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        XCTAssertEqual(updated.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(
            updated.days.map { LocalDate(date: $0.date, timeZone: timeZone) },
            trip.days.map { LocalDate(date: $0.date, timeZone: TimeZone(identifier: "Asia/Tokyo")!) }
        )
        XCTAssertEqual(
            LocalTime(date: try XCTUnwrap(updated.days[0].activities[0].startTime), timeZone: timeZone).minuteOfDay,
            11 * 60 + 30
        )
    }

    func testVenueCountriesAreDistinctAcrossActivities() {
        XCTAssertEqual(OkinawaSample.trip.venueCountryNames, ["Japan"])
    }

    func testReplicatingDayPlansMovesTimesToTheTargetCalendarDay() throws {
        let trip = OkinawaSample.trip
        let source = trip.orderedDays[0]
        let target = trip.orderedDays[2]
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))

        let updated = try TripPlanEditor.replicateDayActivities(in: trip, from: source.id, to: [target.id])
        let copiedActivity = try XCTUnwrap(
            updated.days.first(where: { $0.id == target.id })?.orderedActivities.last(where: { $0.startTime != nil })
        )
        let copiedTime = try XCTUnwrap(copiedActivity.startTime)

        XCTAssertEqual(
            LocalDate(date: copiedTime, timeZone: timeZone),
            LocalDate(date: target.date, timeZone: timeZone)
        )
    }

    func testSwappingDayPlansKeepsTheDateAndSequenceOfEachDay() throws {
        let trip = OkinawaSample.trip
        let first = trip.orderedDays[0]
        let second = trip.orderedDays[1]

        let updated = try TripPlanEditor.swapDayPlans(in: trip, firstDayID: first.id, secondDayID: second.id)
        let updatedFirst = try XCTUnwrap(updated.days.first(where: { $0.id == first.id }))
        let updatedSecond = try XCTUnwrap(updated.days.first(where: { $0.id == second.id }))

        XCTAssertEqual(updatedFirst.sequence, first.sequence)
        XCTAssertEqual(updatedFirst.date, first.date)
        XCTAssertEqual(updatedSecond.sequence, second.sequence)
        XCTAssertEqual(updatedSecond.date, second.date)
        XCTAssertEqual(updatedFirst.title, second.title)
        XCTAssertEqual(updatedFirst.activities.map(\.id), second.activities.map(\.id))
        XCTAssertEqual(updatedSecond.title, first.title)
        XCTAssertEqual(updatedSecond.activities.map(\.id), first.activities.map(\.id))
        let timeZone = try XCTUnwrap(TimeZone(identifier: trip.timeZoneIdentifier))
        let movedTime = try XCTUnwrap(updatedFirst.activities.first?.startTime)
        XCTAssertEqual(LocalDate(date: movedTime, timeZone: timeZone), LocalDate(date: first.date, timeZone: timeZone))
    }

    @MainActor
    func testDeletingStoredTripCascadesToGeneratedDays() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let start = try XCTUnwrap(LocalDate(year: 2026, month: 11, day: 1))
        let end = try XCTUnwrap(LocalDate(year: 2026, month: 11, day: 3))
        let trip = try TripFactory.makeTrip(
            from: TripCreationRequest(
                title: "削除テスト", startDate: start, endDate: end, timeZoneIdentifier: "Asia/Tokyo"
            )
        )
        let storedTrip = try StoredTrip(validatingSnapshot: trip)
        context.insert(storedTrip)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredDay>()), 3)

        context.delete(storedTrip)
        try context.save()

        let reloadedContext = ModelContext(container)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredTrip>()), 0)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredDay>()), 0)
    }

    @MainActor
    func testStoredTripsFetchInChronologicalOrder() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let later = StoredTrip(
            id: UUID(), title: "Later", startDateCode: 20261220, endDateCode: 20261222,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let earlier = StoredTrip(
            id: UUID(), title: "Earlier", startDateCode: 20260901, endDateCode: 20260902,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(later)
        context.insert(earlier)
        try context.save()

        var descriptor = FetchDescriptor<StoredTrip>()
        descriptor.sortBy = [
            SortDescriptor(\StoredTrip.startDateCode),
            SortDescriptor(\StoredTrip.endDateCode),
            SortDescriptor(\StoredTrip.title)
        ]

        XCTAssertEqual(try context.fetch(descriptor).map(\.title), ["Earlier", "Later"])
    }

    func testTripTimelineGroupsUsingEachTripsTimeZone() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 12)))
        let ongoing = TripTimelineEntry(
            id: UUID(),
            startDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 18)),
            endDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 20)),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let upcoming = TripTimelineEntry(
            id: UUID(),
            startDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 20)),
            endDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 23)),
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let past = TripTimelineEntry(
            id: UUID(),
            startDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 15)),
            endDate: try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 18)),
            timeZoneIdentifier: "Asia/Tokyo"
        )

        let groups = TripTimeline.grouped(entries: [upcoming, past, ongoing], now: now)

        XCTAssertEqual(groups[.ongoing]?.map(\.id), [ongoing.id])
        XCTAssertEqual(groups[.upcoming]?.map(\.id), [upcoming.id])
        XCTAssertEqual(groups[.past]?.map(\.id), [past.id])
        XCTAssertEqual(TripTimeline.visibleGroups(for: .upcoming), [.ongoing, .upcoming])
    }

    func testGuideTimelineDerivesTodayNowAndNextWithoutChangingProgress() throws {
        var trip = OkinawaSample.trip
        trip.days[0].activities[0].durationMinutes = 60
        trip.days[0].activities[2].progress = .completed
        trip.days[0].activities[2].progressUpdatedAt = localDate(
            2026, 10, 9, 16, 30,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let original = trip

        let summary = try XCTUnwrap(
            GuideTimelineProjection.todaySummary(
                for: trip,
                now: localDate(2026, 10, 9, 12, 0, timeZoneIdentifier: "Asia/Tokyo")
            )
        )

        XCTAssertEqual(summary.day.id, trip.days[0].id)
        XCTAssertEqual(summary.nowActivity?.id, trip.days[0].activities[0].id)
        XCTAssertEqual(summary.nextActivity?.id, trip.days[0].activities[1].id)
        XCTAssertEqual(summary.remainingActivityCount, 2)
        XCTAssertEqual(summary.rolesByActivityID[trip.days[0].activities[0].id], .now)
        XCTAssertEqual(summary.rolesByActivityID[trip.days[0].activities[1].id], .next)
        XCTAssertEqual(trip, original)
    }

    func testGuideTimelineExcludesCompletedAndSkippedActivities() throws {
        var trip = OkinawaSample.trip
        let changedAt = localDate(2026, 10, 9, 12, 0, timeZoneIdentifier: "Asia/Tokyo")
        trip.days[0].activities[0].durationMinutes = 60
        trip.days[0].activities[0].progress = .completed
        trip.days[0].activities[0].progressUpdatedAt = changedAt
        trip.days[0].activities[1].progress = .skipped
        trip.days[0].activities[1].progressUpdatedAt = changedAt

        let summary = try XCTUnwrap(
            GuideTimelineProjection.todaySummary(for: trip, now: changedAt)
        )

        XCTAssertNil(summary.nowActivity)
        XCTAssertEqual(summary.nextActivity?.id, trip.days[0].activities[2].id)
        XCTAssertEqual(summary.remainingActivityCount, 1)
    }

    func testGuideTimelineDoesNotInferNowWithoutExplicitDuration() throws {
        let trip = OkinawaSample.trip
        let summary = try XCTUnwrap(
            GuideTimelineProjection.todaySummary(
                for: trip,
                now: localDate(2026, 10, 9, 12, 0, timeZoneIdentifier: "Asia/Tokyo")
            )
        )

        XCTAssertNil(summary.nowActivity)
        XCTAssertEqual(summary.nextActivity?.id, trip.days[0].activities[1].id)
        XCTAssertEqual(summary.remainingActivityCount, 3)
    }

    func testGuideTimelineReturnsNoTodayOutsideTripDates() {
        XCTAssertNil(
            GuideTimelineProjection.todaySummary(
                for: OkinawaSample.trip,
                now: localDate(2026, 10, 8, 12, 0, timeZoneIdentifier: "Asia/Tokyo")
            )
        )
    }

    func testSystemExperienceProjectionUsesTheSharedNowNextSourceWithoutPrivateFields() throws {
        var trip = OkinawaSample.trip
        trip.days[0].activities[0].durationMinutes = 60
        trip.days[0].activities[1].reservation = ReservationReference(
            id: UUID(),
            kind: .transport,
            title: "非表示の予約",
            confirmationCode: "SECRET-2048",
            url: nil,
            note: "非表示のメモ"
        )
        let now = localDate(2026, 10, 9, 12, 0, timeZoneIdentifier: "Asia/Tokyo")

        let summary = try XCTUnwrap(
            TripSystemExperienceProjection.currentSummary(for: [trip], now: now)
        )

        XCTAssertEqual(summary.tripID, trip.id)
        XCTAssertEqual(summary.daySequence, 1)
        XCTAssertEqual(summary.nowActivity?.id, trip.days[0].activities[0].id)
        XCTAssertEqual(summary.nextActivity?.id, trip.days[0].activities[1].id)
        XCTAssertTrue(summary.spokenSummary.contains("那覇空港に到着"))
        XCTAssertTrue(summary.spokenSummary.contains("13時00分"))
        XCTAssertTrue(summary.spokenSummary.contains("瀬底島へ移動"))
        XCTAssertFalse(summary.spokenSummary.contains("SECRET-2048"))
        XCTAssertFalse(summary.spokenSummary.contains("非表示のメモ"))
        XCTAssertFalse(summary.spokenSummary.contains("非表示の予約"))
    }

    func testSystemExperienceProjectionPrefersAnActiveActivityAcrossTrips() throws {
        var active = OkinawaSample.trip
        active.title = "進行中のTrip"
        active.days[0].activities[0].durationMinutes = 60
        let nextOnly = Trip(
            id: UUID(uuidString: "A11E0000-0000-4000-8000-00000000BB01")!,
            title: "次の予定だけのTrip",
            dateRange: active.dateRange,
            timeZoneIdentifier: active.timeZoneIdentifier,
            days: active.days.map { day in
                Day(
                    id: day.id,
                    sequence: day.sequence,
                    date: day.date,
                    title: day.title,
                    activities: day.activities.map { activity in
                        var copy = activity
                        copy.durationMinutes = nil
                        return copy
                    }
                )
            }
        )
        let now = localDate(2026, 10, 9, 12, 0, timeZoneIdentifier: "Asia/Tokyo")

        let summary = try XCTUnwrap(
            TripSystemExperienceProjection.currentSummary(
                for: [nextOnly, active],
                now: now
            )
        )

        XCTAssertEqual(summary.tripID, active.id)
        XCTAssertNotNil(summary.nowActivity)

        XCTAssertNil(
            TripSystemExperienceProjection.currentSummary(
                for: [nextOnly],
                now: localDate(2026, 10, 8, 12, 0, timeZoneIdentifier: "Asia/Tokyo")
            )
        )
    }

    func testReservationEditingNormalizesAndValidatesLocalReference() throws {
        let trip = OkinawaSample.trip
        let activityID = trip.days[0].activities[0].id
        let reservationID = UUID()
        let updated = try TripPlanEditor.setReservation(
            in: trip,
            activityID: activityID,
            reservation: ReservationReference(
                id: reservationID,
                kind: .transport,
                title: "  空港リムジン  ",
                confirmationCode: "  BUS-2048  ",
                url: try XCTUnwrap(URL(string: "https://example.com/reservations/BUS-2048")),
                note: "  10分前に集合  "
            )
        )
        let reservation = try XCTUnwrap(updated.days[0].activities[0].reservation)

        XCTAssertEqual(reservation.id, reservationID)
        XCTAssertEqual(reservation.title, "空港リムジン")
        XCTAssertEqual(reservation.confirmationCode, "BUS-2048")
        XCTAssertEqual(reservation.note, "10分前に集合")

        XCTAssertThrowsError(
            try TripPlanEditor.setReservation(
                in: trip,
                activityID: activityID,
                reservation: ReservationReference(
                    id: UUID(),
                    kind: .other,
                    title: " ",
                    confirmationCode: nil,
                    url: nil,
                    note: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .invalidReservationTitle)
        }
        XCTAssertThrowsError(
            try TripPlanEditor.setReservation(
                in: trip,
                activityID: activityID,
                reservation: ReservationReference(
                    id: UUID(),
                    kind: .other,
                    title: "Unsafe",
                    confirmationCode: nil,
                    url: URL(string: "javascript:alert(1)"),
                    note: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .invalidReservationURL)
        }
    }

    func testOfflineReviewSeparatesLocalContentFromOnlineEnhancements() throws {
        var trip = OkinawaSample.trip
        let activityID = trip.days[0].activities[0].id
        let reservationID = UUID()
        trip = try TripPlanEditor.setReservation(
            in: trip,
            activityID: activityID,
            reservation: ReservationReference(
                id: reservationID,
                kind: .transport,
                title: "Airport bus",
                confirmationCode: "BUS-2048",
                url: try XCTUnwrap(URL(string: "https://example.com/booking")),
                note: nil
            )
        )
        trip.days[1].activities[0].place?.externalImage = externalPlaceImage()
        trip.days[1].activities[1].place?.imageData = Data([0x01, 0x02])
        let activeLegs = TravelLegProjection.activeLegs(for: trip)
        let manualLeg = try XCTUnwrap(activeLegs.first)
        trip = try TripPlanEditor.setTravelLegPreference(
            in: trip,
            legID: manualLeg.id,
            transportType: .walking,
            manualDurationMinutes: 20,
            note: nil
        )

        let report = GuideOfflineReview.report(for: trip)

        XCTAssertEqual(report.activityCount, 10)
        XCTAssertEqual(report.venueSnapshotCount, 8)
        XCTAssertEqual(report.userImageCount, 1)
        XCTAssertEqual(report.reservationCount, 1)
        XCTAssertTrue(
            report.onlineDependencies.contains(
                .reservationLink(activityID: activityID, reservationID: reservationID)
            )
        )
        XCTAssertTrue(
            report.onlineDependencies.contains(
                .externalVenueImage(activityID: trip.days[1].activities[0].id)
            )
        )
        XCTAssertFalse(report.onlineDependencies.contains(.travelEstimate(manualLeg.id)))
        XCTAssertEqual(
            report.onlineDependencies.compactMap {
                if case let .travelEstimate(legID) = $0 { legID } else { nil }
            }.count,
            activeLegs.count - 1
        )
    }

    @MainActor
    func testStoredTripRoundTripsReservationReference() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let activityID = OkinawaSample.trip.days[0].activities[0].id
        let reservationID = UUID()
        let updated = try TripPlanEditor.setReservation(
            in: OkinawaSample.trip,
            activityID: activityID,
            reservation: ReservationReference(
                id: reservationID,
                kind: .accommodation,
                title: "瀬底の宿",
                confirmationCode: "STAY-1024",
                url: try XCTUnwrap(URL(string: "https://example.com/stay")),
                note: "フロントで提示"
            )
        )
        context.insert(try StoredTrip(validatingSnapshot: updated))
        try context.save()

        let reloadedContext = ModelContext(container)
        let storedTrip = try XCTUnwrap(
            try reloadedContext.fetch(FetchDescriptor<StoredTrip>()).first
        )
        let reloaded = try XCTUnwrap(storedTrip.snapshot)
        let reservation = try XCTUnwrap(
            reloaded.days.flatMap(\.activities).first(where: { $0.id == activityID })?.reservation
        )
        XCTAssertEqual(reservation.id, reservationID)
        XCTAssertEqual(reservation.kind, .accommodation)
        XCTAssertEqual(reservation.confirmationCode, "STAY-1024")
        XCTAssertEqual(reservation.url?.absoluteString, "https://example.com/stay")

        reloadedContext.delete(storedTrip)
        try reloadedContext.save()
        XCTAssertEqual(
            try reloadedContext.fetchCount(FetchDescriptor<StoredReservationReference>()),
            0
        )
    }

    func testActivityReminderRequiresStartTimeAndCanBeCleared() throws {
        let trip = OkinawaSample.trip
        let activity = try XCTUnwrap(
            trip.orderedDays.flatMap(\.orderedActivities).first(where: { $0.startTime != nil })
        )
        let reminded = try TripPlanEditor.setActivityReminder(
            in: trip,
            activityID: activity.id,
            leadTime: .thirtyMinutes
        )
        XCTAssertEqual(
            reminded.days.flatMap(\.activities).first(where: { $0.id == activity.id })?.reminderLeadTime,
            .thirtyMinutes
        )

        let cleared = try TripPlanEditor.setActivityReminder(
            in: reminded,
            activityID: activity.id,
            leadTime: nil
        )
        XCTAssertNil(
            cleared.days.flatMap(\.activities).first(where: { $0.id == activity.id })?.reminderLeadTime
        )

        let withoutTime = try TripPlanEditor.updateActivity(
            in: trip,
            activityID: activity.id,
            title: activity.title,
            startTime: nil,
            category: activity.category,
            durationMinutes: activity.durationMinutes,
            note: activity.note,
            place: activity.place
        )
        XCTAssertThrowsError(
            try TripPlanEditor.setActivityReminder(
                in: withoutTime,
                activityID: activity.id,
                leadTime: .fifteenMinutes
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .reminderRequiresStartTime)
        }
    }

    func testReminderProjectionIncludesOnlyFuturePlannedExplicitIntent() throws {
        var trip = OkinawaSample.trip
        let activities = trip.orderedDays.flatMap(\.orderedActivities)
            .filter { $0.startTime != nil }
        let first = try XCTUnwrap(activities.first)
        let second = try XCTUnwrap(activities.dropFirst().first)
        trip = try TripPlanEditor.setActivityReminder(
            in: trip,
            activityID: first.id,
            leadTime: .oneHour
        )
        trip = try TripPlanEditor.setActivityReminder(
            in: trip,
            activityID: second.id,
            leadTime: .atStart
        )
        trip = try TripPlanEditor.setActivityProgress(
            in: trip,
            activityID: second.id,
            progress: .completed,
            at: try XCTUnwrap(second.startTime)
        )

        let startTime = try XCTUnwrap(first.startTime)
        let now = startTime.addingTimeInterval(-2 * 60 * 60)
        let schedules = ActivityReminderProjection.pendingSchedules(for: trip, now: now)
        let schedule = try XCTUnwrap(schedules.first)
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedule.activityID, first.id)
        XCTAssertEqual(schedule.fireDate, startTime.addingTimeInterval(-60 * 60))
        XCTAssertEqual(schedule.activityTitle, first.title)
        XCTAssertTrue(
            schedule.id.hasPrefix(ActivityReminderProjection.identifierPrefix(for: trip.id))
        )
        XCTAssertTrue(
            ActivityReminderProjection.pendingSchedules(
                for: trip,
                now: startTime
            ).allSatisfy { $0.activityID != first.id }
        )
    }

    @MainActor
    func testStoredTripRoundTripsActivityReminder() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let activity = try XCTUnwrap(
            OkinawaSample.trip.orderedDays.flatMap(\.orderedActivities)
                .first(where: { $0.startTime != nil })
        )
        let updated = try TripPlanEditor.setActivityReminder(
            in: OkinawaSample.trip,
            activityID: activity.id,
            leadTime: .oneDay
        )
        context.insert(try StoredTrip(validatingSnapshot: updated))
        try context.save()

        let snapshot = try XCTUnwrap(
            try ModelContext(container).fetch(FetchDescriptor<StoredTrip>()).first?.snapshot
        )
        XCTAssertEqual(
            snapshot.days.flatMap(\.activities)
                .first(where: { $0.id == activity.id })?.reminderLeadTime,
            .oneDay
        )
    }

    func testActivityMemoryRequiresVisitedStateAndNormalizesReflection() throws {
        let trip = OkinawaSample.trip
        let activity = trip.orderedDays[0].orderedActivities[0]
        XCTAssertThrowsError(
            try TripPlanEditor.setActivityMemory(
                in: trip,
                activityID: activity.id,
                photoData: Data([1, 2, 3]),
                reflection: " 良い時間だった "
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .memoryRequiresCompletedActivity)
        }

        let visited = try TripPlanEditor.setActivityProgress(
            in: trip,
            activityID: activity.id,
            progress: .completed,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let recorded = try TripPlanEditor.setActivityMemory(
            in: visited,
            activityID: activity.id,
            photoData: Data([1, 2, 3]),
            reflection: " 良い時間だった "
        )
        let memory = try XCTUnwrap(
            recorded.days.flatMap(\.activities).first(where: { $0.id == activity.id })
        )
        XCTAssertEqual(memory.memoryPhotoData, Data([1, 2, 3]))
        XCTAssertEqual(memory.reflection, "良い時間だった")
        XCTAssertThrowsError(
            try TripPlanEditor.setActivityProgress(
                in: recorded,
                activityID: activity.id,
                progress: .planned
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .memoryRequiresCompletedActivity)
        }
        XCTAssertThrowsError(
            try TripPlanEditor.setActivityMemory(
                in: visited,
                activityID: activity.id,
                photoData: nil,
                reflection: String(repeating: "あ", count: 501)
            )
        ) { error in
            XCTAssertEqual(error as? TripPlanEditingError, .invalidReflection)
        }
    }

    func testMemoryProjectionUsesVisitedActivitiesWithoutReusingVenueImages() throws {
        var trip = OkinawaSample.trip
        trip.days[0].activities[0].place?.imageData = Data([9])
        let first = trip.orderedDays[0].orderedActivities[0]
        let second = trip.orderedDays[0].orderedActivities[1]
        trip = try TripPlanEditor.setActivityProgress(
            in: trip,
            activityID: first.id,
            progress: .completed,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        trip = try TripPlanEditor.setActivityMemory(
            in: trip,
            activityID: first.id,
            photoData: nil,
            reflection: "また行きたい"
        )
        trip = try TripPlanEditor.setActivityProgress(
            in: trip,
            activityID: second.id,
            progress: .completed,
            at: Date(timeIntervalSince1970: 1_800_000_060)
        )

        let summary = MemoryProjection.summary(for: trip)
        XCTAssertEqual(summary.visitedCount, 2)
        XCTAssertEqual(summary.recordedCount, 1)
        XCTAssertEqual(summary.entries.map(\.activity.id), [first.id, second.id])
        XCTAssertNil(summary.entries[0].activity.memoryPhotoData)
        XCTAssertNotNil(summary.entries[0].activity.place?.imageData)
    }

    @MainActor
    func testStoredTripRoundTripsActivityMemory() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let activity = OkinawaSample.trip.orderedDays[0].orderedActivities[0]
        var updated = try TripPlanEditor.setActivityProgress(
            in: OkinawaSample.trip,
            activityID: activity.id,
            progress: .completed,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        updated = try TripPlanEditor.setActivityMemory(
            in: updated,
            activityID: activity.id,
            photoData: Data([4, 5, 6]),
            reflection: "忘れたくない景色"
        )
        context.insert(try StoredTrip(validatingSnapshot: updated))
        try context.save()

        let snapshot = try XCTUnwrap(
            try ModelContext(container).fetch(FetchDescriptor<StoredTrip>()).first?.snapshot
        )
        let reloaded = try XCTUnwrap(
            snapshot.days.flatMap(\.activities).first(where: { $0.id == activity.id })
        )
        XCTAssertEqual(reloaded.memoryPhotoData, Data([4, 5, 6]))
        XCTAssertEqual(reloaded.reflection, "忘れたくない景色")
    }

    @MainActor
    func testParticipantRoundTripUsesLocalStore() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        context.insert(StoredParticipant(displayName: "Aiko", note: "運転担当"))
        try context.save()

        let reloadedContext = ModelContext(container)
        let participant = try XCTUnwrap(try reloadedContext.fetch(FetchDescriptor<StoredParticipant>()).first)
        XCTAssertEqual(participant.displayName, "Aiko")
        XCTAssertEqual(participant.note, "運転担当")
    }

    @MainActor
    func testSwiftDataRoundTripPreservesLocalCalendarSemantics() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        var trip = OkinawaSample.trip
        trip.days[0].activities[0].category = .transport
        trip.days[0].activities[0].durationMinutes = 45
        let storedTrip = try StoredTrip(validatingSnapshot: trip)
        context.insert(storedTrip)
        try context.save()

        let reloadedContext = ModelContext(container)
        let fetched = try XCTUnwrap(try reloadedContext.fetch(FetchDescriptor<StoredTrip>()).first)
        let dayOne = try XCTUnwrap(fetched.days.first(where: { $0.sequence == 1 }))
        let arrival = try XCTUnwrap(dayOne.activities.first(where: { $0.sequence == 1 }))
        let snapshot = try XCTUnwrap(fetched.snapshot)

        XCTAssertEqual(fetched.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(fetched.startDateCode, 20261009)
        XCTAssertEqual(dayOne.dateCode, 20261009)
        XCTAssertEqual(arrival.startMinuteOfDay, 11 * 60 + 30)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(snapshot.days.count, 4)
        XCTAssertEqual(snapshot.orderedDays[0].orderedActivities[0].title, "那覇空港に到着")
        XCTAssertEqual(snapshot.orderedDays[0].orderedActivities[0].category, .transport)
        XCTAssertEqual(snapshot.orderedDays[0].orderedActivities[0].durationMinutes, 45)
    }

    @MainActor
    func testStoredTripPersistsCurrencyAndArtworkAfterPlanUpdate() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
        context.insert(storedTrip)
        try context.save()

        var updated = OkinawaSample.trip
        updated.defaultCurrencyCode = "USD"
        updated.coverImageData = Data([0x01, 0x02, 0x03])
        updated.days[1].activities[0].place?.imageData = Data([0x0A, 0x0B])
        try storedTrip.applyPlan(updated, in: context)
        try context.save()

        let reloadedContext = ModelContext(container)
        let reloaded = try XCTUnwrap(try reloadedContext.fetch(FetchDescriptor<StoredTrip>()).first?.snapshot)
        let updatedPlace = try XCTUnwrap(
            reloaded.days.first(where: { $0.sequence == 2 })?.activities.first(where: { $0.sequence == 1 })?.place
        )
        XCTAssertEqual(reloaded.defaultCurrencyCode, "USD")
        XCTAssertEqual(reloaded.coverImageData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(updatedPlace.imageData, Data([0x0A, 0x0B]))
    }

    @MainActor
    func testStoredTripPersistsActivityProgressAfterPlanUpdate() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
        context.insert(storedTrip)
        try context.save()

        let activityID = OkinawaSample.trip.orderedDays[0].orderedActivities[0].id
        let changeDate = Date(timeIntervalSince1970: 1_800_000_000)
        let updated = try TripPlanEditor.setActivityProgress(
            in: OkinawaSample.trip,
            activityID: activityID,
            progress: .skipped,
            at: changeDate
        )
        try storedTrip.applyPlan(updated, in: context)
        try context.save()

        let reloaded = try XCTUnwrap(
            try ModelContext(container).fetch(FetchDescriptor<StoredTrip>()).first?.snapshot
        )
        let activity = try XCTUnwrap(
            reloaded.orderedDays[0].orderedActivities.first(where: { $0.id == activityID })
        )
        XCTAssertEqual(activity.progress, .skipped)
        XCTAssertEqual(activity.progressUpdatedAt, changeDate)
    }

    @MainActor
    func testStoredTripRoundTripsOnlyTravelLegUserIntent() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let legID = try XCTUnwrap(TravelLegProjection.activeLegs(for: OkinawaSample.trip).first?.id)
        let updated = try TripPlanEditor.setTravelLegPreference(
            in: OkinawaSample.trip,
            legID: legID,
            transportType: .transit,
            manualDurationMinutes: 42,
            note: "駅で乗り換え"
        )
        let storedTrip = try StoredTrip(validatingSnapshot: updated)
        context.insert(storedTrip)
        try context.save()

        let reloadedContext = ModelContext(container)
        let fetched = try XCTUnwrap(
            try reloadedContext.fetch(FetchDescriptor<StoredTrip>()).first
        )
        let snapshot = try XCTUnwrap(fetched.snapshot)

        XCTAssertEqual(snapshot.travelLegPreferences, updated.travelLegPreferences)
        XCTAssertEqual(fetched.travelLegPreferences.count, 1)
        XCTAssertEqual(
            try reloadedContext.fetchCount(FetchDescriptor<StoredTravelLegPreference>()),
            1
        )
    }

    @MainActor
    func testStoredTripPersistsWikimediaPlaceImageAttribution() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
        context.insert(storedTrip)
        try context.save()

        var updated = OkinawaSample.trip
        updated.days[1].activities[0].place?.externalImage = ExternalPlaceImage(
            provider: .wikimediaCommons,
            providerImageID: "Churaumi_Aquarium.jpg",
            imageURL: try XCTUnwrap(URL(string: "https://upload.wikimedia.org/example.jpg")),
            sourcePageURL: try XCTUnwrap(URL(string: "https://commons.wikimedia.org/wiki/File:Churaumi_Aquarium.jpg")),
            authorName: "Example photographer",
            authorURL: try XCTUnwrap(URL(string: "https://commons.wikimedia.org/wiki/User:Example")),
            licenseName: "CC BY-SA 4.0",
            licenseURL: try XCTUnwrap(URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")),
            kind: .exactVenue,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
        try storedTrip.applyPlan(updated, in: context)
        try context.save()

        let reloaded = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<StoredTrip>()).first?.snapshot)
        let place = try XCTUnwrap(reloaded.days.first(where: { $0.sequence == 2 })?.activities.first(where: { $0.sequence == 1 })?.place)
        let image = try XCTUnwrap(place.externalImage)
        XCTAssertEqual(image.provider, .wikimediaCommons)
        XCTAssertEqual(image.providerImageID, "Churaumi_Aquarium.jpg")
        XCTAssertEqual(image.authorName, "Example photographer")
        XCTAssertEqual(image.licenseName, "CC BY-SA 4.0")
        XCTAssertEqual(image.kind, .exactVenue)
        XCTAssertEqual(image.fetchedAt, Date(timeIntervalSince1970: 1_000))
    }

    @MainActor
    func testStoredTripApplyPlanSynchronizesActivityAndPlaceChanges() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
        context.insert(storedTrip)
        try context.save()

        var updated = OkinawaSample.trip
        updated.days[1].activities.removeLast()
        updated.days[1].activities[0].place = nil
        updated.days[0].activities[1].place = PlaceSnapshot(
            id: UUID(), name: "瀬底ビーチ", address: "沖縄県国頭郡本部町", latitude: 26.653, longitude: 127.861,
            mapKitIdentifier: nil
        )
        try storedTrip.applyPlan(updated, in: context)
        try context.save()

        let reloaded = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<StoredTrip>()).first?.snapshot)
        let dayTwo = try XCTUnwrap(reloaded.days.first(where: { $0.sequence == 2 }))
        let dayOne = try XCTUnwrap(reloaded.days.first(where: { $0.sequence == 1 }))
        XCTAssertEqual(dayTwo.activities.count, updated.days[1].activities.count)
        XCTAssertNil(dayTwo.orderedActivities.first?.place)
        XCTAssertEqual(dayOne.orderedActivities[1].place?.name, "瀬底ビーチ")
        let reloadedContext = ModelContext(container)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredActivity>()), 9)
        XCTAssertEqual(try reloadedContext.fetchCount(FetchDescriptor<StoredPlaceSnapshot>()), 7)
    }

    @MainActor
    func testInvalidPlanIsRejectedBeforeStoredTripChanges() throws {
        let container = try TripMapStore.makeContainer(inMemoryOnly: true)
        let context = container.mainContext
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
        context.insert(storedTrip)
        try context.save()

        var invalid = OkinawaSample.trip
        invalid.title = "  "
        XCTAssertThrowsError(try storedTrip.applyPlan(invalid, in: context)) { error in
            XCTAssertEqual(error as? TripPersistenceError, .blankTitle)
        }

        XCTAssertEqual(storedTrip.title, OkinawaSample.trip.title)
        XCTAssertEqual(storedTrip.days.count, OkinawaSample.trip.days.count)
    }

    @MainActor
    func testDiskBackedStoreReopensSavedTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("TripMap.store")

        do {
            let container = try TripMapStore.makeContainer(url: storeURL)
            let context = container.mainContext
            context.insert(try StoredTrip(validatingSnapshot: OkinawaSample.trip))
            try context.save()
        }

        let reopenedContainer = try TripMapStore.makeContainer(url: storeURL)
        let reloadedContext = reopenedContainer.mainContext
        let reloaded = try XCTUnwrap(try reloadedContext.fetch(FetchDescriptor<StoredTrip>()).first?.snapshot)
        XCTAssertEqual(reloaded.id, OkinawaSample.trip.id)
        XCTAssertEqual(reloaded.days.count, OkinawaSample.trip.days.count)
    }

    @MainActor
    func testVersionedStoreOpensUnversionedStoreWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("TripMap-unversioned.store")

        var fixture = OkinawaSample.trip
        fixture.coverImageData = Data([0x10, 0x20, 0x30])
        fixture.days[0].activities[0].place?.imageData = Data([0x40, 0x50])
        let memoryActivityID = fixture.days[0].activities[0].id
        fixture = try TripPlanEditor.setActivityProgress(
            in: fixture,
            activityID: memoryActivityID,
            progress: .completed,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        fixture = try TripPlanEditor.setActivityMemory(
            in: fixture,
            activityID: memoryActivityID,
            photoData: Data([0x60, 0x70, 0x80]),
            reflection: "V1 migration fixture"
        )

        do {
            let unversionedSchema = Schema(TripMapSchemaV1.models)
            let configuration = ModelConfiguration(
                schema: unversionedSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: unversionedSchema,
                configurations: configuration
            )
            legacyContainer.mainContext.insert(try StoredTrip(validatingSnapshot: fixture))
            try legacyContainer.mainContext.save()
        }

        let versionedContainer = try TripMapStore.makeContainer(url: storeURL)
        let storedTrips = try versionedContainer.mainContext.fetch(FetchDescriptor<StoredTrip>())
        let reloaded = try XCTUnwrap(storedTrips.first?.snapshot)
        let reloadedMemory = try XCTUnwrap(
            reloaded.days.flatMap(\.activities).first(where: { $0.id == memoryActivityID })
        )

        XCTAssertEqual(storedTrips.count, 1)
        XCTAssertEqual(reloaded.id, fixture.id)
        XCTAssertEqual(reloaded.dateRange, fixture.dateRange)
        XCTAssertEqual(reloaded.orderedDays.map(\.id), fixture.orderedDays.map(\.id))
        XCTAssertEqual(
            reloaded.orderedDays.flatMap(\.orderedActivities).map(\.id),
            fixture.orderedDays.flatMap(\.orderedActivities).map(\.id)
        )
        XCTAssertEqual(reloaded.coverImageData, fixture.coverImageData)
        let fixtureMemory = try XCTUnwrap(
            fixture.days.flatMap(\.activities).first(where: { $0.id == memoryActivityID })
        )
        XCTAssertEqual(
            reloadedMemory.place?.imageData,
            fixtureMemory.place?.imageData
        )
        XCTAssertEqual(reloadedMemory.memoryPhotoData, Data([0x60, 0x70, 0x80]))
        XCTAssertEqual(reloadedMemory.reflection, "V1 migration fixture")
    }

    private func externalPlaceImage(providerImageID: String = "Example.jpg") -> ExternalPlaceImage {
        ExternalPlaceImage(
            provider: .wikimediaCommons,
            providerImageID: providerImageID,
            imageURL: URL(string: "https://upload.wikimedia.org/example.jpg")!,
            sourcePageURL: URL(string: "https://commons.wikimedia.org/wiki/File:Example.jpg")!,
            authorName: "Example photographer",
            authorURL: nil,
            licenseName: "CC BY-SA 4.0",
            licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!,
            kind: .exactVenue,
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        timeZoneIdentifier: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    #if TRIPMAP_LIVE_VENUE_IMAGE_QA
    private func livePlace(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double
    ) -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            mapKitIdentifier: nil
        )
    }
    #endif
}

@available(macOS 26.0, *)
enum OptionalRelationshipSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [Root.self, Child.self]

    @Model
    final class Root {
        var id: UUID = UUID()
        var title: String = ""
        @Relationship(deleteRule: .cascade, inverse: \Child.root)
        var children: [Child] = []

        init(id: UUID, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Model
    final class Child {
        var id: UUID = UUID()
        var sequence: Int = 0
        var root: Root?

        init(id: UUID, sequence: Int) {
            self.id = id
            self.sequence = sequence
        }
    }
}

@available(macOS 26.0, *)
enum OptionalRelationshipSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] = [Root.self, Child.self]

    @Model
    final class Root {
        var id: UUID = UUID()
        var title: String = ""
        @Relationship(deleteRule: .cascade, inverse: \Child.root)
        var children: [Child]? = []

        init(id: UUID, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Model
    final class Child {
        var id: UUID = UUID()
        var sequence: Int = 0
        var root: Root?

        init(id: UUID, sequence: Int) {
            self.id = id
            self.sequence = sequence
        }
    }
}

@available(macOS 26.0, *)
enum OptionalRelationshipMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        OptionalRelationshipSchemaV1.self,
        OptionalRelationshipSchemaV2.self
    ]
    static let stages: [MigrationStage] = [
        .lightweight(
            fromVersion: OptionalRelationshipSchemaV1.self,
            toVersion: OptionalRelationshipSchemaV2.self
        )
    ]
}
