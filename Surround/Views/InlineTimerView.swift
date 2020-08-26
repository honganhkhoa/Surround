//
//  InlineTimerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/14/20.
//

import SwiftUI

struct InlineByoYomiTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if thinkingTime.thinkingTime! > 0 {
                Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                    .font(Font.subheadline.monospacedDigit())
                Text("(\(thinkingTime.periods!))")
                    .font(Font.caption.monospacedDigit())
            } else {
                Text(timeString(timeLeft: thinkingTime.periodTimeLeft!))
                    .font(Font.subheadline.monospacedDigit())
                if thinkingTime.periodsLeft! > 1 {
                    Text("(\(thinkingTime.periodsLeft!))")
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

struct InlineFischerTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(Font.subheadline.monospacedDigit())
    }
}

struct InlineCanadianTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        if thinkingTime.thinkingTimeLeft! > 0 {
            Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
                .font(Font.subheadline.monospacedDigit())
        } else {
            Text("\(timeString(timeLeft: thinkingTime.blockTimeLeft!))/\(thinkingTime.movesLeft!)")
                .font(Font.subheadline.monospacedDigit())
        }
        
    }
}

struct InlineSimpleTimerView: View {
    var thinkingTime: ThinkingTime
    
    var body: some View {
        Text(timeString(timeLeft: thinkingTime.thinkingTimeLeft!))
            .font(Font.subheadline.monospacedDigit())
    }
}

struct InlineTimerView: View {
    var timeControl: TimeControl?
    var clock: Clock?
    var player: StoneColor

    var body: some View {
        guard let clock = clock, let timeControl = timeControl else {
            return AnyView(EmptyView())
        }
        
        let thinkingTime = player == .black ? clock.blackTime : clock.whiteTime
        
        return AnyView(HStack {
            if clock.currentPlayer == player {
                Image(systemName: "hourglass")
            }
            switch timeControl.system {
            case .ByoYomi:
                InlineByoYomiTimerView(thinkingTime: thinkingTime)
            case .Fischer:
                InlineFischerTimerView(thinkingTime: thinkingTime)
            case .Canadian:
                InlineCanadianTimerView(thinkingTime: thinkingTime)
            case .Simple, .Absolute:
                InlineSimpleTimerView(thinkingTime: thinkingTime)
            default:
                Text("").font(.subheadline)
            }
        })
    }
}

struct InlineTimerView_Previews: PreviewProvider {
    static var previews: some View {
        let timeControl1 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "byoyomi", mainTime: 300, periods: 5, periodTime: 30))
        let clock1 = Clock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185, periods: 5, periodTime: 30),
            whiteTime: ThinkingTime(thinkingTime: 0, thinkingTimeLeft: 0, periods: 5, periodsLeft: 1, periodTime: 30, periodTimeLeft: 15),
            currentPlayer: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000)
        
        let timeControl2 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "fischer", initialTime: 600, timeIncrement: 30, maxTime: 600))
        let clock2 = Clock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185),
            whiteTime: ThinkingTime(thinkingTime: 300, thinkingTimeLeft: 300),
            currentPlayer: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000)

        return Group {
            InlineTimerView(timeControl: timeControl1, clock: clock1, player: .black)
            InlineTimerView(timeControl: timeControl1, clock: clock1, player: .white)
            InlineTimerView(timeControl: timeControl2, clock: clock2, player: .white)
        }.previewLayout(.fixed(width: 180, height: 44))
    }
}
