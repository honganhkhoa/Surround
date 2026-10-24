//
//  HomeRules.swift
//  Surround
//
//  Home's layout and wording rules that need no view (canvas "Home Redesign",
//  Direction C), kept apart so unit tests can check them.
//

import CoreGraphics
import Foundation

/// How Home lays its sections out in the width it has beside the sidebar.
enum HomeLayout {
    /// The narrowest Compact row that still fits its time-control line.
    static let compactCellWidth: CGFloat = 312
    /// Large boards stay at least this big, so a 19×19 stone reaches the
    /// 14 pt where boards draw detailed stones and a theme's art.
    static let largeBoardSize: CGFloat = 266
    static let largeTilePadding: CGFloat = 10
    static var largeTileWidth: CGFloat { largeBoardSize + 2 * largeTilePadding }
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let bandMargin: CGFloat = 24
    static let listMargin: CGFloat = 16

    /// Two or three columns of section bands once two Compact cells fit;
    /// otherwise one grouped list, as on iPhone.
    static func compactColumns(for width: CGFloat) -> Int {
        let fitting = Int((width - 2 * bandMargin + columnSpacing) / (compactCellWidth + columnSpacing))
        return fitting >= 2 ? min(3, fitting) : 1
    }

    /// Large tiles never shrink below the detailed-board size: more width
    /// adds columns instead.
    static func largeColumns(for width: CGFloat, margin: CGFloat) -> Int {
        max(1, Int((width - 2 * margin + columnSpacing) / (largeTileWidth + columnSpacing)))
    }
}

extension TimeControlSystem {
    /// What the time control gives each move, for Home's line under a name.
    /// The board already shows its size and the clocks what is left.
    var homeAddedTime: String? {
        switch self {
        case .Fischer(_, let increment, _):
            let duration = durationString(seconds: increment, longFormat: true)
            return String(localized: "+ \(duration) per move")
        case .ByoYomi(_, let periods, let periodTime):
            let duration = durationString(seconds: periodTime, longFormat: true)
            return String(localized: "+ \(periods)× \(duration)", comment: "Homeview - byo-yomi periods and their length, e.g. + 5× 30 seconds")
        case .Canadian(_, let periodTime, let stones):
            let duration = durationString(seconds: periodTime, longFormat: true)
            return String(localized: "+ \(duration) for \(stones) stones")
        case .Simple(let perMove):
            let duration = durationString(seconds: perMove, longFormat: true)
            return String(localized: "\(duration) per move", comment: "Homeview - simple time control, e.g. 1 day per move")
        case .Absolute:
            return String(localized: "No time added", comment: "Homeview - absolute time control: the clock never gains time")
        case .None:
            return String(localized: "No time limits", comment: "TimeControl - short description for no system")
        case .Unknown:
            return nil
        }
    }
}
