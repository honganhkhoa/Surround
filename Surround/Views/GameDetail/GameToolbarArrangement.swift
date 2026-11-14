//  GameToolbarArrangement.swift — which of its four toolbar arrangements Game
//  Detail uses, and where each puts the Active games slot. Pure, so
//  SurroundTests can check both.

import Foundation

enum GameToolbarArrangement: Equatable {
    case vertical          // Duo's vertical toolbar
    case bottomBar         // compact portrait: Active games, a spacer and the modes at the bottom
    case compactLandscape  // Active games, the modes and the utilities at the top
    case wide              // wide windows and the Mac: modes, Active games, utilities

    /// A narrow iPad window arranges its controls like a portrait iPhone:
    /// modes and Active Games in the bottom bar, leaving the top bar room so
    /// nothing moves into its More menu. The Mac keeps them at the top.
    static func placesActiveGamesAtTop(isVerticalToolbar: Bool, compact: Bool,
                                       compactLandscape: Bool, isCatalyst: Bool) -> Bool {
        isCatalyst || (!isVerticalToolbar && (!compact || compactLandscape))
    }

    init(isVerticalToolbar: Bool, compact: Bool, compactLandscape: Bool, isCatalyst: Bool) {
        let placesActiveGamesAtTop = Self.placesActiveGamesAtTop(
            isVerticalToolbar: isVerticalToolbar, compact: compact,
            compactLandscape: compactLandscape, isCatalyst: isCatalyst)
        if isVerticalToolbar {
            self = .vertical
        } else if compact && !compactLandscape && !placesActiveGamesAtTop {
            self = .bottomBar
        } else if compactLandscape {
            self = .compactLandscape
        } else {
            self = .wide
        }
    }

    /// Where this arrangement puts the slot. `navigationBarHidden` is Duo's
    /// wide poses (GameDetailView.hidesNavigationBarInDuoWide); Closed
    /// (`compact`) takes precedence, as its branch did.
    func activeGamesPlacement(compact: Bool, navigationBarHidden: Bool) -> GameActiveGamesPlacement {
        switch self {
        case .vertical: return !compact && navigationBarHidden ? .railSeparated : .rail
        case .bottomBar: return .bottomBar
        case .compactLandscape: return .topBarBeforeModes
        case .wide: return .topBarAfterModes
        }
    }
}

/// Where an arrangement puts Game Detail's Active games slot.
enum GameActiveGamesPlacement: Equatable {
    case rail               // Duo's vertical bar: a group of its own below the controls
    /// Duo's wide poses: `rail` after a flexible spacer that keeps the slot in
    /// its own circle. The spacer is the slot's, emitted even when it is hidden.
    case railSeparated
    case bottomBar          // the bottom bar's leading item, before the spacer and the modes
    case topBarBeforeModes  // the first of the top bar's trailing items
    case topBarAfterModes   // the top bar, between the modes and the utilities

    /// The in-game control's drawn forms (canvas AGameForms).
    enum Form: Equatable { case bottomBar, topBar, rail }

    var form: Form {
        switch self {
        case .rail, .railSeparated: return .rail
        case .bottomBar: return .bottomBar
        case .topBarBeforeModes, .topBarAfterModes: return .topBar
        }
    }
}
