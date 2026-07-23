import XCTest

final class VenueImageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLookAroundInVenueCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa",
            "-tripmap-open-venue-image-qa"
        ]
        app.launch()

        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .firstMatch
        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(
            venueImage.label,
            "渋谷スクランブル交差点 周辺の Look Around 画像"
        )
    }

    @MainActor
    func testWikimediaFallbackInVenueCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa",
            "-tripmap-open-venue-image-qa",
            "-tripmap-venue-image-qa-wikimedia"
        ]
        app.launch()

        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .firstMatch
        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.label, "那覇空港 の Wikimedia Commons 画像")
        XCTAssertTrue(
            app.links.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Wikimedia Commons の画像。作者")
            ).firstMatch.exists
        )
    }

    @MainActor
    func testPhotosPickerUserImageTakesPriority() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa",
            "-tripmap-open-venue-image-qa",
            "-tripmap-venue-image-qa-user"
        ]
        app.launch()

        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .firstMatch
        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.label, "沖縄美ら海水族館 の場所を示す画像")

        let changeImageButton = app.buttons["画像を変更"].firstMatch
        XCTAssertTrue(changeImageButton.waitForExistence(timeout: 10))
        changeImageButton.click()

        let picker = app.sheets.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.coordinate(
            withNormalizedOffset: CGVector(dx: 0.32, dy: 0.39)
        ).click()

        let selectedImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .matching(
                NSPredicate(
                    format: "label == %@",
                    "沖縄美ら海水族館 の選択された画像"
                )
            )
            .firstMatch
        XCTAssertTrue(selectedImage.waitForExistence(timeout: 15))

        app.terminate()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-open-venue-image-qa",
            "-tripmap-venue-image-qa-user"
        ]
        app.launch()

        let persistedImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .matching(
                NSPredicate(
                    format: "label == %@",
                    "沖縄美ら海水族館 の選択された画像"
                )
            )
            .firstMatch
        XCTAssertTrue(persistedImage.waitForExistence(timeout: 15))
    }
}
