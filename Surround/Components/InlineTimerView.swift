//
//  InlineTimerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/14/20.
//

import SwiftUI

struct InlineByoYomiTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    var subFont: Font
    
    var body: some View {
        if thinkingTime.thinkingTimeLeft! > 0 {
            (
                Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(mainFont)
                +
                Text(verbatim: " (\(thinkingTime.periods!))")
                    .font(subFont)
            ).minimumScaleFactor(0.5)
        } else {
            if thinkingTime.periodsLeft! > 1 {
                (
                    Text(verbatim: timeString(timeLeft: thinkingTime.periodTimeLeft!))
                        .font(mainFont)
                    +
                    Text(verbatim: " (\(thinkingTime.periodsLeft!))")
                        .font(subFont)
                ).minimumScaleFactor(0.5)
            } else {
                (
                    Text(verbatim: timeString(timeLeft: thinkingTime.periodTimeLeft!))
                        .font(mainFont)
                    +
                    Text(" SD", comment: "Final byo-yomi period (Sudden Death)")
                        .font(subFont.bold())
                        .foregroundColor(Color.red)
                ).minimumScaleFactor(0.5)
            }
        }
    }
}

struct InlineFischerTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    var subFont: Font

    var body: some View {
        Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(mainFont)
            .minimumScaleFactor(0.5)
    }
}

struct InlineCanadianTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    var subFont: Font

    var body: some View {
        if thinkingTime.thinkingTimeLeft! > 0 {
            Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                .font(mainFont)
                .minimumScaleFactor(0.5)
        } else {
            Text(verbatim: "\(timeString(timeLeft: thinkingTime.blockTimeLeft!))/\(thinkingTime.movesLeft!)")
                .font(mainFont)
                .minimumScaleFactor(0.5)
        }
        
    }
}

struct InlineSimpleTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    var subFont: Font

    var body: some View {
        Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(mainFont)
            .minimumScaleFactor(0.5)
    }
}

struct InlineTimerView: View {
    var timeControl: TimeControl?
    var clock: OGSClock?
    var player: StoneColor
    var mainFont: Font?
    var subFont: Font?
    var pauseControl: OGSPauseControl?
    var showsPauseReason = true
    var gameFinished: Bool

    var body: some View {
        guard let clock = clock, let timeControl = timeControl else {
            return AnyView(EmptyView())
        }
        
        let thinkingTime = player == .black ? clock.blackTime : clock.whiteTime
        let mainFont = self.mainFont ?? Font.subheadline.monospacedDigit()
        let subFont = self.subFont ?? Font.caption.monospacedDigit()

        let playerId = player == .black ? clock.blackPlayerId : clock.whitePlayerId
        let isPaused = pauseControl?.isPaused() ?? false
        let isFinished = self.gameFinished
        let pausedReason = pauseControl?.pauseReason(playerId: playerId) ?? ""
        
        return AnyView(HStack(alignment: .firstTextBaseline) {
            if !clock.started {
                if let timeLeft = clock.timeUntilExpiration {
                    if clock.currentPlayerColor == player {
                        Image(systemName: "hourglass")
                            .foregroundColor(Color(UIColor.systemIndigo))
                        Text(timeString(timeLeft: timeLeft))
                            .font(mainFont.bold())
                            .foregroundColor(Color(UIColor.systemIndigo))
                            .minimumScaleFactor(0.5)
                    } else {
                        Text("Waiting...")
                            .font(mainFont.bold())
                            .foregroundColor(Color(UIColor.systemIndigo))
                            .minimumScaleFactor(0.5)
                    }
                }
            } else {
                if clock.currentPlayerColor == player && !isPaused {
                    Image(systemName: "hourglass")
                }
                switch timeControl.system {
                case .ByoYomi:
                    InlineByoYomiTimerView(thinkingTime: thinkingTime, mainFont: mainFont, subFont: subFont)
                case .Fischer:
                    InlineFischerTimerView(thinkingTime: thinkingTime, mainFont: mainFont, subFont: subFont)
                case .Canadian:
                    InlineCanadianTimerView(thinkingTime: thinkingTime, mainFont: mainFont, subFont: subFont)
                case .Simple, .Absolute:
                    InlineSimpleTimerView(thinkingTime: thinkingTime, mainFont: mainFont, subFont: subFont)
                default:
                    Text(verbatim: "").font(mainFont)
                }
                if isPaused && !isFinished {
                    if showsPauseReason {
                        Text(pausedReason).font(subFont.bold()).minimumScaleFactor(0.5)
                    } else {
                        Image(systemName: "pause.fill")
                    }
                }
            }
        })
    }
}

struct InlineTimerView_Previews: PreviewProvider {
    static var previews: some View {
        let timeControl1 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "byoyomi", mainTime: 300, periods: 5, periodTime: 30))
        let clock1 = OGSClock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185, periods: 5, periodTime: 30),
            whiteTime: ThinkingTime(thinkingTime: 0, thinkingTimeLeft: 0, periods: 5, periodsLeft: 1, periodTime: 30, periodTimeLeft: 15),
            currentPlayerColor: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
            currentPlayerId: 1, blackPlayerId: 1, whitePlayerId: 2
        )
        
        let timeControl2 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "fischer", initialTime: 600, timeIncrement: 30, maxTime: 600))
        let clock2 = OGSClock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185),
            whiteTime: ThinkingTime(thinkingTime: 300, thinkingTimeLeft: 300),
            currentPlayerColor: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
            currentPlayerId: 1, blackPlayerId: 1, whitePlayerId: 2
        )

        return Group {
            InlineTimerView(timeControl: timeControl1, clock: clock1, player: .black, gameFinished: false)
            InlineTimerView(timeControl: timeControl1, clock: clock1, player: .white, gameFinished: false)
            InlineTimerView(timeControl: timeControl2, clock: clock2, player: .white, gameFinished: false)
        }.previewLayout(.fixed(width: 180, height: 44))
    }
}
