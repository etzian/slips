import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 3)
    }
}
