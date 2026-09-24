//
//  TimeControl.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/5/20.
//

import Foundation
import SwiftUI

func durationString(seconds: Int, longFormat: Bool = false) -> String {
    if seconds == 0 {
        return longFormat ? String(localized: "No duration", comment: "Long duration string for 0 seconds") : ""
    }
    
    var secondsLeft = seconds
    let weeks = secondsLeft / (86400 * 7)
    secondsLeft %= 86400 * 7
    let days = secondsLeft / 86400
    secondsLeft %= 86400
    let hours = secondsLeft / 3600
    secondsLeft %= 3600
    let minutes = secondsLeft / 60
    secondsLeft %= 60
    var weeksString = ""
    var daysString = ""
    var hoursString = ""
    var minutesString = ""
    var secondsString = ""
    if weeks > 0 {
        if longFormat {
            weeksString = String(localized: "\(weeks) weeks", comment: "Duration - week parts, long format")
        } else {
            weeksString = String(localized: "\(weeks)w", comment: "Duration - week parts, short format")
        }
    }
    if days > 0 {
        if longFormat {
            daysString = String(localized: "\(days) days", comment: "Duration - day parts, long format")
        } else {
            daysString = String(localized: "\(days)d", comment: "Duration - week parts, short format")
        }
    }
    if hours > 0 {
        if longFormat {
            hoursString = String(localized: "\(hours) hours", comment: "Duration - hours part, long format")
        } else {
            hoursString = String(localized: "\(hours)h", comment: "Duration - hours part, short format")
        }
    }
    if minutes > 0 {
        if longFormat {
            minutesString = String(localized: "\(minutes) minutes", comment: "Duration - minutes part, long format")
        } else {
            minutesString = String(localized: "\(minutes)m", comment: "Duration - minutes part, short format")
        }
    }
    if secondsLeft > 0 {
        if longFormat {
            secondsString = String(localized: "\(secondsLeft) seconds", comment: "Duration - seconds part, long format")
        } else {
            secondsString = String(localized: "\(secondsLeft)s", comment: "Duration - seconds part, short format")
        }
    }

    return  String(localized: "\(weeksString) \(daysString) \(hoursString) \(minutesString) \(secondsString)", comment: "Duration string [weeks days hours minutes seconds]").trimmingCharacters(in: .whitespaces)
}

enum TimeControlSystem: Hashable {
    case Fischer(initialTime: Int, timeIncrement: Int, maxTime: Int)
    case ByoYomi(mainTime: Int, periods: Int, periodTime: Int)
    case Simple(perMove: Int)
    case Canadian(mainTime: Int, periodTime: Int, stonesPerPeriod: Int)
    case Absolute(totalTime: Int)
    case None
    case Unknown(String)
    
    var name: String {
        switch self {
        case .Fischer:
            return String(localized: "Fischer", comment: "TimeControl system name")
        case .ByoYomi:
            return String(localized: "Japanese Byo-Yomi", comment: "TimeControl system name")
        case .Canadian:
            return String(localized: "Canadian Byo-Yomi", comment: "TimeControl system name")
        case .Absolute:
            return String(localized: "Absolute", comment: "TimeControl system name")
        case .Simple:
            return String(localized: "Simple", comment: "TimeControl system name")
        case .None:
            return String(localized: "No time control", comment: "TimeControl system name")
        case .Unknown(let system):
            return system
        }
    }
    
    var shortName: String {
        switch self {
        case .Fischer:
            return String(localized: "Fischer")
        case .ByoYomi:
            return String(localized: "Byo-Yomi", comment: "TimeControl system name - shorter")
        case .Canadian:
            return String(localized: "Canadian", comment: "TimeControl system name - shorter")
        case .Absolute:
            return String(localized: "Absolute", comment: "TimeControl system name - shorter")
        case .Simple:
            return String(localized: "Simple", comment: "TimeControl system name - shorter")
        case .None:
            return String(localized: "No control", comment: "TimeControl system name - shorter")
        case .Unknown(let system):
            return system
        }
    }
    
    var shortDescription: String {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return String(localized: "\(durationString(seconds: initialTime)) + \(durationString(seconds: timeIncrement)) up to \(durationString(seconds: maxTime))", comment: "TimeControl - short description for fischer system")
        case .Simple(let perMove):
            return String(localized: "\(durationString(seconds: perMove))/move", comment: "TimeControl - short description for simple system")
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return String(localized: "\(durationString(seconds: mainTime))\(mainTime > 0 ? " + " : "")\(periods)×\(durationString(seconds: periodTime))", comment: "TimeControl - short description for byo-yomi system")
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return String(localized: "\(durationString(seconds: mainTime))\(mainTime > 0 ? " + " : "")\(durationString(seconds: periodTime))/\(stonesPerPeriod)", comment: "TimeControl - short description for canadian system")
        case .Absolute(let totalTime):
            return durationString(seconds: totalTime)
        case .None:
            return String(localized: "No time limits", comment: "TimeControl - short description for no system")
        case .Unknown:
            return ""
        }
    }
    
    var descriptionText: Text {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return Text(.init(localized: "Clock starts with **\(durationString(seconds: initialTime, longFormat: true))** and increases by **\(durationString(seconds: timeIncrement, longFormat: true))** per move, up to a maximum of **\(durationString(seconds: maxTime, longFormat: true))**.", comment: "TimeControl - long description for fischer system"))
        case .Simple(let perMove):
            return Text(.init(localized: "**\(durationString(seconds: perMove, longFormat: true))** per move.", comment: "TimeControl - long description for simple system"))
        case .ByoYomi(let mainTime, let periods, let periodTime):
            if mainTime == 0 {
                return Text(.init(localized: "**\(periods) periods** of **\(durationString(seconds: periodTime, longFormat: true))**.", comment: "TimeControl - long description for Japanese byo-yomi system without main time"))
            }
            return Text(.init(localized: "Clock starts with **\(durationString(seconds: mainTime, longFormat: true))** main time, follows by **\(periods) periods** of **\(durationString(seconds: periodTime, longFormat: true))**.", comment: "TimeControl - long description for Japanese byo-yomi system"))
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            if mainTime == 0 {
                return Text(.init(localized: "**\(durationString(seconds: periodTime, longFormat: true))** for every **\(stonesPerPeriod) moves**.", comment: "TimeControl - long description for Canadian byo-yomi system without main time"))
            }
            return Text(.init(localized: "Clock starts with **\(durationString(seconds: mainTime, longFormat: true))** main time, follows by **\(durationString(seconds: periodTime, longFormat: true))** for every **\(stonesPerPeriod) moves**.", comment: "TimeControl - long description for Canadian byo-yomi system"))
        case .Absolute(let totalTime):
            return Text(.init(localized: "**\(durationString(seconds: totalTime, longFormat: true))** of total play time for each player.", comment: "TimeControl - long description for absolute system"))
        case .None:
            return Text("No time limits.", comment: "TimeControl - long description for no system")
        case .Unknown:
            return Text(verbatim: "")
        }
    }
    
    /// Unsupported clocks must not be presented as an unlimited game or used
    /// to infer a speed from parameters whose meaning the client does not know.
    var supportsClock: Bool {
        if case .Unknown = self { return false }
        return true
    }

    var averageSecondsPerMove: Double? {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, _):
            return Double(initialTime) / 90.0 + Double(timeIncrement)
        case .ByoYomi(let mainTime, _, let periodTime):
            return Double(mainTime) / 90.0 + Double(periodTime)
        case .Simple(let perMove):
            return Double(perMove)
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return Double(mainTime) / 90.0 + Double(periodTime) / Double(stonesPerPeriod)
        case .Absolute(let totalTime):
            return Double(totalTime) / 90.0
        case .None:
            return 0
        case .Unknown:
            return nil
        }
    }

    var speed: TimeControlSpeed? {
        guard let secondsPerMove = averageSecondsPerMove else { return nil }
        if secondsPerMove == 0 || secondsPerMove > 3600 {
            return .correspondence
        } else if secondsPerMove < 10 {
            return .blitz
        } else {
            return .live
        }
    }

    var timeControlObject: TimeControl {
        TimeControl(system: self)
    }

    static let QuestionableSecondsPerMove = 4
    static let QuestionableAbsoluteTime = 900
    
    var isUnusual: Bool {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, _):
            return !(initialTime > TimeControlSystem.QuestionableAbsoluteTime || timeIncrement > TimeControlSystem.QuestionableSecondsPerMove)
        case .Simple(let perMove):
            return perMove < TimeControlSystem.QuestionableSecondsPerMove
        case .ByoYomi(let mainTime, _, let periodTime):
            return !(mainTime > TimeControlSystem.QuestionableAbsoluteTime || periodTime > TimeControlSystem.QuestionableSecondsPerMove)
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return !(mainTime > TimeControlSystem.QuestionableAbsoluteTime || periodTime / stonesPerPeriod > TimeControlSystem.QuestionableSecondsPerMove)
        case .Absolute(let totalTime):
            return totalTime <= TimeControlSystem.QuestionableAbsoluteTime
        case .None, .Unknown:
            return false
        }
    }
}

enum TimeControlSpeed: String, Codable, Hashable {
    case live
    case rapid
    case correspondence
    case blitz

    var isRealtime: Bool {
        self != .correspondence
    }
    
    func localizedString() -> String {
        switch self {
        case .live, .rapid: return String(localized: "live", comment: "TimeControlSpeed enum localization")
        case .correspondence: return String(localized: "correspondence", comment: "TimeControlSpeed enum localization")
        case .blitz: return String(localized: "blitz", comment: "TimeControlSpeed enum localization")
        }
    }
    
    var defaultTimeOptions: [TimeControlSystem] {
        switch self {
        case .blitz:
            return [
                .ByoYomi(mainTime: 30, periods: 5, periodTime: 5),
                .Fischer(initialTime: 30, timeIncrement: 10, maxTime: 60),
                .Canadian(mainTime: 30, periodTime: 30, stonesPerPeriod: 5),
                .Simple(perMove: 5),
                .Absolute(totalTime: 300)
            ]
        case .live, .rapid:
            return [
                .ByoYomi(mainTime: 10 * 60, periods: 5, periodTime: 30),
                .Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300),
                .Canadian(mainTime: 10 * 60, periodTime: 180, stonesPerPeriod: 10),
                .Simple(perMove: 60),
                .Absolute(totalTime: 900)
            ]
        case .correspondence:
            return [
                .Fischer(initialTime: 3 * 86400, timeIncrement: 86400, maxTime: 7 * 86400),
                .ByoYomi(mainTime: 7 * 86400, periods: 5, periodTime: 86400),
                .Canadian(mainTime: 7 * 86400, periodTime: 7 * 86400, stonesPerPeriod: 10),
                .Simple(perMove: 2 * 86400),
                .Absolute(totalTime: 28 * 86400),
                .None
            ]
        }
    }
}

@dynamicMemberLookup
struct TimeControl: Codable, Equatable, Hashable {
    struct TimeControlCodingData: Codable, Hashable {
        internal init(timeControl: String, system: String? = nil, initialTime: Int? = nil, timeIncrement: Int? = nil, maxTime: Int? = nil, mainTime: Int? = nil, periods: Int? = nil, periodTime: Int? = nil, perMove: Int? = nil, stonesPerPeriod: Int? = nil, totalTime: Int? = nil, speed: TimeControlSpeed? = nil, pauseOnWeekends: Bool? = nil) {
            self.timeControl = timeControl
            self.system = system ?? timeControl
            self.initialTime = initialTime
            self.timeIncrement = timeIncrement
            self.maxTime = maxTime
            self.mainTime = mainTime
            self.periods = periods
            self.periodTime = periodTime
            self.perMove = perMove
            self.stonesPerPeriod = stonesPerPeriod
            self.totalTime = totalTime
            self.speed = speed?.rawValue
            self.pauseOnWeekends = pauseOnWeekends
        }
        
        var timeControl: String
        var system: String?
        var initialTime: Int?
        var timeIncrement: Int?
        var maxTime: Int?
        var mainTime: Int?
        var periods: Int?
        var periodTime: Int?
        var perMove: Int?
        var stonesPerPeriod: Int?
        var totalTime: Int?
        /// Raw OGS wire value. Keep the transport representation separate from
        /// the app's supported speed classifications so future values remain
        /// decodable without requiring a hand-written codec for every field.
        var speed: String?
        var pauseOnWeekends: Bool?

        fileprivate func validatedSystem(codingPath: [CodingKey] = []) throws -> TimeControlSystem {
            let systemName = system ?? timeControl
            func required(_ value: Int?, _ field: String, strictlyPositive: Bool = false) throws -> Int {
                guard let value, !strictlyPositive || value > 0 else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: codingPath,
                        debugDescription: "Invalid or missing \(field) for \(systemName) time control"
                    ))
                }
                return value
            }

            // These fields are required by Goban's JGOFTimeControl variants.
            // Zero main time is valid for overtime-only games. Only the two
            // values used as divisors must be positive to avoid arithmetic traps.
            switch systemName {
            case "fischer":
                return .Fischer(
                    initialTime: try required(initialTime, "initial_time"),
                    timeIncrement: try required(timeIncrement, "time_increment"),
                    maxTime: try required(maxTime, "max_time")
                )
            case "byoyomi":
                return .ByoYomi(
                    mainTime: try required(mainTime, "main_time"),
                    periods: try required(periods, "periods"),
                    periodTime: try required(periodTime, "period_time", strictlyPositive: true)
                )
            case "simple":
                return .Simple(perMove: try required(perMove, "per_move"))
            case "canadian":
                return .Canadian(
                    mainTime: try required(mainTime, "main_time"),
                    periodTime: try required(periodTime, "period_time"),
                    stonesPerPeriod: try required(stonesPerPeriod, "stones_per_period", strictlyPositive: true)
                )
            case "absolute":
                return .Absolute(totalTime: try required(totalTime, "total_time"))
            case "none":
                return .None
            default:
                return .Unknown(systemName)
            }
        }
    }
    
    var codingData: TimeControlCodingData {
        didSet {
            // Form bindings edit individual wire fields. Keep the last valid
            // control if an edit removes a required field or changes to an
            // incomplete system, just as decoding rejects malformed snapshots.
            guard let updatedSystem = try? codingData.validatedSystem() else {
                codingData = oldValue
                return
            }
            system = updatedSystem
        }
    }
    private(set) var system: TimeControlSystem

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let codingData = try container.decode(TimeControlCodingData.self)
        system = try codingData.validatedSystem(codingPath: decoder.codingPath)
        self.codingData = codingData
    }

    init(codingData: TimeControlCodingData) throws {
        system = try codingData.validatedSystem()
        self.codingData = codingData
    }

    fileprivate init(system: TimeControlSystem) {
        self.system = system
        switch system {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            codingData = TimeControlCodingData(
                timeControl: "fischer",
                initialTime: initialTime, timeIncrement: timeIncrement, maxTime: maxTime, speed: system.speed
            )
        case .Simple(let perMove):
            codingData = TimeControlCodingData(
                timeControl: "simple", perMove: perMove, speed: system.speed
            )
        case .ByoYomi(let mainTime, let periods, let periodTime):
            codingData = TimeControlCodingData(
                timeControl: "byoyomi", mainTime: mainTime, periods: periods, periodTime: periodTime, speed: system.speed
            )
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            codingData = TimeControlCodingData(
                timeControl: "canadian", mainTime: mainTime, periodTime: periodTime, stonesPerPeriod: stonesPerPeriod, speed: system.speed
            )
        case .Absolute(let totalTime):
            codingData = TimeControlCodingData(
                timeControl: "absolute", totalTime: totalTime, speed: system.speed
            )
        case .None:
            codingData = TimeControlCodingData(
                timeControl: "none"
            )
        case .Unknown(let name):
            codingData = TimeControlCodingData(timeControl: name)
        }
    }

    /// OGS's speed tag is presentation metadata. If the server introduces a
    /// new tag, retain the authoritative clock fields and classify from them
    /// instead of rejecting the entire game payload.
    var speed: TimeControlSpeed? {
        guard let wireSpeed = codingData.speed else {
            return nil
        }
        return TimeControlSpeed(rawValue: wireSpeed) ?? system.speed
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var encodableCodingData = codingData
        if let wireSpeed = encodableCodingData.speed,
           TimeControlSpeed(rawValue: wireSpeed) == nil {
            encodableCodingData.speed = nil
        }
        try container.encode(encodableCodingData)
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<TimeControlCodingData, T>) -> T {
        get {
            if keyPath == \.timeControl {
                if let system = self.codingData.system, system != self.codingData.timeControl {
                    if let timeControl = system as? T {
                        return timeControl
                    }
                }
            }
            return self.codingData[keyPath: keyPath]
        }
        set { self.codingData[keyPath: keyPath] = newValue }
    }
    
    var shortDescription: String {
        return system.shortDescription
    }
    
    var systemName: String {
        return system.name
    }
}
