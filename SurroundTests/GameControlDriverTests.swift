//
//  GameControlDriverTests.swift
//  SurroundTests
//
//  The Debug drivers the in-game control's journeys launch with: how their
//  flags parse, where a malformed flag stops the launch, the state cycle's
//  order, the freeze control's rule and the connection commands' names.
//

#if DEBUG
import XCTest

final class GameControlDriverTests: XCTestCase {
    private typealias Contract = SurroundUITestContract
    private typealias Drivers = SurroundUITestContract.GameControlDrivers
    private typealias ParseError = SurroundUITestContract.GameControlDrivers.ParseError

    private let testing = SurroundUITestContract.launchArgument
    private let liveBanner = SurroundUITestContract.liveGameBannerNavigationLaunchArgument
    private let cycle = SurroundUITestContract.gameControlCycleLaunchArgument
    private let control = SurroundUITestContract.forum224ControlLaunchArgument
    private let watchdog = SurroundUITestContract.mainThreadWatchdogLaunchArgument
    private let conditionalMoves = SurroundUITestContract.liveGameBannerConditionalMovesLaunchArgument

    private func failure(_ arguments: [String]) -> ParseError? {
        do {
            _ = try Drivers.parse(arguments)
            return nil
        } catch {
            return error as? ParseError
        }
    }

    func testNoFlagRunsNoDriver() throws {
        XCTAssertEqual(try Drivers.parse([]), Drivers())
        XCTAssertEqual(try Drivers.parse([testing, liveBanner]), Drivers(), "The fixture alone drives nothing.")
        XCTAssertEqual(try Drivers.parse([testing, Contract.fixtureClockTicksLaunchArgument]), Drivers())
    }

    func testTheCycleNeedsTheLiveBannerFixtureAndAKnownEvent() throws {
        XCTAssertEqual(try Drivers.parse([testing, liveBanner, cycle, "on-disappear"]).cycle, .onDisappear)
        XCTAssertEqual(try Drivers.parse([cycle, "on-appear", liveBanner, testing]).cycle, .onAppear)
        XCTAssertEqual(try Drivers.parse([testing, liveBanner, cycle, "on-appear", cycle, "x"]).cycle, .onAppear,
                       "The first occurrence wins.")

        XCTAssertEqual(failure([testing, liveBanner, cycle]), .missingValue(flag: cycle))
        XCTAssertEqual(failure([testing, liveBanner, cycle, "on-tap"]), .invalidValue(flag: cycle, value: "on-tap"))
        let launch = "\(testing) with \(liveBanner)"
        XCTAssertEqual(failure([testing, cycle, "on-appear"]), .needs(flag: cycle, launch: launch))
        XCTAssertEqual(failure([liveBanner, cycle, "on-appear"]), .needs(flag: cycle, launch: launch),
                       "The fixture is a UI-testing launch's.")
        let invalid = ParseError.invalidValue(flag: cycle, value: "on-tap").description
        XCTAssertTrue(invalid.contains("on-disappear") && invalid.contains("on-appear"), invalid)
    }

    func testTheConditionalMovesGameNeedsTheLiveBannerFixture() throws {
        XCTAssertTrue(try Drivers.parse([testing, liveBanner, conditionalMoves]).addsConditionalMovesGame)
        XCTAssertEqual(failure([testing, conditionalMoves]),
                       .needs(flag: conditionalMoves, launch: "\(testing) with \(liveBanner)"))
    }

    func testTheFreezeControlTakesABandOfSpareHeights() throws {
        let freeze = Contract.OwnGameFreezeControl.self
        XCTAssertEqual(try Drivers.parse([testing, control, "70,122"]).freezeControl, freeze.init(low: 70, high: 122))
        XCTAssertEqual(try Drivers.parse([testing, control, "82.5, 134.5"]).freezeControl,
                       freeze.init(low: 82.5, high: 134.5))
        XCTAssertEqual(try Drivers.parse([testing, control, "0,52"]).freezeControl, freeze.init(low: 0, high: 52))

        XCTAssertEqual(failure([testing, control]), .missingValue(flag: control))
        for value in ["70", "70,", ",122", "122,70", "70,70", "-1,52", "a,b", "70,122,5", "inf,10", "nan,1"] {
            XCTAssertEqual(failure([testing, control, value]), .invalidValue(flag: control, value: value), value)
        }
        XCTAssertEqual(failure([control, "70,122"]), .needs(flag: control, launch: testing))
        let missing = ParseError.missingValue(flag: control).description
        XCTAssertTrue(missing.contains("70,122"), missing)
    }

    func testTheWatchdogRunsInAnyDebugLaunch() throws {
        XCTAssertTrue(try Drivers.parse([watchdog]).runsMainThreadWatchdog)
        XCTAssertTrue(try Drivers.parse([testing, liveBanner, watchdog, cycle, "on-appear"]).runsMainThreadWatchdog)
        XCTAssertFalse(try Drivers.parse([testing]).runsMainThreadWatchdog)
    }

    /// Each cycle of the own-game navigation journey opens three games and
    /// closes three screens. Four states and three steps share no factor, so
    /// over any four cycles each open meets every state once.
    func testTheCycleStepsThroughFourStatesThatEachOpenMeets() {
        typealias State = Contract.GameControlCycleState
        XCTAssertEqual(State.allCases.map(\.next), [.base, .dot, .outage, .chip])
        XCTAssertEqual(State.allCases.filter(\.isUserToMove), [.chip, .outage])
        XCTAssertEqual(State.allCases.filter(\.hasReceivedChallenge), [.dot])
        XCTAssertEqual(State.allCases.filter(\.isSocketDown), [.outage])

        for firstCycle in 0..<4 {
            var state = State.chip
            for _ in 0..<(3 * firstCycle) { state = state.next }
            var met = Array(repeating: Set<State>(), count: 3)
            for _ in 0..<4 {
                for open in 0..<3 {
                    met[open].insert(state)
                    state = state.next
                }
            }
            XCTAssertEqual(met, Array(repeating: Set(State.allCases), count: 3), "From cycle \(firstCycle + 1)")
        }
    }

    /// Version 2.4's rule: hidden, the item needs `low` spare; shown, any.
    /// Inside a hide that starts hidden, the last decision stays hidden, so
    /// a spare between `low` and `high` without the item shows it, and with
    /// its bar's `high - low` taken it hides again.
    func testTheFreezeControlKeepsVersion24sRule() {
        let rule = Contract.OwnGameFreezeControl(low: 70, high: 122)
        XCTAssertFalse(rule.shows(spare: 69.9, wasShown: false))
        XCTAssertTrue(rule.shows(spare: 70, wasShown: false))
        XCTAssertTrue(rule.shows(spare: 0, wasShown: true), "Shown, it stays while any height is spare.")
        XCTAssertFalse(rule.shows(spare: -1, wasShown: true))

        let hidden = 82.7, barHeight = rule.high - rule.low
        XCTAssertTrue(rule.loops(withSpareWithoutItem: hidden))
        XCTAssertTrue(rule.shows(spare: hidden, wasShown: false))
        XCTAssertFalse(rule.shows(spare: hidden - barHeight, wasShown: false), "Inside the hide it flips back.")
        XCTAssertTrue(rule.shows(spare: hidden - barHeight, wasShown: true), "After a layout it stays.")
        XCTAssertFalse(rule.loops(withSpareWithoutItem: 122), "With 122 spare the bar leaves 70.")
        XCTAssertFalse(rule.loops(withSpareWithoutItem: 69.9))
    }

    func testTheConnectionCommandsAreTheirOwnDarwinNames() {
        let names = Contract.ConnectionCommand.allCases.map(\.rawValue)
        XCTAssertEqual(names, ["com.honganhkhoa.Surround.debug.connection.drop",
                               "com.honganhkhoa.Surround.debug.connection.restore"])
        XCTAssertTrue(Set(names).isDisjoint(with: Contract.SuperchatCommand.allCases.map(\.rawValue)))
    }
}
#endif
