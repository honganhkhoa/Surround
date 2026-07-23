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
                // A scalar clock value arrives in milliseconds; Surround works in seconds.
                blackTime = ThinkingTime(
                    thinkingTime: blackThinkingTime / 1000,
                    thinkingTimeLeft: blackThinkingTime / 1000
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
                // A scalar clock value arrives in milliseconds; Surround works in seconds.
                whiteTime = ThinkingTime(
                    thinkingTime: whiteThinkingTime / 1000,
                    thinkingTimeLeft: whiteThinkingTime / 1000
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
        // Only a truthy start_mode marks the game as not yet started; false and an
        // omitted key are equivalent and mean the normal clock is running.
        started = !(try container.decodeIfPresent(Bool.self, forKey: .startMode) ?? false)
        
        pausedTime = try container.decodeIfPresent(Double.self, forKey: .pausedSince)
        if let pauseDetail = try container.decodeIfPresent(OGSPauseDetail.self, forKey: .pause) {
            pauseControl = pauseDetail.pauseControl
        }
    }
    
    mutating func calculateTimeLeft(with system: TimeControlSystem, serverTimeOffset: Double = 0, pauseControl: OGSPauseControl?, now: Double = Date().timeIntervalSince1970 * 1000) {

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
        
        // logic from goban -> OGSConnectivity.ts -> computeNewPlayerClock
        let paused = pauseControl?.isPaused() ?? false
        let since = (paused && pausedTime != nil) ? max(pausedTime!, lastMoveTime) : now
        let secondsElapsed = floor((since - (lastMoveTime + serverTimeOffset)) / 1000)

        if secondsElapsed > 0 {
            var currentPlayerThinkingTime = currentPlayerColor == .black ? blackTime : whiteTime
            var otherPlayerThinkingTime = currentPlayerColor == .black ? whiteTime : blackTime
            switch system {
            case .ByoYomi(_, _, let periodTime):
                let periodTime = Double(periodTime)
                var overtimeUsage = 0.0
                if (currentPlayerThinkingTime.thinkingTime ?? 0) > 0 {
                    let mainTimeLeft = currentPlayerThinkingTime.thinkingTime! - secondsElapsed
                    if mainTimeLeft <= 0 {
                        overtimeUsage = -mainTimeLeft
                        currentPlayerThinkingTime.thinkingTimeLeft = 0
                    } else {
                        currentPlayerThinkingTime.thinkingTimeLeft = mainTimeLeft
                    }
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = 0
                    overtimeUsage = secondsElapsed
                }
                currentPlayerThinkingTime.periodsLeft = currentPlayerThinkingTime.periods
                currentPlayerThinkingTime.periodTimeLeft = periodTime
                if overtimeUsage > 0 {
                    let periodsUsed = floor(overtimeUsage / periodTime)
                    currentPlayerThinkingTime.periodsLeft = (currentPlayerThinkingTime.periods ?? 0) - Int(periodsUsed)
                    currentPlayerThinkingTime.periodTimeLeft = periodTime - (overtimeUsage - periodsUsed * periodTime)
                    if (currentPlayerThinkingTime.periodsLeft ?? 0) <= 0 {
                        // Every period is spent, so this clock has timed out. Goban
                        // keeps the leftover period time for display and flags a
                        // separate timed_out state; Surround does not model that flag,
                        // so the effective time must read zero instead.
                        currentPlayerThinkingTime.periodsLeft = 0
                        currentPlayerThinkingTime.periodTimeLeft = 0
                    } else if (currentPlayerThinkingTime.periodTimeLeft ?? 0) < 0 {
                        currentPlayerThinkingTime.periodTimeLeft = 0
                    }
                }
            case .Canadian(_, _, _):
                let timeLeft = (currentPlayerThinkingTime.thinkingTime ?? 0) - secondsElapsed
                currentPlayerThinkingTime.thinkingTimeLeft = max(0, timeLeft)
                var blockTimeLeft = currentPlayerThinkingTime.blockTime ?? 0
                if timeLeft < 0 {
                    blockTimeLeft += timeLeft
                }
                currentPlayerThinkingTime.blockTimeLeft = max(0, blockTimeLeft)
            case .Simple(let perMove):
                if paused {
                    currentPlayerThinkingTime.thinkingTimeLeft = max(0, Double(perMove) - secondsElapsed)
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = max(0, timeUntilExpiration ?? Double(perMove) - secondsElapsed)
                }
                otherPlayerThinkingTime.thinkingTimeLeft = Double(perMove)
            case .Absolute, .Fischer(_, _, _):
                if paused {
                    currentPlayerThinkingTime.thinkingTimeLeft = max(0, (currentPlayerThinkingTime.thinkingTime ?? 0) - secondsElapsed)
                } else {
                    currentPlayerThinkingTime.thinkingTimeLeft = max(0, timeUntilExpiration ?? (currentPlayerThinkingTime.thinkingTime ?? 0) - secondsElapsed)
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
