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

    private func localizationBundle(for locale: Locale?) -> Bundle {
        let languageCode: String?
        if #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, tvOS 16.0, watchOS 9.0, *) {
            languageCode = locale?.language.languageCode?.identifier
        } else {
            languageCode = locale?.languageCode
        }

        guard let languageCode,
              let path = Bundle.main.path(
                  forResource: languageCode,
                  ofType: "lproj"
              ),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
    
    func formatTimeLeft(
        timeLeft: Int,
        locale: Locale? = nil
    ) -> String {
        return formatTimeLeft(
            timeLeft: TimeInterval(timeLeft),
            locale: locale
        )
    }
    
    func formatTimeLeft(
        timeLeft: TimeInterval,
        locale: Locale? = nil
    ) -> String {
        let resolvedLocale = locale ?? .current
        let resolvedBundle = localizationBundle(for: locale)
        var secondsLeft = max(Int(timeLeft), 0)
        let daysLeft = secondsLeft / 86400
        secondsLeft -= daysLeft * 86400
        let hoursLeft = secondsLeft / 3600
        secondsLeft -= hoursLeft * 3600
        let minutesLeft = secondsLeft / 60
        secondsLeft -= minutesLeft * 60
        
        if daysLeft > 1 {
            let daysString = String(
                localized: "\(daysLeft) days left",
                bundle: resolvedBundle,
                locale: resolvedLocale,
                comment: "Time left - more than 2 days left, days part"
            )
            let hoursString = String(
                localized: "\(hoursLeft)h left",
                bundle: resolvedBundle,
                locale: resolvedLocale,
                comment: "Time left - more than 2 days left, hours part"
            )
            if hoursLeft > 0 {
                return String(
                    localized: "\(daysString) \(hoursString)",
                    bundle: resolvedBundle,
                    locale: resolvedLocale,
                    comment: "Time left on timer - more than 2 days [days - hours]"
                )
            } else {
                return daysString
            }
        } else {
            if daysLeft == 1 {
                return String(
                    localized: "\(hoursLeft + 24)h left",
                    bundle: resolvedBundle,
                    locale: resolvedLocale,
                    comment: "Time left - 1 day to 2 days."
                )
            } else {
                if hoursLeft >= 1 {
                    return String(
                        localized: "\(hoursLeft)h \(minutesLeft, specifier: "%02d")m",
                        bundle: resolvedBundle,
                        locale: resolvedLocale,
                        comment: "Time left - 1 hour to 1 day."
                    )
                } else {
                    return String(
                        localized: "\(minutesLeft, specifier: "%02d"):\(secondsLeft, specifier: "%02d")",
                        bundle: resolvedBundle,
                        locale: resolvedLocale,
                        comment: "Time left - less than 1 hour."
                    )
                }
            }
        }
    }
    
}

func timeString(
    timeLeft: TimeInterval,
    locale: Locale? = nil
) -> String {
    return TimeUtilities.shared.formatTimeLeft(
        timeLeft: timeLeft,
        locale: locale
    )
}

func timeString(
    timeLeft: Int,
    locale: Locale? = nil
) -> String {
    return TimeUtilities.shared.formatTimeLeft(
        timeLeft: timeLeft,
        locale: locale
    )
}
