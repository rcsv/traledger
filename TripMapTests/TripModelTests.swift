import SwiftData
import XCTest
@testable import TripMap

final class TripModelTests: XCTestCase {
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
        let storedTrip = try StoredTrip(validatingSnapshot: OkinawaSample.trip)
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
}
