//
//  TimeUtilities.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/7/20.
//

import Foundation

enum LocalizationBundleResolver {
    static func preferredLocalization(
        for locale: Locale,
        from availableLocalizations: [String]
    ) -> String? {
        Bundle.preferredLocalizations(
            from: availableLocalizations,
            forPreferences: [locale.identifier]
        ).first
    }

    static func bundle(
        for locale: Locale?,
        in baseBundle: Bundle = .main
    ) -> Bundle {
        guard let locale,
              let localization = preferredLocalization(
                  for: locale,
                  from: baseBundle.localizations
              ),
              let path = baseBundle.path(
                  forResource: localization,
                  ofType: "lproj"
              ),
              let localizedBundle = Bundle(path: path) else {
            return baseBundle
        }
        return localizedBundle
    }
}

class TimeUtilities {
    static let shared = TimeUtilities()
    lazy var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    func formatTimeLeft(
        timeLeft: Int,
        locale: Locale? = nil,
        baseBundle: Bundle = .main
    ) -> String {
        return formatTimeLeft(
            timeLeft: TimeInterval(timeLeft),
            locale: locale,
            baseBundle: baseBundle
        )
    }
    
    func formatTimeLeft(
        timeLeft: TimeInterval,
        locale: Locale? = nil,
        baseBundle: Bundle = .main
    ) -> String {
        let resolvedLocale = locale ?? .current
        let resolvedBundle = LocalizationBundleResolver.bundle(
            for: locale,
            in: baseBundle
        )
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
