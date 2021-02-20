//
//  TimerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import SwiftUI

struct ByoYomiTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        VStack(alignment: .trailing) {
            if thinkingTime.thinkingTimeLeft! > 0 {
                Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(Font.subheadline.monospacedDigit())
                Text("+ \(thinkingTime.periods!)× \(timeString(timeLeft: TimeInterval(thinkingTime.periodTime!)))")
                    .font(Font.caption.monospacedDigit())
            } else {
                Text(timeString(timeLeft: thinkingTime.periodTimeLeft!))
                    .font(Font.subheadline.monospacedDigit())
                if thinkingTime.periodsLeft! > 1 {
                    Text("+ \(thinkingTime.periodsLeft! - 1)× \(timeString(timeLeft: TimeInterval(thinkingTime.periodTime!)))")
                        .font(Font.caption.monospacedDigit())
                } else {
                    Text("SD")
                        .font(Font.caption.bold())
                        .foregroundColor(Color.red)
                }
            }
        }
    }
}

struct FischerTimerView: View {
    var thinkingTime: ThinkingTime
    var timeIncrement: Int
    
    var body: some View {
        VStack(alignment: .trailing) {
            Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                .font(Font.subheadline.monospacedDigit())
            Text("+ \(timeString(timeLeft: timeIncrement))")
                .font(Font.caption.monospacedDigit())
        }
    }
}

struct CanadianTimerView: View {
    var thinkingTime: ThinkingTime
    var periodTime: Int
    var stonesPerPeriod: Int
    
    var body: some View {
        if thinkingTime.thinkingTimeLeft! > 0 {
            VStack(alignment: .trailing) {
                Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(Font.subheadline.monospacedDigit())
                Text("+ \(timeString(timeLeft: periodTime))/\(stonesPerPeriod)")
                    .font(Font.caption.monospacedDigit())
            }
        } else {
            Text("\(timeString(timeLeft: thinkingTime.blockTimeLeft!))/\(thinkingTime.movesLeft!)")
                .font(Font.subheadline.monospacedDigit())
        }
    }
}

struct SimpleTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(Font.subheadline.monospacedDigit())
    }
}

struct TimerView: View {
    var timeControl: TimeControl?
    var clock: OGSClock?
    var player: StoneColor
    
    var body: some View {
        guard let clock = clock,
              let timeControl = timeControl else {
            return AnyView(EmptyView())
        }
        
        if !clock.started {
            if let timeLeft = clock.timeUntilExpiration {
                if clock.currentPlayer == player {
                    return AnyView(
                        erasing: Text(timeString(timeLeft: timeLeft))
                            .font(Font.subheadline.monospacedDigit().bold())
                    )
                } else {
                    return AnyView(
                        erasing: Text("Waiting...")
                            .font(Font.subheadline.monospacedDigit().bold())
                    )
                }
            }
        } else {
            let thinkingTime = (player == .black ? clock.blackTime : clock.whiteTime)

            switch timeControl.system {
            case .ByoYomi:
                return AnyView(ByoYomiTimerView(thinkingTime: thinkingTime))
            case .Fischer(_, let timeIncrement, _):
                return AnyView(FischerTimerView(thinkingTime: thinkingTime, timeIncrement: timeIncrement))
            case .Canadian(_, let periodTime, let stonesPerPeriod):
                return AnyView(CanadianTimerView(thinkingTime: thinkingTime, periodTime: periodTime, stonesPerPeriod: stonesPerPeriod))
            case .Simple, .Absolute:
                return AnyView(SimpleTimerView(thinkingTime: thinkingTime))
            default:
                return AnyView(EmptyView())
            }
        }
        return AnyView(EmptyView())
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        let timeControl1 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "byoyomi", mainTime: 300, periods: 5, periodTime: 30))
        let clock1 = OGSClock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185, periods: 5, periodTime: 30),
            whiteTime: ThinkingTime(thinkingTime: 0, thinkingTimeLeft: 0, periods: 5, periodsLeft: 1, periodTime: 30, periodTimeLeft: 15),
            currentPlayer: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000,
            currentPlayerId: 1, blackPlayerId: 1, whitePlayerId: 2
        )

        let timeControl2 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "fischer", initialTime: 600, timeIncrement: 30, maxTime: 600))
        let clock2 = OGSClock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185),
            whiteTime: ThinkingTime(thinkingTime: 300, thinkingTimeLeft: 300),
            currentPlayer: .black,
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
