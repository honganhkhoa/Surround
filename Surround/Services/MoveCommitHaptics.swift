//
//  MoveCommitHaptics.swift
//  Surround
//

import UIKit

/// Committing a stone is one event: its click and a single impact, played
/// together. A refusal from OGS after that optimistic impact is an error.
/// Boards prepare the impact ahead, at touch-down, at a pending stone and on
/// Submit's press-down, so it lands with the click. Tests inject a recorder.
protocol MoveCommitHaptics: AnyObject {
    func prepare()
    func playCommit()
    func playRefusal()
}

/// Prepared UIKit generators, following Settings › Haptics. SwiftUI's
/// `sensoryFeedback` has no prepare step and plays from a view's update,
/// while a commit happens in GameControlState, so these are called directly.
/// Mac Catalyst has no haptics, so it compiles them out.
final class SystemMoveCommitHaptics: MoveCommitHaptics {
    static let shared = SystemMoveCommitHaptics()

    /// One impact for every theme, until device trials suggest tuning it.
    static let intensity: CGFloat = 0.75

    #if !targetEnvironment(macCatalyst)
    private lazy var impact = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var notification = UINotificationFeedbackGenerator()
    #endif

    private init() {}

    private var isEnabled: Bool {
        userDefaults[.hapticsFeedback] != false
    }

    func prepare() {
        #if !targetEnvironment(macCatalyst)
        guard isEnabled else { return }
        impact.prepare()
        #endif
    }

    func playCommit() {
        #if !targetEnvironment(macCatalyst)
        guard isEnabled else { return }
        impact.impactOccurred(intensity: Self.intensity)
        #endif
    }

    func playRefusal() {
        #if !targetEnvironment(macCatalyst)
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
        #endif
    }
}

/// A board touch's part in the commit's haptics. A pending stone is only a
/// preview, not a success: touching down and releasing on a legal point play
/// nothing themselves and only ready the impact that its commit plays.
/// Moving between points still ticks, through the board's own generator.
struct BoardTouchHaptics {
    var haptics: MoveCommitHaptics = SystemMoveCommitHaptics.shared

    func touchBegan() {
        haptics.prepare()
    }

    func touchEnded(placingPendingStone: Bool) {
        if placingPendingStone {
            haptics.prepare()
        }
    }
}
