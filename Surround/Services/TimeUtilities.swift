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
        var secondsLeft = Int(timeLeft)
        let daysLeft = secondsLeft / 86400
        secondsLeft -= daysLeft * 86400
        let hoursLeft = secondsLeft / 3600
        secondsLeft -= hoursLeft * 3600
        let minutesLeft = secondsLeft / 60
        secondsLeft -= minutesLeft * 60
        
        if daysLeft > 1 {
            var result = "\(daysLeft) days"
            if hoursLeft > 0 {
                result += " \(hoursLeft)h"
            }
            if hoursLeft > 1 {
                result += "s"
            }
            return result
        } else {
            if daysLeft == 1 {
                return "\(hoursLeft + 24)h"
            } else {
                if hoursLeft >= 1 {
                    return String(format: "%dh %02dm", hoursLeft, minutesLeft)
                } else {
                    return String(format: "%02d:%02d", minutesLeft, secondsLeft)
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
