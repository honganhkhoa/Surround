//
//  SceneCoverPolicy.swift
//  Surround
//
//  The scene cover's window choices, free of UIKit so SurroundTests can
//  check them without a scene. Ships with the moderator superchat cover.
//

import Foundation

/// How a scene's cover behaves. The defaults are the adopted behaviour
/// (10 Nov 2026); the alternatives are fallbacks for checks still open
/// (Full Keyboard Access, Switch Control, presentations).
struct SceneCoverOptions: Equatable {
    enum ModalTarget: Equatable {
        /// `accessibilityViewIsModal` on the cover window, so VoiceOver
        /// should skip the scene's other windows.
        case window
        /// Only on the cover's root view.
        case rootView
    }

    /// Resign the first responder of every visible window below the cover
    /// before it takes key, so the keyboard stops typing underneath.
    var endsEditingUnderneath = true
    var modalTarget = ModalTarget.window
    /// While raised, also hide the windows below from accessibility and turn
    /// off their user interaction.
    var locksWindowsBelow = false
    /// For a window that opens covered: raise while the anchor attaches,
    /// instead of one run-loop turn later. Only a scene's first request:
    /// later raises wait a main turn.
    var raisesWhileAttaching = true
}

enum SceneCoverPolicy {
    struct Window<ID: Hashable>: Equatable {
        var id: ID
        var level: CGFloat
        var isHidden: Bool
    }

    /// The visible windows below the cover, in scene order. The software
    /// keyboard's windows sit above the cover and are never included.
    static func windowsBelow<ID>(
        _ cover: ID, in windows: [Window<ID>], coverLevel: CGFloat
    ) -> [ID] {
        windows.filter { $0.id != cover && !$0.isHidden && $0.level < coverLevel }.map(\.id)
    }

    /// Who takes key back when the cover lowers: the window that was key
    /// before it rose, else the scene's content window, else the lowest
    /// visible window below the cover.
    static func keyWindowAfterLowering<ID>(
        _ windows: [Window<ID>], cover: ID, coverLevel: CGFloat,
        previousKey: ID?, content: ID?
    ) -> ID? {
        let candidates = windows.filter { $0.id != cover && !$0.isHidden && $0.level < coverLevel }
        if let previousKey, candidates.contains(where: { $0.id == previousKey }) { return previousKey }
        if let content, candidates.contains(where: { $0.id == content }) { return content }
        return candidates.min { $0.level < $1.level }?.id
    }

    /// A window that opens covered raises while its anchor attaches, so no
    /// frame of the screen underneath shows. Only the scene's first request:
    /// a later re-attach can come inside a layout pass (forum-224).
    static func raisesWhileAttaching(
        attaching: Bool, isFirstRequest: Bool, options: SceneCoverOptions,
        wantsRaised: Bool, isRaised: Bool
    ) -> Bool {
        attaching && isFirstRequest && options.raisesWhileAttaching && wantsRaised && !isRaised
    }
}
