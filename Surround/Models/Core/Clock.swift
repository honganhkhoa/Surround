//
//  Clock.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import Foundation

struct ThinkingTime: Codable {
    var thinkingTime: Double?
    var thinkingTimeLeft: Double?
    
    // Byo-Yomi
    var periods: Int?
    var periodsLeft: Int?
    var periodTime: Int?
    var periodTimeLeft: Int?

    // Canadian
    var movesLeft: Int?
    var blockTime: Double?
    var blockTimeLeft: Double?
}

struct Clock {
    var blackTime: ThinkingTime
    var whiteTime: ThinkingTime
    var currentPlayer: StoneColor
    var lastMoveTime: Double
    var pausedTime: Double?
    var started: Bool = false
    var currentPlayerId: Int
    var blackPlayerId: Int
    var whitePlayerId: Int
}

extension Clock: Decodable {
    enum CodingKeys: String, CodingKey {
        case blackTime
        case whiteTime
        case blackPlayerId
        case whitePlayerId
        case currentPlayer
        case lastMove
        case startMode
        case pausedSince
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Clock.CodingKeys.self)
        if let blackThinkingTime = try? container.decode(Double.self, forKey: .blackTime) {
            blackTime = ThinkingTime(thinkingTime: blackThinkingTime)
        } else {
            blackTime = try container.decode(ThinkingTime.self, forKey: .blackTime)
        }
        blackTime.thinkingTimeLeft = blackTime.thinkingTime
        blackTime.periodsLeft = blackTime.periods
        blackTime.periodTimeLeft = blackTime.periodTime
        blackTime.blockTimeLeft = blackTime.blockTime

        if let whiteThinkingTime = try? container.decode(Double.self, forKey: .whiteTime) {
            whiteTime = ThinkingTime(thinkingTime: whiteThinkingTime)
        } else {
            whiteTime = try container.decode(ThinkingTime.self, forKey: .whiteTime)
        }
        whiteTime.thinkingTimeLeft = whiteTime.thinkingTime
        whiteTime.periodsLeft = whiteTime.periods
        whiteTime.periodTimeLeft = whiteTime.periodTime
        whiteTime.blockTimeLeft = whiteTime.blockTime
        
        blackPlayerId = try container.decode(Int.self, forKey: .blackPlayerId)
        whitePlayerId = try container.decode(Int.self, forKey: .whitePlayerId)
        currentPlayerId = try container.decode(Int.self, forKey: .currentPlayer)
        currentPlayer = currentPlayerId == blackPlayerId ? .black : .white
        
        lastMoveTime = try container.decode(Double.self, forKey: .lastMove)
        started = !container.contains(.startMode)
        
        pausedTime = try container.decodeIfPresent(Double.self, forKey: .pausedSince)
    }
    
    mutating func calculateTimeLeft(with system: TimeControlSystem, serverTimeOffset: Double = 0) {
        guard started else {
            return
        }
        // goban/lib/goban.js:~8246

        let now = Date().timeIntervalSince1970 * 1000
        let since = pausedTime == nil ? now : max(pausedTime!, lastMoveTime)
        let secondsElapsed = floor((since - (lastMoveTime + serverTimeOffset)) / 1000)

        if secondsElapsed > 0 {
            var thinkingTime = currentPlayer == .black ? blackTime : whiteTime
            switch system {
            case .ByoYomi(_, _, let periodTime):
                var timeLeft = thinkingTime.thinkingTime! - secondsElapsed
                if timeLeft > 0 {
                    thinkingTime.thinkingTimeLeft = timeLeft
                } else {
                    thinkingTime.thinkingTimeLeft = 0
                    thinkingTime.periodsLeft = thinkingTime.periods
                    timeLeft += Double(periodTime)
                    while timeLeft < 0 && thinkingTime.periodsLeft! > 0 {
                        timeLeft += Double(periodTime)
                        thinkingTime.periodsLeft! -= 1
                    }
                    if timeLeft < 0 {
                        thinkingTime.periodTimeLeft = 0
                    } else {
                        thinkingTime.periodTimeLeft = Int(timeLeft)
                    }
                }
            case .Fischer(_, _, _):
                thinkingTime.thinkingTimeLeft = thinkingTime.thinkingTime! - secondsElapsed
            case .Canadian(_, let periodTime, _):
                var timeLeft = thinkingTime.thinkingTime! - secondsElapsed
                if timeLeft > 0 {
                    thinkingTime.thinkingTimeLeft = timeLeft
                } else {
                    timeLeft += Double(periodTime)
                    thinkingTime.thinkingTimeLeft = 0
                    thinkingTime.blockTimeLeft = timeLeft
                }
            case .Simple, .Absolute:
                let timeLeft = thinkingTime.thinkingTime! - secondsElapsed
                thinkingTime.thinkingTimeLeft = timeLeft
            default:
                break
            }
            
            if currentPlayer == .black {
                self.blackTime = thinkingTime
            } else {
                self.whiteTime = thinkingTime
            }
        }
    }
}
