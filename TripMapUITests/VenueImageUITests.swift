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

        let expectedLabel = "渋谷スクランブル交差点 周辺の Look Around 画像"
        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .matching(NSPredicate(format: "label == %@", expectedLabel))
            .firstMatch
        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.label, expectedLabel)
    }

    @MainActor
    func testRegularVenueCardUsesWidescreenImage() {
        let app = launchUserImageFixture(
            additionalArguments: ["-tripmap-venue-image-qa-regular"]
        )
        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .firstMatch

        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.frame.width, 176, accuracy: 2)
        XCTAssertEqual(venueImage.frame.height, 99, accuracy: 2)
        XCTAssertTrue(app.buttons["画像を変更"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["Mapsで開く"].firstMatch.isHittable)
    }

    @MainActor
    func testNarrowVenueCardUsesSquareImage() {
        let app = launchUserImageFixture(
            additionalArguments: ["-tripmap-venue-image-qa-narrow"]
        )
        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .firstMatch

        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.frame.width, 88, accuracy: 2)
        XCTAssertEqual(venueImage.frame.height, 88, accuracy: 2)
        XCTAssertTrue(app.buttons["画像を変更"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["Mapsで開く"].firstMatch.isHittable)
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

        let expectedLabel = "那覇空港 の Wikimedia Commons 画像"
        let venueImage = app.descendants(matching: .any)
            .matching(identifier: "venue-image")
            .matching(NSPredicate(format: "label == %@", expectedLabel))
            .firstMatch
        XCTAssertTrue(venueImage.waitForExistence(timeout: 15))
        XCTAssertEqual(venueImage.label, expectedLabel)
        XCTAssertTrue(
            app.links.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Wikimedia Commons の画像。作者")
            ).firstMatch.exists
        )
    }

    @MainActor
    func testActivityCardDoubleClickOpensEditor() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.doubleClick()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "activity-editor")
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["保存"].firstMatch.exists)
    }

    @MainActor
    func testActivityCardReturnOpensEditor() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.click()
        activityCard.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "activity-editor")
                .firstMatch
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testActivityCardContextMenuOffersEditAndDelete() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.rightClick()

        XCTAssertTrue(app.menuItems["予定を編集"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["予定を削除"].firstMatch.exists)
    }

    @MainActor
    func testCategoryDurationSuggestionAppliesWhenUnset() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.doubleClick()

        let suggestion = app.buttons["duration-suggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertEqual(suggestion.label, "おすすめの所要時間：1時間30分")
        suggestion.click()

        XCTAssertFalse(suggestion.exists)
        XCTAssertTrue(
            app.staticTexts["所要時間 1時間30分"].firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testDurationSuggestionDoesNotReplaceExistingDuration() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-1"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.doubleClick()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "activity-editor")
                .firstMatch
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.buttons["duration-suggestion"].firstMatch.exists)
        XCTAssertTrue(
            app.staticTexts["所要時間 45分"].firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testActivityEditorOpensVenueSearchWithClearInitialState() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.doubleClick()

        let venueSearchButton = app.buttons["venue-search-button"].firstMatch
        XCTAssertTrue(venueSearchButton.waitForExistence(timeout: 10))
        venueSearchButton.click()

        XCTAssertTrue(
            app.searchFields["施設名または住所"].firstMatch
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["場所を検索"].firstMatch.exists)
        XCTAssertFalse(app.buttons["この場所を設定"].firstMatch.isEnabled)
    }

    @MainActor
    func testWikimediaAttributionReceivesKeyboardFocus() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa",
            "-tripmap-open-venue-image-qa",
            "-tripmap-venue-image-qa-wikimedia"
        ]
        app.launch()

        let attribution = app.links["wikimedia-attribution"].firstMatch
        XCTAssertTrue(attribution.waitForExistence(timeout: 15))
        app.activate()

        let focusedAttribution = app.links.matching(
            NSPredicate(
                format: "identifier == %@ AND hasKeyboardFocus == true",
                "wikimedia-attribution"
            )
        ).firstMatch
        for _ in 0..<30 where !focusedAttribution.exists {
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(
            focusedAttribution.exists,
            "Wikimedia attribution must be reachable without a pointer."
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

    @MainActor
    private func launchUserImageFixture(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-tripmap-seed-venue-image-qa",
            "-tripmap-open-venue-image-qa",
            "-tripmap-venue-image-qa-user"
        ] + additionalArguments
        app.launch()
        openVenueImageFixtureIfNeeded(in: app)
        return app
    }

    @MainActor
    private func openVenueImageFixtureIfNeeded(in app: XCUIApplication) {
        let userImageActivity = app.buttons["activity-3"].firstMatch
        guard !userImageActivity.waitForExistence(timeout: 5) else { return }

        let fixtureTrip = app.buttons[
            "trip-A11E0000-0000-4000-8000-000000000000"
        ].firstMatch
        if fixtureTrip.waitForExistence(timeout: 5) {
            app.activate()
            fixtureTrip.click()
        }
    }
}
