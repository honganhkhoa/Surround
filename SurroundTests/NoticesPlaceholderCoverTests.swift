//
//  NoticesPlaceholderCoverTests.swift
//  SurroundTests
//
//  The Debug-only placeholder cover's launch flags and its app-wide raise
//  and lower state. The scene cover's window choices are in
//  SceneCoverPolicyTests.
//

#if DEBUG
import Combine
import XCTest

final class NoticesPlaceholderCoverTests: XCTestCase {
    private typealias Configuration = NoticesPlaceholderCoverConfiguration
    private typealias Contract = NoticesPlaceholderCoverContract

    /// The placeholder's options without variants: the scene cover's
    /// defaults, except that it raises one turn after attaching unless the
    /// `raise-while-attaching` variant asks.
    private var placeholderDefaults: SceneCoverOptions {
        var options = SceneCoverOptions()
        options.raisesWhileAttaching = false
        return options
    }

    // MARK: - Launch arguments

    func testNothingExistsWithoutTheCoverFlag() throws {
        XCTAssertNil(try Configuration.parse(["Surround", "--surround-ui-testing"]))
        XCTAssertNil(try Configuration.parse([
            "Surround", Contract.raiseAfterArgument, "3", Contract.variantArgument, "focus-reply",
        ]))
    }

    func testTheFlagAloneWaitsForACommand() throws {
        let configuration = try XCTUnwrap(Configuration.parse(["Surround", Contract.launchArgument]))
        XCTAssertEqual(configuration, Configuration())
        XCTAssertNil(configuration.raiseAfterLaunch)
        XCTAssertEqual(configuration.reraiseDelay, 5)
        XCTAssertEqual(configuration.coverOptions, placeholderDefaults)
    }

    func testDelaysAndVariantsAreRead() throws {
        let configuration = try XCTUnwrap(Configuration.parse([
            "Surround", Contract.launchArgument,
            Contract.raiseAfterArgument, "0",
            Contract.reraiseAfterArgument, "2.5",
            Contract.variantArgument, "focus-reply, keep-responder,modal-root",
        ]))
        XCTAssertEqual(configuration.raiseAfterLaunch, 0)
        XCTAssertEqual(configuration.reraiseDelay, 2.5)
        XCTAssertEqual(configuration.variants, [.focusReply, .keepResponder, .modalRoot])
    }

    func testEachVariantChangesOnlyItsOwnCoverOption() {
        func options(_ variant: Configuration.Variant) -> SceneCoverOptions {
            Configuration(variants: [variant]).coverOptions
        }
        var expected = placeholderDefaults
        expected.endsEditingUnderneath = false
        XCTAssertEqual(options(.keepResponder), expected)
        expected = placeholderDefaults
        expected.modalTarget = .rootView
        XCTAssertEqual(options(.modalRoot), expected)
        expected = placeholderDefaults
        expected.locksWindowsBelow = true
        XCTAssertEqual(options(.lockUnderneath), expected)
        expected = placeholderDefaults
        expected.raisesWhileAttaching = true
        XCTAssertEqual(options(.raiseWhileAttaching), expected)
        XCTAssertEqual(options(.focusReply), placeholderDefaults)
        XCTAssertEqual(options(.keepContentEnabled), placeholderDefaults)
    }

    func testMalformedValuesStopTheLaunch() {
        let flag = Contract.launchArgument
        let raise = Contract.raiseAfterArgument
        for value in ["soon", "-1", "nan", "inf", "601"] {
            XCTAssertThrowsError(try Configuration.parse([flag, raise, value])) {
                XCTAssertEqual($0 as? Configuration.ParseError, .invalidDelay(argument: raise, value: value))
            }
        }
        for arguments in [[flag, raise], [flag, raise, "--surround-ui-testing"]] {
            XCTAssertThrowsError(try Configuration.parse(arguments)) {
                XCTAssertEqual($0 as? Configuration.ParseError, .missingValue(argument: raise))
            }
        }
        XCTAssertThrowsError(try Configuration.parse([flag, Contract.variantArgument, "focus-reply,blink"])) {
            XCTAssertEqual($0 as? Configuration.ParseError, .unknownVariant("blink"))
        }
    }

    // MARK: - Raising and lowering

    func testAZeroLaunchDelayStartsRaised() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(
            configuration: Configuration(raiseAfterLaunch: 0), schedule: schedule.schedule)
        XCTAssertTrue(state.isRaised)
        XCTAssertEqual(schedule.pendingCount, 0)
    }

    func testALaunchDelayRaisesWhenItsTimeComes() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(
            configuration: Configuration(raiseAfterLaunch: 8), schedule: schedule.schedule)
        XCTAssertFalse(state.isRaised)
        XCTAssertEqual(schedule.delays, [8])
        schedule.fireAll()
        XCTAssertTrue(state.isRaised)
        XCTAssertFalse(state.hasPendingRaise)
    }

    func testLoweringCancelsATimedRaise() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(configuration: Configuration(), schedule: schedule.schedule)
        state.raise(after: 3)
        state.lower()
        XCTAssertEqual(schedule.pendingCount, 0)
        schedule.fireAll()
        XCTAssertFalse(state.isRaised)
    }

    func testLowerThenRaiseAgainWaitsTheReraiseDelay() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(
            configuration: Configuration(reraiseDelay: 4), schedule: schedule.schedule)
        state.raise()
        state.lowerThenRaiseAgain()
        XCTAssertFalse(state.isRaised)
        XCTAssertEqual(schedule.delays.last, 4)
        schedule.fireAll()
        XCTAssertTrue(state.isRaised)
    }

    func testANewTimedRaiseReplacesTheOneWaiting() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(configuration: Configuration(), schedule: schedule.schedule)
        state.raise(after: 3)
        state.raise(after: 9)
        XCTAssertEqual(schedule.pendingCount, 1)
        XCTAssertEqual(schedule.delays, [3, 9])
    }

    func testRepeatedCommandsPublishOnlyChanges() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(configuration: Configuration(), schedule: schedule.schedule)
        var published = [Bool]()
        let subscription = state.$isRaised.dropFirst().sink { published.append($0) }
        state.raise(); state.raise(); state.lower(); state.lower()
        XCTAssertEqual(published, [true, false])
        subscription.cancel()
    }

    func testDarwinCommandsRaiseLowerAndToggle() {
        let schedule = ManualSchedule()
        let state = NoticesPlaceholderCoverState(configuration: Configuration(), schedule: schedule.schedule)
        state.perform(.raise); XCTAssertTrue(state.isRaised)
        state.perform(.toggle); XCTAssertFalse(state.isRaised)
        state.perform(.toggle); XCTAssertTrue(state.isRaised)
        state.perform(.lower); XCTAssertFalse(state.isRaised)
    }
}

/// Runs scheduled work only when a test fires it.
private final class ManualSchedule {
    private(set) var delays = [TimeInterval]()
    private var work = [Int: () -> Void]()
    private var nextID = 0

    var pendingCount: Int { work.count }

    var schedule: NoticesPlaceholderCoverState.Schedule {
        { [unowned self] delay, block in
            self.nextID += 1
            let id = self.nextID
            self.delays.append(delay)
            self.work[id] = block
            return AnyCancellable { [weak self] in self?.work[id] = nil }
        }
    }

    func fireAll() {
        let due = work.sorted { $0.key < $1.key }.map(\.value)
        work.removeAll()
        due.forEach { $0() }
    }
}
#endif
