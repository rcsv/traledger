import XCTest

final class VenueImageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLookAroundThenWikimediaFallbackInVenueCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa"
        ]
        app.launch()

        let tripLabel = app.staticTexts["Venue Image QA"].firstMatch
        XCTAssertTrue(tripLabel.waitForExistence(timeout: 10))
        tripLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).click()

        let dayLabel = app.staticTexts["Venue image QA"].firstMatch
        XCTAssertTrue(dayLabel.waitForExistence(timeout: 10))
        dayLabel.click()

        let lookAroundLabel = "渋谷スクランブル交差点 周辺の Look Around 画像"
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: lookAroundLabel)
                .firstMatch
                .waitForExistence(timeout: 15)
        )

        let fallbackActivity = app.staticTexts["Wikimediaを確認"].firstMatch
        XCTAssertTrue(fallbackActivity.waitForExistence(timeout: 10))
        fallbackActivity.click()

        let wikimediaLabel = "那覇空港 の Wikimedia Commons 画像"
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: wikimediaLabel)
                .firstMatch
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(
            app.links.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Wikimedia Commons の画像。作者")
            ).firstMatch.exists
        )
    }
}
