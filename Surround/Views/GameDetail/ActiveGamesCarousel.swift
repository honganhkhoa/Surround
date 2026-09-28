//
//  ActiveGamesCarousel.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/9/20.
//

import SwiftUI
import Combine

struct ActiveGamesCarousel: View {
    var currentGame: Binding<Game?>
    @Namespace var selectingGame
    var activeGames: [Game]
    @State var scrollTarget: GameID?
    @State var discardNextScrollTarget = false
    @State var renderedCurrentGame: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()
    @State var renderedCurrentGameCollected: AnyPublisher<[Bool], Never> = PassthroughSubject<[Bool], Never>().eraseToAnyPublisher()
    var cellSize: CGFloat = 120.0
    var selectionRingPadding: CGFloat = 5.0
    var padding: CGFloat = 5.0
    var onSelectGame: (() -> Void)?

    func gameCell(game: Game) -> some View {
        ActiveGamePopoverEntry(
            game: game,
            isSelected: game.ID == currentGame.wrappedValue?.ID,
            cellSize: cellSize,
            selectionRingPadding: selectionRingPadding,
            selectionNamespace: selectingGame
        ) {
            withAnimation {
                discardNextScrollTarget = true
                currentGame.wrappedValue = game
                scrollTarget = currentGame.wrappedValue?.ID
            }
            onSelectGame?()
        }
        .id(game.ID)
        .onChange(of: currentGame.wrappedValue) { _, _ in
            self.renderedCurrentGame.send(game == currentGame.wrappedValue)
        }
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                LazyHStack(alignment: .bottom, spacing: 0) {
                    ForEach(activeGames) { game in
                        gameCell(game: game)
                    }
                }
                .padding(.horizontal, 5)
                .onChange(of: scrollTarget) { _, target in
                    if let target = target {
                        if discardNextScrollTarget {
                            discardNextScrollTarget = false
                        } else {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollView.scrollTo(target)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: cellSize + selectionRingPadding * 2 + padding * 2)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameActiveGamesCarousel)
        .onReceive(renderedCurrentGameCollected) { rendered in
            if rendered.allSatisfy({ !$0 }) {
                if scrollTarget != currentGame.wrappedValue?.ID {
                    scrollTarget = currentGame.wrappedValue?.ID
                }
            }
        }
        .onAppear {
            scrollTarget = currentGame.wrappedValue?.ID
            self.renderedCurrentGameCollected = self.renderedCurrentGame.collect(.byTime(DispatchQueue.main, 1.0)).eraseToAnyPublisher()
        }
    }
}

private struct ActiveGamePopoverEntry: View {
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var preferences = userDefaults
    @ObservedObject var game: Game
    let isSelected: Bool
    let cellSize: CGFloat
    let selectionRingPadding: CGFloat
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void

    private func playerLabel(_ player: OGSUser) -> String {
        player.usernameAndRank(hidesRank: preferences[.hidesRank] ?? false)
    }

    private var matchupLabel: String? {
        let versus = String(localized: "vs.")
        if let user = ogs.user, let color = game.stoneColor(of: user) {
            let opponentColor = color.opponentColor()
            let opponents = (game.rengo ? game.orderedRengoTeam[opponentColor] : nil)
                ?? game.currentPlayer(with: opponentColor).map { [$0] }
                ?? []
            if !opponents.isEmpty {
                return "\(versus) " + opponents.map(playerLabel).joined(separator: ", ")
            }
        }
        if let black = game.blackPlayer, let white = game.whitePlayer {
            return "\(playerLabel(black)) \(versus) \(playerLabel(white))"
        }
        return nil
    }

    private var accessibilityLabel: String {
        let gameName = game.gameName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts = [gameName, matchupLabel ?? ""].filter { !$0.isEmpty }
        if parts.isEmpty { parts.append(String(localized: "Game")) }
        let status = game.status
        if !status.isEmpty { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .trailing) {
                ZStack(alignment: .center) {
                    if game.gamePhase == .stoneRemoval {
                        Color(UIColor.systemOrange).cornerRadius(3)
                    } else if game.clock?.currentPlayerId == ogs.user?.id {
                        Color(UIColor.systemTeal).cornerRadius(3)
                    } else {
                        if colorScheme == .dark {
                            Color(UIColor.systemGray5)
                        } else {
                            Color(UIColor.systemBackground)
                        }
                    }
                    BoardView(boardPosition: game.currentPosition)
                        .frame(width: cellSize, height: cellSize)
                        .padding(.horizontal, 5)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .padding(1)
                            .foregroundColor(Color(UIColor.label))
                            .matchedGeometryEffect(id: "selectionIndicator", in: selectionNamespace)
                    }
                }
                .frame(width: cellSize + selectionRingPadding * 2, height: cellSize + selectionRingPadding * 2)
            }
            .padding(.horizontal, selectionRingPadding / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameActiveGamesEntry(game))
        .contentShape(Rectangle())
        .hoverEffect(.lift)
    }
}

#if DEBUG
private struct ActiveGamesCarouselPreviewState {
    let games: [Game]
    var currentGame: Game?

    init() {
        let games = [
            TestData.Ongoing19x19wBot1,
            TestData.Ongoing19x19wBot2,
            TestData.Ongoing19x19wBot3,
        ]
        self.games = games
        currentGame = games[0]
    }
}

#Preview("Active games carousel", traits: .fixedLayout(width: 350, height: 150)) {
    @Previewable @State var preview = ActiveGamesCarouselPreviewState()
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "kata-bot", id: 592684),
        activeGames: preview.games
    )

    ActiveGamesCarousel(
        currentGame: $preview.currentGame,
        activeGames: preview.games
    )
    .environmentObject(ogs)
}
#endif
