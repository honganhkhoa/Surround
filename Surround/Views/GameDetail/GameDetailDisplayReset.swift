//
//  GameDetailDisplayReset.swift
//  Surround
//

import Foundation

/// Decides whether `GameDetailView` restores its default display choices when
/// the game it shows is replaced.
///
/// The active-games carousel and *Next game* only ever move between games of
/// the same speed class, and the choices made there — Zen mode, Analyze, the
/// compact display mode, the hidden Chat board — belong to that browsing
/// session. Crossing the realtime/correspondence boundary cannot happen that
/// way: it means an external jump, either the live-game banner or a resolved
/// route, so the destination starts again from the full game view.
///
/// Keeping this separate from the view makes the rule directly testable in
/// both directions.
enum GameDetailDisplayReset {
    static func restoresDisplayDefaults(
        from oldSpeed: TimeControlSpeed?,
        to newSpeed: TimeControlSpeed?
    ) -> Bool {
        newSpeed?.isRealtime != oldSpeed?.isRealtime
    }
}
