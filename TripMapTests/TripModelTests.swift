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
        interaction.selectActivity(second.id, source: .list, in: trip)

        trip.days[1].activities.removeAll(where: { $0.id == second.id })
        interaction.reconcile(with: trip)
        XCTAssertEqual(interaction.selectedActivityID, third.id)

        trip.days[1].activities.removeAll(where: { $0.id == third.id })
        interaction.reconcile(with: trip)
        XCTAssertEqual(interaction.selectedActivityID, dayTwo.orderedActivities[0].id)
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
}
