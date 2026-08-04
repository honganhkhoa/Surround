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
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(mainFont)
                Text(verbatim: " (\(thinkingTime.periods!))")
                    .font(subFont)
            }
            .minimumScaleFactor(0.5)
        } else {
            if thinkingTime.periodsLeft! > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: timeString(timeLeft: thinkingTime.periodTimeLeft!))
                        .font(mainFont)
                    Text(verbatim: " (\(thinkingTime.periodsLeft!))")
                        .font(subFont)
                }
                .minimumScaleFactor(0.5)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: timeString(timeLeft: thinkingTime.periodTimeLeft!))
                        .font(mainFont)
                    Text(" SD", comment: "Final byo-yomi period (Sudden Death)")
                        .font(subFont.bold())
                        .foregroundColor(Color.red)
                }
                .minimumScaleFactor(0.5)
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

    var body: some View {
        guard let clock = clock, let timeControl = timeControl else {
            return AnyView(EmptyView())
        }
        
        let thinkingTime = player == .black ? clock.blackTime : clock.whiteTime
        let mainFont = self.mainFont ?? Font.subheadline.monospacedDigit()
        let subFont = self.subFont ?? Font.caption.monospacedDigit()

        let playerId = player == .black ? clock.blackPlayerId : clock.whitePlayerId
        let isPaused = pauseControl?.isPaused() ?? false
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
                if isPaused {
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

#if DEBUG
private func inlineByoYomiTimerPreviewData() -> (timeControl: TimeControl, clock: OGSClock) {
    let timeControl = TimeControl(
        codingData: TimeControl.TimeControlCodingData(
            timeControl: "byoyomi",
            mainTime: 300,
            periods: 5,
            periodTime: 30
        )
    )
    let clock = OGSClock(
        blackTime: ThinkingTime(
            thinkingTime: 200,
            thinkingTimeLeft: 185,
            periods: 5,
            periodTime: 30
        ),
        whiteTime: ThinkingTime(
            thinkingTime: 0,
            thinkingTimeLeft: 0,
            periods: 5,
            periodsLeft: 1,
            periodTime: 30,
            periodTimeLeft: 15
        ),
        currentPlayerColor: .black,
        lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
        currentPlayerId: 1,
        blackPlayerId: 1,
        whitePlayerId: 2
    )
    return (timeControl, clock)
}

private func inlineFischerTimerPreviewData() -> (timeControl: TimeControl, clock: OGSClock) {
    let timeControl = TimeControl(
        codingData: TimeControl.TimeControlCodingData(
            timeControl: "fischer",
            initialTime: 600,
            timeIncrement: 30,
            maxTime: 600
        )
    )
    let clock = OGSClock(
        blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185),
        whiteTime: ThinkingTime(thinkingTime: 300, thinkingTimeLeft: 300),
        currentPlayerColor: .black,
        lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
        currentPlayerId: 1,
        blackPlayerId: 1,
        whitePlayerId: 2
    )
    return (timeControl, clock)
}

private func inlineCanadianTimerPreviewData() -> (timeControl: TimeControl, clock: OGSClock) {
    let timeControl = TimeControl(
        codingData: TimeControl.TimeControlCodingData(
            timeControl: "canadian",
            mainTime: 600,
            periodTime: 180,
            stonesPerPeriod: 10
        )
    )
    let clock = OGSClock(
        blackTime: ThinkingTime(
            thinkingTime: 300,
            thinkingTimeLeft: 285,
            movesLeft: 10,
            blockTime: 180,
            blockTimeLeft: 180
        ),
        whiteTime: ThinkingTime(
            thinkingTime: 0,
            thinkingTimeLeft: 0,
            movesLeft: 4,
            blockTime: 180,
            blockTimeLeft: 75
        ),
        currentPlayerColor: .black,
        lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
        currentPlayerId: 1,
        blackPlayerId: 1,
        whitePlayerId: 2
    )
    return (timeControl, clock)
}

private func inlineSimpleTimerPreviewData() -> (timeControl: TimeControl, clock: OGSClock) {
    let timeControl = TimeControl(
        codingData: TimeControl.TimeControlCodingData(
            timeControl: "simple",
            perMove: 60
        )
    )
    let clock = OGSClock(
        blackTime: ThinkingTime(thinkingTime: 60, thinkingTimeLeft: 42),
        whiteTime: ThinkingTime(thinkingTime: 60, thinkingTimeLeft: 60),
        currentPlayerColor: .black,
        lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
        currentPlayerId: 1,
        blackPlayerId: 1,
        whitePlayerId: 2
    )
    return (timeControl, clock)
}

#Preview("Byo-yomi — Main time", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineByoYomiTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .black)
}

#Preview("Byo-yomi — Final period", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineByoYomiTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .white)
}

#Preview("Fischer — Opponent", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineFischerTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .white)
}

#Preview("Canadian — Main time", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineCanadianTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .black)
}

#Preview("Canadian — Overtime", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineCanadianTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .white)
}

#Preview("Simple — Per move", traits: .fixedLayout(width: 180, height: 44)) {
    let previewData = inlineSimpleTimerPreviewData()
    InlineTimerView(timeControl: previewData.timeControl, clock: previewData.clock, player: .black)
}
#endif
