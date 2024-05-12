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

enum TimeControlSystem: Equatable {
    case Fischer(initialTime: Int, timeIncrement: Int, maxTime: Int)
    case ByoYomi(mainTime: Int, periods: Int, periodTime: Int)
    case Simple(perMove: Int)
    case Canadian(mainTime: Int, periodTime: Int, stonesPerPeriod: Int)
    case Absolute(totalTime: Int)
    case None
    
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
        }
    }
    
    var averageSecondsPerMove: Double {
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
        }
    }

    var speed: TimeControlSpeed {
        let secondsPerMove = self.averageSecondsPerMove
        if secondsPerMove < 10 {
            return .blitz
        } else if secondsPerMove <= 3600 {
            return .live
        } else {
            return .correspondence
        }
    }

    var timeControlObject: TimeControl {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "fischer",
                initialTime: initialTime, timeIncrement: timeIncrement, maxTime: maxTime, speed: speed
            ))
        case .Simple(let perMove):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "simple", perMove: perMove, speed: speed
            ))
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "byoyomi", mainTime: mainTime, periods: periods, periodTime: periodTime, speed: speed
            ))
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "canadian", mainTime: mainTime, periodTime: periodTime, stonesPerPeriod: stonesPerPeriod, speed: speed
            ))
        case .Absolute(let totalTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "absolute", totalTime: totalTime, speed: speed
            ))
        case .None:
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "none"
            ))
        }
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
        case .None:
            return false
        }
    }
}

enum TimeControlSpeed: String, Codable, Hashable {
    case live
    case correspondence
    case blitz
    
    func localizedString() -> String {
        switch self {
        case .live: return String(localized: "live", comment: "TimeControlSpeed enum localization")
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
        case .live:
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
            self.speed = speed
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
        var speed: TimeControlSpeed?
        var pauseOnWeekends: Bool?
    }
    
    var codingData: TimeControlCodingData
    
    init(from decoder:Decoder) throws {
        let container = try decoder.singleValueContainer()
        codingData = try container.decode(TimeControlCodingData.self)
    }
    
    init(codingData: TimeControlCodingData) {
        self.codingData = codingData
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingData)
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
    
    var system: TimeControlSystem {
        switch self.timeControl {
        case "fischer":
            return .Fischer(initialTime: self.initialTime!, timeIncrement: self.timeIncrement!, maxTime: self.maxTime!)
        case "byoyomi":
            return .ByoYomi(mainTime: self.mainTime!, periods: self.periods!, periodTime: self.periodTime!)
        case "simple":
            return .Simple(perMove: self.perMove!)
        case "canadian":
            return .Canadian(mainTime: self.mainTime!, periodTime: self.periodTime!, stonesPerPeriod: self.stonesPerPeriod!)
        case "absolute":
            return .Absolute(totalTime: self.totalTime!)
        default:
            return .None
        }
    }
    
    var shortDescription: String {
        return system.shortDescription
    }
    
    var systemName: String {
        return system.name
    }
}
