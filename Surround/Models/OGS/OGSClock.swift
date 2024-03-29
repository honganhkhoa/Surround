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
    
    var timeLeft: Double? {
        if thinkingTimeLeft == 0 {
            return periodTimeLeft ?? blockTimeLeft ?? thinkingTimeLeft
        } else {
            return thinkingTimeLeft ?? periodTimeLeft ?? blockTimeLeft
        }
    }
}

struct OGSPauseDetail: Decodable {
    var pauseControl: OGSPauseControl?
    var paused: Bool?
    var pausedSince: Double?
}

struct OGSClock {
    var blackTime: ThinkingTime
    var whiteTime: ThinkingTime
    var currentPlayerColor: StoneColor
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

    func nextPlayerId(with color: StoneColor) -> Int {
        switch color {
        case .black:
            return blackPlayerId
        case .white:
            return whitePlayerId
        }
    }
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
        currentPlayerColor = currentPlayerId == blackPlayerId ? .black : .white

        if let blackThinkingTime = try? container.decode(Double.self, forKey: .blackTime) {
            if currentPlayerColor == .black {
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
            if currentPlayerColor == .white {
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
        let since = (paused && pausedTime != nil) ? max(pausedTime!, lastMoveTime) : now
        let secondsElapsed = floor((since - (lastMoveTime + serverTimeOffset)) / 1000)

        if secondsElapsed > 0 {
            var currentPlayerThinkingTime = currentPlayerColor == .black ? blackTime : whiteTime
            var otherPlayerThinkingTime = currentPlayerColor == .black ? whiteTime : blackTime
            switch system {
            case .ByoYomi(_, _, let periodTime):
                var timeLeft = currentPlayerThinkingTime.thinkingTime! - secondsElapsed
                if timeLeft > 0 {
                    currentPlayerThinkingTime.thinkingTimeLeft = timeLeft
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = 0
                    currentPlayerThinkingTime.periodsLeft = currentPlayerThinkingTime.periods
                    timeLeft += Double(periodTime)
                    while timeLeft < 0 && currentPlayerThinkingTime.periodsLeft! > 0 {
                        timeLeft += Double(periodTime)
                        currentPlayerThinkingTime.periodsLeft! -= 1
                    }
                    if timeLeft < 0 {
                        currentPlayerThinkingTime.periodTimeLeft = 0
                    } else {
                        currentPlayerThinkingTime.periodTimeLeft = timeLeft
                    }
                }
            case .Canadian(_, let periodTime, _):
                var timeLeft = currentPlayerThinkingTime.thinkingTime! - secondsElapsed
                if timeLeft > 0 {
                    currentPlayerThinkingTime.thinkingTimeLeft = timeLeft
                } else {
                    timeLeft += Double(periodTime)
                    currentPlayerThinkingTime.thinkingTimeLeft = 0
                    currentPlayerThinkingTime.blockTimeLeft = timeLeft
                }
            case .Simple(let perMove):
                if paused {
                    currentPlayerThinkingTime.thinkingTimeLeft = Double(perMove) - secondsElapsed
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = timeUntilExpiration
                }
                otherPlayerThinkingTime.thinkingTimeLeft = Double(perMove)
            case .Absolute, .Fischer(_, _, _):
                if paused {
                    currentPlayerThinkingTime.thinkingTimeLeft = currentPlayerThinkingTime.thinkingTime! - secondsElapsed
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = timeUntilExpiration
                }
            default:
                break
            }
            
            if currentPlayerColor == .black {
                self.blackTime = currentPlayerThinkingTime
                self.whiteTime = otherPlayerThinkingTime
            } else {
                self.whiteTime = currentPlayerThinkingTime
                self.blackTime = otherPlayerThinkingTime
            }
        }        
    }
}
