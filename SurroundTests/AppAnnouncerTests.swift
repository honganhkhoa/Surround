//
//  AppAnnouncerTests.swift
//  SurroundTests
//
//  VoiceOver announcements and haptics post once per app: on behalf of the
//  window the user is in, and once for copies of one event that several
//  windows report.
//

import XCTest

final class AppAnnouncerTests: XCTestCase {
    private final class Clock {
        var now: TimeInterval = 1_000
    }

    /// A scene-state provider the test sets directly.
    private final class Scenes: AppAnnouncerSceneStates {
        var frontmostWindow: UUID?
        var open = Set<UUID>()
        func isOpen(_ window: UUID) -> Bool { open.contains(window) }
    }

    private final class Output: AppAnnouncerOutput {
        enum Event: Equatable {
            case speech(String, AppAnnouncement.Priority)
            case haptic(AppAnnouncement.Haptic)
        }

        private(set) var events = [Event]()

        var spoken: [String] {
            events.compactMap { event -> String? in
                if case .speech(let text, _) = event { return text }
                return nil
            }
        }

        func speak(_ text: String, priority: AppAnnouncement.Priority) {
            events.append(.speech(text, priority))
        }

        func play(_ haptic: AppAnnouncement.Haptic) {
            events.append(.haptic(haptic))
        }
    }

    private let windowA = UUID()
    private let windowB = UUID()
    private let ownerA = UUID()
    private let ownerB = UUID()

    private func makeAnnouncer(
        _ clock: Clock, _ scenes: AppAnnouncerSceneStates, _ output: Output
    ) -> AppAnnouncer {
        AppAnnouncer(now: { clock.now }, scenes: scenes, output: output)
    }

    private func scenes(open: Set<UUID>, frontmost: UUID?) -> Scenes {
        let scenes = Scenes()
        scenes.open = open
        scenes.frontmostWindow = frontmost
        return scenes
    }

    private func said(
        _ key: AppAnnouncement.Key,
        _ text: String = "Text",
        _ audience: AppAnnouncement.Audience = .frontmostWindow
    ) -> AppAnnouncement {
        AppAnnouncement(key, audience: audience, speech: text)
    }

    // MARK: Which window the user is in

    func testOneWindowIsFrontmostWhileItIsOnScreen() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .inactive)
        XCTAssertEqual(windows.frontmost, windowA, "A window still launching is on screen.")
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
        windows.update(windowA, owner: ownerA, activation: .inactive)
        XCTAssertEqual(windows.frontmost, windowA, "Control Center leaves the one window in front.")
        windows.update(windowA, owner: ownerA, activation: .background)
        XCTAssertNil(windows.frontmost)
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
    }

    func testANewWindowIsWhereTheUserIs() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
        windows.update(windowB, owner: ownerB, activation: .active)
        XCTAssertEqual(windows.frontmost, windowB)
    }

    func testAMacWindowThatBecomesKeyComesToTheFront() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        windows.update(windowB, owner: ownerB, activation: .active)
        XCTAssertEqual(windows.frontmost, windowB)
        windows.update(windowA, owner: ownerA, activation: .active, focused: true)
        XCTAssertEqual(windows.frontmost, windowA)
    }

    func testReturningFromControlCenterKeepsTheOrder() {
        for reactivation in [[windowB, windowA], [windowA, windowB]] {
            var windows = AppAnnouncerWindows()
            let owners = [windowA: ownerA, windowB: ownerB]
            windows.update(windowA, owner: ownerA, activation: .active)
            windows.update(windowB, owner: ownerB, activation: .active)
            windows.update(windowA, owner: ownerA, activation: .inactive)
            windows.update(windowB, owner: ownerB, activation: .inactive)
            XCTAssertEqual(windows.frontmost, windowB)
            for window in reactivation {
                windows.update(window, owner: owners[window]!, activation: .active)
            }
            XCTAssertEqual(windows.frontmost, windowB,
                           "Both scenes activate again, in either order; the user is still in B.")
        }
    }

    func testAWindowBackFromTheBackgroundComesToTheFront() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        windows.update(windowB, owner: ownerB, activation: .active)
        windows.update(windowA, owner: ownerA, activation: .background)
        XCTAssertEqual(windows.frontmost, windowB)
        windows.update(windowA, owner: ownerA, activation: .inactive)
        XCTAssertEqual(windows.frontmost, windowB, "Entering the foreground isn't arriving yet.")
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
    }

    func testAnOnScreenWindowCountsOnlyWhileNoWindowIsActive() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
        windows.update(windowB, owner: ownerB, activation: .inactive)
        XCTAssertEqual(windows.frontmost, windowA)
        windows.update(windowA, owner: ownerA, activation: .background)
        XCTAssertEqual(windows.frontmost, windowB)
    }

    func testFocusOnAWindowThatIsNotActiveIsIgnored() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        windows.update(windowB, owner: ownerB, activation: .active)
        windows.update(windowA, owner: ownerA, activation: .inactive, focused: true)
        XCTAssertEqual(windows.frontmost, windowB)
    }

    func testAWindowRegisteredInTheBackgroundComesForwardWhenItActivates() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        XCTAssertEqual(windows.frontmost, windowA)
        windows.update(windowB, owner: ownerB, activation: .background)
        XCTAssertEqual(windows.frontmost, windowA, "A restored window waits in the background.")
        windows.update(windowB, owner: ownerB, activation: .active)
        XCTAssertEqual(windows.frontmost, windowB)
    }

    func testClosingTheFrontmostWindowHandsTheFrontBack() {
        var windows = AppAnnouncerWindows()
        windows.update(windowA, owner: ownerA, activation: .active)
        windows.update(windowB, owner: ownerB, activation: .active)
        XCTAssertEqual(windows.frontmost, windowB)
        windows.remove(windowB, owner: ownerB)
        XCTAssertEqual(windows.frontmost, windowA)
        XCTAssertFalse(windows.contains(windowB))
    }

    func testAnOldAnchorCannotWithdrawItsReplacement() {
        var windows = AppAnnouncerWindows()
        let old = UUID(), replacement = UUID()
        windows.update(windowA, owner: old, activation: .active)
        windows.update(windowA, owner: replacement, activation: .active)
        windows.remove(windowA, owner: old)
        XCTAssertTrue(windows.contains(windowA),
                      "A reconnected scene's new anchor registered before the old one went.")
        windows.remove(windowA, owner: replacement)
        XCTAssertFalse(windows.contains(windowA))
        XCTAssertNil(windows.frontmost)
    }

    // MARK: Posting

    func testOneWindowHearsEveryDistinctAnnouncementInOrder() {
        // Today's six call sites, as one window posts them in quick succession.
        for activation in [AppAnnouncerWindows.Activation.active, .inactive, .background] {
            let windows = AppAnnouncerWindowRegistry()
            windows.update(windowA, owner: ownerA, activation: activation)
            let clock = Clock(), output = Output()
            let announcer = makeAnnouncer(clock, windows, output)
            let posts: [AppAnnouncement] = [
                said(.quickMatchStarted(["s1", "s2"]), "Searching for 2 correspondence games", .anyWindow),
                said(.quickMatchCancelled("s1"), "Search cancelled", .anyWindow),
                said(.quickMatchCancelled("s2"), "Search cancelled", .anyWindow),
                said(.friendshipResult(UUID()), "Sent friend request", .anyWindow),
                said(.friendshipResult(UUID()), "Friend request accepted", .anyWindow),
                said(.quickMatchNotConfirmed(["s3"]), "OGS did not confirm this search.", .anyWindow),
                said(.quickMatchNotConfirmed(["s3", "s4"]), "OGS did not confirm 2 searches.", .anyWindow),
                said(.quickMatchSearchesEnded, "Your search ended.", .anyWindow),
                said(.gameStarted(901), "Game found", .anyWindow),
            ]
            for post in posts {
                XCTAssertEqual(announcer.post(post, from: windowA), .posted, "\(activation)")
                clock.now += 0.1
            }
            XCTAssertEqual(
                output.spoken, posts.compactMap(\.speech),
                "A single window hears what it heard before: under Control Center, and in the background (A1)."
            )
        }
    }

    func testTheSameEventFromTwoWindowsIsSpokenOnce() {
        let clock = Clock(), output = Output()
        let announcer = makeAnnouncer(clock, scenes(open: [windowA, windowB], frontmost: windowA), output)
        let key = AppAnnouncement.Key("search-cancelled")
        XCTAssertEqual(announcer.post(said(key, "Search cancelled", .anyWindow), from: windowB), .posted)
        clock.now += 0.2
        XCTAssertEqual(announcer.post(said(key, "Search cancelled", .anyWindow), from: windowA), .duplicate)
        XCTAssertEqual(output.spoken, ["Search cancelled"])
    }

    func testAnAnyWindowResultSpeaksFromAWindowBehind() {
        let output = Output()
        let announcer = makeAnnouncer(Clock(), scenes(open: [windowA, windowB], frontmost: windowA), output)
        XCTAssertEqual(
            announcer.post(said(.friendshipResult(UUID()), "Sent friend request", .anyWindow), from: windowB),
            .posted,
            "Moving to another window doesn't silence the result of what the user did in this one."
        )
        XCTAssertEqual(output.spoken, ["Sent friend request"])
    }

    func testOnlyTheFrontmostWindowSpeaksItsOwnEvents() {
        let output = Output()
        let announcer = makeAnnouncer(Clock(), scenes(open: [windowA, windowB], frontmost: windowA), output)
        let key = AppAnnouncement.Key("connection")
        XCTAssertEqual(announcer.post(said(key, "Reconnecting"), from: windowB), .notFrontmost)
        XCTAssertEqual(output.events, [])
        XCTAssertEqual(announcer.post(said(key, "Reconnecting"), from: windowA), .posted,
                       "The dropped copy didn't use up the key.")
        XCTAssertEqual(output.spoken, ["Reconnecting"])
    }

    func testAWindowThatComesToTheFrontDoesNotRepeatWhatWasJustSaid() {
        let clock = Clock(), output = Output()
        let front = scenes(open: [windowA, windowB], frontmost: windowA)
        let announcer = makeAnnouncer(clock, front, output)
        let key = AppAnnouncement.Key("connection")
        XCTAssertEqual(announcer.post(said(key, "Reconnecting"), from: windowA), .posted)
        front.frontmostWindow = windowB
        clock.now += 1
        XCTAssertEqual(announcer.post(said(key, "Reconnecting"), from: windowB), .duplicate)
        XCTAssertEqual(output.spoken, ["Reconnecting"])
    }

    func testAKeyIsSpokenAgainAfterTheInterval() {
        let clock = Clock(), output = Output()
        let announcer = makeAnnouncer(clock, scenes(open: [windowA], frontmost: windowA), output)
        let key = AppAnnouncement.Key("searches-ended")
        XCTAssertEqual(announcer.post(said(key), from: windowA), .posted)
        clock.now = 1_000 + 4.9
        XCTAssertEqual(announcer.post(said(key), from: windowA), .duplicate)
        clock.now = 1_000 + AppAnnouncer.duplicateInterval
        XCTAssertEqual(announcer.post(said(key), from: windowA), .posted)
        XCTAssertEqual(output.spoken, ["Text", "Text"])
    }

    func testOnlyAnyWindowResultsAreSpokenWhileEveryWindowIsInTheBackground() {
        let clock = Clock(), output = Output()
        let front = scenes(open: [windowA, windowB], frontmost: nil)
        let announcer = makeAnnouncer(clock, front, output)
        let ownEvent = AppAnnouncement.Key("connection"), result = AppAnnouncement.Key("search-cancelled")
        XCTAssertEqual(announcer.post(said(ownEvent, "Reconnecting"), from: windowA), .noWindowInFront)
        XCTAssertEqual(output.events, [], "A window's own events wait for a window in front.")
        XCTAssertEqual(announcer.post(said(result, "Search cancelled", .anyWindow), from: windowA), .posted,
                       "A result still posts from the background, as every announcement did before.")
        XCTAssertEqual(output.spoken, ["Search cancelled"])
        clock.now += 0.3
        XCTAssertEqual(announcer.post(said(result, "Search cancelled", .anyWindow), from: windowB), .duplicate,
                       "Another window's copy in the background is the same event.")
        XCTAssertEqual(output.spoken, ["Search cancelled"])
        front.frontmostWindow = windowA
        clock.now += 1
        XCTAssertEqual(announcer.post(said(ownEvent, "Reconnecting"), from: windowA), .posted,
                       "The copy dropped in the background didn't use up its key.")
        XCTAssertEqual(output.spoken, ["Search cancelled", "Reconnecting"])
    }

    func testAClosedWindowNeverSpeaks() {
        let output = Output()
        let announcer = makeAnnouncer(Clock(), scenes(open: [windowA], frontmost: windowA), output)
        XCTAssertEqual(
            announcer.post(said(.quickMatchCancelled("s1"), "Search cancelled", .anyWindow), from: windowB),
            .windowClosed
        )
        XCTAssertEqual(output.events, [])
    }

    func testSpeechAndAHapticShareOneKey() {
        let output = Output()
        let announcer = makeAnnouncer(Clock(), scenes(open: [windowA], frontmost: windowA), output)
        let announcement = AppAnnouncement(
            .gameStarted(7), audience: .frontmostWindow, speech: "Low", haptic: .warning
        )
        XCTAssertEqual(announcer.post(announcement, from: windowA), .posted)
        XCTAssertEqual(output.events, [.speech("Low", .normal), .haptic(.warning)])
        XCTAssertEqual(announcer.post(announcement, from: windowA), .duplicate)
        XCTAssertEqual(output.events, [.speech("Low", .normal), .haptic(.warning)],
                       "A copy neither speaks nor plays.")
    }

    func testPriorityReachesTheOutput() {
        let output = Output()
        let announcer = makeAnnouncer(Clock(), scenes(open: [windowA], frontmost: windowA), output)
        let connected = AppAnnouncement(
            AppAnnouncement.Key("connected"), audience: .frontmostWindow, speech: "Connected", priority: .low
        )
        XCTAssertEqual(announcer.post(connected, from: windowA), .posted)
        XCTAssertEqual(output.events, [.speech("Connected", .low)])
    }

    func testOnlyRecentKeysAreRemembered() {
        let clock = Clock(), output = Output()
        let announcer = makeAnnouncer(clock, scenes(open: [windowA], frontmost: windowA), output)
        for index in 0..<10 {
            XCTAssertEqual(announcer.post(said(AppAnnouncement.Key("key-\(index)")), from: windowA), .posted)
        }
        XCTAssertEqual(announcer.rememberedKeyCount, 10)
        clock.now += AppAnnouncer.duplicateInterval
        XCTAssertEqual(announcer.post(said(AppAnnouncement.Key("key-10")), from: windowA), .posted)
        XCTAssertEqual(announcer.rememberedKeyCount, 1, "Keys older than the interval are forgotten.")
    }

    func testIsFrontmostFollowsTheScenes() {
        let front = scenes(open: [windowA, windowB], frontmost: windowA)
        let announcer = makeAnnouncer(Clock(), front, Output())
        XCTAssertTrue(announcer.isFrontmost(windowA))
        front.frontmostWindow = windowB
        XCTAssertFalse(announcer.isFrontmost(windowA))
        XCTAssertTrue(announcer.isFrontmost(windowB))
    }

    func testKeysNameTheEventWhicheverWindowBuildsThem() {
        typealias Key = AppAnnouncement.Key
        XCTAssertEqual(Key.quickMatchStarted(["b", "a"]), .quickMatchStarted(["a", "b"]))
        XCTAssertEqual(Key.quickMatchNotConfirmed(["b", "a"]), .quickMatchNotConfirmed(["a", "b"]))
        XCTAssertNotEqual(Key.quickMatchCancelled("a"), .quickMatchCancelled("b"))
        XCTAssertNotEqual(Key.quickMatchStarted(["a"]), .quickMatchCancelled("a"))
        XCTAssertNotEqual(Key.friendshipResult(UUID()), .friendshipResult(UUID()))
        XCTAssertEqual(Key.gameStarted(901), .gameStarted(901),
                       "Game found now and Activity's Game started later are one event.")
    }
}
