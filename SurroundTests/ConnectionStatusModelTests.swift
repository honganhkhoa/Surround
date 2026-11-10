//
//  ConnectionStatusModelTests.swift
//  SurroundTests
//
//  The connection status rules from the in-app notices design: when a drop
//  shows, when OGS can't be reached, when Connected shows, Retry, the network
//  path and windows that leave the screen.
//

import XCTest

final class ConnectionStatusModelTests: XCTestCase {
    private typealias Model = ConnectionStatusModel

    /// One window, driven as `ConnectionStatusSource` drives the model: each
    /// event at the current time, and each deadline delivered as time passes it.
    private struct Window {
        var state = Model.State()
        var now: TimeInterval = 1_000
        var effects: [Model.Effect] = []
        /// What the window shows: like ConnectionStatusSource, it changes only
        /// when an event or a deadline arrives.
        var status = Model.Status.hidden

        var deadline: TimeInterval? { Model.nextDeadline(state, now: now) }
        var connects: Int { effects.filter { $0 == .connect }.count }
        var announcements: [Model.Announcement] {
            effects.compactMap { effect -> Model.Announcement? in
                if case .announce(let announcement) = effect { return announcement }
                return nil
            }
        }

        /// On screen, with the socket open or not, and no effects recorded yet.
        static func onScreen(connected: Bool = true, path: NetworkPathStatus = .satisfied) -> Window {
            var window = Window()
            window.send(.socket(isConnected: connected))
            window.send(.path(path))
            window.send(.visibility(true))
            window.effects = []
            return window
        }

        mutating func send(_ event: Model.Event) {
            effects += Model.reduce(&state, event, now: now)
            status = Model.status(state, now: now)
        }

        mutating func wait(_ seconds: TimeInterval) {
            let end = now + seconds
            while let next = deadline, next <= end {
                now = next
                send(.tick)
            }
            now = end
        }
    }

    // MARK: - Drops and outages

    func testADropShorterThanTwoSecondsShowsNothing() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(1.5)
        XCTAssertEqual(window.status, .hidden, "A drop shows only once it lasts two seconds.")
        window.send(.socket(isConnected: true))
        XCTAssertEqual(window.status, .hidden)
        window.wait(10)
        XCTAssertEqual(window.status, .hidden, "Nobody saw the blip, so no Connected follows it.")
        XCTAssertTrue(window.effects.isEmpty, "A blip is neither announced nor reconnected.")
        XCTAssertNil(window.deadline, "Nothing runs once the socket is back.")
    }

    func testAnOutageSaysReconnectingAfterTwoSecondsThenCantReachOGSAfterThirty() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(2)
        XCTAssertEqual(window.status, .reconnecting)
        XCTAssertEqual(window.announcements, [.reconnecting])
        XCTAssertEqual(window.deadline, 1_030, "Can't reach OGS needs a wake-up 30 s after the drop.")
        window.wait(27.5)
        XCTAssertEqual(window.status, .reconnecting)
        window.wait(0.5)
        XCTAssertEqual(window.status, .unreachable(.timedOut), "30 s after the drop, not after it showed.")
        XCTAssertTrue(window.status.offersRetry)
        XCTAssertEqual(window.announcements, [.reconnecting], "VoiceOver hears it once per outage.")
        XCTAssertNil(window.deadline, "Nothing changes with time alone now.")
    }

    func testConnectedShowsForTwoSecondsOnlyAfterAnOutageThatShowed() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(3)
        window.send(.socket(isConnected: true))
        XCTAssertEqual(window.status, .connected, "Someone saw the outage, so they see it end.")
        XCTAssertFalse(window.status.offersRetry)
        XCTAssertEqual(window.announcements, [.reconnecting, .connected])
        window.wait(1.5)
        XCTAssertEqual(window.status, .connected)
        window.wait(0.5)
        XCTAssertEqual(window.status, .hidden, "Connected shows for two seconds.")
        XCTAssertNil(window.deadline)
    }

    func testADropWhileConnectedShowsKeepsTheOutageOnScreen() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(3)
        window.send(.socket(isConnected: true))
        window.wait(1)
        window.send(.socket(isConnected: false))
        XCTAssertEqual(window.status, .reconnecting, "The outage stays on screen with no blank in between.")
        XCTAssertEqual(window.announcements, [.reconnecting, .connected],
                       "The same outage is not announced again.")
        window.wait(30)
        XCTAssertEqual(window.status, .unreachable(.timedOut), "30 s after the second drop.")
    }

    // MARK: - The network path

    func testLosingTheNetworkIsSaidOnlyOnceTheSocketDrops() {
        var window = Window.onScreen()
        window.send(.path(.unsatisfied))
        window.wait(60)
        XCTAssertEqual(window.status, .hidden, "Outages come from the socket; a working socket outranks the path.")
        window.send(.socket(isConnected: false))
        window.wait(1.5)
        XCTAssertEqual(window.status, .hidden, "A window that has connected waits two seconds, even with no network.")
        window.wait(0.5)
        XCTAssertEqual(window.status, .unreachable(.noNetwork), "With no network there is no 30 s wait.")
        XCTAssertEqual(window.announcements, [.unreachable])

        var switching = Window.onScreen()
        switching.send(.socket(isConnected: false))
        switching.wait(1)
        switching.send(.path(.unsatisfied))
        XCTAssertEqual(switching.status, .hidden,
                       "A path that goes during the wait, as when networks switch, doesn't skip it.")
        switching.wait(0.5)
        XCTAssertEqual(switching.status, .hidden)
        switching.wait(0.5)
        XCTAssertEqual(switching.status, .unreachable(.noNetwork))
        XCTAssertEqual(switching.announcements, [.unreachable])
    }

    func testLosingTheNetworkDuringAnOutageSaysCantReachOGSAtOnce() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(5)
        window.send(.path(.unsatisfied))
        XCTAssertEqual(window.status, .unreachable(.noNetwork))
        XCTAssertEqual(window.announcements, [.reconnecting], "Only the first step of an outage is announced.")
    }

    func testTheNetworkComingBackReconnectsAtOnce() {
        var window = Window.onScreen(path: .unsatisfied)
        window.send(.socket(isConnected: false))
        window.wait(60)
        XCTAssertEqual(window.status, .unreachable(.noNetwork))
        XCTAssertEqual(window.connects, 0)
        window.send(.path(.satisfied))
        XCTAssertEqual(window.connects, 1, "The socket doesn't sit out its backoff once the network is back.")
        XCTAssertEqual(window.status, .reconnecting)
        window.wait(29.5)
        XCTAssertEqual(window.status, .reconnecting, "The fresh attempt restarts the 30 s.")
        window.send(.socket(isConnected: true))
        XCTAssertEqual(window.status, .connected)

        var early = Window.onScreen(path: .unsatisfied)
        early.send(.socket(isConnected: false))
        early.wait(1)
        early.send(.path(.satisfied))
        XCTAssertEqual(early.connects, 1)
        XCTAssertEqual(early.status, .hidden, "A network back during the wait doesn't show the outage early.")
        early.wait(1)
        XCTAssertEqual(early.status, .reconnecting)
    }

    // MARK: - Windows that open before their first connection

    func testAWindowThatOpensOfflineSaysCantReachOGSAtOnce() {
        var window = Window()
        window.send(.socket(isConnected: false))
        window.send(.visibility(true))
        XCTAssertEqual(window.status, .hidden, "No path report yet counts as a network.")
        window.send(.path(.unsatisfied))
        XCTAssertEqual(window.status, .unreachable(.noNetwork), "A window that opens offline says so at once.")
        XCTAssertEqual(window.announcements, [.unreachable])

        // A later window gets the shared monitor's path in its source's init,
        // before it is on screen.
        var laterWindow = Window()
        laterWindow.send(.socket(isConnected: false))
        laterWindow.send(.path(.unsatisfied))
        laterWindow.send(.visibility(true))
        XCTAssertEqual(laterWindow.status, .unreachable(.noNetwork),
                       "A window that opens offline says so at once in either order.")
        XCTAssertEqual(laterWindow.announcements, [.unreachable])
    }

    func testAWindowThatOpensWithANetworkButNoOGSWaitsLikeAnyDrop() {
        var window = Window.onScreen(connected: false)
        window.wait(1.5)
        XCTAssertEqual(window.status, .hidden)
        window.wait(0.5)
        XCTAssertEqual(window.status, .reconnecting)
        window.wait(28)
        XCTAssertEqual(window.status, .unreachable(.timedOut))
        XCTAssertEqual(window.announcements, [.reconnecting])
    }

    func testAFirstConnectionWithinTwoSecondsShowsNothing() {
        var window = Window.onScreen(connected: false)
        window.wait(1.5)
        window.send(.socket(isConnected: true))
        window.wait(10)
        XCTAssertEqual(window.status, .hidden, "A normal launch says nothing about its connection.")
        XCTAssertTrue(window.effects.isEmpty)
    }

    // MARK: - Retry

    func testRetryReconnectsAndRestartsTheClock() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(30)
        XCTAssertEqual(window.status, .unreachable(.timedOut))
        window.send(.retry)
        XCTAssertEqual(window.connects, 1)
        XCTAssertEqual(window.status, .reconnecting, "Retry visibly does something.")
        window.wait(29.5)
        XCTAssertEqual(window.status, .reconnecting, "Retry restarts the 30 s, as connect() restarts the backoff.")
        window.wait(0.5)
        XCTAssertEqual(window.status, .unreachable(.timedOut))
        XCTAssertEqual(window.announcements, [.reconnecting], "A Retry is not announced.")
    }

    func testRetryWithNoNetworkSaysReconnectingForTwoSeconds() {
        var window = Window.onScreen(path: .unsatisfied)
        window.send(.socket(isConnected: false))
        window.wait(2)
        XCTAssertEqual(window.status, .unreachable(.noNetwork))
        window.send(.retry)
        XCTAssertEqual(window.connects, 1)
        XCTAssertEqual(window.status, .reconnecting, "A tap visibly does something, even with no network.")
        XCTAssertEqual(window.deadline, window.now + 2, "The Retry feedback needs a wake-up when it ends.")
        window.wait(2)
        XCTAssertEqual(window.status, .unreachable(.noNetwork))
    }

    func testRetryNeedsAnOutageOnScreen() {
        var window = Window.onScreen()
        window.send(.retry)
        XCTAssertEqual(window.connects, 0, "An open socket needs no reconnect.")
        window.send(.visibility(false))
        window.send(.socket(isConnected: false))
        window.send(.retry)
        XCTAssertEqual(window.connects, 0, "A window off screen offers no Retry.")
    }

    // MARK: - Off screen

    func testAWindowOffScreenForgetsTheOutage() {
        var window = Window.onScreen()
        window.send(.socket(isConnected: false))
        window.wait(5)
        window.send(.visibility(false))
        XCTAssertEqual(window.status, .hidden)
        XCTAssertNil(window.deadline, "Nothing runs for a window nobody sees.")
        window.send(.socket(isConnected: true))
        window.send(.visibility(true))
        XCTAssertEqual(window.status, .hidden, "Nobody saw the outage end, so no Connected.")
        XCTAssertEqual(window.announcements, [.reconnecting])
    }

    func testReturningToTheForegroundWaitsTwoSecondsAgain() {
        var window = Window.onScreen(path: .unsatisfied)
        window.send(.socket(isConnected: false))
        window.wait(5)
        window.send(.visibility(false))
        window.wait(600)
        window.send(.visibility(true))
        XCTAssertEqual(window.status, .hidden, "The stored path may be stale right after a return.")
        window.wait(1.5)
        XCTAssertEqual(window.status, .hidden)
        window.wait(0.5)
        XCTAssertEqual(window.status, .unreachable(.noNetwork))
        XCTAssertEqual(window.announcements, [.unreachable, .unreachable],
                       "An outage seen again after a return is a new one.")
    }

    func testNothingIsScheduledWhileConnected() {
        var window = Window.onScreen()
        XCTAssertNil(window.deadline)
        window.send(.path(.unsatisfied))
        window.send(.path(.satisfied))
        XCTAssertNil(window.deadline, "The offline fixtures never run a timer.")
        XCTAssertEqual(window.connects, 0, "An open socket needs no reconnect.")
    }
}
