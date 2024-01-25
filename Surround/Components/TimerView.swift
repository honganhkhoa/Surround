//
//  TimerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import SwiftUI

struct ByoYomiTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    var subFont: Font
    
    var body: some View {
        VStack(alignment: .trailing) {
            if thinkingTime.thinkingTimeLeft! > 0 {
                Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(mainFont.monospacedDigit())
                Text(verbatim: "+ \(thinkingTime.periods!)× \(timeString(timeLeft: TimeInterval(thinkingTime.periodTime!)))")
                    .font(subFont.monospacedDigit())
            } else {
                Text(verbatim: timeString(timeLeft: thinkingTime.periodTimeLeft!))
                    .font(mainFont.monospacedDigit())
                if thinkingTime.periodsLeft! > 1 {
                    Text(verbatim: "+ \(thinkingTime.periodsLeft! - 1)× \(timeString(timeLeft: TimeInterval(thinkingTime.periodTime!)))")
                        .font(subFont.monospacedDigit())
                } else {
                    Text("SD")
                        .font(subFont.bold())
                        .foregroundColor(Color.red)
                }
            }
        }
    }
}

struct FischerTimerView: View {
    var thinkingTime: ThinkingTime
    var timeIncrement: Int
    var mainFont: Font
    var subFont: Font
    
    var body: some View {
        VStack(alignment: .trailing) {
            Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                .font(mainFont.monospacedDigit())
            Text(verbatim: "+ \(timeString(timeLeft: timeIncrement))")
                .font(subFont.monospacedDigit())
        }
    }
}

struct CanadianTimerView: View {
    var thinkingTime: ThinkingTime
    var periodTime: Int
    var stonesPerPeriod: Int
    var mainFont: Font
    var subFont: Font
    
    var body: some View {
        if thinkingTime.thinkingTimeLeft! > 0 {
            VStack(alignment: .trailing) {
                Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(mainFont.monospacedDigit())
                Text(verbatim: "+ \(timeString(timeLeft: periodTime))/\(stonesPerPeriod)")
                    .font(subFont.monospacedDigit())
            }
        } else {
            Text(verbatim: "\(timeString(timeLeft: thinkingTime.blockTimeLeft!))/\(thinkingTime.movesLeft!)")
                .font(mainFont.monospacedDigit())
        }
    }
}

struct SimpleTimerView: View {
    var thinkingTime: ThinkingTime
    var mainFont: Font
    
    var body: some View {
        Text(verbatim: timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(mainFont.monospacedDigit())
    }
}

struct TimerView: View {
    var timeControl: TimeControl?
    var clock: OGSClock?
    var player: StoneColor
    var mainFont = Font.subheadline
    var subFont = Font.caption
    
    var body: some View {
        if let clock = clock, let timeControl = timeControl {
            if !clock.started {
                if let timeLeft = clock.timeUntilExpiration {
                    if clock.currentPlayerColor == player {
                        Text(timeString(timeLeft: timeLeft))
                            .font(mainFont.monospacedDigit().bold())
                    } else {
                        Text("Waiting...")
                            .font(mainFont.monospacedDigit().bold())
                    }
                }
            } else {
                if let thinkingTime = (player == .black ? self.clock?.blackTime : self.clock?.whiteTime) {
                    switch timeControl.system {
                    case .ByoYomi:
                        ByoYomiTimerView(thinkingTime: thinkingTime, mainFont: mainFont, subFont: subFont)
                    case .Fischer(_, let timeIncrement, _):
                        FischerTimerView(thinkingTime: thinkingTime, timeIncrement: timeIncrement, mainFont: mainFont, subFont: subFont)
                    case .Canadian(_, let periodTime, let stonesPerPeriod):
                        CanadianTimerView(thinkingTime: thinkingTime, periodTime: periodTime, stonesPerPeriod: stonesPerPeriod, mainFont: mainFont, subFont: subFont)
                    case .Simple, .Absolute:
                        SimpleTimerView(thinkingTime: thinkingTime, mainFont: mainFont)
                    default:
                        EmptyView()
                    }
                } else {
                    EmptyView()
                }
            }
        } else {
            EmptyView()
        }
    }
}

struct TimerView_Previews: PreviewProvider {
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
            TimerView(timeControl: timeControl1, clock: clock1, player: .black)
            TimerView(timeControl: timeControl1, clock: clock1, player: .white)
            TimerView(timeControl: timeControl2, clock: clock2, player: .black)
        }.previewLayout(.fixed(width: 180, height: 88))
    }
}
