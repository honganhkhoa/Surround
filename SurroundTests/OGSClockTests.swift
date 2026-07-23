//
//  OGSClockTests.swift
//  SurroundTests
//

import XCTest

final class OGSClockTests: XCTestCase {
    // All scenarios use a fixed last-move timestamp and an explicit `now`, both
    // in milliseconds like the OGS wire format. Fixtures are kept coherent with
    // that contract: `expiration` equals the time left on the running clock added
    // to `last_move`, and simple clocks arrive as scalar millisecond values.
    private let lastMove = 1_700_000_000_000.0

    func testByoYomiMainTimeCountsDown() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 600, periods: 5, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 600, periods: 5, periodTime: 30), pauseControl: nil, now: lastMove + 30_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 570)
        XCTAssertEqual(clock.blackTime.periodsLeft, 5)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 30)
        XCTAssertEqual(clock.whiteTime.thinkingTimeLeft, 600)
    }

    /// The exact moment main time runs out. With 10s main and 30s periods, 40s
    /// elapsed consumes exactly one period, leaving four periods with a full 30s
    /// on the current one — matching goban's `computeNewPlayerClock`.
    func testByoYomiFirstPeriodBoundary() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 10, periods: 5, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 10, periods: 5, periodTime: 30), pauseControl: nil, now: lastMove + 40_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.periodsLeft, 4)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 30)
    }

    func testByoYomiConsumesPeriodsAfterMainTime() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 10, periods: 5, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 10, periods: 5, periodTime: 30), pauseControl: nil, now: lastMove + 95_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.periodsLeft, 3)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 5)
        XCTAssertEqual(clock.blackTime.timeLeft, 5)
    }

    /// Down to the last of two periods, partway through it: one period remains
    /// with the elapsed overtime subtracted from the current period.
    func testByoYomiFinalPeriodBoundary() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 10, periods: 2, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 10, periods: 2, periodTime: 30), pauseControl: nil, now: lastMove + 55_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.periodsLeft, 1)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 15)
    }

    /// Well past every period, periods_left clamps to zero and the effective time
    /// left reads zero — not the leftover period time goban keeps for display.
    func testByoYomiTimeoutShowsNoTimeLeft() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 10, periods: 2, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 10, periods: 2, periodTime: 30), pauseControl: nil, now: lastMove + 200_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.periodsLeft, 0)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.timeLeft, 0)
    }

    /// At exact exhaustion — the last period consumed to the second — the clock
    /// must still read zero rather than a full fresh period.
    func testByoYomiExactExhaustionShowsNoTimeLeft() throws {
        var clock = try makeClock(blackTime: byoYomiTime(thinkingTime: 10, periods: 2, periodTime: 30))

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 10, periods: 2, periodTime: 30), pauseControl: nil, now: lastMove + 70_000)

        XCTAssertEqual(clock.blackTime.periodsLeft, 0)
        XCTAssertEqual(clock.blackTime.periodTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.timeLeft, 0)
    }

    func testCanadianMainTimeOverflowsIntoServerBlockTime() throws {
        // block_time (100) is deliberately different from the time control's
        // period_time (180) so the overtime draws down the server-sent block.
        var clock = try makeClock(blackTime: #"{"thinking_time": 60, "moves_left": 10, "block_time": 100}"#)

        clock.calculateTimeLeft(with: .Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10), pauseControl: nil, now: lastMove + 90_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.blockTimeLeft, 70)
        XCTAssertEqual(clock.blackTime.timeLeft, 70)
    }

    func testCanadianTimeoutClampsBlockToZero() throws {
        var clock = try makeClock(blackTime: #"{"thinking_time": 60, "moves_left": 10, "block_time": 100}"#)

        clock.calculateTimeLeft(with: .Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10), pauseControl: nil, now: lastMove + 300_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(clock.blackTime.blockTimeLeft, 0)
    }

    func testFischerUsesExpirationAndServerTimeOffsetWhileRunning() throws {
        let clock = try makeFischerClock(now: lastMove + 30_000)
        XCTAssertEqual(clock.timeUntilExpiration, 270)
        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 270)
        XCTAssertEqual(clock.whiteTime.thinkingTimeLeft, 300)

        var offsetClock = try makeClock(
            blackTime: #"{"thinking_time": 300}"#,
            extraFields: #""expiration": \#(lastMove + 300_000),"#
        )
        offsetClock.calculateTimeLeft(
            with: .Fischer(initialTime: 300, timeIncrement: 10, maxTime: 300),
            serverTimeOffset: 5000,
            pauseControl: nil,
            now: lastMove + 30_000
        )
        XCTAssertEqual(offsetClock.blackTime.thinkingTimeLeft, 275)
    }

    func testFischerClampsToZeroAfterExpiration() throws {
        let clock = try makeFischerClock(now: lastMove + 360_000)
        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
    }

    func testAbsoluteClampsToZeroAfterExpiration() throws {
        var clock = try makeClock(
            blackTime: #"{"thinking_time": 900}"#,
            extraFields: #""expiration": \#(lastMove + 900_000),"#
        )

        clock.calculateTimeLeft(with: .Absolute(totalTime: 900), pauseControl: nil, now: lastMove + 1_000_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 0)
    }

    func testPausedClockFreezesElapsedTimeAtPauseTime() throws {
        var clock = try makeClock(
            blackTime: #"{"thinking_time": 900}"#,
            extraFields: #""expiration": \#(lastMove + 900_000), "paused_since": \#(lastMove + 10_000),"#
        )
        let weekendPause = try makePauseControl(#"{"weekend": true}"#)

        clock.calculateTimeLeft(with: .Absolute(totalTime: 900), pauseControl: weekendPause, now: lastMove + 500_000)

        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 890)
    }

    /// A scalar clock (simple time) is milliseconds on the wire and must decode to
    /// seconds, independently of the later calculateTimeLeft() overwrite. Asserted
    /// on the non-current player, whose raw value survives decoding untouched.
    func testSimpleScalarClockDecodesMillisecondsToSeconds() throws {
        let clock = try makeClock(
            blackTime: "30000",
            extraFields: #""expiration": \#(lastMove + 30_000),"#
        )

        XCTAssertEqual(clock.whiteTime.thinkingTime, 30)
        XCTAssertEqual(clock.whiteTime.thinkingTimeLeft, 30)
    }

    func testSimpleScalarClockResetsOtherPlayerAndClampsWhenExpired() throws {
        // Simple time controls arrive as scalar millisecond values on the wire.
        var running = try makeClock(
            blackTime: "30000",
            extraFields: #""expiration": \#(lastMove + 30_000),"#
        )
        running.calculateTimeLeft(with: .Simple(perMove: 30), pauseControl: nil, now: lastMove + 5_000)
        XCTAssertEqual(running.blackTime.thinkingTimeLeft, 25)
        XCTAssertEqual(running.whiteTime.thinkingTimeLeft, 30)

        var expired = try makeClock(
            blackTime: "30000",
            extraFields: #""expiration": \#(lastMove + 30_000),"#
        )
        expired.calculateTimeLeft(with: .Simple(perMove: 30), pauseControl: nil, now: lastMove + 40_000)
        XCTAssertEqual(expired.blackTime.thinkingTimeLeft, 0)
        XCTAssertEqual(expired.whiteTime.thinkingTimeLeft, 30)
    }

    func testSimpleClockFreezesWhenPaused() throws {
        var paused = try makeClock(
            blackTime: "30000",
            extraFields: #""expiration": \#(lastMove + 30_000), "paused_since": \#(lastMove + 10_000),"#
        )
        let weekendPause = try makePauseControl(#"{"weekend": true}"#)
        paused.calculateTimeLeft(with: .Simple(perMove: 30), pauseControl: weekendPause, now: lastMove + 500_000)
        XCTAssertEqual(paused.blackTime.thinkingTimeLeft, 20)
        XCTAssertEqual(paused.whiteTime.thinkingTimeLeft, 30)
    }

    func testAutoResignCountdownUsesInjectedNow() throws {
        var clock = try makeClock(
            blackTime: #"{"thinking_time": 300}"#,
            extraFields: #""expiration": \#(lastMove + 300_000),"#
        )
        clock.autoResignTime[.black] = lastMove + 60_000

        clock.calculateTimeLeft(with: .Fischer(initialTime: 300, timeIncrement: 10, maxTime: 300), pauseControl: nil, now: lastMove + 20_000)

        XCTAssertEqual(clock.blackTimeUntilAutoResign, 40)
        XCTAssertNil(clock.whiteTimeUntilAutoResign)
    }

    func testStartModeClockOnlyUpdatesExpiration() throws {
        var clock = try makeClock(
            blackTime: byoYomiTime(thinkingTime: 600, periods: 5, periodTime: 30),
            extraFields: #""start_mode": true, "expiration": \#(lastMove + 300_000),"#
        )

        clock.calculateTimeLeft(with: .ByoYomi(mainTime: 600, periods: 5, periodTime: 30), pauseControl: nil, now: lastMove + 30_000)

        XCTAssertFalse(clock.started)
        XCTAssertEqual(clock.timeUntilExpiration, 270)
        XCTAssertEqual(clock.blackTime.thinkingTimeLeft, 600)
        XCTAssertEqual(clock.blackTime.periodsLeft, 5)
    }

    /// Only a truthy start_mode freezes the clock. An explicit false and an
    /// omitted key are both "started", so the normal clock runs — matching the
    /// truthiness test the official client uses.
    func testStartModeFalseOrOmittedMeansTheGameHasStarted() throws {
        let omitted = try makeClock(blackTime: byoYomiTime(thinkingTime: 600, periods: 5, periodTime: 30))
        XCTAssertTrue(omitted.started)

        var explicitFalse = try makeClock(
            blackTime: byoYomiTime(thinkingTime: 600, periods: 5, periodTime: 30),
            extraFields: #""start_mode": false,"#
        )
        XCTAssertTrue(explicitFalse.started)

        explicitFalse.calculateTimeLeft(with: .ByoYomi(mainTime: 600, periods: 5, periodTime: 30), pauseControl: nil, now: lastMove + 30_000)
        XCTAssertEqual(explicitFalse.blackTime.thinkingTimeLeft, 570)
    }

    private func makeFischerClock(now: Double) throws -> OGSClock {
        var clock = try makeClock(
            blackTime: #"{"thinking_time": 300}"#,
            extraFields: #""expiration": \#(lastMove + 300_000),"#
        )
        clock.calculateTimeLeft(with: .Fischer(initialTime: 300, timeIncrement: 10, maxTime: 300), pauseControl: nil, now: now)
        return clock
    }

    private func byoYomiTime(thinkingTime: Int, periods: Int, periodTime: Int) -> String {
        #"{"thinking_time": \#(thinkingTime), "periods": \#(periods), "period_time": \#(periodTime)}"#
    }

    private func makeClock(blackTime: String, whiteTime: String? = nil, extraFields: String = "") throws -> OGSClock {
        let json = #"""
        {
            "black_player_id": 1,
            "white_player_id": 2,
            "current_player": 1,
            \#(extraFields)
            "last_move": \#(lastMove),
            "black_time": \#(blackTime),
            "white_time": \#(whiteTime ?? blackTime)
        }
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSClock.self, from: Data(json.utf8))
    }

    private func makePauseControl(_ json: String) throws -> OGSPauseControl {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSPauseControl.self, from: Data(json.utf8))
    }
}
