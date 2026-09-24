//
//  TimeControlTests.swift
//  SurroundTests
//

import DictionaryCoding
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
                #"{"time_control":"byoyomi","system":"byoyomi","main_time":300,"periods":5,"period_time":20,"speed":"rapid","pause_on_weekends":false}"#,
                .ByoYomi(mainTime: 300, periods: 5, periodTime: 20),
                .rapid,
                false
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

    func testUnknownSpeedFallsBackToSystemClassification() throws {
        let payload = #"{"time_control":"byoyomi","system":"byoyomi","main_time":600,"periods":5,"period_time":30,"speed":"future-speed","pause_on_weekends":false}"#

        let control = try decoder.decode(TimeControl.self, from: Data(payload.utf8))

        XCTAssertEqual(control.system, .ByoYomi(mainTime: 600, periods: 5, periodTime: 30))
        XCTAssertEqual(control.speed, .live)

        let encoded = try encoder.encode(control)
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNil(encodedObject["speed"])
    }

    func testMissingSpeedRemainsUnclassified() throws {
        let payload = #"{"time_control":"byoyomi","system":"byoyomi","main_time":600,"periods":5,"period_time":30,"pause_on_weekends":false}"#

        let control = try decoder.decode(TimeControl.self, from: Data(payload.utf8))

        XCTAssertEqual(control.system, .ByoYomi(mainTime: 600, periods: 5, periodTime: 30))
        XCTAssertNil(control.speed)
    }

    func testUnknownSpeedForNoTimeControlFallsBackToCorrespondence() throws {
        let payload = #"{"time_control":"none","system":"none","speed":"future-speed","pause_on_weekends":false}"#

        let control = try decoder.decode(TimeControl.self, from: Data(payload.utf8))

        XCTAssertEqual(control.system, .None)
        XCTAssertEqual(control.speed, .correspondence)
        XCTAssertEqual(control.speed?.isRealtime, false)
    }

    func testRapidSpeedRoundTripsThroughOGSWireFormat() throws {
        let control = try TimeControl(
            codingData: .init(
                timeControl: "byoyomi",
                mainTime: 300,
                periods: 5,
                periodTime: 20,
                speed: .rapid,
                pauseOnWeekends: false
            )
        )

        let decoded = try decoder.decode(TimeControl.self, from: encoder.encode(control))

        XCTAssertEqual(decoded.system, .ByoYomi(mainTime: 300, periods: 5, periodTime: 20))
        XCTAssertEqual(decoded.speed, .rapid)
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

    func testMissingAndNullRequiredFieldsAreRejectedByBothDecoders() throws {
        let fixtures: [(String, [String: Int])] = [
            ("fischer", ["initial_time": 120, "time_increment": 30, "max_time": 300]),
            ("byoyomi", ["main_time": 600, "periods": 5, "period_time": 30]),
            ("simple", ["per_move": 60]),
            ("canadian", ["main_time": 600, "period_time": 180, "stones_per_period": 10]),
            ("absolute", ["total_time": 900]),
        ]
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase

        for (system, fields) in fixtures {
            var validPayload: [String: Any] = fields
            validPayload["time_control"] = system
            validPayload["system"] = system
            for field in fields.keys {
                for value in [nil, NSNull()] as [Any?] {
                    var payload = validPayload
                    payload[field] = value
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    let context = "\(system).\(field) = \(String(describing: value))"

                    XCTAssertThrowsError(
                        try decoder.decode(TimeControl.self, from: data), context
                    )
                    XCTAssertThrowsError(
                        try dictionaryDecoder.decode(TimeControl.self, from: payload), context
                    )
                }
            }
        }
    }

    func testOvertimeOnlyControlsKeepZeroMainTime() throws {
        let payloads = [
            #"{"time_control":"byoyomi","main_time":0,"periods":5,"period_time":30}"#,
            #"{"time_control":"canadian","main_time":0,"period_time":180,"stones_per_period":10}"#,
        ]
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        for payload in payloads {
            let data = Data(payload.utf8)
            let control = try decoder.decode(TimeControl.self, from: data)
            let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let dictionaryControl = try dictionaryDecoder.decode(TimeControl.self, from: dictionary)

            XCTAssertEqual(control.mainTime, 0)
            XCTAssertNotEqual(control.system, .None)
            XCTAssertEqual(dictionaryControl, control)
            XCTAssertEqual(try decoder.decode(TimeControl.self, from: encoder.encode(control)), control)
        }
    }

    func testZeroTimeValuesRemainDecodableWhereTheyAreNotDivisors() throws {
        let fixtures: [(String, TimeControlSystem)] = [
            (#"{"time_control":"simple","per_move":0}"#, .Simple(perMove: 0)),
            (#"{"time_control":"absolute","total_time":0}"#, .Absolute(totalTime: 0)),
            (#"{"time_control":"fischer","initial_time":0,"time_increment":0,"max_time":0}"#,
             .Fischer(initialTime: 0, timeIncrement: 0, maxTime: 0)),
        ]
        for (payload, system) in fixtures {
            XCTAssertEqual(try decoder.decode(TimeControl.self, from: Data(payload.utf8)).system, system)
        }
    }

    func testMalformedAuthoritativeSystemDoesNotFallBackToLegacyControl() throws {
        let payload = #"{"time_control":"simple","system":"byoyomi","per_move":60,"main_time":0,"periods":5}"#
        XCTAssertThrowsError(try decoder.decode(TimeControl.self, from: Data(payload.utf8)))
    }

    func testUnknownSystemRemainsDecodableWithoutInventingClockValues() throws {
        let payload = #"{"time_control":"simple","system":"future-system","speed":"live"}"#
        let data = Data(payload.utf8)
        let control = try decoder.decode(TimeControl.self, from: data)
        let dictionaryDecoder = DictionaryDecoder()
        dictionaryDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(control.system, .Unknown("future-system"))
        XCTAssertEqual(control.timeControl, "future-system")
        XCTAssertEqual(control.codingData.timeControl, "simple")
        XCTAssertEqual(control.codingData.system, "future-system")
        XCTAssertFalse(control.system.supportsClock)
        XCTAssertNotEqual(control.system, .None)
        XCTAssertEqual(control.shortDescription, "")
        XCTAssertNil(control.system.averageSecondsPerMove)
        XCTAssertNil(control.system.speed)
        XCTAssertEqual(control.speed, .live)
        XCTAssertEqual(try dictionaryDecoder.decode(TimeControl.self, from: dictionary), control)
        XCTAssertEqual(try decoder.decode(TimeControl.self, from: encoder.encode(control)), control)
    }

    func testUnknownSystemDoesNotInferSpeedFromMissingOrUnknownMetadata() throws {
        for payload in [
            #"{"time_control":"future-system"}"#,
            #"{"time_control":"future-system","speed":"future-speed"}"#,
        ] {
            let control = try decoder.decode(TimeControl.self, from: Data(payload.utf8))
            XCTAssertEqual(control.system, .Unknown("future-system"))
            XCTAssertNil(control.speed)
        }
    }

    func testUnknownTypedSystemPreservesItsWireName() throws {
        let control = TimeControlSystem.Unknown("future-system").timeControlObject
        XCTAssertEqual(control.codingData.system, "future-system")
        XCTAssertEqual(try decoder.decode(TimeControl.self, from: encoder.encode(control)), control)
    }

    func testInvalidRawConstructionThrows() {
        XCTAssertThrowsError(try TimeControl(codingData: .init(timeControl: "byoyomi")))
        XCTAssertThrowsError(try TimeControl(codingData: .init(
            timeControl: "canadian", mainTime: 0, periodTime: 30, stonesPerPeriod: 0
        )))
    }

    func testInvalidEditsPreserveTheLastValidControl() throws {
        var control = TimeControlSystem.ByoYomi(mainTime: 600, periods: 5, periodTime: 30).timeControlObject
        let original = control

        control.mainTime = nil
        XCTAssertEqual(control, original)
        control.codingData.periods = nil
        XCTAssertEqual(control, original)
        control.codingData.periodTime = 0
        XCTAssertEqual(control, original)
        control.codingData = .init(timeControl: "canadian", mainTime: 0)
        XCTAssertEqual(control, original)

        control.mainTime = 0
        control.codingData.periods = 3
        XCTAssertEqual(control.system, .ByoYomi(mainTime: 0, periods: 3, periodTime: 30))
        XCTAssertEqual(try decoder.decode(TimeControl.self, from: encoder.encode(control)), control)

        control.codingData = .init(timeControl: "simple", perMove: 60)
        XCTAssertEqual(control.system, .Simple(perMove: 60))
    }

    func testSpeedClassificationBoundaries() {
        XCTAssertEqual(TimeControlSystem.None.speed, .correspondence)
        XCTAssertEqual(TimeControlSystem.Simple(perMove: 0).speed, .correspondence)
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
