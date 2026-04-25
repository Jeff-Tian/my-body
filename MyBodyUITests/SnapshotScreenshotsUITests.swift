//  SnapshotScreenshotsUITests.swift
//  MyBodyUITests
//
//  Drives fastlane snapshot screenshots for 身记.
//
import XCTest

final class SnapshotScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for el in elements {
                if el.exists { return el }
            }
            usleep(150_000)
        }
        return nil
    }

    @MainActor
    func testGenerateScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        // Inject sample data so the home / trends screens look realistic even on a fresh simulator.
        app.launchArguments += ["-UITestScreenshots", "1"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App not foreground")

        // Tab bar buttons (system-localized). Try both zh-Hans and en fallbacks.
        let tabBars = app.tabBars
        XCTAssertTrue(tabBars.firstMatch.waitForExistence(timeout: 15), "Tab bar not found")

        let homeTab = waitForAny([
            tabBars.buttons["首页"],
            tabBars.buttons["Home"],
            tabBars.buttons.element(boundBy: 0)
        ], timeout: 10)
        let trendsTab = waitForAny([
            tabBars.buttons["趋势"],
            tabBars.buttons["Trends"],
            tabBars.buttons.element(boundBy: 1)
        ], timeout: 10)
        let settingsTab = waitForAny([
            tabBars.buttons["设置"],
            tabBars.buttons["Settings"],
            tabBars.buttons.element(boundBy: 2)
        ], timeout: 10)

        // 1) Home
        homeTab?.tap()
        usleep(800_000)
        snapshot("01-home")

        // 2) Trends (history list)
        trendsTab?.tap()
        usleep(800_000)
        snapshot("02-trends")

        // 3) Detail — tap the first history row on the Trends tab to push DetailView.
        // NavigationLink's accessibility element type varies by iOS version (button / link /
        // other), so match by identifier across all descendant types.
        let historyRow = app.descendants(matching: .any)["history-row-0"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 8), "history-row-0 not found on Trends tab")
        // Row sits below a long chart; scroll it fully into view before tapping.
        var scrollAttempts = 0
        while !historyRow.isHittable && scrollAttempts < 6 {
            app.swipeUp()
            usleep(300_000)
            scrollAttempts += 1
        }
        // Coordinate tap is more reliable than `.tap()` for SwiftUI NavigationLink on iOS 26.
        historyRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Confirm push occurred: the row element should no longer be reachable on screen.
        let pushed = !historyRow.waitForExistence(timeout: 3) || !historyRow.isHittable
        XCTAssertTrue(pushed, "DetailView did not push after tapping history-row-0")
        usleep(700_000)
        snapshot("03-detail")
        // Pop back so the Settings snapshot starts from a clean state.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists { backButton.tap() }
        usleep(400_000)

        // 4) Settings
        settingsTab?.tap()
        usleep(600_000)
        snapshot("04-settings")

        // Back to Home for a final clean shot (captures empty-state variant if needed).
        homeTab?.tap()
    }
}
