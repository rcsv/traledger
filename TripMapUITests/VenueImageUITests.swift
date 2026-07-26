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
    func testTimelineAndMapControlsKeepClearVisualHierarchy() {
        let app = launchUserImageFixture(
            additionalArguments: ["-tripmap-venue-image-qa-regular"]
        )
        let mapSearch = app.buttons["map-venue-search-button"].firstMatch
        let toolbar = app.toolbars.firstMatch

        XCTAssertTrue(mapSearch.waitForExistence(timeout: 15))
        XCTAssertTrue(mapSearch.isHittable)
        XCTAssertTrue(toolbar.exists)
        XCTAssertGreaterThanOrEqual(
            mapSearch.frame.minY,
            toolbar.frame.maxY - 2,
            "Map actions must start below the window toolbar."
        )

        for (identifier, label) in [
            ("plan-memory-button", "思い出を開く"),
            ("plan-map-visibility-button", "地図を隠す"),
            ("plan-add-from-place-button", "場所から予定を追加"),
            ("plan-add-activity-button", "選択中の日に予定を追加"),
            ("plan-day-actions-menu", "選択中の日の操作"),
            ("plan-edit-activity-button", "選択中の予定を編集"),
            ("plan-activity-actions-menu", "選択中の予定のその他の操作")
        ] {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(control.exists, "\(identifier) must remain available.")
            XCTAssertEqual(control.label, label)
        }

        for identifier in [
            "activity-insert-start",
            "activity-insert-between-1",
            "activity-insert-between-2",
            "activity-insert-end"
        ] {
            let insertionPoint = app.buttons[identifier].firstMatch
            XCTAssertTrue(insertionPoint.exists, "\(identifier) must remain available.")
            XCTAssertTrue(insertionPoint.isHittable, "\(identifier) must remain operable.")
        }

        let screenshot = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        screenshot.name = "Timeline and map control hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "activity-drag-3")
                .firstMatch.exists
        )
        activityCard.rightClick()

        XCTAssertTrue(app.menuItems["予定を編集"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["予定を削除"].firstMatch.exists)
    }

    @MainActor
    func testActivityCardReorderSupportsUndoAndRedo() {
        let app = launchUserImageFixture()
        let activityCard = app.buttons["activity-3"].firstMatch

        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.rightClick()
        let moveEarlier = app.menuItems["前へ移動"].firstMatch
        XCTAssertTrue(moveEarlier.waitForExistence(timeout: 5))
        moveEarlier.click()

        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activity-2",
                    "ユーザー画像を確認"
                )
            ).firstMatch.waitForExistence(timeout: 10)
        )

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activity-3",
                    "ユーザー画像を確認"
                )
            ).firstMatch.waitForExistence(timeout: 10)
        )

        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier == %@ AND label CONTAINS %@",
                    "activity-2",
                    "ユーザー画像を確認"
                )
            ).firstMatch.waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testTravelLegRowsExplainLoadedAndUnavailableStates() {
        let app = launchUserImageFixture(
            additionalArguments: ["-tripmap-travel-leg-qa"]
        )
        let loadedLeg = app.descendants(matching: .any)
            .matching(identifier: "travel-leg-1-2")
            .firstMatch
        let unavailableLeg = app.descendants(matching: .any)
            .matching(identifier: "travel-leg-2-3")
            .firstMatch

        XCTAssertTrue(loadedLeg.waitForExistence(timeout: 15))
        XCTAssertTrue(loadedLeg.label.contains("車 25分"))
        XCTAssertTrue(unavailableLeg.waitForExistence(timeout: 10))
        XCTAssertTrue(unavailableLeg.label.contains("経路を利用できません"))

        let screenshot = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot(),
            quality: .original
        )
        screenshot.name = "Travel Leg rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        let sheet = openVenueSearchFromActivityEditor(in: app)
        let header = app.descendants(matching: .any)
            .matching(identifier: "venue-search-header")
            .firstMatch
        let searchFields = app.descendants(matching: .any)
            .matching(identifier: "venue-search-field")
        let searchField = searchFields.firstMatch
        let results = app.descendants(matching: .any)
            .matching(identifier: "venue-search-results")
            .firstMatch
        let preview = app.descendants(matching: .any)
            .matching(identifier: "venue-search-preview")
            .firstMatch
        let footer = app.descendants(matching: .any)
            .matching(identifier: "venue-search-footer")
            .firstMatch
        let confirm = app.buttons["venue-search-confirm"].firstMatch

        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(header.exists)
        XCTAssertTrue(searchField.exists)
        XCTAssertEqual(searchFields.count, 1, "検索欄は一つだけ表示される必要があります。")
        XCTAssertTrue(searchField.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier == %@ AND hasKeyboardFocus == true",
                        "venue-search-field"
                    )
                )
                .firstMatch.exists,
            "Sheet を開いた直後は検索欄にキーボードフォーカスが必要です。"
        )
        XCTAssertTrue(results.exists)
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(footer.exists)
        XCTAssertTrue(app.staticTexts["場所を検索"].firstMatch.exists)
        XCTAssertFalse(confirm.isEnabled)

        XCTAssertGreaterThanOrEqual(
            results.frame.minY,
            header.frame.maxY - 2,
            "検索結果ペインは明示ヘッダーより下に配置される必要があります。"
        )
        XCTAssertGreaterThanOrEqual(
            preview.frame.minY,
            header.frame.maxY - 2,
            "プレビューペインは明示ヘッダーより下に配置される必要があります。"
        )
        XCTAssertLessThanOrEqual(
            searchField.frame.minY,
            header.frame.maxY + 64,
            "検索欄は検索ペインの先頭に配置される必要があります。"
        )
        XCTAssertLessThan(
            searchField.frame.midX,
            preview.frame.minX,
            "検索欄は左側の検索ペイン内に配置される必要があります。"
        )
        XCTAssertGreaterThanOrEqual(
            footer.frame.minY,
            min(results.frame.maxY, preview.frame.maxY) - 2,
            "操作ボタンは分割ペインの下に固定される必要があります。"
        )

        let screenshot = XCTAttachment(
            screenshot: sheet.screenshot(),
            quality: .original
        )
        screenshot.name = "Venue search explicit macOS layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "activity-editor")
                .firstMatch.exists,
            "Escape で Venue 検索だけを閉じ、Activity 編集へ戻る必要があります。"
        )
    }

    @MainActor
    func testVenueSearchFixturesCoverStablePresentationStates() {
        for state in [
            "completion-loading",
            "completion-list",
            "result-resolving",
            "result-list",
            "no-result"
        ] {
            let app = launchUserImageFixture(additionalArguments: [
                "-tripmap-venue-search-qa-state", state
            ])
            let sheet = openVenueSearchFromActivityEditor(in: app)
            assertVenueSearchChrome(in: app, state: state)

            switch state {
            case "completion-loading":
                XCTAssertTrue(
                    app.descendants(matching: .any)[
                        "venue-search-completion-loading"
                    ].firstMatch.exists
                )
            case "completion-list":
                XCTAssertTrue(
                    app.buttons["venue-search-completion-0"].firstMatch
                        .waitForExistence(timeout: 5)
                )
                XCTAssertTrue(app.buttons["venue-search-completion-1"].firstMatch.exists)
            case "result-resolving":
                XCTAssertTrue(
                    app.descendants(matching: .any)[
                        "venue-search-result-resolving"
                    ].firstMatch.exists
                )
            case "result-list":
                XCTAssertTrue(
                    app.buttons["venue-search-result-0"].firstMatch
                        .waitForExistence(timeout: 5)
                )
                XCTAssertFalse(app.buttons["venue-search-confirm"].firstMatch.isEnabled)
            case "no-result":
                XCTAssertTrue(
                    app.descendants(matching: .any)[
                        "venue-search-no-result"
                    ].firstMatch.exists
                )
            default:
                XCTFail("未対応の Venue 検索 QA state: \(state)")
            }

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testVenueSearchFailureFixtureKeepsSheetRecoverable() {
        let app = launchUserImageFixture(additionalArguments: [
            "-tripmap-venue-search-qa-state", "failure"
        ])
        let sheet = openVenueSearchFromActivityEditor(in: app)
        let alertTitle = app.staticTexts["場所を検索できませんでした"].firstMatch

        XCTAssertTrue(alertTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["QA fixture: 場所を検索できません。"].firstMatch.exists
        )
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(alertTitle.waitForNonExistence(timeout: 5))

        XCTAssertTrue(sheet.exists)
        assertVenueSearchChrome(in: app, state: "failure")
        XCTAssertFalse(app.buttons["venue-search-confirm"].firstMatch.isEnabled)
    }

    @MainActor
    func testPlannerPlaceInsertionUsesSharedVenueSearchLayout() {
        let app = launchUserImageFixture()
        let addFromPlace = app.buttons["plan-add-from-place-button"].firstMatch

        XCTAssertTrue(addFromPlace.waitForExistence(timeout: 15))
        addFromPlace.click()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "venue-search-sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        assertVenueSearchChrome(in: app, state: "planner-place-insertion")
        XCTAssertTrue(
            app.descendants(matching: .any)["venue-search-idle"].firstMatch.exists
        )
        XCTAssertFalse(app.buttons["venue-search-confirm"].firstMatch.isEnabled)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(addFromPlace.exists)
    }

    @MainActor
    func testVenueSearchDarkAppearanceKeepsExplicitHierarchy() {
        let app = launchUserImageFixture(
            additionalArguments: [
                "-tripmap-venue-search-qa-state", "result-list",
                "-tripmap-qa-dark-appearance"
            ]
        )
        let sheet = openVenueSearchFromActivityEditor(in: app)

        assertVenueSearchChrome(in: app, state: "dark-result-list")
        XCTAssertTrue(
            app.buttons["venue-search-result-0"].firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["venue-search-confirm"].firstMatch.isEnabled)

        let screenshot = XCTAttachment(
            screenshot: sheet.screenshot(),
            quality: .original
        )
        screenshot.name = "Venue search dark appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testDoctorActivityIssueOpensTargetEditor() {
        let app = launchUserImageFixture()
        let overview = app.descendants(matching: .any)
            .matching(identifier: "trip-overview")
            .firstMatch

        XCTAssertTrue(overview.waitForExistence(timeout: 15))
        overview.click()

        let issue = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "doctor-issue-missingActivityDuration-activity-"
            )
        ).firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertTrue(issue.label.contains("ユーザー画像を確認"))
        issue.click()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "activity-editor")
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["duration-suggestion"].firstMatch.exists)
        XCTAssertTrue(app.buttons["保存"].firstMatch.exists)
    }

    @MainActor
    func testDoctorParticipantIssueOpensAssignmentPicker() {
        let app = launchUserImageFixture()
        let overview = app.descendants(matching: .any)
            .matching(identifier: "trip-overview")
            .firstMatch

        XCTAssertTrue(overview.waitForExistence(timeout: 15))
        overview.click()

        let issue = app.buttons[
            "doctor-issue-participantsNotAssigned-participants"
        ].firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        issue.click()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "participant-picker")
                .firstMatch
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["participant-picker-create-button"].firstMatch.exists)
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
            return
        }

        app.activate()
        app.typeKey("l", modifierFlags: [.command, .option])
        if userImageActivity.waitForExistence(timeout: 10) {
            return
        }
        if fixtureTrip.waitForExistence(timeout: 5) {
            fixtureTrip.click()
        }
    }

    @MainActor
    private func openVenueSearchFromActivityEditor(
        in app: XCUIApplication
    ) -> XCUIElement {
        let activityCard = app.buttons["activity-3"].firstMatch
        XCTAssertTrue(activityCard.waitForExistence(timeout: 15))
        activityCard.doubleClick()

        let venueSearchButton = app.buttons["venue-search-button"].firstMatch
        XCTAssertTrue(venueSearchButton.waitForExistence(timeout: 10))
        venueSearchButton.click()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "venue-search-sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        return sheet
    }

    @MainActor
    private func assertVenueSearchChrome(
        in app: XCUIApplication,
        state: String
    ) {
        for identifier in [
            "venue-search-header",
            "venue-search-field",
            "venue-search-results",
            "venue-search-preview",
            "venue-search-footer"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(identifier: identifier)
                    .firstMatch.exists,
                "\(identifier) must remain visible in the \(state) state."
            )
        }
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "venue-search-field")
                .count,
            1,
            "検索欄は \(state) state でも一つだけ表示される必要があります。"
        )
    }
}
