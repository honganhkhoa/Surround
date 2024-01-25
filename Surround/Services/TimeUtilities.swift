//
//  TimeUtilities.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import Foundation

class TimeUtilities {
    static let shared = TimeUtilities()
    lazy var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    func formatTimeLeft(timeLeft: Int) -> String {
        return formatTimeLeft(timeLeft: TimeInterval(timeLeft))
    }
    
    func formatTimeLeft(timeLeft: TimeInterval) -> String {
        var secondsLeft = max(Int(timeLeft), 0)
        let daysLeft = secondsLeft / 86400
        secondsLeft -= daysLeft * 86400
        let hoursLeft = secondsLeft / 3600
        secondsLeft -= hoursLeft * 3600
        let minutesLeft = secondsLeft / 60
        secondsLeft -= minutesLeft * 60
        
        if daysLeft > 1 {
            let daysString = String(localized: "\(daysLeft) days left", comment: "Time left - more than 2 days left, days part")
            let hoursString = String(localized: "\(hoursLeft)h left", comment: "Time left - more than 2 days left, hours part")
            if hoursLeft > 0 {
                return String(localized: "\(daysString) \(hoursString)", comment: "Time left on timer - more than 2 days [days - hours]")
            } else {
                return daysString
            }
        } else {
            if daysLeft == 1 {
                return String(localized: "\(hoursLeft + 24)h left", comment: "Time left - 1 day to 2 days.")
            } else {
                if hoursLeft >= 1 {
                    return String(localized: "\(hoursLeft)h \(minutesLeft, specifier: "%02d")m", comment: "Time left - 1 hour to 1 day.")
                } else {
                    return String(localized: "\(minutesLeft, specifier: "%02d"):\(secondsLeft, specifier: "%02d")", comment: "Time left - less than 1 hour.")
                }
            }
        }
    }
    
}

func timeString(timeLeft: TimeInterval) -> String {
    return TimeUtilities.shared.formatTimeLeft(timeLeft: timeLeft)
}

func timeString(timeLeft: Int) -> String {
    return TimeUtilities.shared.formatTimeLeft(timeLeft: timeLeft)
}
