//
//  TimerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import SwiftUI

struct ByoYomiTimerView: View {
    var clock: Clock
    var player: StoneColor
    
    func timeString(timeLeft: TimeInterval) -> String {
        return TimeUtilities.shared.formatTimeLeft(timeLeft: timeLeft)
    }
    
    func timeString(timeLeft: Int) -> String {
        return TimeUtilities.shared.formatTimeLeft(timeLeft: Double(timeLeft))
    }
    
    var body: some View {
        let thinkingTime = player == .black ? clock.blackTime : clock.whiteTime
        
        return VStack(alignment: .trailing) {
            if thinkingTime.thinkingTime! > 0 {
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

struct TimerView: View {
    var timeControl: TimeControl?
    var clock: Clock?
    var player: StoneColor
    
    var body: some View {
        guard let clock = clock, let timeControl = timeControl else {
            return AnyView(EmptyView())
        }
        
        switch timeControl.system {
        case .ByoYomi:
            return AnyView(ByoYomiTimerView(clock: clock, player: player))
        default:
            return AnyView(EmptyView())
        }
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        let timeControl1 = TimeControl(codingData: TimeControl.TimeControlCodingData(timeControl: "byoyomi", mainTime: 300, periods: 5, periodTime: 30))
        let clock1 = Clock(
            blackTime: ThinkingTime(thinkingTime: 200, thinkingTimeLeft: 185, periods: 5, periodTime: 30),
            whiteTime: ThinkingTime(thinkingTime: 0, thinkingTimeLeft: 185, periods: 3, periodTime: 30),
            currentPlayer: .black,
            lastMoveTime: Date().timeIntervalSince1970 * 1000 - 10 * 3600 * 1000)
        
        return TimerView(timeControl: timeControl1, clock: clock1, player: .black).previewLayout(.fixed(width: 180, height: 88))
    }
}
