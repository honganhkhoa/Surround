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
    var periodTime: Double?
    var periodTimeLeft: Double?

    // Canadian
    var movesLeft: Int?
    var blockTime: Double?
    var blockTimeLeft: Double?
}

struct OGSPauseDetail: Decodable {
    var pauseControl: OGSPauseControl?
    var paused: Bool?
    var pausedSince: Double?
}

struct OGSClock {
    var blackTime: ThinkingTime
    var whiteTime: ThinkingTime
    var currentPlayer: StoneColor
    var lastMoveTime: Double
    var pausedTime: Double?
    var started: Bool = true
    var currentPlayerId: Int
    var blackPlayerId: Int
    var whitePlayerId: Int
    var pauseControl: OGSPauseControl?
    var expiration: Double?
    var timeUntilExpiration: TimeInterval?
    
    var blackTimeUntilAutoResign: TimeInterval?
    var whiteTimeUntilAutoResign: TimeInterval?
    var autoResignTime = [StoneColor: Double]()
}

extension OGSClock: Decodable {
    enum CodingKeys: String, CodingKey {
        case blackTime
        case whiteTime
        case blackPlayerId
        case whitePlayerId
        case currentPlayer
        case lastMove
        case startMode
        case pausedSince
        case pause
        case expiration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OGSClock.CodingKeys.self)

        expiration = try container.decodeIfPresent(Double.self, forKey: .expiration)
        if let expiration = expiration {
            timeUntilExpiration = expiration / 1000 - Date().timeIntervalSince1970
        }

        blackPlayerId = try container.decode(Int.self, forKey: .blackPlayerId)
        whitePlayerId = try container.decode(Int.self, forKey: .whitePlayerId)
        currentPlayerId = try container.decode(Int.self, forKey: .currentPlayer)
        currentPlayer = currentPlayerId == blackPlayerId ? .black : .white

        if let blackThinkingTime = try? container.decode(Double.self, forKey: .blackTime) {
            if currentPlayer == .black {
                blackTime = ThinkingTime(
                    thinkingTime: timeUntilExpiration,
                    thinkingTimeLeft: timeUntilExpiration
                )
            } else {
                blackTime = ThinkingTime(
                    thinkingTime: blackThinkingTime,
                    thinkingTimeLeft: blackThinkingTime
                )
            }
        } else if let blackThinkingTime = try? container.decode(ThinkingTime.self, forKey: .blackTime) {
            blackTime = blackThinkingTime
            blackTime.thinkingTimeLeft = blackTime.thinkingTime
            blackTime.periodsLeft = blackTime.periods
            blackTime.periodTimeLeft = blackTime.periodTime
            blackTime.blockTimeLeft = blackTime.blockTime
        } else {
            blackTime = ThinkingTime()
        }

        if let whiteThinkingTime = try? container.decode(Double.self, forKey: .whiteTime) {
            if currentPlayer == .white {
                whiteTime = ThinkingTime(
                    thinkingTime: timeUntilExpiration,
                    thinkingTimeLeft: timeUntilExpiration
                )
            } else {
                whiteTime = ThinkingTime(
                    thinkingTime: whiteThinkingTime,
                    thinkingTimeLeft: whiteThinkingTime
                )
            }
        } else if let whiteThinkingTime = try? container.decode(ThinkingTime.self, forKey: .whiteTime) {
            whiteTime = whiteThinkingTime
            whiteTime.thinkingTimeLeft = whiteTime.thinkingTime
            whiteTime.periodsLeft = whiteTime.periods
            whiteTime.periodTimeLeft = whiteTime.periodTime
            whiteTime.blockTimeLeft = whiteTime.blockTime
        } else {
            whiteTime = ThinkingTime()
        }
                
        lastMoveTime = try container.decode(Double.self, forKey: .lastMove)
        started = !container.contains(.startMode)
        
        pausedTime = try container.decodeIfPresent(Double.self, forKey: .pausedSince)
        if let pauseDetail = try container.decodeIfPresent(OGSPauseDetail.self, forKey: .pause) {
            pauseControl = pauseDetail.pauseControl
        }
        
        
    }
    
    mutating func calculateTimeLeft(with system: TimeControlSystem, serverTimeOffset: Double = 0, pauseControl: OGSPauseControl?) {

        let now = Date().timeIntervalSince1970 * 1000

        if let blackAutoResignTime = autoResignTime[.black] {
            blackTimeUntilAutoResign = (blackAutoResignTime + serverTimeOffset - now) / 1000
        } else {
            blackTimeUntilAutoResign = nil
        }
        if let whiteAutoResignTime = autoResignTime[.white] {
            whiteTimeUntilAutoResign = (whiteAutoResignTime + serverTimeOffset - now) / 1000
        } else {
            whiteTimeUntilAutoResign = nil
        }
        
        // Expiration can be for stone removal or waiting to start (start mode)
        if let expiration = expiration {
            timeUntilExpiration = (expiration + serverTimeOffset - now) / 1000
        }

        if !started {
            return
        }
        
        // logic from GobanCore.ts -> GobanCore -> setGameClock -> make_player_clock
        let paused = pauseControl?.isPaused() ?? false
        let since = paused ? max(pausedTime!, lastMoveTime) : now
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
                        thinkingTime.periodTimeLeft = timeLeft
                    }
                }
            case .Canadian(_, let periodTime, _):
                var timeLeft = thinkingTime.thinkingTime! - secondsElapsed
                if timeLeft > 0 {
                    thinkingTime.thinkingTimeLeft = timeLeft
                } else {
                    timeLeft += Double(periodTime)
                    thinkingTime.thinkingTimeLeft = 0
                    thinkingTime.blockTimeLeft = timeLeft
                }
            case .Simple, .Absolute, .Fischer(_, _, _):
                if paused {
                    thinkingTime.thinkingTimeLeft = thinkingTime.thinkingTime! - secondsElapsed
                } else {
                    thinkingTime.thinkingTimeLeft = timeUntilExpiration
                }
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
