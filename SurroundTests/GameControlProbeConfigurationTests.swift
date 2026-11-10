//
//  GameControlProbeConfigurationTests.swift
//  SurroundTests
//
//  The Debug-only toolbar-item probe's launch flags, and the event summary
//  its popover shows.
//

#if DEBUG
import XCTest

final class GameControlProbeConfigurationTests: XCTestCase {
    private typealias Contract = SurroundUITestContract
    private typealias Configuration = GameControlProbeConfiguration

    private let probe = ["Surround", SurroundUITestContract.gameControlProbeLaunchArgument]

    func testProbeIsOffWithoutItsOwnFlag() throws {
        XCTAssertNil(try Configuration.parse(["Surround"]))
        XCTAssertNil(try Configuration.parse(["Surround", Contract.gameControlProbeVariantLaunchArgument, "chip"]))
    }

    func testBaseProbeUsesTheDrawnSizes() throws {
        let configuration = try XCTUnwrap(Configuration.parse(probe))
        XCTAssertEqual(configuration.variants, [])
        XCTAssertNil(configuration.size)
        XCTAssertEqual(configuration.size(for: .bottomBar), CGSize(width: 200, height: 48))
        XCTAssertEqual(configuration.size(for: .topBar), CGSize(width: 96, height: 44))
        XCTAssertEqual(configuration.size(for: .rail), CGSize(width: 62, height: 60))
    }

    func testVariantsAndSizeParse() throws {
        let configuration = try XCTUnwrap(Configuration.parse(probe + [
            Contract.gameControlProbeVariantLaunchArgument, "chip, rail-tile,every-game",
            Contract.gameControlProbeSizeLaunchArgument, "160x48",
        ]))
        XCTAssertEqual(configuration.variants, [.chip, .railTile, .everyGame])
        for form in [GameActiveGamesPlacement.Form.bottomBar, .topBar, .rail] {
            XCTAssertEqual(configuration.size(for: form), CGSize(width: 160, height: 48), "\(form)")
        }
    }

    func testMalformedFlagsThrow() {
        let variant = Contract.gameControlProbeVariantLaunchArgument
        let size = Contract.gameControlProbeSizeLaunchArgument
        let cases: [([String], Configuration.ParseError)] = [
            ([variant, "chip,glow"], .unknownVariant("glow")),
            ([size, "wide"], .invalidSize("wide")),
            ([size, "10x10"], .invalidSize("10x10")),
            ([variant], .missingValue(variant)),
            // A following flag is no value either.
            ([size, variant, "chip"], .missingValue(size)),
        ]
        for (arguments, expected) in cases {
            XCTAssertThrowsError(try Configuration.parse(probe + arguments), "\(arguments)") { error in
                XCTAssertEqual(error as? Configuration.ParseError, expected, "\(arguments)")
            }
        }
    }

    func testEventsSummaryCountsEachKindAndTheLast() {
        var events = GameControlProbeEvents()
        XCTAssertEqual(events.summary, "tap 0 · hold 0 · secondary-click 0 · accessibility-action 0")
        events.record(.tap)
        events.record(.hold)
        events.record(.hold)
        XCTAssertEqual(events.summary, "tap 1 · hold 2 · secondary-click 0 · accessibility-action 0 · last hold")
        XCTAssertEqual(events.last, .hold)
    }
}
#endif
