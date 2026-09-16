//
//  ChallengeDraft.swift
//  Surround
//

import Foundation
import Combine

/// Editable challenge values retained while navigating through player profiles.
final class ChallengeDraft: ObservableObject, Identifiable {
    let id = UUID()

    @Published var challenge: OGSChallengeTemplate
    @Published var gameName: String
    @Published var isPrivate: Bool
    @Published var isRanked: Bool
    @Published var boardWidth: Int
    @Published var boardHeight: Int
    @Published var standardBoardSize: Bool
    @Published var timeControlSpeed: TimeControlSpeed
    @Published var isBlitz: Bool
    @Published var blitzTimeControl: TimeControl
    @Published var liveTimeControl: TimeControl
    @Published var correspondenceTimeControl: TimeControl
    @Published var pauseOnWeekend: Bool
    @Published var isOpen: Bool
    @Published var rankRestricted: Bool
    @Published var maxRank: Int
    @Published var minRank: Int
    @Published var opponent: OGSUser? {
        didSet { challenge.challenged = opponent }
    }
    @Published var handicap: Int
    @Published var automaticColor: Bool
    @Published var yourColor: StoneColor
    @Published var rulesSet: OGSRule
    @Published var komi: Double
    @Published var analysisDisabled: Bool

    static var defaultChallengeTemplate: OGSChallengeTemplate {
        OGSChallengeTemplate(
            game: OGSChallengeTemplate.GameDetail(
                width: 19,
                height: 19,
                ranked: true,
                isPrivate: false,
                handicap: 0,
                disableAnalysis: false,
                name: defaultGameName,
                rules: .japanese,
                timeControl: TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            )
        )
    }

    var finalTimeControlSpeed: TimeControlSpeed {
        if timeControlSpeed == .correspondence {
            return .correspondence
        } else {
            if isBlitz {
                return .blitz
            } else {
                return timeControlSpeed
            }
        }
    }

    var finalTimeControl: TimeControl {
        switch finalTimeControlSpeed {
        case .blitz:
            return blitzTimeControl
        case .live, .rapid:
            return liveTimeControl
        case .correspondence:
            return correspondenceTimeControl
        }
    }

    init(initialChallenge: OGSChallengeTemplate? = nil) {
        let baseChallenge = initialChallenge ?? Self.defaultChallengeTemplate
        let ruleSet = baseChallenge.game.rules
        let gameName = baseChallenge.game.name.isEmpty ? defaultGameName : baseChallenge.game.name

        let boardWidth = baseChallenge.game.width
        let boardHeight = baseChallenge.game.height
        let standardBoardSize = boardWidth == boardHeight && [9, 13, 19].contains(boardWidth)

        let timeControl = baseChallenge.game.timeControl
        let speed = timeControl.speed
        let timeControlSpeed: TimeControlSpeed = speed == .correspondence ? .correspondence : .live
        let isBlitz = speed == .blitz
        var blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
        var liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
        var correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
        switch speed {
        case .blitz:
            blitzTimeControl = timeControl
        case .live:
            liveTimeControl = timeControl
        case .correspondence:
            correspondenceTimeControl = timeControl
        default:
            liveTimeControl = timeControl
        }

        let isOpen = baseChallenge.challenged == nil
        let restrictedMin = baseChallenge.game.minRank ?? -1000
        let restrictedMax = baseChallenge.game.maxRank ?? 1000
        let rankRestricted = isOpen && (restrictedMin != -1000 || restrictedMax != 1000)
        let minRank = rankRestricted ? min(max(restrictedMin, 5), 38) : 5
        let maxRank = rankRestricted ? min(max(restrictedMax, 5), 38) : 36

        let automaticColor = baseChallenge.challengerColor == nil
        let yourColor = baseChallenge.challengerColor ?? .black

        self.challenge = baseChallenge
        self.gameName = gameName
        self.isPrivate = baseChallenge.game.isPrivate
        self.isRanked = baseChallenge.game.ranked
        self.boardWidth = boardWidth
        self.boardHeight = boardHeight
        self.standardBoardSize = standardBoardSize
        self.timeControlSpeed = timeControlSpeed
        self.isBlitz = isBlitz
        self.blitzTimeControl = blitzTimeControl
        self.liveTimeControl = liveTimeControl
        self.correspondenceTimeControl = correspondenceTimeControl
        self.pauseOnWeekend = timeControl.pauseOnWeekends ?? true
        self.isOpen = isOpen
        self.rankRestricted = rankRestricted
        self.maxRank = maxRank
        self.minRank = minRank
        self.opponent = baseChallenge.challenged
        self.handicap = baseChallenge.game.handicap
        self.automaticColor = automaticColor
        self.yourColor = yourColor
        self.rulesSet = ruleSet
        self.komi = baseChallenge.game.komi ?? ruleSet.defaultKomi
        self.analysisDisabled = baseChallenge.game.disableAnalysis
    }
}
