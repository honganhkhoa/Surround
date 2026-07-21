//
//  TimeControlTests.swift
//  SurroundTests
//

import XCTest

final class TimeControlTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func testDecodesEveryOGSTimeControlSystem() throws {
        let fixtures: [(json: String, expected: TimeControlSystem, speed: TimeControlSpeed, pausesOnWeekends: Bool)] = [
            (
                #"{"time_control":"fischer","system":"fischer","initial_time":120,"time_increment":30,"max_time":300,"speed":"live","pause_on_weekends":false}"#,
                .Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300),
                .live,
                false
            ),
            (
                #"{"time_control":"byoyomi","system":"byoyomi","main_time":600,"periods":5,"period_time":30,"speed":"live","pause_on_weekends":true}"#,
                .ByoYomi(mainTime: 600, periods: 5, periodTime: 30),
                .live,
                true
            ),
            (
                #"{"time_control":"simple","system":"simple","per_move":172800,"speed":"correspondence","pause_on_weekends":true}"#,
                .Simple(perMove: 172800),
                .correspondence,
                true
            ),
            (
                #"{"time_control":"canadian","system":"canadian","main_time":600,"period_time":180,"stones_per_period":10,"speed":"live","pause_on_weekends":false}"#,
                .Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10),
                .live,
                false
            ),
            (
                #"{"time_control":"absolute","system":"absolute","total_time":900,"speed":"live","pause_on_weekends":false}"#,
                .Absolute(totalTime: 900),
                .live,
                false
            ),
            (
                #"{"time_control":"none","system":"none","speed":"correspondence","pause_on_weekends":true}"#,
                .None,
                .correspondence,
                true
            )
        ]

        for fixture in fixtures {
            let control = try decoder.decode(TimeControl.self, from: Data(fixture.json.utf8))

            XCTAssertEqual(control.system, fixture.expected, fixture.json)
            XCTAssertEqual(control.speed, fixture.speed, fixture.json)
            XCTAssertEqual(control.pauseOnWeekends, fixture.pausesOnWeekends, fixture.json)
        }
    }

    func testSystemFieldTakesPrecedenceOverLegacyTimeControlField() throws {
        let payload = #"{"time_control":"simple","system":"fischer","per_move":60,"initial_time":120,"time_increment":30,"max_time":300}"#

        let control = try decoder.decode(TimeControl.self, from: Data(payload.utf8))

        XCTAssertEqual(control.timeControl, "fischer")
        XCTAssertEqual(control.system, .Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300))
    }

    func testSystemsRoundTripThroughOGSWireFormat() throws {
        let systems: [TimeControlSystem] = [
            .Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300),
            .ByoYomi(mainTime: 600, periods: 5, periodTime: 30),
            .Simple(perMove: 60),
            .Canadian(mainTime: 600, periodTime: 180, stonesPerPeriod: 10),
            .Absolute(totalTime: 900),
            .None
        ]

        for system in systems {
            let encoded = try encoder.encode(system.timeControlObject)
            let decoded = try decoder.decode(TimeControl.self, from: encoded)

            XCTAssertEqual(decoded.system, system)
        }
    }

    func testSpeedClassificationBoundaries() {
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 9).speed, .blitz)
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 10).speed, .live)
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 3600).speed, .live)
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 3601).speed, .correspondence)

        XCTAssertEqual(TimeControlSystem.Fischer(initialTime: 900, timeIncrement: 0, maxTime: 900).speed, .live)
        XCTAssertEqual(TimeControlSystem.ByoYomi(mainTime: 0, periods: 5, periodTime: 5).speed, .blitz)
        XCTAssertEqual(TimeControlSystem.Canadian(mainTime: 0, periodTime: 100, stonesPerPeriod: 10).speed, .live)
        XCTAssertEqual(TimeControlSystem.Absolute(totalTime: 900).speed, .live)
    }

    func testUnusualTimeControlBoundaries() {
        XCTAssertTrue(TimeControlSystem.Simple(perMove: 3).isUnusual)
        XCTAssertFalse(TimeControlSystem.Simple(perMove: 4).isUnusual)

        XCTAssertTrue(TimeControlSystem.Absolute(totalTime: 900).isUnusual)
        XCTAssertFalse(TimeControlSystem.Absolute(totalTime: 901).isUnusual)

        XCTAssertTrue(TimeControlSystem.Fischer(initialTime: 900, timeIncrement: 4, maxTime: 900).isUnusual)
        XCTAssertFalse(TimeControlSystem.Fischer(initialTime: 901, timeIncrement: 4, maxTime: 901).isUnusual)

        XCTAssertTrue(TimeControlSystem.ByoYomi(mainTime: 900, periods: 5, periodTime: 4).isUnusual)
        XCTAssertFalse(TimeControlSystem.ByoYomi(mainTime: 900, periods: 5, periodTime: 5).isUnusual)

        XCTAssertTrue(TimeControlSystem.Canadian(mainTime: 900, periodTime: 40, stonesPerPeriod: 10).isUnusual)
        XCTAssertFalse(TimeControlSystem.Canadian(mainTime: 900, periodTime: 50, stonesPerPeriod: 10).isUnusual)
        XCTAssertFalse(TimeControlSystem.None.isUnusual)
    }
}
