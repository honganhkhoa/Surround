import XCTest
import UIKit
import Vision

/// Offline journeys through MainView's real Messages tab. Independent device
/// launches cover fixed geometry; native Duo transitions remain separate.
final class MessagesNavigationUITests: SurroundJourneyUITestCase {
    private let friendID = SurroundUITestContract.profileFixturePickerFriendID
    private let searchPlayerID = SurroundUITestContract.profileFixtureOpponentID
    private let firstPeerID = 765_826
    private let secondPeerID = 955_348

    private enum ConversationPresentation { case wideRoot, nativePush }

    func testMessagesReadLoadingStatusKeepsCachedInboxGeometry() {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesLoadingLaunchArgument,
            SurroundUITestContract.friendshipLaunchArgument,
        ])
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        var anchors = messagesLoadingAnchors(in: app)
        anchors["scroll"] = element("messages.inboxScroll", in: app, matching: .scrollView)
        anchors["request"] = element(SurroundUITestContract.AccessibilityID.friendRequestProfile(
            SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]), in: app, matching: .button)
        anchors["friend"] = element("messages.friend.message.\(friendID)", in: app, matching: .button)
        let frames = anchors.mapValues(\.frame)

        tap(SurroundUITestContract.AccessibilityID.messagesLoadingStartRead, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:1;requests:1;errors:0;search:0", in: app)
        assertMessagesLoadingStatus("Loading friends…, Loading friend requests…", in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        XCTAssertTrue(anchors["request"]!.isHittable, "A refresh must keep the cached requests usable.")
        keepScreenshot("Cached inbox during both read activities", in: app)

        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndFriends, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:1;errors:0;search:0", in: app)
        assertMessagesLoadingStatus("Loading friend requests…", in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndRequests, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        keepScreenshot("Cached inbox after both read activities", in: app)
    }

    func testMessagesEmptyReadLoadingErrorAndRetryKeepNavigationStable() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesLoadingLaunchArgument],
            launchEnvironment: ["SURROUND_UI_MESSAGES_LOADING_INITIAL": "1",
                                "SURROUND_UI_MESSAGES_LOADING_EMPTY": "1"])
        assertMessagesLoadingFixture("friends:1;requests:1;errors:0;search:0", in: app)
        assertMessagesLoadingStatus("Loading friends…, Loading friend requests…", in: app)
        let empty = app.staticTexts["No conversations yet"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10) && empty.isHittable,
                      "Initial reads must retain the readable empty inbox.")
        var anchors = messagesLoadingAnchors(in: app, includesConversation: false)
        anchors["scroll"] = element("messages.inboxScroll", in: app, matching: .scrollView)
        anchors["empty"] = empty
        let frames = anchors.mapValues(\.frame)
        keepScreenshot("Initial empty inbox during read activity", in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndFriends, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:1;errors:0;search:0", in: app)
        assertMessagesLoadingStatus("Loading friend requests…", in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndRequests, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)

        tap(SurroundUITestContract.AccessibilityID.messagesLoadingStartRead, in: app, matching: .button)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingFailRead, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:2;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        XCTAssertTrue(app.staticTexts["Couldn’t load friends"].exists)
        XCTAssertTrue(app.staticTexts["Couldn’t load friend requests"].exists)
        keepScreenshot("Empty inbox preserves both read errors and retry", in: app)
        tap(app.buttons["Try Again"].firstMatch, description: "Retry the failed inbox reads", in: app)
        assertMessagesLoadingFixture("friends:1;requests:1;errors:0;search:0", in: app)
        assertMessagesLoadingStatus("Loading friends…, Loading friend requests…", in: app)
        XCTAssertFalse(app.staticTexts["Couldn’t load friends"].exists)
        XCTAssertFalse(app.staticTexts["Couldn’t load friend requests"].exists)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndFriends, in: app, matching: .button)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingEndRequests, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        keepScreenshot("Empty inbox after successful retry state", in: app)
    }

    func testMessagesSearchLoadingCancelAndEmptyResultKeepNavigationStable() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesLoadingLaunchArgument])
        let anchors = messagesLoadingAnchors(in: app)
        let restingFrames = anchors.mapValues(\.frame)
        setSearch("Copper", in: app)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:1", in: app)
        assertMessagesLoadingStatus("Searching…", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        keepScreenshot("Held player search uses the navigation activity slot", in: app)
        cancelInboxSearch(in: app)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        XCTAssertTrue(waitForCondition { !app.keyboards.firstMatch.exists })
        assertMessagesLoadingFramesAfterSearchCancel(anchors, equalTo: restingFrames, in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingReleaseSearch, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        XCTAssertEqual(anchors["search"]!.value as? String, "")
        XCTAssertFalse(query("messages.cancelPlayerSearch", in: app).exists,
                       "Releasing a canceled search must not restore its discovery presentation.")

        let emptyQuery = "NoSuchMessagesLoadingPlayer777"
        setSearch(emptyQuery, in: app)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:1", in: app)
        assertMessagesLoadingStatus("Searching…", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let keyboardFrames = anchors.mapValues(\.frame)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingReleaseSearch, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        let emptyHeading = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "No Results for", emptyQuery)).firstMatch
        let emptyHeadingVisible = emptyHeading.waitForExistence(timeout: 10)
            && waitUntilHittable(emptyHeading, timeout: 10)
        if !emptyHeadingVisible {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Loaded empty search – native heading hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            keepScreenshot("Loaded empty search – native heading assertion", in: app)
        }
        XCTAssertTrue(emptyHeadingVisible, "The loaded empty result must show the native heading for this exact query.")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(emptyHeading.frame.maxY, keyboard.frame.minY + 1,
                                 "The loaded empty heading must be readable above the software keyboard.")
        assertMessagesLoadingFrames(anchors, equalTo: keyboardFrames, in: app)
        keepScreenshot("Loaded empty player search keeps keyboard and detail geometry", in: app)
        cancelInboxSearch(in: app)
        XCTAssertTrue(waitForCondition { !app.keyboards.firstMatch.exists })
        assertMessagesLoadingStatus(nil, in: app)
        assertMessagesLoadingFramesAfterSearchCancel(anchors, equalTo: restingFrames, in: app)
    }

    func testMessagesSearchLoadingFailureAndRetryKeepNavigationStable() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesLoadingLaunchArgument],
            launchEnvironment: ["SURROUND_UI_MESSAGES_SEARCH_FAIL_ONCE": "1"])
        let anchors = messagesLoadingAnchors(in: app)
        setSearch("Copper", in: app)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:1", in: app)
        assertMessagesLoadingStatus("Searching…", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let frames = anchors.mapValues(\.frame)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingReleaseSearch, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        XCTAssertTrue(app.staticTexts["Couldn’t search players"].waitForExistence(timeout: 10))
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        keepScreenshot("Player search failure clears activity and preserves retry", in: app)
        tap(app.buttons["Try Again"].firstMatch, description: "Retry the failed player search", in: app)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:1", in: app)
        assertMessagesLoadingStatus("Searching…", in: app)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        tap(SurroundUITestContract.AccessibilityID.messagesLoadingReleaseSearch, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertFalse(app.staticTexts["Couldn’t search players"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        assertMessagesLoadingFrames(anchors, equalTo: frames, in: app)
        keepScreenshot("Player search retry loads results without moving navigation", in: app)
    }

    private func assertMessagesLoadingFixture(_ state: String, in app: XCUIApplication) {
        let probe = element(SurroundUITestContract.AccessibilityID.messagesLoadingStartRead, in: app, matching: .button)
        XCTAssertTrue(waitForValue(state, in: probe, timeout: 10),
                      "The opt-in fixture must expose the actual read flags, errors and held search count.")
    }

    private func assertMessagesLoadingStatus(_ label: String?, in app: XCUIApplication) {
        let statusID = "messages.loadingStatus"
        let status = query(statusID, in: app)
        if let label {
            // SwiftUI can give the spinner's wrapper the same identifier.
            // Count the actual activity widget while idle still excludes all IDs.
            let activeStatus = app.activityIndicators.matching(identifier: statusID).firstMatch
            let announced = waitForCondition { activeStatus.exists && activeStatus.label == label }
            if !announced { keepMessagesLoadingAccessibilityFailure("active announcement", in: app) }
            XCTAssertTrue(announced,
                          "The fixed navigation slot must announce the active operation.")
            XCTAssertTrue(app.navigationBars.activityIndicators
                .matching(identifier: statusID).firstMatch.exists,
                "Background activity must belong to native navigation instead of a scroll section.")
            let count = app.activityIndicators.matching(identifier: statusID).count
            if count != 1 { keepMessagesLoadingAccessibilityFailure("active identifier count \(count)", in: app) }
            XCTAssertEqual(count, 1)
        } else {
            let hidden = waitForCondition { !status.exists }
            if !hidden { keepMessagesLoadingAccessibilityFailure("inactive identifier remains", in: app) }
            XCTAssertTrue(hidden, "Inactive activity must be hidden from accessibility.")
            let slots = app.descendants(matching: .any).matching(identifier: "messages.loadingSlot")
                .allElementsBoundByIndex
            if slots.contains(where: { !$0.label.isEmpty }) {
                keepMessagesLoadingAccessibilityFailure("inactive slot retains a loading label", in: app)
            }
            for slot in slots {
                XCTAssertEqual(slot.label, "", "An enumerated inactive slot must clear its previous activity label.")
            }
        }
    }

    private func keepMessagesLoadingAccessibilityFailure(_ reason: String, in app: XCUIApplication) {
        let matches = ["messages.loadingStatus", "messages.loadingSlot"].flatMap { identifier in
            app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
        }
        let description = matches.enumerated().map { index, status in
            "match \(index): type=\(status.elementType.rawValue), hittable=\(status.isHittable), frame=\(status.frame)\n"
                + status.debugDescription
        }.joined(separator: "\n\n")
        let status = XCTAttachment(string: description)
        status.name = "Messages loading status – \(reason)"
        status.lifetime = .keepAlways
        add(status)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Messages loading hierarchy – \(reason)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        keepScreenshot("Messages loading accessibility failure – \(reason)", in: app)
    }

    private func messagesLoadingAnchors(in app: XCUIApplication,
                                       includesConversation: Bool = true) -> [String: XCUIElement] {
        var anchors = ["search": element("messages.playerSearchField", in: app, matching: .textField),
                       "navigation": app.navigationBars["Messages"].firstMatch]
        if usesColumns(in: app) {
            if includesConversation {
                anchors["composer"] = assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
            }
            anchors["detail"] = element("messages.detailPane", in: app)
        }
        return anchors
    }

    private func assertMessagesLoadingFramesAfterSearchCancel(_ anchors: [String: XCUIElement],
                                                              equalTo frames: [String: CGRect], in app: XCUIApplication) {
        // Retain the full intrinsic-size evidence even when the center check passes.
        let actualFrames = messagesLoadingFramesWithDiagnostics(anchors, equalTo: frames, in: app)
        let fixedAnchors = anchors.filter { $0.key != "search" }
        assertMessagesLoadingFrames(fixedAnchors, equalTo: frames, in: app)
        let actual = actualFrames["search"]!
        let expected = frames["search"]!
        // After first focus, the native text field's accessibility height changes
        // about its fixed center. Cancellation must preserve that center and width;
        // activity completion/error/retry still checks every frame component.
        XCTAssertEqual(actual.midX, expected.midX, accuracy: 1, "Search must retain its horizontal center after cancellation.")
        XCTAssertEqual(actual.midY, expected.midY, accuracy: 1, "Search must retain its vertical center after cancellation.")
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, "Search must retain its width after cancellation.")
    }

    private func assertMessagesLoadingFrames(_ anchors: [String: XCUIElement],
                                             equalTo frames: [String: CGRect], in app: XCUIApplication) {
        let actualFrames = messagesLoadingFramesWithDiagnostics(anchors, equalTo: frames, in: app)
        for name in anchors.keys.sorted() {
            let actual = actualFrames[name]!
            let expected = frames[name]!
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, "\(name) must retain its horizontal position.")
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, "\(name) must retain its vertical position.")
            XCTAssertEqual(actual.width, expected.width, accuracy: 1, "\(name) must retain its width.")
            XCTAssertEqual(actual.height, expected.height, accuracy: 1, "\(name) must retain its height.")
        }
    }

    private func messagesLoadingFramesWithDiagnostics(_ anchors: [String: XCUIElement],
                                                      equalTo frames: [String: CGRect], in app: XCUIApplication) -> [String: CGRect] {
        let actualFrames = anchors.mapValues(\.frame)
        let moved = anchors.keys.contains { name in
            let actual = actualFrames[name]!
            let expected = frames[name]!
            return abs(actual.minX - expected.minX) > 1 || abs(actual.minY - expected.minY) > 1
                || abs(actual.width - expected.width) > 1 || abs(actual.height - expected.height) > 1
        }
        if moved {
            func describe(_ frame: CGRect) -> [String: Double] {
                ["x": Double(frame.minX), "y": Double(frame.minY),
                 "width": Double(frame.width), "height": Double(frame.height),
                 "centerX": Double(frame.midX), "centerY": Double(frame.midY)]
            }
            let snapshot = anchors.keys.reduce(into: [String: [String: [String: Double]]]()) { result, name in
                result[name] = ["expected": describe(frames[name]!), "actual": describe(actualFrames[name]!)]
            }
            if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "Messages loading geometry – full anchor frames"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Messages loading geometry – hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            keepScreenshot("Messages loading geometry – before frame assertion", in: app)
        }
        return actualFrames
    }

    func testInitialShortHistoryOpeningStaysAboveComposerWithoutInput() throws {
        try assertInitialHistoryOpening(mode: nil, delay: "0", interval: "0")
    }

    func testInitialTwoMessageOpeningStaysAboveComposerWithoutInput() throws {
        try assertInitialHistoryOpening(mode: nil, delay: "0", interval: "0", messageCount: 2)
    }

    func testInitialThreeMessageOpeningStaysAboveComposerWithoutInput() throws {
        try assertInitialHistoryOpening(mode: nil, delay: "0", interval: "0", messageCount: 3)
    }

    func testInitialEmptyHistoryFastReplayStaysAboveComposerWithoutInput() throws {
        try assertInitialHistoryOpening(mode: "empty", delay: "0.02", interval: "0.03")
    }

    func testInitialEmptyHistoryStaggeredReplayStaysAboveComposerWithoutInput() throws {
        try assertInitialHistoryOpening(mode: "empty", delay: "0.2", interval: "0.35")
    }

    private func assertInitialHistoryOpening(mode: String?, delay: String, interval: String,
                                            messageCount: Int = 4) throws {
        var arguments = [SurroundUITestContract.messagesShortHistoryLaunchArgument,
                         SurroundUITestContract.messagesInitialOpeningLaunchArgument]
        if mode != nil { arguments.append(SurroundUITestContract.messagesDelayedHistoryLaunchArgument) }
        var environment = ["SURROUND_UI_MESSAGES_VIDEO_TEXT_SHAPE": "1",
                           "SURROUND_UI_MESSAGES_REPLAY_DELAY": delay,
                           "SURROUND_UI_MESSAGES_REPLAY_INTERVAL": interval,
                           "SURROUND_UI_MESSAGES_SHORT_COUNT": String(messageCount)]
        if let mode { environment["SURROUND_UI_MESSAGES_REPLAY_MODE"] = mode }
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
            SurroundUITestContract.messagesContentLaunchArgument,
        ] + arguments, launchEnvironment: environment, orientation: .portrait)
        // These portrait fixtures occupy the full window. Decide the expected
        // presentation independently of retained root elements behind a push.
        let window = app.windows.firstMatch.frame
        let expectsColumns = window.width >= 660
        let activeComposer = assertConversation("hakhoa", peerID: firstPeerID,
            presentation: expectsColumns ? .wideRoot : .nativePush, in: app)
        let composer: XCUIElement
        let transcript: XCUIElement
        if expectsColumns {
            let detail = element("messages.detailPane", in: app)
            composer = detail.textFields.matching(identifier:
                SurroundUITestContract.AccessibilityID.privateMessageComposer).firstMatch
            XCTAssertTrue(waitUntilHittable(composer, timeout: 10),
                          "Initial wide opening must leave the root detail composer usable.")
            XCTAssertEqual(composer.frame, activeComposer.frame,
                           "The root detail must own the only active composer.")
            XCTAssertTrue(detail.frame.contains(composer.frame) && window.contains(composer.frame))
            transcript = rootTranscript(in: app)
        } else {
            composer = activeComposer
            transcript = nativeTranscript(over: window, in: app)
            XCTAssertNotNil(visibleBack(from: "hakhoa", in: app),
                            "Initial compact opening must use the native conversation push.")
        }
        let latestText = messageCount == 2 ? "Hi" : messageCount == 3
            ? "[surround qa surround-e2e-browser-msg-20261002t123634z-def9830c 1/2] phone to duo/ipad delivery check."
            : SurroundUITestContract.messagesVideoHistoryLatestText
        let latest = transcript.staticTexts.matching(NSPredicate(format: "label == %@", latestText)).firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        if expectsColumns {
            assertWideRoot(in: app)
            let inbox = element("messages.inboxPane", in: app)
            let search = inbox.textFields["messages.playerSearchField"].firstMatch
            let row = inbox.buttons[SurroundUITestContract.AccessibilityID.privateMessageRow(firstPeerID)].firstMatch
            XCTAssertTrue(waitUntilHittable(search, timeout: 10) && window.contains(search.frame),
                          "Initial wide opening must leave the inbox search visible and usable.")
            XCTAssertTrue(waitUntilHittable(row, timeout: 10) && inbox.frame.contains(row.frame)
                          && window.contains(row.frame),
                          "Initial wide opening must leave the selected inbox thread fully readable.")
            XCTAssertNil(visibleBack(from: "Messages", in: app),
                         "Initial wide opening must not cover its columns with a compact push.")
        }
        for sample in 0..<6 {
            if sample > 0 { RunLoop.current.run(until: Date().addingTimeInterval(0.6)) }
            keepScreenshot("Initial \(messageCount)-message history \(mode ?? "static") sample \(sample)", in: app)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(latest.isHittable, "No input after launch may be needed to repair the fitting transcript.")
            XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY + 1,
                                     "Initial fitting content must stay above its stationary composer.")
        }
    }

    func testConversationTypingKeepsLatestReadableThroughSoftwareKeyboardTransition() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This journey requires the iOS software keyboard.")
        #else
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        let wide = usesColumns(in: app)
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let transcript = wide ? rootTranscript(in: app) : nativeTranscript(over: app.windows.firstMatch.frame, in: app)
        let pane = wide ? element("messages.detailPane", in: app) : app.windows.firstMatch
        let latest = transcript.staticTexts["Offline message from hakhoa"].firstMatch
        let keyboard = app.keyboards.firstMatch
        XCTAssertFalse(keyboard.exists, "The initial latest witness must precede keyboard focus.")
        let letterKey = keyboard.keys.matching(NSPredicate(format: "label == %@ OR label == %@", "u", "U")).firstMatch

        func assertLatestIsReadable(_ checkpoint: String, requiresSoftwareKeyboard: Bool,
                                    requiresKeyboardAbsent: Bool = false) {
            let readable = waitForCondition {
                let window = app.windows.firstMatch.frame
                let composerFrame = composer.frame
                guard !window.isEmpty, !window.isNull, composer.exists, composer.isHittable,
                      !composerFrame.isEmpty, !composerFrame.isNull, window.contains(composerFrame) else { return false }
                if requiresSoftwareKeyboard {
                    // A visible letter key distinguishes a full software keyboard
                    // from a hardware-keyboard accessory bar.
                    guard keyboard.exists, letterKey.exists, letterKey.isHittable else { return false }
                    let keyboardFrame = keyboard.frame
                    let keyFrame = letterKey.frame
                    guard !keyboardFrame.isEmpty, !keyboardFrame.isNull,
                          !keyFrame.isEmpty, !keyFrame.isNull,
                          window.contains(keyboardFrame), keyboardFrame.contains(keyFrame),
                          composerFrame.maxY <= keyboardFrame.minY + 1 else { return false }
                } else if requiresKeyboardAbsent && keyboard.exists { return false }
                guard latest.exists, latest.isHittable else { return false }
                let viewport = self.transcriptViewport(transcript, above: composer, within: pane.frame, in: app)
                let latestFrame = latest.frame
                return !viewport.isEmpty && !viewport.isNull && !latestFrame.isEmpty && !latestFrame.isNull
                    && viewport.contains(latestFrame)
            }
            keepScreenshot(checkpoint, in: app)
            XCTAssertTrue(readable, "\(checkpoint): the exact latest message and composer must fit the same unobscured viewport without a repair gesture.")
        }
        assertLatestIsReadable("Messages before draft typing", requiresSoftwareKeyboard: false,
                               requiresKeyboardAbsent: true)
        let draft = "Unsent through software keyboard transition"
        tap(composer, description: "Focus the private-message draft", in: app)
        composer.typeText(String(draft.prefix(1)))
        XCTAssertTrue(waitForValue(String(draft.prefix(1)), in: composer, timeout: 10))
        // The first typeText call can show only the hardware-keyboard accessory.
        // Keep the first-character readability check before completing the draft.
        assertLatestIsReadable("Messages after first draft character", requiresSoftwareKeyboard: false)
        composer.typeText(String(draft.dropFirst()))
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        assertLatestIsReadable("Messages after complete draft with full software keyboard", requiresSoftwareKeyboard: true)
        #endif
    }

    func testLongHistoryIncomingMessagesFollowLatestWithKeyboardAndDraft() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesOverflowLaunchArgument,
            SurroundUITestContract.messagesIncomingLaunchArgument,
        ], launchEnvironment: ["SURROUND_UI_MESSAGES_REPLAY_DELAY": "40",
                               "SURROUND_UI_MESSAGES_REPLAY_INTERVAL": "1",
                               "SURROUND_UI_MESSAGES_REPLAY_HELD": "1"])
        let wide = usesColumns(in: app)
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let transcript = wide ? rootTranscript(in: app) : nativeTranscript(over: app.windows.firstMatch.frame, in: app)
        let initialLatest = transcript.staticTexts["Offline message from hakhoa"].firstMatch
        XCTAssertTrue(waitUntilHittable(initialLatest, timeout: 10), "Seed a conversation that follows latest.")
        let draft = "Unsent draft while new replies arrive"
        enterDraft(draft, in: composer, app: app)
        let progress = transcript
        XCTAssertEqual(progress.value as? String, "delivered:0/2", "The draft and following position must precede the appends.")
        #if !targetEnvironment(macCatalyst)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Incoming replies must exercise the software-keyboard viewport.")
        #endif
        keepScreenshot("Following latest before incoming replay", in: app)
        tap("test.messagesReplay.release", in: app, matching: .button)
        XCTAssertTrue(waitForValue("delivered:2/2", in: progress, timeout: 50),
                      "Both fresh incoming replies must be delivered through the offline service.")
        let latest = transcript.staticTexts[SurroundUITestContract.messagesIncomingLatestText].firstMatch
        XCTAssertTrue(waitUntilHittable(latest, timeout: 10), "Following latest must reveal the new incoming reply.")
        XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY + 1,
                                 "The newest reply must remain above the composer after keyboard avoidance.")
        XCTAssertTrue(composer.isHittable)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        keepScreenshot("Long history follows incoming replies with retained draft", in: app)
    }

    func testLongHistoryIncomingMessagesPreserveOlderReadingPositionAndDraft() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesOverflowLaunchArgument,
            SurroundUITestContract.messagesIncomingLaunchArgument,
        ], launchEnvironment: ["SURROUND_UI_MESSAGES_REPLAY_DELAY": "40",
                               "SURROUND_UI_MESSAGES_REPLAY_INTERVAL": "1",
                               "SURROUND_UI_MESSAGES_REPLAY_HELD": "1"])
        let wide = usesColumns(in: app)
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let draft = "Unsent draft while reading older replies"
        enterDraft(draft, in: composer, app: app)
        let transcript = wide ? rootTranscript(in: app) : nativeTranscript(over: app.windows.firstMatch.frame, in: app)
        let initialLatest = transcript.staticTexts["Offline message from hakhoa"].firstMatch
        func readableViewport() -> CGRect {
            let bounds = transcript.frame.intersection(app.windows.firstMatch.frame)
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                          height: max(0, min(bounds.maxY, composer.frame.minY) - bounds.minY))
                .insetBy(dx: 8, dy: 8)
        }
        let olderHistory = transcript.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Offline history ", " for hakhoa\n"
        ))
        for _ in 0..<4 {
            dragMessagesViewport(transcriptViewport(transcript, above: composer,
                within: wide ? element("messages.detailPane", in: app).frame : app.windows.firstMatch.frame, in: app),
                                 toward: nil, earlierWhenAbsent: true, in: app)
            if !initialLatest.isHittable {
                let viewport = readableViewport()
                if olderHistory.allElementsBoundByIndex.contains(where: { viewport.contains($0.frame) && $0.isHittable }) { break }
            }
        }
        XCTAssertFalse(initialLatest.isHittable, "Seed a reading position that is independent of latest.")
        let olderMessages = olderHistory.allElementsBoundByIndex.filter { readableViewport().contains($0.frame) && $0.isHittable }
            .sorted { $0.frame.midY < $1.frame.midY }
        let witnessLabel = try XCTUnwrap(olderMessages.dropFirst(olderMessages.count / 2).first?.label,
                                        "Seed one fully readable older-message witness.")
        let witness = transcript.staticTexts.matching(NSPredicate(format: "label == %@", witnessLabel)).firstMatch
        let progress = transcript
        XCTAssertEqual(progress.value as? String, "delivered:0/2", "The reading witness must precede the appends.")
        keepScreenshot("Older witness before incoming replay", in: app)
        tap("test.messagesReplay.release", in: app, matching: .button)
        XCTAssertTrue(waitForValue("delivered:2/2", in: progress, timeout: 50),
                      "Both incoming replies must arrive while the older history remains selected.")
        XCTAssertTrue(witness.isHittable && readableViewport().contains(witness.frame),
                      "The exact older reading witness must remain fully readable after incoming appends.")
        XCTAssertFalse(initialLatest.isHittable, "New replies must not switch older reading back to latest.")
        XCTAssertFalse(transcript.staticTexts[SurroundUITestContract.messagesIncomingLatestText].firstMatch.isHittable)
        XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        keepScreenshot("Older witness and draft retained after incoming replay", in: app)
    }

    func testCompactMessagesTitleCollapsesOnInboxScrollAndExpandsAtTop() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.friendshipLaunchArgument,
            SurroundUITestContract.messagesOverflowLaunchArgument,
        ])
        try requireCompact(in: app)
        let scroll = element("messages.inboxScroll", in: app, matching: .scrollView)
        let navigationBar = app.navigationBars["Messages"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let firstRequest = query(SurroundUITestContract.AccessibilityID.friendRequestProfile(
            SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]), in: app)
        for _ in 0..<6 {
            if navigationBar.frame.height >= 80 && firstRequest.isHittable { break }
            scroll.swipeDown()
        }
        let expandedHeight = navigationBar.frame.height
        XCTAssertGreaterThanOrEqual(expandedHeight, 80, "The top of the compact inbox must show its large native title.")
        XCTAssertTrue(firstRequest.isHittable)
        let requestOrigin = firstRequest.frame.minY
        let search = element("messages.playerSearchField", in: app, matching: .textField)
        let searchWidth = search.frame.width
        keepScreenshot("Compact Messages large title before inbox scroll", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Initial large title")
        for _ in 0..<3 {
            scroll.swipeUp()
            if navigationBar.frame.height < expandedHeight - 30 { break }
        }
        XCTAssertTrue(waitForCondition { navigationBar.frame.height < expandedHeight - 30
            && navigationBar.frame.height <= 60 }, "Scrolling the inbox must collapse Messages into its native inline title.")
        XCTAssertTrue(!firstRequest.exists || firstRequest.frame.minY < requestOrigin - 30,
                      "The inbox content must actually scroll before asserting title collapse.")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(search.frame),
                      "The collapsed search field must remain fully inside the active window.")
        XCTAssertGreaterThanOrEqual(search.frame.minY, navigationBar.frame.maxY - 1)
        XCTAssertLessThanOrEqual(search.frame.minY, navigationBar.frame.maxY + 40)
        XCTAssertEqual(search.frame.width, searchWidth, accuracy: 1)
        keepScreenshot("Compact Messages inline title with pinned search", in: app)
        // XCTest reports this safeAreaInset field as not hittable after native
        // title collapse, although UIKit hit-testing resolves its exact visible
        // frame center to the enabled text field. Verify the real tap outcome.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: search.frame.midX - window.frame.minX,
            dy: search.frame.midY - window.frame.minY)).tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "Collapsed search must remain usable with the native keyboard.")
        tap("messages.cancelPlayerSearch", in: app, matching: .button)
        XCTAssertTrue(waitForCondition { !keyboard.exists }, "Cancel must dismiss the search keyboard before restoring the large title.")
        for _ in 0..<6 {
            scroll.swipeDown()
            if firstRequest.isHittable && navigationBar.frame.height >= expandedHeight - 2 { break }
        }
        XCTAssertTrue(waitForCondition { firstRequest.isHittable && navigationBar.frame.height >= expandedHeight - 2 })
        XCTAssertEqual(navigationBar.frame.height, expandedHeight, accuracy: 2,
                       "Returning to the inbox top must restore the native large title.")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(search.frame),
                      "The restored search field must remain fully inside the active window.")
        keepScreenshot("Compact Messages title expands after returning to top", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Restored large title")
    }

    func testCompactMessagesSearchKeepsExpandedTitleThroughFocusResultsAndCancel() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This journey requires compact Messages with the iOS software keyboard.")
        #else
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesLoadingLaunchArgument,
            SurroundUITestContract.friendshipLaunchArgument,
            SurroundUITestContract.messagesOverflowLaunchArgument,
        ])
        try requireCompact(in: app)
        let scroll = element("messages.inboxScroll", in: app, matching: .scrollView)
        let navigationBar = app.navigationBars["Messages"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let firstRequest = query(SurroundUITestContract.AccessibilityID.friendRequestProfile(
            SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]), in: app)
        for _ in 0..<6 {
            if navigationBar.frame.height >= 80 && firstRequest.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertGreaterThanOrEqual(navigationBar.frame.height, 80,
                                    "Search must begin at the expanded compact inbox top.")
        XCTAssertTrue(firstRequest.isHittable)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        let anchors = messagesLoadingAnchors(in: app)
        let restingFrames = anchors.mapValues(\.frame)
        keepScreenshot("Expanded Messages before custom search", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Expanded inbox before search")

        let search = anchors["search"]!
        tap(search, description: "Focus empty search from the expanded inbox", in: app)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "Search must own the software keyboard.")
        let description = app.staticTexts["Search by username to view a profile or start a conversation."].firstMatch
        XCTAssertTrue(waitUntilHittable(description, timeout: 10))
        XCTAssertLessThanOrEqual(description.frame.maxY, keyboard.frame.minY + 1,
                                 "Empty search guidance must remain readable above the keyboard.")
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        let focusedFrames = anchors.mapValues(\.frame)
        keepScreenshot("Expanded Messages with empty focused search", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Empty focused search")

        search.typeText("Copper")
        XCTAssertTrue(waitForValue("Copper", in: search, timeout: 10))
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:1", in: app)
        assertMessagesLoadingStatus("Searching…", in: app)
        XCTAssertTrue(keyboard.exists)
        XCTAssertTrue(app.buttons["Clear search"].firstMatch.isHittable,
                      "A typed query must expose the existing Clear button.")
        // The Clear button changes text-field width when the query becomes nonempty.
        assertMessagesLoadingFrames(anchors.filter { $0.key != "search" }, equalTo: focusedFrames, in: app)
        let typedFrames = anchors.mapValues(\.frame)
        keepScreenshot("Expanded Messages with held Copper search", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Held Copper search")

        tap(SurroundUITestContract.AccessibilityID.messagesLoadingReleaseSearch, in: app, matching: .button)
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(keyboard.exists, "Loading results must preserve the focused query and keyboard.")
        assertMessagesLoadingFrames(anchors, equalTo: typedFrames, in: app)
        keepScreenshot("Expanded Messages with loaded CopperKoi results", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Loaded CopperKoi results")

        cancelInboxSearch(in: app)
        XCTAssertTrue(waitForCondition { !keyboard.exists }, "Cancel must dismiss the search keyboard.")
        XCTAssertTrue(waitForValue("", in: search, timeout: 10))
        XCTAssertTrue(waitUntilHittable(firstRequest, timeout: 10), "Cancel must restore the expanded inbox content.")
        assertMessagesLoadingFixture("friends:0;requests:0;errors:0;search:0", in: app)
        assertMessagesLoadingStatus(nil, in: app)
        assertMessagesLoadingFramesAfterSearchCancel(anchors, equalTo: restingFrames, in: app)
        keepScreenshot("Expanded Messages restored after search Cancel", in: app)
        try assertRenderedMessagesTitle(in: app, navigationBar: navigationBar, stage: "Search Cancel restores inbox")
        #endif
    }

    private func assertRenderedMessagesTitle(in app: XCUIApplication, navigationBar: XCUIElement,
                                             stage: String) throws {
        let screenshot = app.screenshot()
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let window = app.windows.firstMatch.frame
        let bar = navigationBar.frame.intersection(window)
        let scaleX = CGFloat(image.width) / window.width
        let scaleY = CGFloat(image.height) / window.height
        let pixels = CGRect(x: (bar.minX - window.minX) * scaleX,
                            y: (bar.minY - window.minY) * scaleY,
                            width: bar.width * scaleX, height: bar.height * scaleY).integral
        let titleImage = try XCTUnwrap(image.cropping(to: pixels))
        let attachment = XCTAttachment(image: UIImage(cgImage: titleImage))
        attachment.name = "\(stage) – rendered navigation bar"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: titleImage, options: [:]).perform([request])
        XCTAssertTrue((request.results ?? []).contains { observation in
            observation.topCandidates(1).first?.string.caseInsensitiveCompare("Messages") == .orderedSame
        }, "The expanded navigation bar must visibly paint Messages; bar geometry or the tab label cannot satisfy it.")
    }

    func testDelayedShortHistoryBackfillStaysAboveComposerWithoutInput() throws {
        try assertDelayedHistoryWithoutInput(mode: "backfill")
    }

    func testDelayedShortHistoryAppendStaysAboveComposerWithoutInput() throws {
        try assertDelayedHistoryWithoutInput(mode: "append")
    }

    func testEmptyHistoryReplayStaysAboveComposerWithoutInput() throws {
        try assertDelayedHistoryWithoutInput(mode: "empty", videoTextShape: true)
    }

    func testVideoShapedShortHistoryWaitStaysAboveComposerWithoutInput() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesShortHistoryLaunchArgument],
            launchEnvironment: ["SURROUND_UI_MESSAGES_VIDEO_TEXT_SHAPE": "1"])
        guard !usesColumns(in: app) else { throw XCTSkip("This journey covers the compact supplied-video presentation.") }
        openInboxConversation(firstPeerID, in: app)
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let latest = app.staticTexts.matching(NSPredicate(format: "label == %@",
            SurroundUITestContract.messagesVideoHistoryLatestText)).firstMatch
        for sample in 1...8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            keepScreenshot("Video-shaped short history waiting sample \(sample)", in: app)
            XCTAssertTrue(latest.isHittable)
            XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY + 1)
        }
    }

    private func assertDelayedHistoryWithoutInput(mode: String, videoTextShape: Bool = false) throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesShortHistoryLaunchArgument,
            SurroundUITestContract.messagesDelayedHistoryLaunchArgument,
        ], launchEnvironment: ["SURROUND_UI_MESSAGES_REPLAY_MODE": mode,
            "SURROUND_UI_MESSAGES_VIDEO_TEXT_SHAPE": videoTextShape ? "1" : "0"])
        guard !usesColumns(in: app) else { throw XCTSkip("This journey covers the compact supplied-video presentation.") }
        if mode == "empty" { tapFriend(firstPeerID, in: app) }
        else { openInboxConversation(firstPeerID, in: app) }
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let latest = app.staticTexts.matching(NSPredicate(format: "label == %@",
            videoTextShape ? SurroundUITestContract.messagesVideoHistoryLatestText : SurroundUITestContract.messagesShortHistoryLatestText)).firstMatch
        for sample in 1...8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            keepScreenshot("Delayed \(mode) no-input sample \(sample)", in: app)
            XCTAssertEqual(app.state, .runningForeground)
            if latest.exists {
                XCTAssertTrue(latest.isHittable, "Simply waiting for asynchronous history must keep the latest message readable.")
                XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY + 1,
                    "A delayed history update must not move the transcript underneath its stationary composer.")
            }
        }
        XCTAssertTrue(latest.exists, "The delayed latest message must have arrived.")
        XCTAssertTrue(app.staticTexts["Hello"].exists, "The older history must have arrived.")
        XCTAssertTrue(app.staticTexts["Hi"].exists)
    }

    func testShortConversationOpeningKeepsMessageAboveComposer() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesShortHistoryLaunchArgument])
        guard !usesColumns(in: app) else {
            throw XCTSkip("This journey covers the compact push seen in the supplied video.")
        }
        for opening in 1...3 {
            openInboxConversation(firstPeerID, in: app)
            let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
            let message = app.staticTexts.matching(NSPredicate(format: "label == %@",
                SurroundUITestContract.messagesShortHistoryLatestText)).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 10))
            for sample in 1...3 {
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                keepScreenshot("Short conversation opening \(opening) settled sample \(sample)", in: app)
                XCTAssertTrue(message.isHittable, "The short conversation must remain readable without a repair gesture.")
                XCTAssertLessThanOrEqual(message.frame.maxY, composer.frame.minY + 1,
                    "Settling a short conversation must not move its message below the composer.")
            }
            back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
    }

    func testShortConversationScrollGestureKeepsMessageAboveComposer() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesShortHistoryLaunchArgument])
        guard !usesColumns(in: app) else { throw XCTSkip("This journey covers compact transcript scrolling.") }
        openInboxConversation(firstPeerID, in: app)
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        let message = app.staticTexts.matching(NSPredicate(format: "label == %@",
            SurroundUITestContract.messagesShortHistoryLatestText)).firstMatch
        let transcript = nativeTranscript(over: app.windows.firstMatch.frame, in: app)
        keepScreenshot("Short conversation before scroll gesture", in: app)
        for gesture in 1...3 {
            if gesture == 2 { transcript.swipeUp() }
            else { transcript.swipeDown() }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            keepScreenshot("Short conversation after settled scroll gesture \(gesture)", in: app)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(message.isHittable)
            XCTAssertLessThanOrEqual(message.frame.maxY, composer.frame.minY + 1,
                "A completed scroll gesture in a fitting short history must not leave messages beneath the composer.")
        }
    }

    func testConversationBackgroundReturnPreservesSceneViewportAndDraft() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This journey exercises iOS background and scene activation.")
        #else
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.messagesOverflowLaunchArgument,
            SurroundUITestContract.sceneActivationLaunchArgument,
        ])
        let wide = usesColumns(in: app)
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let composer = assertConversation("hakhoa", peerID: firstPeerID, in: app)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Capture the unfocused composer before the software keyboard appears.")
        let keyboardHiddenWindow = app.windows.firstMatch.frame
        let keyboardHiddenComposer = composer.frame
        XCTAssertTrue(keyboardHiddenWindow.contains(keyboardHiddenComposer))
        keepScreenshot("Messages keyboard-hidden composer baseline", in: app)

        func assertKeyboardHiddenComposerMatchesBaseline() {
            XCTAssertFalse(app.keyboards.firstMatch.exists, "Returning to Messages must leave keyboard focus dismissed.")
            let window = app.windows.firstMatch.frame
            let returnedComposer = composer.frame
            XCTAssertEqual(window, keyboardHiddenWindow, "This background journey must return to the same native window bounds.")
            XCTAssertTrue(composer.isHittable && window.contains(returnedComposer))
            // First focus can change a text field's AX intrinsic size.
            // Compare its center with this run's unfocused baseline.
            XCTAssertEqual(returnedComposer.midX - window.minX,
                           keyboardHiddenComposer.midX - keyboardHiddenWindow.minX, accuracy: 1)
            XCTAssertEqual(window.maxY - returnedComposer.midY,
                           keyboardHiddenWindow.maxY - keyboardHiddenComposer.midY, accuracy: 1,
                           "A dismissed keyboard must restore the composer to its original distance from the window bottom.")
        }
        let draft = "Unsent through repeated background returns"
        enterDraft(draft, in: composer, app: app)
        let sceneProbe = app.descendants(matching: .any).matching(identifier: "test.sceneActivation").firstMatch
        XCTAssertTrue(sceneProbe.waitForExistence(timeout: 10))
        let original = try JSONSerialization.jsonObject(with: Data((sceneProbe.value as? String ?? "").utf8)) as? [String: Any]
        let sessionID = try XCTUnwrap(original?["sessionID"] as? String)
        let sessionIDs = try XCTUnwrap(original?["sessionIDs"] as? [String])

        func assertLatestMessageIsReadable() {
            let transcript = app.scrollViews.matching(identifier: SurroundUITestContract.AccessibilityID.profileConversation)
                .allElementsBoundByIndex.first { $0.isHittable } ?? app.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
            let latest = transcript.staticTexts["Offline message from hakhoa"].firstMatch
            XCTAssertTrue(waitUntilHittable(latest, timeout: 10), "The latest message must stay readable without a repair gesture.")
            XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY + 1,
                                     "Message content must remain above the composer after backgrounding.")
            XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
        }
        assertLatestMessageIsReadable()
        keepScreenshot("Messages before background return", in: app)
        for cycle in 1...3 {
            XCUIDevice.shared.press(.home)
            if !app.wait(for: .runningBackground, timeout: 3) {
                XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()
            }
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(waitForCondition { (sceneProbe.value as? String)?.contains("\"isActive\":true") == true })
            let returned = try JSONSerialization.jsonObject(with: Data((sceneProbe.value as? String ?? "").utf8)) as? [String: Any]
            XCTAssertEqual(returned?["sessionID"] as? String, sessionID)
            XCTAssertEqual(returned?["sessionIDs"] as? [String], sessionIDs)
            assertLatestMessageIsReadable()
            assertKeyboardHiddenComposerMatchesBaseline()
            keepScreenshot("Messages after background return \(cycle)", in: app)
        }

        // Exercise a real older reading position as well as following latest.
        // Freeze an external label; a different nearby message cannot satisfy it.
        let transcript = wide ? rootTranscript(in: app) : nativeTranscript(over: app.windows.firstMatch.frame, in: app)
        let latest = transcript.staticTexts["Offline message from hakhoa"].firstMatch
        func readableViewport() -> CGRect {
            let bounds = transcript.frame.intersection(app.windows.firstMatch.frame)
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                          height: max(0, min(bounds.maxY, composer.frame.minY) - bounds.minY))
                .insetBy(dx: 8, dy: 8)
        }
        let olderHistory = transcript.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Offline history ", " for hakhoa\n"
        ))
        for _ in 0..<8 {
            dragMessagesViewport(transcriptViewport(transcript, above: composer,
                within: wide ? element("messages.detailPane", in: app).frame : app.windows.firstMatch.frame, in: app),
                                 toward: nil, earlierWhenAbsent: true, in: app)
            if !latest.isHittable {
                let viewport = readableViewport()
                if olderHistory.allElementsBoundByIndex.contains(where: { viewport.contains($0.frame) && $0.isHittable }) { break }
            }
        }
        XCTAssertFalse(latest.isHittable, "Seed an actual older reading position before backgrounding.")
        let viewport = readableViewport()
        let visibleOlderMessages = olderHistory.allElementsBoundByIndex.filter { viewport.contains($0.frame) && $0.isHittable }
            .sorted { $0.frame.midY < $1.frame.midY }
        XCTAssertFalse(visibleOlderMessages.isEmpty, "Seed a fully readable older-message witness.")
        let historyLabel = try XCTUnwrap(visibleOlderMessages.dropFirst(visibleOlderMessages.count / 2).first?.label)
        let history = app.staticTexts.matching(NSPredicate(format: "label == %@", historyLabel)).firstMatch
        XCTAssertTrue(history.isHittable)
        keepScreenshot("Older message before background return", in: app)
        // Two repeats keep this bounded on Duo, where native idle waits after
        // an interactive keyboard dismissal can each consume a full minute.
        for cycle in 1...2 {
            XCUIDevice.shared.press(.home)
            if !app.wait(for: .runningBackground, timeout: 3) {
                XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()
            }
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(waitForCondition { (sceneProbe.value as? String)?.contains("\"isActive\":true") == true })
            let returned = try JSONSerialization.jsonObject(with: Data((sceneProbe.value as? String ?? "").utf8)) as? [String: Any]
            XCTAssertEqual(returned?["sessionID"] as? String, sessionID)
            XCTAssertEqual(returned?["sessionIDs"] as? [String], sessionIDs)
            XCTAssertTrue(waitForCondition {
                history.isHittable && readableViewport().contains(history.frame)
            }, "The exact older message must remain fully readable without another scroll gesture.")
            XCTAssertLessThanOrEqual(history.frame.maxY, composer.frame.minY + 1)
            XCTAssertTrue(waitForValue(draft, in: composer, timeout: 10))
            assertKeyboardHiddenComposerMatchesBaseline()
            keepScreenshot("Older message after background return \(cycle)", in: app)
        }
        #endif
    }

    func testPlayerSearchEmptyStateStaysAboveSoftwareKeyboard() throws {
        #if targetEnvironment(macCatalyst)
        throw XCTSkip("This journey requires the iOS software keyboard.")
        #else
        let app = launchMessages()
        guard !usesColumns(in: app) else {
            throw XCTSkip("The pixel check covers compact search on the active phone display.")
        }
        let search = element("messages.playerSearchField", in: app, matching: .textField)
        tap(search, description: "Focus empty player search", in: app)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "A software keyboard is required.")
        guard keyboard.exists else { return }
        let description = app.staticTexts["Search by username to view a profile or start a conversation."].firstMatch
        XCTAssertTrue(waitUntilHittable(description, timeout: 10))
        XCTAssertLessThanOrEqual(description.frame.maxY, keyboard.frame.minY,
                                 "The complete search description must be readable above the keyboard.")
        // Keyboard AX bounds can exclude its prediction strip. Check the actual
        // rendered words as well, so a label hidden behind that strip cannot pass.
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Empty player search above software keyboard"
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(screenshot.image.cgImage), options: [:]).perform([request])
        let renderedWords = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased().filter(\.isLetter)
        let expectedWords = "Search by username to view a profile or start a conversation."
            .lowercased().filter(\.isLetter)
        XCTAssertTrue(renderedWords.contains(expectedWords),
                      "The complete description must be present in the visible pixels, including its last line.")
        #endif
    }

    func testWidePlayerSearchCancelPreservesSelectedPeerAndDraft() throws {
        let app = launchMessages()
        guard usesColumns(in: app) else { throw XCTSkip("This journey covers selection retained in the wide root.") }
        let bounds = assertWideRoot(in: app)
        setSearch("Copper", in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        let draft = "Unsent selected search recipient"
        enterDraft(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                presentation: .wideRoot, in: app), app: app)
        cancelInboxSearch(in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        XCTAssertNil(visibleBack(from: "Messages", in: app))
        keepScreenshot("Search Cancel retains selected peer and draft", in: app)
    }

    func testProfileBiographyPlayerAndGameLinksBackPreservesSearchAndDraft() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.profileBiographyLaunchArgument])
        let wide = usesColumns(in: app)
        let bounds = wide ? assertWideRoot(in: app) : nil
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let draft = "Unsent while reading a biography"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), app: app)
        if !wide { back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app) }
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        openAbout(in: app)
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerAbout, over: bounds, in: app) }
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.press(.home)
        app.activate()
        element(SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        biographyWebView(in: app)
        #endif
        tapBiographyLink("JuniperStone", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app) }
        let linkedProfileScroll = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile,
                                         in: app, matching: .scrollView)
        let linkedAbout = element(SurroundUITestContract.AccessibilityID.profileAbout,
                                  in: app, matching: .button)
        let viewport = unobscuredProfileViewport(linkedProfileScroll, in: app)
        let readingArea = CGRect(x: viewport.minX, y: viewport.minY,
                                 width: viewport.width, height: viewport.height * 0.35)
        // Place the source About row nearer the top when the Profile scrolls.
        // A short Profile that fits its viewport can retain its original position.
        for _ in 0..<3 {
            let previous = linkedAbout.frame
            guard dragScrollView(linkedProfileScroll, axis: .vertical, targetFrame: previous,
                                 containerFrame: readingArea, interactionPoint: CGVector(dx: 0.5, dy: 0.5),
                                 dragStartPoint: CGPoint(x: viewport.midX, y: viewport.midY),
                                 dragVelocity: XCUIGestureVelocity(rawValue: 60), dragHoldDuration: 0.2) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if linkedAbout.frame == previous { break }
        }
        let linkedAboutFrame = openAbout(in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        let restoredLinkedAbout = query(SurroundUITestContract.AccessibilityID.profileAbout, in: app)
        XCTAssertTrue(restoredLinkedAbout.isHittable,
                      "The ID-only linked Profile must keep its original reading position after About caches its user.")
        XCTAssertEqual(restoredLinkedAbout.frame.minY, linkedAboutFrame.minY, accuracy: 4,
                       "About must reveal the same Profile view owner and scroll position on Back.")
        back(from: "Profile", to: SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        tapBiographyLink("View a game", in: app)
        let gameID = SurroundUITestContract.screenshotPrimaryGameID
        let game = element(SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        let board = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
        let boardValue = board.value as? String
        XCTAssertFalse(boardValue?.isEmpty ?? true,
                       "The linked fixture board must expose its position before testing Back retention.")
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.gameDetail(gameID), over: bounds, in: app) }
        tap(SurroundUITestContract.AccessibilityID.profileBannerAvatarEntry(
            SurroundUITestContract.profileFixtureOwnerID), in: app, matching: .button)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        back(from: "Profile", to: SurroundUITestContract.AccessibilityID.gameDetail(gameID), in: app)
        XCTAssertEqual(element(SurroundUITestContract.AccessibilityID.gameBoard, in: app).value as? String, boardValue,
                       "The linked game's board must survive a nested player Profile and Back.")
        XCTAssertTrue(game.exists)
        back(from: "Game", to: SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        // Repeat the route to detect stale payloads or an extra About screen.
        openAbout(in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        if wide {
            XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app), timeout: 10))
        }
        cancelInboxSearch(in: app)
        if !wide {
            openInboxConversation(firstPeerID, in: app)
            XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .nativePush, in: app), timeout: 10))
        } else {
            assertWideRoot(in: app)
            assertInboxSelection(firstPeerID, in: app)
        }
        keepScreenshot("Profile biography – native links restore Messages context", in: app)
    }

    func testWideBiographyBackPreservesInboxAndPeerHistory() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.profileBiographyLaunchArgument,
            SurroundUITestContract.messagesOverflowLaunchArgument,
        ])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let draft = "Unsent before reading older history and About"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app), app: app)
        let allFriendIDs = Array(801_001...801_006) + SurroundUITestContract.messagesOverflowFriendIDs
        XCTAssertTrue(expandFriends(in: app, expectedFriendIDs: allFriendIDs))
        let anchorID = "messages.friend.message.914040"
        let anchor = revealBiographyInboxAnchor(anchorID, in: app)
        let anchorY = anchor.frame.minY
        revealOlderHistory(username: "hakhoa", index: 25, in: app)
        let historyWitness = centralVisibleHistoryWitness(username: "hakhoa", in: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        openAbout(in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerAbout, over: bounds, in: app)
        tapBiographyLink("More about JuniperStone", in: app)
        assertLoadedProfile(named: "JuniperStone", isOwnProfile: true, in: app)
        back(from: "Profile", to: SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        XCTAssertTrue(biographyWebView(in: app).links["More about JuniperStone"].firstMatch.isHittable,
                      "Back should retain the biography's scrolled reading context.")
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        let restoredAnchor = query(anchorID, in: app)
        XCTAssertTrue(waitUntilHittable(restoredAnchor, timeout: 10))
        XCTAssertEqual(restoredAnchor.frame.minY, anchorY, accuracy: 16,
                       "About and a linked player must preserve the inbox's scrolled context.")
        assertHistoryWitnessVisible(historyWitness, username: "hakhoa", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app), timeout: 10))
        keepScreenshot("Profile biography – Back restores inbox and older peer history", in: app)
    }

    func testMessageInboxAndRequestProfileAboutEntryPoints() {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.profileBiographyLaunchArgument,
            SurroundUITestContract.friendshipLaunchArgument,
        ])
        let wide = usesColumns(in: app)
        let bounds = wide ? assertWideRoot(in: app) : nil
        let conversation = inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(firstPeerID), in: app)
        let action = openProfileContextMenu(for: conversation,
            expecting: SurroundUITestContract.AccessibilityID.profileMessageMenuEntry(firstPeerID), in: app)
        tap(action, description: "Open inbox conversation Profile", in: app)
        assertLoadedProfile(named: "hakhoa", in: app)
        openAbout(in: app)
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerAbout, over: bounds, in: app) }
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        let playerID = SurroundUITestContract.friendshipFixtureRequestPlayerIDs[0]
        let request = inboxElement(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID), in: app)
        tap(request, description: "Read request sender Profile without answering the request", in: app)
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[0]
        assertLoadedProfile(named: username, in: app)
        openAbout(in: app)
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerAbout, over: bounds, in: app) }
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: username, to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        XCTAssertTrue(inboxElement(SurroundUITestContract.AccessibilityID.friendRequestProfile(playerID), in: app).isHittable,
                      "Reading About must leave the incoming request available.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        if let bounds { assertWideRoot(in: app, expectedBounds: bounds) }
        keepScreenshot("Profile biography – inbox and request entry points", in: app)
    }

    func testUnavailableBiographyGameCanRetryAndReturnToAbout() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.profileBiographyLaunchArgument])
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        openAbout(in: app)
        tapBiographyLink("Unavailable game", in: app)
        element("profile.linkedGame.error", in: app)
        XCTAssertTrue(app.staticTexts["Unable to load game"].exists)
        tap("profile.linkedGame.retry", in: app, matching: .button)
        element("profile.linkedGame.error", in: app)
        back(from: "Game", to: SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        biographyLink("Unavailable game", in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
    }

    func testBiographySanitizationMediaFailureAndTimeFormatsAtLargestDarkText() {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.profileBiographyLaunchArgument,
            SurroundUITestContract.appearanceLaunchArgument, "dark",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ], launchEnvironment: ["TZ": "America/Los_Angeles"])
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        XCTAssertTrue(waitForValue("dark", in: element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app), timeout: 10))
        element(SurroundUITestContract.AccessibilityID.profileBiographySummary, in: app)
        keepScreenshot("Profile biography – formatted summary in dark and largest text", in: app)
        openAbout(in: app)
        let web = biographyWebView(in: app)
        let readable = biographyText(containing: "Readable biography", in: app)
        revealBiographyElement(readable, in: web, app: app)
        XCTAssertTrue(waitUntilHittable(readable, timeout: 10), "Sanitized authored colors and tiny text must remain readable.")
        XCTAssertFalse(app.staticTexts["Unsafe script ran"].exists,
                       "Authored scripts must not run or appear as biography text.")
        let failure = biographyText(containing: "Go board photograph", in: app)
        revealBiographyElement(failure, in: web, app: app)
        XCTAssertTrue(failure.label.contains("Unable to load image"))
        let secondFailure = biographyText(containing: "Second Go photograph", in: app)
        revealBiographyElement(secondFailure, in: web, app: app)
        XCTAssertTrue(secondFailure.label.contains("Unable to load image"),
                      "Consecutive failed images must each have a labeled placeholder.")
        let rejectedImage = biographyText(containing: "Sanitizer-rejected Go photograph", in: app)
        revealBiographyElement(rejectedImage, in: web, app: app)
        XCTAssertTrue(rejectedImage.label.contains("Unable to load image"))
        keepScreenshot("Profile biography – sanitizer-rejected image in dark and largest text", in: app)
        let audio = biographyLink("Open audio", in: app)
        let video = biographyLink("Open video", in: app)
        XCTAssertTrue(audio.label.contains("audio"))
        XCTAssertTrue(video.label.contains("video"))
        // 09:30 in UTC+7 is 19:30 on the preceding date in this test's zone.
        let supportedDate = biographyText(containing: "2026/10/03", in: app)
        revealBiographyElement(supportedDate, in: web, app: app)
        let unsupportedDate = biographyText(containing: "Date format unavailable", in: app)
        revealBiographyElement(unsupportedDate, in: web, app: app)
        XCTAssertTrue(unsupportedDate.isHittable,
                      "Unsupported authored formats need a localized accessible fallback.")
        keepScreenshot("Profile biography – failed media and time fallback in dark and largest text", in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
    }

    func testBiographySanitizationRejectedImageInLightMode() {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.profileBiographyLaunchArgument,
            SurroundUITestContract.appearanceLaunchArgument, "light",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
        ])
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        XCTAssertTrue(waitForValue("light", in: element(SurroundUITestContract.AccessibilityID.profileLoaded, in: app), timeout: 10))
        openAbout(in: app)
        let web = biographyWebView(in: app)
        let rejectedImage = biographyText(containing: "Sanitizer-rejected Go photograph", in: app)
        revealBiographyElement(rejectedImage, in: web, app: app)
        XCTAssertTrue(rejectedImage.label.contains("Unable to load image"))
        keepScreenshot("Profile biography – sanitizer-rejected image in light", in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
    }

    func testProfileBiographyFragmentLinksJumpAndBackPreservesSearch() {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.profileBiographyLaunchArgument])
        let bounds = usesColumns(in: app) ? assertWideRoot(in: app) : nil
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        openAbout(in: app)
        if let bounds { assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerAbout, over: bounds, in: app) }
        for (label, destination) in [
            ("Jump to escaped heading", "Escaped fragment destination"),
            ("Jump to text anchor", "Text anchor destination"),
            ("Jump to empty anchor", "Empty anchor destination"),
        ] {
            let link = biographyLink(label, in: app)
            let target = biographyText(containing: destination, in: app)
            let sourceY = target.frame.minY
            tap(link, description: "Follow authored biography fragment \(label)", in: app)
            let web = biographyWebView(in: app)
            func visibleFragmentViewport() -> CGRect {
                let bounds = web.frame.intersection(app.frame)
                var top = bounds.minY
                var bottom = bounds.maxY
                for bar in app.navigationBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
                    top = max(top, bar.frame.maxY)
                }
                for bar in app.tabBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
                    bottom = min(bottom, bar.frame.minY)
                }
                return CGRect(x: bounds.minX, y: top, width: bounds.width, height: max(0, bottom - top))
            }
            let jumpedToTarget = waitForCondition {
                let targetFrame = target.frame
                return target.isHittable
                    && visibleFragmentViewport().contains(CGPoint(x: targetFrame.midX, y: targetFrame.midY))
                    && abs(targetFrame.minY - sourceY) > 40
            }
            XCTAssertTrue(jumpedToTarget,
                          "The fragment must scroll to its own surviving HTML target. "
                          + "Target: \(target.frame); prior target y: \(sourceY); "
                          + "visible viewport: \(visibleFragmentViewport()); source link: \(link.frame).")
            XCTAssertTrue(app.navigationBars["About"].isHittable,
                          "A valid local fragment must remain in About without a browser presentation.")
            XCTAssertFalse(link.isHittable, "The source link must leave the viewport after the jump.")
            keepScreenshot("Profile biography – \(destination)", in: app)
        }
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
    }

    #if !targetEnvironment(macCatalyst)
    @MainActor
    func testProfileBiographyExternalBrowserBackPreservesReadingContextAndDraft() async throws {
        let server = try ProfileBiographyBrowserServer()
        addTeardownBlock { server.stop() }
        let url = try await server.start(in: self)
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.profileBiographyLaunchArgument],
                                 launchEnvironment: ["SURROUND_UI_BIOGRAPHY_BROWSER_URL": url.absoluteString])
        let wide = usesColumns(in: app)
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let draft = "Unsent while following a biography browser link"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), app: app)
        if !wide { back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app) }
        setSearch("Copper", in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        openAbout(in: app)
        let sourceLink = biographyLink("Open local biography page", in: app)
        let sourceY = sourceLink.frame.minY
        tap(sourceLink, description: "Open the test-owned biography page in Safari", in: app)
        let requestedTarget = try await server.waitForRequest(in: self)
        XCTAssertEqual(requestedTarget, ProfileBiographyBrowserServer.requestTarget,
                       "Safari must retain the authored path and query; fragments stay in the browser.")
        let marker = app.webViews.staticTexts[ProfileBiographyBrowserServer.pageMarker].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Safari must display the actual loopback page.")
        XCTAssertTrue(waitUntilHittable(marker, timeout: 10))
        keepScreenshot("Profile biography – local page in Safari", in: app)
        var close: XCUIElement?
        XCTAssertTrue(waitForCondition {
            close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Done"]))
                .allElementsBoundByIndex.first(where: { $0.isHittable })
            return close != nil
        }, "Safari must expose its system dismissal control.")
        guard let close else { return }
        tap(close, description: "Return from Safari to About", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        let restoredLink = biographyWebView(in: app).links["Open local biography page"].firstMatch
        XCTAssertTrue(waitUntilHittable(restoredLink, timeout: 10))
        XCTAssertEqual(restoredLink.frame.minY, sourceY, accuracy: 4,
                       "Safari dismissal must restore the biography reading position without a repair gesture.")
        keepScreenshot("Profile biography – Safari dismissal resumes About", in: app)
        back(from: "About", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        if wide {
            XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app), timeout: 10))
        }
        cancelInboxSearch(in: app)
        if !wide {
            openInboxConversation(firstPeerID, in: app)
            XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, presentation: .nativePush, in: app), timeout: 10))
        } else {
            assertWideRoot(in: app)
            assertInboxSelection(firstPeerID, in: app)
        }
    }
    #endif

    func testCompactPlayerSearchBackPreservesQueryAndDraft() throws {
        let app = launchMessages()
        try requireCompact(in: app)
        setSearch("Copper", in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        let draft = "Unsent search conversation"
        enterDraft(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                presentation: .nativePush, in: app), app: app)
        openConversationProfile(searchPlayerID, username: "CopperKoi", in: app)
        back(from: "CopperKoi", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .nativePush, in: app), timeout: 10),
                      "Reopening the searched peer must restore its own draft.")
    }

    func testCompactInlineFriendConversationBackRestoresMessages() throws {
        let app = launchMessages()
        try requireCompact(in: app)
        assertDefaultFriendsStrip(in: app)
        expandFriends(in: app)
        tapFriend(friendID, in: app)
        let draft = "Unsent from inline Friends"
        enterDraft(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                presentation: .nativePush, in: app), app: app)
        openConversationProfile(friendID, username: "BambooPath", in: app)
        back(from: "BambooPath", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        tapVisible("messages.challenge.\(friendID)", in: app)
        assertChallenge(for: "BambooPath", in: app)
        back(from: "Challenge", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
        back(from: "BambooPath", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "Inline Friends must not leave a Friends destination below the conversation.")
        XCTAssertFalse(visibleElement("messages.friend.message.\(friendID)", in: app).isSelected,
                       "The compact inbox must not mark a friend as a displayed conversation after Back.")
        // Expansion uses ordinary view lifetime; Back need not force either form.
        tapFriend(friendID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("BambooPath", peerID: friendID,
                                                               presentation: .nativePush, in: app), timeout: 10))
    }

    func testPlayerSearchProfileBackAndMessageOnlyActions() {
        let app = launchMessages()
        let wide = usesColumns(in: app)
        let bounds = wide ? assertWideRoot(in: app) : nil
        assertDefaultFriendsStrip(in: app)
        setSearch("Copper", in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        assertSearchActionsOnly(for: searchPlayerID, in: app)
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        if let bounds {
            assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        }
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        cancelInboxSearch(in: app)
        setSearch("Bamboo", in: app)
        assertSearch("Bamboo", playerID: friendID, in: app)
        assertSearchActionsOnly(for: friendID, in: app)
        let friendProfile = visibleElement("messages.search.profile.\(friendID)", in: app)
        XCTAssertEqual(friendProfile.value as? String, "7k · Friend",
                       "The local friend's rank and friendship must be accessible together.")
        tap("messages.search.message.\(friendID)", in: app, matching: .button)
        assertConversation("BambooPath", peerID: friendID, presentation: wide ? .wideRoot : .nativePush, in: app)
        if !wide { back(from: "BambooPath", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app) }
        assertSearch("Bamboo", playerID: friendID, in: app)
        cancelInboxSearch(in: app)
        if wide { assertConversation("BambooPath", peerID: friendID, presentation: .wideRoot, in: app) }
        assertDefaultFriendsStrip(in: app)
    }

    func testConversationUsernameProfileBackPreservesDraft() {
        let app = launchMessages()
        let wide = usesColumns(in: app)
        let bounds = wide ? assertWideRoot(in: app) : nil
        if !wide { openInboxConversation(firstPeerID, in: app) }
        let draft = "Unsent while viewing the conversation peer"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), app: app)

        tapVisible("messages.conversation.profile.\(firstPeerID)", in: app)
        assertLoadedProfile(named: "hakhoa", in: app)
        if let bounds {
            assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        }
        keepScreenshot("Conversation username opens peer Profile", in: app)
        back(from: "hakhoa", to: wide ? SurroundUITestContract.AccessibilityID.screenMessages : "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), timeout: 10),
                      "Back from the username's Profile must retain the selected peer and unsent draft.")
        keepScreenshot("Conversation username Profile Back retains draft", in: app)
    }

    func testWideFullWidthProfileAndChallengeBackRestoreRootDraftAndQuery() throws {
        let app = launchMessages()
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let draft = "Unsent wide root conversation"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                presentation: .wideRoot, in: app), app: app)
        setSearch("Copper", in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        let searchBounds = element("messages.playerSearchField", in: app, matching: .textField).frame
        let detailBounds = element("messages.detailPane", in: app).frame
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideSearchRoot(in: app, searchBounds: searchBounds, detailBounds: detailBounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        tapVisible("messages.challenge.\(firstPeerID)", in: app)
        assertChallenge(for: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenCustomGame, over: bounds, in: app)
        back(from: "Challenge", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideSearchRoot(in: app, searchBounds: searchBounds, detailBounds: detailBounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "Back must restore the wide root without a conversation pushed over it.")
    }

    func testWideProfileMessageNativeBackRestoresProfileThenRootSelection() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app, matching: .button)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .nativePush, in: app)
        assertFullWidthDestination("messages.conversation", over: bounds, in: app)
        revealNativeOlderHistory(username: "hakhoa", index: 25, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "hakhoa", in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        // The same peer has separate live root and pushed transcripts. Native
        // Back must resume the root's latest view rather than the push's history.
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        openInboxConversation(firstPeerID, in: app)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertLatestHistoryVisible(username: "hakhoa", in: app)
        let rootDraft = "Unsent original root peer"
        enterDraft(rootDraft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                    presentation: .wideRoot, in: app), app: app)
        setSearch("Copper", in: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        let searchBounds = element("messages.playerSearchField", in: app, matching: .textField).frame
        let detailBounds = element("messages.detailPane", in: app).frame
        tap("messages.search.profile.\(searchPlayerID)", in: app, matching: .button)
        assertLoadedProfile(named: "CopperKoi", in: app)
        tap(SurroundUITestContract.AccessibilityID.profileMessage, in: app, matching: .button)
        let nestedDraft = "Unsent native Profile message"
        enterDraft(nestedDraft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                      presentation: .nativePush, in: app), app: app)
        assertFullWidthDestination("messages.conversation", over: bounds, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app)
        assertLoadedProfile(named: "CopperKoi", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "CopperKoi", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideSearchRoot(in: app, searchBounds: searchBounds, detailBounds: detailBounds)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertTrue(waitForValue(rootDraft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                                   presentation: .wideRoot, in: app), timeout: 10),
                      "A shared native push must not replace the root's independently selected peer.")
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        XCTAssertTrue(waitForValue(nestedDraft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                                     presentation: .wideRoot, in: app), timeout: 10),
                      "Root selection must restore the draft created for that peer in the native push.")
        XCTAssertNil(visibleBack(from: "Messages", in: app))
    }

    func testWideInlineFriendsAndSearchCancelRetainLatestPeer() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        assertInboxSelection(firstPeerID, in: app)
        let stripPrefix = visibleFriendPrefix("messages.friends.strip", in: app)
        XCTAssertEqual(stripPrefix.first, "messages.friend.message.\(SurroundUITestContract.messagesOverflowRecentFriendID)",
                       "A recent friend's conversation must take priority over alphabetical order.")
        XCTAssertEqual(stripPrefix.dropFirst().first, "messages.friend.message.\(friendID)")
        let expanded = expandFriends(in: app,
            expectedFriendIDs: Array(801_001...801_006) + SurroundUITestContract.messagesOverflowFriendIDs)
        XCTAssertTrue(expanded, "The overflow fixture must expose inline expansion.")
        XCTAssertEqual(visibleFriendPrefix("messages.friends.grid", in: app), stripPrefix,
                       "Expansion must preserve the same recent-first ordering as the strip.")
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertInboxSelection(firstPeerID, in: app)
        tapFriend(SurroundUITestContract.messagesOverflowRecentFriendID, in: app)
        assertConversation("RainyGrove", peerID: SurroundUITestContract.messagesOverflowRecentFriendID,
                           presentation: .wideRoot, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app),
                     "A direct inline friend selection must remain in the wide root.")
        if expanded { collapseFriends(in: app) }
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        assertInboxSelection(secondPeerID, in: app)
        setSearch("Copper", in: app)
        tap("messages.search.message.\(searchPlayerID)", in: app, matching: .button)
        let draft = "Unsent latest search recipient"
        enterDraft(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                presentation: .wideRoot, in: app), app: app)
        assertSearch("Copper", playerID: searchPlayerID, in: app)
        XCTAssertNil(visibleBack(from: "Messages", in: app))
        cancelInboxSearch(in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("CopperKoi", peerID: searchPlayerID,
                                                               presentation: .wideRoot, in: app), timeout: 10),
                      "Cancel must keep the latest selected recipient and exact draft.")
        // CopperKoi has no thread fixture; neither existing thread is selected.
        assertInboxSelection(nil, in: app)
        assertDefaultFriendsStrip(in: app)
    }

    func testReadingOnePeerPreservesOtherUnreadThreadAndPeerDrafts() {
        let app = launchMessages()
        let wide = usesColumns(in: app)
        if wide {
            assertConversation("hakhoa", peerID: firstPeerID, in: app)
            assertUnread(false, peerID: firstPeerID, in: app)
        } else {
            assertUnread(true, peerID: firstPeerID, in: app)
            openInboxConversation(firstPeerID, in: app)
        }
        let firstDraft = "Unsent draft for hakhoa"
        enterDraft(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), app: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        back(from: "hakhoa", to: "messages.conversation", in: app)
        XCTAssertTrue(waitForValue(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), timeout: 10))
        if !wide {
            back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        assertUnread(false, peerID: firstPeerID, in: app)
        assertUnread(true, peerID: secondPeerID, in: app)

        openInboxConversation(secondPeerID, in: app)
        let secondComposer = assertConversation("khoahong", peerID: secondPeerID, in: app)
        assertEmptyComposer(secondComposer)
        let secondDraft = "Unsent draft for khoahong"
        enterDraft(secondDraft, in: secondComposer, app: app)
        if !wide {
            back(from: "khoahong", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        assertUnread(false, peerID: secondPeerID, in: app)
        openInboxConversation(firstPeerID, in: app)
        XCTAssertTrue(waitForValue(firstDraft, in: assertConversation("hakhoa", peerID: firstPeerID, in: app), timeout: 10),
                      "Switching peers must restore the first peer's draft without leaking the second peer's text.")
        if !wide {
            back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        }
        openInboxConversation(secondPeerID, in: app)
        XCTAssertTrue(waitForValue(secondDraft, in: assertConversation("khoahong", peerID: secondPeerID, in: app), timeout: 10),
                      "Each peer must retain its own unsent draft after repeated navigation.")
    }

    func testWideScrolledInboxAndPeerHistorySurviveProfileBackAndPeerSwitches() throws {
        let app = launchMessages(additionalLaunchArguments: [SurroundUITestContract.messagesOverflowLaunchArgument])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let allFriendIDs = Array(801_001...801_006) + SurroundUITestContract.messagesOverflowFriendIDs
        XCTAssertTrue(expandFriends(in: app, expectedFriendIDs: allFriendIDs),
                      "The opt-in overflow fixture must offer a real expanded grid.")
        let anchorID = "messages.friend.message.914040"
        let friendAnchor = inboxElement(anchorID, in: app)
        let anchorFrame = friendAnchor.frame
        XCTAssertFalse(query("messages.friends.toggle", in: app).isHittable,
                       "The Friends anchor must be below the initial inbox viewport.")
        revealOlderHistory(username: "hakhoa", index: 25, in: app)
        let firstHistoryWitness = centralVisibleHistoryWitness(username: "hakhoa", in: app)
        openConversationProfile(firstPeerID, username: "hakhoa", in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        back(from: "hakhoa", to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        let restoredFriend = query(anchorID, in: app)
        XCTAssertTrue(waitUntilHittable(restoredFriend, timeout: 10),
                      "Native Back must restore the scrolled inbox's visible friend context.")
        XCTAssertEqual(restoredFriend.frame.minY, anchorFrame.minY, accuracy: 16,
                       "Back must preserve the visible inbox anchor, without a reveal gesture.")
        assertHistoryWitnessVisible(firstHistoryWitness, username: "hakhoa", in: app)

        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        revealOlderHistory(username: "khoahong", index: 40, in: app)
        let secondHistoryWitness = centralVisibleHistoryWitness(username: "khoahong", in: app)
        openInboxConversation(firstPeerID, in: app)
        assertConversation("hakhoa", peerID: firstPeerID, presentation: .wideRoot, in: app)
        assertHistoryWitnessVisible(firstHistoryWitness, username: "hakhoa", in: app)
        openInboxConversation(secondPeerID, in: app)
        assertConversation("khoahong", peerID: secondPeerID, presentation: .wideRoot, in: app)
        assertHistoryWitnessVisible(secondHistoryWitness, username: "khoahong", in: app)
    }

    func testWideInboxRequestRetryAndFullWidthProfileErrorOwnership() throws {
        let app = launchMessages(additionalLaunchArguments: [
            SurroundUITestContract.friendshipLaunchArgument,
            SurroundUITestContract.friendshipFailsOnceLaunchArgument,
        ])
        try requireColumns(in: app)
        let bounds = assertWideRoot(in: app)
        let draft = "Unsent while resolving inbox requests"
        enterDraft(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                presentation: .wideRoot, in: app), app: app)
        let ids = SurroundUITestContract.friendshipFixtureRequestPlayerIDs
        let firstAccept = inboxElement(SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[0]), in: app)
        tap(firstAccept, description: "Accept the offline inbox request whose first response fails", in: app)
        retryFixtureAcceptance(in: app)
        XCTAssertTrue(waitForCondition {
            !self.query(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[0]), in: app).exists
        })
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        let secondProfile = inboxElement(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[1]), in: app)
        let requestCreated = Date(timeIntervalSince1970: 1_789_516_800)
        let relativeAge = requestCreated.formatted(
            Date.RelativeFormatStyle(presentation: .named, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(secondProfile.value as? String, "5k, \(relativeAge)",
                       "The dated request's rank and relative age must be accessible together.")
        tap(secondProfile, description: "Open the other request's full-width Profile", in: app)
        let username = SurroundUITestContract.friendshipFixtureRequestUsernames[1]
        assertLoadedProfile(named: username, in: app)
        assertFullWidthDestination(SurroundUITestContract.AccessibilityID.screenPlayerProfile, over: bounds, in: app)
        let banner = element(SurroundUITestContract.AccessibilityID.profileFriendRequest, in: app)
        let accept = banner.buttons[SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[1])].firstMatch
        tap(accept, description: "Accept the offline request from its visible Profile", in: app)
        retryFixtureAcceptance(in: app)
        XCTAssertTrue(waitForCondition { !banner.exists })
        XCTAssertTrue(waitForCondition {
            self.query(SurroundUITestContract.AccessibilityID.profileFriendshipAction, in: app).label == "Friends"
        })
        back(from: username, to: SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        assertWideRoot(in: app, expectedBounds: bounds)
        XCTAssertTrue(waitForValue(draft, in: assertConversation("hakhoa", peerID: firstPeerID,
                                                               presentation: .wideRoot, in: app), timeout: 10))
        XCTAssertFalse(query(SurroundUITestContract.AccessibilityID.friendRequestProfile(ids[1]), in: app).exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "The covered inbox must not replay Profile's resolved error after Back.")
        inboxElement(SurroundUITestContract.AccessibilityID.friendRequestAccept(ids[2]), in: app)
    }

    private func launchMessages(additionalLaunchArguments: [String] = [],
                                launchEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = launchApp(additionalLaunchArguments: [
            SurroundUITestContract.compatibilityScreenshotLaunchArgument,
            SurroundUITestContract.compatibilitySceneLaunchArgument,
            SurroundUITestContract.CompatibilityScene.messagesInbox.rawValue,
            SurroundUITestContract.profileContentLaunchArgument,
            SurroundUITestContract.messagesContentLaunchArgument,
        ] + additionalLaunchArguments, launchEnvironment: launchEnvironment,
        orientation: UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft)
        element(SurroundUITestContract.AccessibilityID.screenMessages, in: app)
        return app
    }

    @discardableResult
    private func openAbout(in app: XCUIApplication) -> CGRect {
        let scroll = element(SurroundUITestContract.AccessibilityID.screenPlayerProfile, in: app, matching: .scrollView)
        let action = element(SurroundUITestContract.AccessibilityID.profileAbout, in: app, matching: .button)
        for _ in 0..<8 {
            let viewport = unobscuredProfileViewport(scroll, in: app)
            if viewport.contains(action.frame) && action.isHittable { break }
            guard dragScrollView(scroll, axis: .vertical, targetFrame: action.frame,
                                 containerFrame: viewport, interactionPoint: CGVector(dx: 0.5, dy: 0.5),
                                 dragStartPoint: CGPoint(x: viewport.midX, y: viewport.midY),
                                 dragVelocity: XCUIGestureVelocity(rawValue: 60), dragHoldDuration: 0.2) else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let sourceFrame = action.frame
        XCTAssertTrue(unobscuredProfileViewport(scroll, in: app).contains(sourceFrame),
                      "The About row must be clear of the navigation and tab bars before tapping.")
        tap(action, description: "Read the full player biography", in: app)
        element(SurroundUITestContract.AccessibilityID.screenPlayerAbout, in: app)
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 10))
        biographyWebView(in: app)
        return sourceFrame
    }

    private func unobscuredProfileViewport(_ scroll: XCUIElement, in app: XCUIApplication) -> CGRect {
        let bounds = scroll.frame.intersection(app.frame)
        var top = bounds.minY + 12
        var bottom = bounds.maxY - 12
        for bar in app.navigationBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
            top = max(top, bar.frame.maxY + 12)
        }
        for bar in app.tabBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
            bottom = min(bottom, bar.frame.minY - 12)
        }
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: max(0, bottom - top))
    }

    private func revealBiographyInboxAnchor(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let scroll = element("messages.inboxScroll", in: app, matching: .scrollView)
        let anchor = inboxElement(identifier, in: app)
        let viewport = inboxViewport(scroll, in: app)
        XCTAssertTrue(anchor.exists && viewport.contains(anchor.frame) && anchor.isHittable,
                      "The biography journey must begin with a visible scrolled inbox anchor.")
        return anchor
    }

    @discardableResult
    private func biographyWebView(in app: XCUIApplication) -> XCUIElement {
        element(SurroundUITestContract.AccessibilityID.profileBiographyContent, in: app, matching: .webView)
    }

    @discardableResult
    private func biographyLink(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let web = biographyWebView(in: app)
        let link = web.links[label].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "The authored \(label) link must remain accessible.")
        revealBiographyElement(link, in: web, app: app)
        return link
    }

    private func tapBiographyLink(_ label: String, in app: XCUIApplication) {
        tap(biographyLink(label, in: app), description: "Open biography link \(label)", in: app)
    }

    private func biographyText(containing text: String, in app: XCUIApplication) -> XCUIElement {
        let result = biographyWebView(in: app).staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Expected authored or localized biography text \(text).")
        return result
    }

    private func revealBiographyElement(_ target: XCUIElement, in web: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            let viewport = unobscuredProfileViewport(web, in: app).insetBy(dx: 2, dy: 0)
            if target.isHittable && viewport.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) { return }
            let maximumDelta = viewport.height * 0.25
            let targetFrame = target.exists
                ? validInteractionFrame(target.frame, interactionPoint: CGVector(dx: 0.5, dy: 0.5)) : nil
            let requestedDelta = targetFrame.map { viewport.midY - $0.midY } ?? -maximumDelta
            let delta = min(maximumDelta, max(-maximumDelta, requestedDelta))
            guard !viewport.isEmpty, delta.isFinite, abs(delta) >= 12 else { break }
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: viewport.midX - window.frame.minX,
                dy: viewport.midY - window.frame.minY))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)),
                        withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.2)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let viewport = unobscuredProfileViewport(web, in: app).insetBy(dx: 2, dy: 0)
        let revealed = target.isHittable && viewport.contains(CGPoint(x: target.frame.midX, y: target.frame.midY))
        if !revealed {
            keepInteractionHierarchy(target, container: web, in: app, reason: "unable to reveal biography content")
        }
        XCTAssertTrue(revealed, "Biography content must remain reachable within its own scroll view.")
    }

    private func query(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func usesColumns(in app: XCUIApplication) -> Bool {
        let inbox = query("messages.inboxPane", in: app)
        let detail = query("messages.detailPane", in: app)
        return inbox.exists && detail.exists && inbox.frame.width > 1 && detail.frame.width > 1
            && detail.frame.minX >= inbox.frame.maxX - 1
            && query("messages.playerSearchField", in: app).isHittable
    }

    private func requireCompact(in app: XCUIApplication) throws {
        if usesColumns(in: app) {
            throw XCTSkip("Requires the actual compact Messages root; run on an iPhone or Duo Closed.")
        }
    }

    private func requireColumns(in app: XCUIApplication) throws {
        if !usesColumns(in: app) {
            throw XCTSkip("Requires the actual two-column Messages root; run on an iPad or Duo Open/Book.")
        }
    }

    private func visibleElement(_ identifier: String, in app: XCUIApplication,
                                matching type: XCUIElement.ElementType = .button) -> XCUIElement {
        var found: XCUIElement?
        XCTAssertTrue(waitForCondition {
            found = app.descendants(matching: type).matching(identifier: identifier)
                .allElementsBoundByIndex.first(where: { $0.isHittable })
            return found != nil
        }, "Expected a usable \(identifier) on the visible destination.")
        return found ?? query(identifier, in: app)
    }

    private func tapVisible(_ identifier: String, in app: XCUIApplication) {
        tap(visibleElement(identifier, in: app), description: identifier, in: app)
    }

    private func setSearch(_ value: String, in app: XCUIApplication) {
        let field = element("messages.playerSearchField", in: app, matching: .textField)
        tap(field, description: "Focus inbox player search", in: app)
        field.typeText(value)
        XCTAssertTrue(waitForValue(value, in: field, timeout: 10))
    }

    private func assertSearch(_ value: String, playerID: Int, in app: XCUIApplication) {
        XCTAssertTrue(waitForValue(value, in: element("messages.playerSearchField", in: app, matching: .textField), timeout: 10))
        visibleElement("messages.search.profile.\(playerID)", in: app)
        visibleElement("messages.search.message.\(playerID)", in: app)
        element("messages.cancelPlayerSearch", in: app, matching: .button)
    }

    private func assertSearchActionsOnly(for playerID: Int, in app: XCUIApplication) {
        for identifier in [
            "messages.search.challenge.\(playerID)",
            SurroundUITestContract.AccessibilityID.profileFriendshipAction,
            SurroundUITestContract.AccessibilityID.friendRequestAccept(playerID),
            SurroundUITestContract.AccessibilityID.friendRequestReject(playerID),
        ] {
            XCTAssertFalse(query(identifier, in: app).exists, "Search must expose Profile and Message without secondary friendship actions.")
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Sent")).count, 0)
    }

    private func assertDefaultFriendsStrip(in app: XCUIApplication) {
        element("messages.friends.strip", in: app)
        XCTAssertFalse(query("messages.friends.grid", in: app).exists)
        XCTAssertFalse(query("messages.addFriend", in: app).exists)
        XCTAssertFalse(query("messages.friends", in: app).exists, "Friends is inline content, not a destination.")
    }

    private func visibleFriendPrefix(_ identifier: String, in app: XCUIApplication) -> [String] {
        let section = element(identifier, in: app)
        let buttons = section.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "messages.friend.message."
        ))
        return (0..<3).map { index in
            let button = buttons.element(boundBy: index)
            XCTAssertTrue(waitUntilHittable(button, timeout: 10),
                          "The ordered Friends prefix must be visible in its current presentation.")
            return button.identifier
        }
    }

    @discardableResult
    private func expandFriends(in app: XCUIApplication,
                               expectedFriendIDs: [Int] = Array(801_001...801_006)) -> Bool {
        if !query("messages.friends.toggle", in: app).exists {
            let strip = element("messages.friends.strip", in: app)
            XCTAssertTrue(expectedFriendIDs.allSatisfy { id in
                let friend = strip.buttons["messages.friend.message.\(id)"].firstMatch
                return friend.exists && friend.isHittable
                    && friend.frame.minX >= strip.frame.minX - 1
                    && friend.frame.maxX <= strip.frame.maxX + 1
            }, "The toggle may be absent only when every friend fits in the measured row.")
            return false
        }
        tap(inboxElement("messages.friends.toggle", in: app), description: "Expand inline Friends", in: app)
        element("messages.friends.grid", in: app)
        XCTAssertFalse(query("messages.friends.strip", in: app).exists)
        return true
    }

    private func collapseFriends(in app: XCUIApplication) {
        tap(inboxElement("messages.friends.toggle", in: app), description: "Restore the horizontal Friends row", in: app)
        assertDefaultFriendsStrip(in: app)
    }

    private func tapFriend(_ peerID: Int, in app: XCUIApplication) {
        tap(inboxElement("messages.friend.message.\(peerID)", in: app), description: "Select inline friend \(peerID)", in: app)
    }

    @discardableResult
    private func inboxElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let scroll = element("messages.inboxScroll", in: app, matching: .scrollView)
        // Lazy friend rows must be revealed before requiring AX existence.
        let candidate = scroll.descendants(matching: .button).matching(identifier: identifier).firstMatch
        for _ in 0..<8 {
            let viewport = inboxViewport(scroll, in: app)
            if candidate.exists && viewport.contains(candidate.frame) && candidate.isHittable { return candidate }
            dragMessagesViewport(viewport, toward: candidate.exists ? candidate.frame : nil,
                                 earlierWhenAbsent: false, in: app)
        }
        XCTAssertTrue(waitForCondition {
            candidate.exists && self.inboxViewport(scroll, in: app).contains(candidate.frame) && candidate.isHittable
        },
                      "Expected \(identifier) to be fully readable inside its inbox viewport after bounded scrolling.")
        return candidate
    }

    private func messagesViewport(_ bounds: CGRect, in app: XCUIApplication) -> CGRect {
        let bounds = bounds.intersection(app.windows.firstMatch.frame).intersection(app.frame)
        guard !bounds.isEmpty, !bounds.isNull, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return .zero }
        var top = bounds.minY
        var bottom = bounds.maxY
        for bar in app.navigationBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
            top = max(top, bar.frame.maxY)
        }
        for bar in app.tabBars.allElementsBoundByIndex where bar.frame.intersects(bounds) {
            bottom = min(bottom, bar.frame.minY)
        }
        for keyboard in app.keyboards.allElementsBoundByIndex where keyboard.frame.intersects(bounds) {
            bottom = min(bottom, keyboard.frame.minY)
        }
        // Keyboard AX can omit the input-assistant strip. The visible peer
        // composer supplies a measured boundary for both Messages panes.
        let composers = app.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
        if let composer = composers.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            bottom = min(bottom, composer.frame.minY)
        }
        guard bottom > top + 24, bounds.width > 16 else { return .zero }
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
            .insetBy(dx: 8, dy: 12)
    }

    private func inboxViewport(_ scroll: XCUIElement, in app: XCUIApplication) -> CGRect {
        // This is also polled inside waitForCondition; avoid nested waits.
        guard scroll.exists else { return .zero }
        let pane = query("messages.inboxPane", in: app)
        let bounds = pane.exists ? scroll.frame.intersection(pane.frame) : scroll.frame
        let viewport = messagesViewport(bounds, in: app)
        guard !viewport.isEmpty else { return .zero }
        let search = app.textFields.matching(identifier: "messages.playerSearchField").firstMatch
        let top = search.exists ? max(viewport.minY, search.frame.maxY + 12) : viewport.minY
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top))
    }

    private func transcriptViewport(_ transcript: XCUIElement, above composer: XCUIElement,
                                    within paneBounds: CGRect, in app: XCUIApplication) -> CGRect {
        let viewport = messagesViewport(transcript.frame.intersection(paneBounds), in: app)
        guard !viewport.isEmpty else { return .zero }
        let heading = query("messages.conversation.heading", in: app)
        let top = heading.exists && heading.isHittable && heading.frame.intersects(paneBounds)
            ? max(viewport.minY, heading.frame.maxY + 12) : viewport.minY
        let bottom = min(viewport.maxY, composer.frame.minY - 12)
        return CGRect(x: viewport.minX, y: top, width: viewport.width,
                      height: max(0, bottom - top))
    }

    private func dragMessagesViewport(_ viewport: CGRect, toward target: CGRect?,
                                      earlierWhenAbsent: Bool, in app: XCUIApplication) {
        XCTAssertFalse(viewport.isEmpty, "A Messages scroll gesture needs an unobscured viewport.")
        guard !viewport.isEmpty else { return }
        let target = target.flatMap { frame in
            !frame.isEmpty && !frame.isNull && frame.minY.isFinite && frame.height.isFinite ? frame : nil
        }
        let maximumDelta = viewport.height * 0.8
        let requestedDelta = target.map { viewport.midY - $0.midY }
            ?? (earlierWhenAbsent ? maximumDelta : -maximumDelta)
        let delta = min(maximumDelta, max(-maximumDelta, requestedDelta))
        guard abs(delta) >= min(12, maximumDelta) else { return }
        let startY = delta > 0 ? viewport.minY + viewport.height * 0.1
            : viewport.maxY - viewport.height * 0.1
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: viewport.midX - window.frame.minX, dy: startY - window.frame.minY))
        // Both contacts stay in the measured viewport, even when AX includes
        // the sidebar, composer, or keyboard in a ScrollView's full bounds.
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)),
                    withVelocity: target == nil ? .fast : .slow, thenHoldForDuration: 0)
    }

    private func cancelInboxSearch(in app: XCUIApplication) {
        tap("messages.cancelPlayerSearch", in: app, matching: .button)
        XCTAssertTrue(waitForCondition { !self.query("messages.cancelPlayerSearch", in: app).exists })
        element("messages.inboxScroll", in: app, matching: .scrollView)
    }

    private func openInboxConversation(_ peerID: Int, in app: XCUIApplication) {
        tap(inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app),
            description: "Select fixture conversation \(peerID)", in: app)
    }

    @discardableResult
    private func assertConversation(_ username: String, peerID: Int,
                                    presentation: ConversationPresentation? = nil, in app: XCUIApplication) -> XCUIElement {
        let composer = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                                      in: app, matching: .textField)
        XCTAssertEqual(composer.placeholderValue, "Message \(username)")
        let activeComposers = app.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
            .allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(activeComposers.count, 1, "One visible conversation composer must own interaction.")
        let profile = visibleElement(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peerID), in: app)
        XCTAssertTrue(profile.label.contains(username))
        if (presentation ?? (usesColumns(in: app) ? .wideRoot : .nativePush)) == .wideRoot {
            let heading = element("messages.conversation.heading", in: app)
            let identity = heading.buttons["messages.conversation.profile.\(peerID)"].firstMatch
            XCTAssertTrue(waitUntilHittable(identity, timeout: 10), "The wide root must visibly identify its selected peer.")
            XCTAssertTrue(identity.label.contains(username))
        }
        return composer
    }

    private func enterDraft(_ value: String, in composer: XCUIElement, app: XCUIApplication) {
        tap(composer, description: "Focus the private-message draft", in: app)
        // Return submits messages. Draft journeys never type it.
        let firstCharacter = String(value.prefix(1))
        // Confirm input readiness before the remaining keyboard events. This
        // does not retry or repair a partially entered draft.
        composer.typeText(firstCharacter)
        XCTAssertTrue(waitForValue(firstCharacter, in: composer, timeout: 10),
                      "The focused composer must receive the first keyboard event exactly.")
        composer.typeText(String(value.dropFirst()))
        XCTAssertTrue(waitForValue(value, in: composer, timeout: 10))
    }

    private func openConversationProfile(_ peerID: Int, username: String, in app: XCUIApplication) {
        tapVisible(SurroundUITestContract.AccessibilityID.profileMessageToolbarEntry(peerID), in: app)
        assertLoadedProfile(named: username, in: app)
    }

    private func assertChallenge(for username: String, in app: XCUIApplication) {
        element(SurroundUITestContract.AccessibilityID.screenCustomGame, in: app)
        XCTAssertTrue(app.navigationBars["Challenge"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(SurroundUITestContract.AccessibilityID.customGameOpponent, in: app).label.contains(username))
    }

    private func assertWideSearchRoot(in app: XCUIApplication, searchBounds: CGRect, detailBounds: CGRect) {
        assertWideRoot(in: app)
        // Scroll-view AX groups can include offscreen extents. Compare the visible
        // search control and detail pane in the same retained search presentation.
        let search = element("messages.playerSearchField", in: app, matching: .textField).frame
        let detail = element("messages.detailPane", in: app).frame
        XCTAssertEqual(search.minX, searchBounds.minX, accuracy: 2)
        XCTAssertEqual(search.maxX, searchBounds.maxX, accuracy: 2)
        XCTAssertEqual(detail.minX, detailBounds.minX, accuracy: 2)
        XCTAssertEqual(detail.maxX, detailBounds.maxX, accuracy: 2)
    }

    @discardableResult
    private func assertWideRoot(in app: XCUIApplication, expectedBounds: CGRect? = nil) -> CGRect {
        let inbox = element("messages.inboxPane", in: app)
        let detail = element("messages.detailPane", in: app)
        XCTAssertTrue(query("messages.playerSearchField", in: app).isHittable)
        XCTAssertGreaterThan(inbox.frame.width, 1)
        XCTAssertGreaterThan(detail.frame.width, 1)
        XCTAssertGreaterThanOrEqual(detail.frame.minX, inbox.frame.maxX - 1)
        let bounds = inbox.frame.union(detail.frame)
        if let expectedBounds {
            XCTAssertEqual(bounds.minX, expectedBounds.minX, accuracy: 2)
            XCTAssertEqual(bounds.width, expectedBounds.width, accuracy: 2)
        }
        return bounds
    }

    private func assertFullWidthDestination(_ identifier: String, over bounds: CGRect, in app: XCUIApplication) {
        var destination: XCUIElement?
        XCTAssertTrue(waitForCondition {
            destination = app.descendants(matching: .any).matching(identifier: identifier)
                .allElementsBoundByIndex.first {
                    $0.frame.width >= bounds.width * 0.9 && $0.frame.intersects(bounds)
                }
            return destination != nil
        }, "The pushed destination must span the allocated Messages content, including both root columns.")
        if let destination {
            XCTAssertLessThanOrEqual(destination.frame.minX, bounds.minX + 24)
            XCTAssertGreaterThanOrEqual(destination.frame.maxX, bounds.maxX - 24)
        }
        XCTAssertFalse(query("messages.playerSearchField", in: app).isHittable, "The full-width push must cover root inbox controls.")
        let detail = query("messages.detailPane", in: app)
        if detail.exists {
            for composer in detail.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
                .allElementsBoundByIndex {
                XCTAssertFalse(composer.isHittable, "The retained root composer must yield interaction to the pushed destination.")
            }
        }
    }

    private func visibleBack(from title: String, in app: XCUIApplication) -> XCUIElement? {
        let identified = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back"))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        if let identified { return identified }
        let buttons = app.navigationBars[title].exists ? app.navigationBars[title].buttons : app.navigationBars.buttons
        let named = buttons.matching(NSPredicate(format: "label IN %@", ["Messages", "hakhoa", "khoahong", "CopperKoi", "BambooPath", "About", "Profile", "Game"] + SurroundUITestContract.friendshipFixtureRequestUsernames))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        if let named { return named }
        // Older systems label Back with the authored game's full name. Use
        // the titled pushed bar's first control, as the shared journey helper does.
        return app.navigationBars[title].exists
            ? app.navigationBars[title].buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) : nil
    }

    private func back(from title: String, to destination: String, in app: XCUIApplication) {
        var control: XCUIElement?
        XCTAssertTrue(waitForCondition {
            control = self.visibleBack(from: title, in: app)
            return control != nil
        }, "A native push must retain a usable Back control.")
        guard let control else { return }
        tap(control, description: "Back from \(title)", in: app)
        let usable: XCUIElement
        switch destination {
        case "messages.conversation":
            usable = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer, in: app, matching: .textField)
        case SurroundUITestContract.AccessibilityID.screenMessages:
            usable = visibleElement("messages.playerSearchField", in: app, matching: .textField)
        case SurroundUITestContract.AccessibilityID.screenPlayerProfile:
            let about = query(SurroundUITestContract.AccessibilityID.profileAbout, in: app)
            if about.exists && about.isHittable {
                // About was opened from this retained row. At accessibility
                // sizes the profile actions can be below its viewport.
                usable = about
            } else {
                let message = query(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
                usable = message.exists ? visibleElement(SurroundUITestContract.AccessibilityID.profileMessage, in: app)
                    : visibleElement(SurroundUITestContract.AccessibilityID.profileEdit, in: app)
            }
        case SurroundUITestContract.AccessibilityID.screenPlayerAbout:
            usable = biographyWebView(in: app)
        default:
            if destination.hasPrefix("game.detail.") {
                usable = element(SurroundUITestContract.AccessibilityID.gameBoard, in: app)
            } else {
                XCTFail("No restored-control assertion for \(destination)")
                return
            }
        }
        XCTAssertTrue(usable.isHittable, "Back must restore a usable control on its originating screen.")
    }

    private func assertUnread(_ unread: Bool, peerID: Int, in app: XCUIApplication) {
        let row = inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app)
        XCTAssertTrue(waitForCondition { ((row.value as? String) == "Unread conversation") == unread },
                      "Only the viewed peer's unread marker should clear.")
    }

    private func assertInboxSelection(_ selectedPeerID: Int?, in app: XCUIApplication) {
        for peerID in [firstPeerID, secondPeerID] {
            let row = inboxElement(SurroundUITestContract.AccessibilityID.privateMessageRow(peerID), in: app)
            XCTAssertTrue(waitForCondition { row.isSelected == (selectedPeerID == peerID) })
        }
    }

    private func rootTranscript(in app: XCUIApplication) -> XCUIElement {
        let detail = element("messages.detailPane", in: app)
        let transcript = detail.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        return transcript
    }

    private func nativeTranscript(over bounds: CGRect, in app: XCUIApplication) -> XCUIElement {
        var transcript: XCUIElement?
        XCTAssertTrue(waitForCondition {
            let destination = app.descendants(matching: .any).matching(identifier: "messages.conversation")
                .allElementsBoundByIndex.first { conversation in
                    conversation.frame.width >= bounds.width * 0.9 && conversation.frame.intersects(bounds)
                        && conversation.textFields.matching(identifier: SurroundUITestContract.AccessibilityID.privateMessageComposer)
                            .allElementsBoundByIndex.contains(where: { $0.isHittable })
                }
            transcript = destination?.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
            return transcript?.exists == true
        }, "Older-history gestures must target the active full-width conversation, not the retained root transcript.")
        return transcript ?? app.scrollViews[SurroundUITestContract.AccessibilityID.profileConversation].firstMatch
    }

    private func revealNativeOlderHistory(username: String, index: Int, over bounds: CGRect, in app: XCUIApplication) {
        let transcript = nativeTranscript(over: bounds, in: app)
        let composer = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                                      in: app, matching: .textField)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        for _ in 0..<8 {
            let viewport = transcriptViewport(transcript, above: composer, within: bounds, in: app)
            if marker.exists && viewport.contains(marker.frame) && marker.isHittable { break }
            dragMessagesViewport(viewport, toward: marker.exists ? marker.frame : nil,
                                 earlierWhenAbsent: true, in: app)
        }
        XCTAssertTrue(marker.exists && transcriptViewport(transcript, above: composer, within: bounds, in: app).contains(marker.frame) && marker.isHittable,
                      "The native push must reach a fully visible older message before Back.")
        XCTAssertFalse(transcript.staticTexts["Offline message from \(username)"].firstMatch.isHittable)
    }

    private func assertLatestHistoryVisible(username: String, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertTrue(waitUntilHittable(latest, timeout: 10),
                      "The retained root must resume its latest message without a repair gesture.")
        let older = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: 25)
        )).firstMatch
        XCTAssertFalse(older.isHittable, "The pushed conversation's older context must not replace the root's latest view.")
    }

    private func revealOlderHistory(username: String, index: Int, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let pane = element("messages.detailPane", in: app)
        let composer = visibleElement(SurroundUITestContract.AccessibilityID.privateMessageComposer,
                                      in: app, matching: .textField)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        for _ in 0..<8 {
            let viewport = transcriptViewport(transcript, above: composer, within: pane.frame, in: app)
            if marker.exists && viewport.contains(marker.frame) && marker.isHittable { break }
            dragMessagesViewport(viewport, toward: marker.exists ? marker.frame : nil,
                                 earlierWhenAbsent: true, in: app)
        }
        XCTAssertTrue(marker.exists && transcriptViewport(transcript, above: composer, within: pane.frame, in: app).contains(marker.frame) && marker.isHittable,
                      "The older message seed must be fully inside the transcript viewport before navigation.")
        assertOlderHistoryVisible(username: username, index: index, in: app)
    }

    private func assertOlderHistoryVisible(username: String, index: Int, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(
            format: "label == %@",
            SurroundUITestContract.messagesOverflowHistoryText(username: username, index: index)
        )).firstMatch
        XCTAssertTrue(waitUntilHittable(marker, timeout: 10),
                      "The selected peer must restore its own older message context without scrolling again.")
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertFalse(latest.isHittable, "History restoration must not silently jump to the newest message.")
    }

    private func centralVisibleHistoryWitness(username: String, in app: XCUIApplication) -> String {
        let transcript = rootTranscript(in: app)
        let detail = element("messages.detailPane", in: app)
        let composer = detail.textFields[SurroundUITestContract.AccessibilityID.privateMessageComposer].firstMatch
        XCTAssertTrue(waitUntilHittable(composer, timeout: 10))
        let bounds = transcript.frame.intersection(app.windows.firstMatch.frame)
        // The ScrollView may extend beneath the composer. Capture only a
        // readable message from the actual unobscured transcript viewport.
        let viewport = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                              height: max(0, min(bounds.maxY, composer.frame.minY) - bounds.minY))
            .insetBy(dx: 8, dy: 8)
        let visible = transcript.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@",
            "Offline history ", " for \(username)\n"
        )).allElementsBoundByIndex.compactMap { message -> (label: String, midY: CGFloat)? in
            let frame = message.frame
            guard viewport.contains(frame) && message.isHittable else { return nil }
            return (message.label, frame.midY)
        }.sorted { $0.midY < $1.midY }
        guard !visible.isEmpty else {
            XCTFail("A readable older-message witness must exist before leaving the peer.")
            return ""
        }
        // Freeze one external AX label before navigation. Native reflow can
        // move it within the viewport; a neighboring label cannot replace it.
        return visible[visible.count / 2].label
    }

    private func assertHistoryWitnessVisible(_ witness: String, username: String, in app: XCUIApplication) {
        let transcript = rootTranscript(in: app)
        let marker = transcript.staticTexts.matching(NSPredicate(format: "label == %@", witness)).firstMatch
        XCTAssertTrue(waitUntilHittable(marker, timeout: 10),
                      "The same pre-navigation reading witness must remain visible without scrolling again.")
        let latest = transcript.staticTexts["Offline message from \(username)"].firstMatch
        XCTAssertFalse(latest.isHittable, "History restoration must not silently jump to the newest message.")
    }

    private func assertEmptyComposer(_ composer: XCUIElement) {
        let value = composer.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == composer.placeholderValue, "A new peer must not inherit another peer's draft.")
    }

    private func retryFixtureAcceptance(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Couldn’t accept friend request"].exists)
        XCTAssertEqual(app.alerts.count, 1, "The visible screen must own one error presenter.")
        tap(alert.buttons["Retry"].firstMatch, description: "Retry the offline failed acceptance", in: app)
        XCTAssertTrue(waitForCondition { !alert.exists })
    }

    private func waitForCondition(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }
}
