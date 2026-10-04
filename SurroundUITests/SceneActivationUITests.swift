import XCTest
import UIKit

#if !targetEnvironment(macCatalyst)
/// Real Home Screen activation of the offline app, including UIKit session identity.
final class SceneActivationUITests: SurroundJourneyUITestCase {
    private struct SceneSnapshot: Decodable {
        let sessionID: String
        let sessionIDs: [String]
        let isActive: Bool
        let supportsMultipleScenes: Bool
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["SURROUND_RUN_SCENE_ACTIVATION_TESTS"] == "1" else {
            throw XCTSkip("Home Screen activation requires explicit opt-in on a dedicated simulator.")
        }
    }

    private func launchSceneFixture() throws -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.sceneActivationLaunchArgument,
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
            SurroundUITestContract.messagesContentLaunchArgument,
        ], orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func scene(in app: XCUIApplication, stage: String) throws -> SceneSnapshot {
        let probe = app.descendants(matching: .any)
            .matching(identifier: "test.sceneActivation").firstMatch
        let activeProbe = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            probe.exists && (probe.value as? String)?.contains("\"isActive\":true") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [activeProbe], timeout: 15), .completed,
                       "Expected an active scene probe at \(stage).")
        let json = try XCTUnwrap(probe.value as? String)
        let attachment = XCTAttachment(string: json)
        attachment.name = stage
        attachment.lifetime = .keepAlways
        add(attachment)
        let snapshot = try JSONDecoder().decode(SceneSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.isActive, "Expected an active scene at \(stage): \(json)")
        return snapshot
    }

    private func returnThroughHomeScreen(_ app: XCUIApplication) {
        backgroundToHomeScreen(app)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Surround"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "Expected this isolated app's Home Screen icon.")
        icon.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func backgroundToHomeScreen(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Some Duo runtimes do not deliver the injected hardware Home button.
        // Activate the system Home Screen; the return still taps its actual icon.
        if !app.wait(for: .runningBackground, timeout: 3) { springboard.activate() }
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10), "The app must actually background before a return.")
        XCTAssertTrue(springboard.icons["Surround"].firstMatch.waitForExistence(timeout: 10))
    }

    func testHomeScreenReturnPreservesConversationAndScene() throws {
        let app = try launchSceneFixture()
        let original = try scene(in: app, stage: "original scene")
        tap("messages.friend.message.801001", in: app, matching: .button)
        let peer = element(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(801001), in: app)
        XCTAssertTrue(peer.label.contains("BambooPath"))
        let composer = element(SurroundUITestContract.AccessibilityID.privateMessageComposer, in: app, matching: .textField)
        XCTAssertEqual(composer.placeholderValue, "Message BambooPath")
        composer.tap()
        let draft = "Scene return draft"
        composer.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        for cycle in 1...3 {
            returnThroughHomeScreen(app)
            let returned = try scene(in: app, stage: "Home Screen return \(cycle)")
            XCTAssertEqual(returned.sessionIDs, original.sessionIDs, "Home Screen return must not create a session.")
            XCTAssertEqual(returned.sessionID, original.sessionID, "Return must activate the original scene.")
            XCTAssertTrue(peer.exists && peer.label.contains("BambooPath"), "The original conversation peer must remain selected.")
            XCTAssertEqual(composer.placeholderValue, "Message BambooPath")
            XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10), "The conversation draft must remain in its original window.")
        }
        keepScreenshot("Conversation retained after Home Screen returns", in: app)
    }

}
#endif
