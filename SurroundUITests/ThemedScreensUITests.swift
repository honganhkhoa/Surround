//
//  ThemedScreensUITests.swift
//  SurroundUITests
//
//  Screens beyond Home and Settings that wear the theme on the whole app
//  (Public games and Game history), and the whole app turning dark under a
//  dark-only theme, including screens that do not wear themes yet.
//

import XCTest
import UIKit

final class ThemedScreensUITests: SurroundJourneyUITestCase {
    private typealias ID = SurroundUITestContract.AccessibilityID

    /// Public games and Game history wear the theme on the whole app: its
    /// scene behind the list and each game on a card, as on Home. In Light
    /// Mode, Nebula & Pearl's midnight scene shows the theme is there, and
    /// Classic keeps its plain light pages; the captures are for review.
    func testPublicGamesAndHistoryWearTheTheme() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("Covered on iPhone and iPad; Mac shares the iPad layout.")
        #else
        let device = XCUIDevice.shared
        let original = device.appearance
        addTeardownBlock { device.appearance = original }
        device.appearance = .light

        for theme in ["rakedGarden", "nebulaPearl", "standard"] {
            let app = launchApp(additionalLaunchArguments: [
                SurroundUITestContract.homeFinishedOnlyLaunchArgument,
                SurroundUITestContract.themeLaunchArgument, theme,
            ], orientation: .portrait)
            element(ID.screenHome, in: app)
            if UIDevice.current.userInterfaceIdiom == .pad { restoreFullSizeWindow(in: app) }

            let viewAll = elementAfterScrolling(ID.homeHistoryViewAll, in: app, matching: .button)
            tap(viewAll, description: "Open the full game history", in: app)
            element(ID.screenGameHistory, in: app)
            element(ID.homeHistoryGame(SurroundUITestContract.homeFinishedOnlyHistoryGameID), in: app)
            keepScreenshot("Game history – \(theme)", in: app)
            assertPage(element(ID.screenGameHistory, in: app, matching: .scrollView), wears: theme)

            selectMainNavigation(ID.navigationPublicGames, in: app)
            element(ID.screenPublicGames, in: app)
            let game = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "publicGames.game.")).firstMatch
            XCTAssertTrue(game.waitForExistence(timeout: 10), "\(theme): Public games lists the fixture game")
            keepScreenshot("Public games – \(theme)", in: app)
            assertPage(element(ID.screenPublicGames, in: app, matching: .scrollView), wears: theme)
            app.terminate()
        }
        #endif
    }

    /// A dark-only theme on the whole app turns every screen dark, here
    /// Messages, which does not wear themes yet. With Games only, Messages
    /// keeps the system's Light Mode.
    func testDarkOnlyThemeDarkensTheWholeApp() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The Mac follows the same window appearance; this checks the Simulator.")
        #else
        let device = XCUIDevice.shared
        let original = device.appearance
        addTeardownBlock { device.appearance = original }
        device.appearance = .light

        for (scope, arguments, expectsDark) in [
            ("Whole app", [String](), true),
            ("Games only", [SurroundUITestContract.themeGamesOnlyLaunchArgument], false),
        ] {
            let app = launchApp(additionalLaunchArguments: arguments + [
                SurroundUITestContract.themeLaunchArgument, "nebulaPearl",
            ], orientation: .portrait)
            element(ID.screenHome, in: app)
            if UIDevice.current.userInterfaceIdiom == .pad { restoreFullSizeWindow(in: app) }
            selectMainNavigation(ID.navigationMessages, in: app)
            let messages = element(ID.screenMessages, in: app)
            Thread.sleep(forTimeInterval: 1)
            keepScreenshot("Messages – Nebula & Pearl, \(scope)", in: app)
            guard let brightness = meanBrightness(of: messages) else {
                XCTFail("\(scope): Messages could be measured")
                return
            }
            if expectsDark {
                XCTAssertLessThan(brightness, 0.35, "\(scope): Messages turns dark with Nebula & Pearl (\(brightness))")
            } else {
                XCTAssertGreaterThan(brightness, 0.6, "\(scope): Messages keeps Light Mode (\(brightness))")
            }
            app.terminate()
        }
        #endif
    }

    /// In Light Mode, Nebula & Pearl's page is its midnight scene and
    /// Classic's is plain and light. (Raked Garden's light sand is left to
    /// the captures.)
    private func assertPage(_ page: XCUIElement, wears theme: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard theme != "rakedGarden" else { return }
        guard let brightness = meanBrightness(of: page) else {
            XCTFail("\(theme): the page could be measured", file: file, line: line)
            return
        }
        if theme == "nebulaPearl" {
            XCTAssertLessThan(brightness, 0.35, "Nebula & Pearl's scene fills the page (\(brightness))", file: file, line: line)
        } else {
            XCTAssertGreaterThan(brightness, 0.6, "Classic keeps the plain light page (\(brightness))", file: file, line: line)
        }
    }

    /// The mean luminance of the middle of an element's rendering, from 0
    /// (black) to 1 (white), ignoring its edges.
    private func meanBrightness(of element: XCUIElement) -> Double? {
        guard let image = element.screenshot().image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        var sum = 0.0
        var count = 0
        for y in 10..<54 {
            for x in 6..<58 {
                let index = (y * size + x) * 4
                sum += (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1])
                        + 0.0722 * Double(pixels[index + 2])) / 255
                count += 1
            }
        }
        return sum / Double(count)
    }
}
