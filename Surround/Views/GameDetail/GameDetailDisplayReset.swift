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
/// session. So do switches the in-game control makes from one live game to
/// another, in Zen too. A switch across the realtime/correspondence boundary
/// starts again from the full game view, whether the in-game control makes it
/// in place (its chip, its Zen circle or a live row in its popover, from a
/// correspondence game) or it comes from an external jump, such as the
/// Activity bar's live game or a resolved route.
///
/// Keeping this separate from the view makes the rule directly testable in
/// both directions.
enum GameDetailDisplayReset {
    /// Each game counts by `Game.resolvedSpeed`, so a game whose payload has
    /// no speed tag counts by its clock, as the service sorts it.
    static func restoresDisplayDefaults(from oldGame: Game, to newGame: Game) -> Bool {
        restoresDisplayDefaults(from: oldGame.resolvedSpeed, to: newGame.resolvedSpeed)
    }

    static func restoresDisplayDefaults(
        from oldSpeed: TimeControlSpeed?,
        to newSpeed: TimeControlSpeed?
    ) -> Bool {
        newSpeed?.isRealtime != oldSpeed?.isRealtime
    }
}
