import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["placeholder"].waitForExistence(timeout: 10)
            || app.staticTexts.firstMatch.waitForExistence(timeout: 10))
    }
}
