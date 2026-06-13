//
//  kodai_macosUITests.swift
//  kodai_macosUITests
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//

import XCTest

final class kodai_macosUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testGlassBoxNavigationAndThemes() throws {
        let app = XCUIApplication()
        app.launch()

        let glassBoxButton = app.buttons["glassBox.sidebar"]
        XCTAssertTrue(glassBoxButton.waitForExistence(timeout: 5))
        glassBoxButton.click()

        let glassBoxDetail = app.scrollViews["glassBox.detail"]
        XCTAssertTrue(glassBoxDetail.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["glassBox.status"].exists)
        XCTAssertTrue(app.staticTexts["Model Pulse"].exists)
        XCTAssertTrue(app.staticTexts["Context Pressure"].exists)
        XCTAssertTrue(app.staticTexts["Response Heat"].exists)
        XCTAssertTrue(app.staticTexts["Focus Lock"].exists)
        glassBoxDetail.scroll(byDeltaX: 0, deltaY: -240)
        XCTAssertTrue(app.staticTexts["Task Pressure"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Readiness"].waitForExistence(timeout: 2))

        app.buttons["glassBox.backToChat"].click()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 3))

        let settingsButton = app.buttons["settings.open"]
        XCTAssertTrue(settingsButton.exists)
        settingsButton.click()

        let themePicker = app.popUpButtons["settings.theme"]
        XCTAssertTrue(themePicker.waitForExistence(timeout: 3))

        themePicker.click()
        app.menuItems["Blue Gradient"].click()

        themePicker.click()
        app.menuItems["Sage Glass"].click()

        glassBoxButton.click()
        XCTAssertTrue(app.scrollViews["glassBox.detail"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
