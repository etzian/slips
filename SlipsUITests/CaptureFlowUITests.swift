import XCTest

/// Capture → review → save, driven only by accessibility identifiers and labels (what VoiceOver uses).
final class CaptureFlowUITests: XCTestCase {
    @MainActor
    func testCaptureReviewSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()

        app.tabBars.buttons.element(boundBy: 1).tap()
        let sample = app.buttons["capture.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()

        let save = app.buttons["review.save"]
        XCTAssertTrue(app.buttons["review.kind"].waitForExistence(timeout: 30), "review screen did not open")
        app.buttons["review.kind"].tap()
        app.buttons["Personal"].firstMatch.tap()
        app.buttons["review.subcategory"].tap()
        app.buttons["Groceries"].firstMatch.tap()

        var tries = 0
        while !save.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Back to the capture start, and the slip is in the library.
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["MAGASIN FICTIF"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testFirstRunShowsOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-firstRun"]
        app.launch()
        let start = app.buttons["firstRun.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
