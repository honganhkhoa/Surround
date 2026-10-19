//
//  GameLayoutUITestHarness.swift
//  Surround
//
//  Deterministically exercise adaptive arrangements without rebuilding the
//  game route. Actual device-pose changes remain a Simulator smoke check.
//

import SwiftUI

enum GameLayoutUITestContract {
    static let launchArgument = "--surround-game-layout-transitions"
    static let compact = "uitest.gameLayout.compact"
    static let regular = "uitest.gameLayout.regular"
    static let current = "uitest.gameLayout.current"
}

#if DEBUG && MAIN_APP
struct GameLayoutTransitionUITestModifier: ViewModifier {
    @State private var compact = false

    private var isEnabled: Bool {
        SurroundUITestContract.isEnabled
            && ProcessInfo.processInfo.arguments.contains(
                GameLayoutUITestContract.launchArgument
            )
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .environment(
                    \.horizontalSizeClass,
                    compact ? .compact : .regular
                )
                .frame(maxWidth: compact ? 430 : .infinity)
                .frame(maxWidth: .infinity)
                // An inset around NavigationStack covers its native toolbar
                // on iPad. Keep the fixture controls in the unused leading
                // title area so Analyze and Chat receive their actual taps.
                .overlay(alignment: .topLeading) {
                    HStack {
                        Button("Compact layout") { compact = true }
                            .accessibilityIdentifier(
                                GameLayoutUITestContract.compact
                            )
                        Text(compact ? "compact" : "regular")
                            .accessibilityIdentifier(
                                GameLayoutUITestContract.current
                            )
                        Button("Regular layout") { compact = false }
                            .accessibilityIdentifier(
                                GameLayoutUITestContract.regular
                            )
                    }
                    .buttonStyle(.bordered)
                    .padding(6)
                    .background(.bar, in: Capsule())
                    .padding(.leading, 12)
                    .padding(.top, 4)
                }
        } else {
            content
        }
    }
}
#endif
