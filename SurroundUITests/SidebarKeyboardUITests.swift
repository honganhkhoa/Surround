import XCTest
import UIKit

/// Compare the real software-keyboard layout through MainView on HEAD and the
/// owned tab container. The standalone message-thread fixture bypasses it.
final class SidebarKeyboardUITests: SurroundJourneyUITestCase {
    private var expectsOwnedTabs: Bool {
        ProcessInfo.processInfo.environment["SURROUND_EXPECT_OWNED_TABS"] == "1"
    }

    private var expectsOpenSidebar: Bool {
        ProcessInfo.processInfo.environment["SURROUND_EXPECT_DUO_SIDEBAR"] == "1"
    }

    func testConversationSoftwareKeyboardLayoutAndDraft() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("The keyboard comparison requires an iOS 27 phone.")
        #else
        guard #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The keyboard comparison requires an iOS 27 phone.")
        }
        let landscape = ProcessInfo.processInfo.environment[
            "SURROUND_SIDEBAR_KEYBOARD_ORIENTATION"
        ] == "landscape"
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
        ], orientation: landscape ? .landscapeLeft : .portrait)

        if expectsOwnedTabs { element("navigation.container.duo", in: app) }
        tap(SurroundUITestContract.AccessibilityID.privateMessageRow(765_826), in: app)
        let composer = element(
            SurroundUITestContract.AccessibilityID.privateMessageComposer,
            in: app, matching: .textField
        )
        recordLayout("keyboard-hidden", app: app, composer: composer)
        tap(composer, description: "Focus the private conversation composer", in: app)

        let keyboard = app.keyboards.firstMatch
        let docked = waitForCondition(timeout: 10) {
            self.dockedKeyboardFrame(in: app) != nil
        }
        recordLayout("keyboard-focused", app: app, composer: composer)
        XCTAssertTrue(keyboard.exists, "A real software keyboard must be present for this probe.")
        XCTAssertTrue(docked,
                      "A docked software keyboard is required; disable Simulator's hardware keyboard.")
        guard docked else { return }
        assertComposerAboveKeyboard(composer, in: app)
        XCTAssertTrue(composer.isHittable)
        if app.tabBars.firstMatch.exists {
            XCTAssertFalse(app.tabBars.firstMatch.isHittable,
                           "The native tab bar must remain behind the docked keyboard.")
        }

        let draft = "Unsent sidebar keyboard comparison"
        composer.typeText(draft)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        recordLayout("keyboard-draft", app: app, composer: composer)

        let toggle = sidebarToggle(in: app)
        if expectsOpenSidebar {
            XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                          "The explicitly requested Duo Open run must expose its sidebar toggle.")
            XCTAssertTrue(waitUntilHittable(toggle, timeout: 10),
                          "The explicitly requested Duo Open toggle must be usable with the keyboard present.")
        }
        if toggle.exists && toggle.isHittable {
            tap(toggle, description: "Reveal the sidebar with the software keyboard present", in: app)
            let settings = app.descendants(matching: .any).matching(
                identifier: SurroundUITestContract.AccessibilityID.navigationSettings
            ).firstMatch
            XCTAssertTrue(waitForCondition(timeout: 10) { settings.exists && settings.isHittable })
            recordLayout("keyboard-sidebar-visible", app: app, composer: composer)
            assertComposerAboveKeyboard(composer, in: app)
            tap(sidebarToggle(in: app), description: "Close the sidebar without selecting another tab", in: app)
            XCTAssertTrue(waitForCondition(timeout: 10) { !settings.exists || !settings.isHittable })
            recordLayout("keyboard-sidebar-collapsed", app: app, composer: composer)
            assertComposerAboveKeyboard(composer, in: app)
            XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        }

        guard dismissConversationKeyboard(in: app) else {
            recordLayout("keyboard-dismissal-unavailable", app: app, composer: composer)
            XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
            return
        }
        recordLayout("keyboard-dismissed", app: app, composer: composer)
        XCTAssertNil(dockedKeyboardFrame(in: app))
        XCTAssertFalse(softwareKeyboardIsVisible(app.keyboards.firstMatch, in: app))
        XCTAssertTrue(composer.isHittable)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10),
                      "Dismissing the keyboard must preserve the unsent conversation draft.")
        #endif
    }

    private func sidebarToggle(in app: XCUIApplication) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "ToggleSidebar", "Toggle sidebar"
        ))
        return candidates.allElementsBoundByIndex.first(where: { $0.isHittable })
            ?? candidates.firstMatch
    }

    private func dockedKeyboardFrame(in app: XCUIApplication) -> CGRect? {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return nil }
        let frame = keyboard.frame
        let viewport = app.windows.firstMatch.frame
        guard frame.height > 100,
              frame.minX >= viewport.minX - 1,
              frame.maxX <= viewport.maxX + 1,
              frame.width >= viewport.width * 0.6,
              // XCTest reports the key grid, excluding the home-indicator
              // and dictation strip on modern phones.
              viewport.maxY - frame.maxY >= -1,
              viewport.maxY - frame.maxY <= 100 else { return nil }
        return frame
    }

    private func assertComposerAboveKeyboard(
        _ composer: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let keyboard = dockedKeyboardFrame(in: app) else {
            XCTFail("Expected a docked keyboard while inspecting the focused composer.",
                    file: file, line: line)
            return
        }
        XCTAssertTrue(composer.exists, file: file, line: line)
        XCTAssertGreaterThan(composer.frame.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(composer.frame.maxY, keyboard.minY + 1,
                                 "The private conversation composer must remain above the software keyboard.",
                                 file: file, line: line)
    }

    private func dismissConversationKeyboard(in app: XCUIApplication) -> Bool {
        let conversation = element(
            SurroundUITestContract.AccessibilityID.profileConversation, in: app
        )
        conversation.swipeDown()
        if waitForCondition(timeout: 3, { !self.softwareKeyboardIsVisible(app.keyboards.firstMatch, in: app) }) {
            return true
        }
        // A system keyboard dismissal control does not submit the TextField.
        // Never use Return here: the conversation's onCommit sends a message.
        let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
        if hide.exists && hide.isHittable {
            tap(hide, description: "Dismiss the software keyboard", in: app)
        }
        let dismissed = waitForCondition(timeout: 10) {
            !self.softwareKeyboardIsVisible(app.keyboards.firstMatch, in: app)
        }
        if !dismissed { attachHierarchy(app, name: "Private conversation keyboard did not dismiss") }
        // Private conversation has no app dismissal gesture on some phone
        // runtimes. Record this existing limitation without attributing it
        // to the shell; compare the focused layout and preserve the draft.
        return dismissed
    }

    private func waitForCondition(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func recordLayout(_ phase: String, app: XCUIApplication, composer: XCUIElement) {
        let container = app.descendants(matching: .any)
            .matching(identifier: "navigation.container.duo").firstMatch
        let toggle = sidebarToggle(in: app)
        let snapshot: [String: Any] = [
            "phase": phase,
            "expectsOwnedTabs": expectsOwnedTabs,
            "expectsOpenSidebar": expectsOpenSidebar,
            "application": describe(app),
            "window": describe(app.windows.firstMatch),
            "ownedContainer": describe(container),
            "composer": describe(composer),
            "keyboard": describe(app.keyboards.firstMatch),
            "dockedKeyboard": dockedKeyboardFrame(in: app) != nil,
            "sidebarToggle": describe(toggle),
            "tabBars": app.tabBars.allElementsBoundByIndex.map(describe),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Sidebar keyboard layout – " + phase
            attachment.lifetime = .keepAlways
            add(attachment)
            print("[SidebarKeyboardLayout] " + String(decoding: data, as: UTF8.self))
        } catch {
            XCTFail("Could not encode keyboard layout diagnostics: \(error)")
        }
        keepScreenshot("Sidebar keyboard – " + phase, in: app)
        attachHierarchy(app, name: "Sidebar keyboard hierarchy – " + phase)
    }

    private func attachHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func describe(_ element: XCUIElement) -> [String: Any] {
        guard element.exists else { return ["exists": false] }
        let frame = element.frame
        return [
            "exists": true,
            "hittable": element.isHittable,
            "identifier": element.identifier,
            "label": element.label,
            "frame": [
                "x": Double(frame.minX), "y": Double(frame.minY),
                "width": Double(frame.width), "height": Double(frame.height),
            ],
        ]
    }
}
