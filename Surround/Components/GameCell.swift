//
//  GameCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI

struct PlayerInfoLine: View {
    @ObservedObject var game: Game
    var color: StoneColor
    var displayMode: GameCell.CellDisplayMode
    var conditionalMovesContext: ConditionalMovesPresentationContext?
    var navigationAccessibilityIdentifier: String
    @EnvironmentObject var ogs: OGSService

    var isUserLine: Bool {
        guard let user = ogs.user else {
            return false
        }
        if game.rengo {
            return game.gameData?.rengoTeams?[color].firstIndex(where: { $0.id == user.id }) != nil
        } else {
            return color == game.userStoneColor
        }
    }
    
    var body: some View {
        if displayMode == .full {
            HStack {
                Stone(color: color, shadowRadius: 1).frame(width: 15, height: 15)
                HStack(alignment: .firstTextBaseline) {
                    Group {
                        if isUserLine {
                            userLabel
                        } else {
                            if let player = game.currentPlayer(with: color) {
                                opponentLabel(player)
                            }
                        }
                    }
                    if game.rengo, let rengoTeam = game.gameData?.rengoTeams?[color], rengoTeam.count > 1 {
                        HStack(spacing: 2) {
                            Text(verbatim: "+ \(rengoTeam.count - 1)×")
                            Image(systemName: "person.fill")
                        }
                        .font(.subheadline)
                    }
                    Spacer()
                    InlineTimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color, pauseControl: game.pauseControl)
                }
            }
        } else {
            HStack(alignment: .top) {
                Stone(color: color, shadowRadius: 1).frame(width: 15, height: 15)
                    .offset(y: 2)
                VStack(alignment: .leading) {
                    HStack {
                        Group {
                            if isUserLine {
                                userLabel
                            } else {
                                if let player = game.currentPlayer(with: color) {
                                    opponentLabel(player)
                                }
                            }
                        }
                        if game.rengo, let rengoTeam = game.gameData?.rengoTeams?[color], rengoTeam.count > 1 {
                            HStack(spacing: 2) {
                                Text(verbatim: "+ \(rengoTeam.count - 1)×")
                                Image(systemName: "person.fill")
                            }
                            .font(.subheadline)
                        }
                    }
                    InlineTimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color, pauseControl: game.pauseControl)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var userLabel: some View {
        Text("You")
            .font(Font.subheadline.bold())
            .padding(.horizontal, 3)
            .background(Color(UIColor.systemTeal).cornerRadius(5))
            .offset(x: -3)
        if let conditionalMovesContext,
           !game.conditionalMoveBranches.isEmpty {
            ConditionalMovesButton(
                game: game,
                context: conditionalMovesContext
            )
        }
    }

    @ViewBuilder
    private func opponentLabel(_ player: OGSUser) -> some View {
        let label = Text(verbatim: player.usernameAndRank)
            .font(.subheadline)
            .bold()
            .lineLimit(1)
            .foregroundColor(player.uiColor)
        if navigationAccessibilityIdentifier.isEmpty {
            label
        } else {
            label.accessibilityIdentifier(navigationAccessibilityIdentifier)
        }
    }
}

struct GameCell: View {
    @ObservedObject var game: Game
    var displayMode: CellDisplayMode = .full
    var opensGame: (() -> Void)?
    var showsConditionalMoves = false
    var navigationAccessibilityIdentifier = ""
    @EnvironmentObject var ogs: OGSService

    enum CellDisplayMode: String, Codable {
        case full
        case compact
    }
    
    var gameOutCome: some View {
        VStack {
            if game.gameData?.winner == game.gameData?.players.black.id {
                Text("B+", comment: "Black wins (short status on large thumbnails)").font(.title).bold()
            } else {
                Text("W+", comment: "White wins (short status on large thumbnails)").font(.title).bold()
            }
            Text(game.gameData?.outcome ?? "")
        }
        .padding()
        .background(Color.gray.opacity(0.9))
        .cornerRadius(5)
    }

    private var conditionalMovesContext: ConditionalMovesPresentationContext? {
        guard showsConditionalMoves, let gameID = game.ogsID else {
            return nil
        }
        return .home(gameID: gameID)
    }

    private var playerInfoNavigationAccessibilityIdentifier: String {
        guard !navigationAccessibilityIdentifier.isEmpty else {
            return ""
        }
        return "\(navigationAccessibilityIdentifier).playerInfo"
    }

    private var navigationAccessibilityLabel: Text {
        if let gameName = game.gameName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !gameName.isEmpty {
            return Text(verbatim: gameName)
        }
        if let user = ogs.user,
           let userColor = game.stoneColor(of: user),
           let opponent = game.currentPlayer(
            with: userColor.opponentColor()
           ) {
            let versus = String(localized: "vs.")
            return Text(verbatim: "\(versus) \(opponent.usernameAndRank)")
        }
        if let blackPlayer = game.blackPlayer,
           let whitePlayer = game.whitePlayer {
            let versus = String(localized: "vs.")
            return Text(
                verbatim: "\(blackPlayer.usernameAndRank) \(versus) "
                    + whitePlayer.usernameAndRank
            )
        }
        return Text("Game")
    }

    private var boardContent: some View {
        ZStack {
            BoardView(boardPosition: game.currentPosition)
            if game.gameData?.outcome != nil {
                gameOutCome
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var boardNavigation: some View {
        if let opensGame {
            Button(action: opensGame) {
                ZStack {
                    boardContent
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier(navigationAccessibilityIdentifier)
            .accessibilityLabel(navigationAccessibilityLabel)
        } else {
            boardContent
        }
    }

    @ViewBuilder
    private var cellContent: some View {
        if displayMode == .full {
            VStack {
                PlayerInfoLine(
                    game: game,
                    color: .black,
                    displayMode: displayMode,
                    conditionalMovesContext: conditionalMovesContext,
                    navigationAccessibilityIdentifier:
                        playerInfoNavigationAccessibilityIdentifier
                )
                boardNavigation
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: .infinity)
                PlayerInfoLine(
                    game: game,
                    color: .white,
                    displayMode: displayMode,
                    conditionalMovesContext: conditionalMovesContext,
                    navigationAccessibilityIdentifier:
                        playerInfoNavigationAccessibilityIdentifier
                )
            }
            .contentShape(Rectangle())
        } else {
            GeometryReader { geometry in
                HStack {
                    boardNavigation
                        .frame(width: geometry.size.height, height: geometry.size.height, alignment: .center)
                    VStack {
                        PlayerInfoLine(
                            game: game,
                            color: .black,
                            displayMode: displayMode,
                            conditionalMovesContext: conditionalMovesContext,
                            navigationAccessibilityIdentifier:
                                playerInfoNavigationAccessibilityIdentifier
                        )
                        PlayerInfoLine(
                            game: game,
                            color: .white,
                            displayMode: displayMode,
                            conditionalMovesContext: conditionalMovesContext,
                            navigationAccessibilityIdentifier:
                                playerInfoNavigationAccessibilityIdentifier
                        )
                    }
                }
            }
            .frame(minHeight: 120)
            .contentShape(Rectangle())
        }
    }

    var body: some View {
        if let opensGame {
            cellContent
                .onTapGesture(perform: opensGame)
        } else {
            cellContent
        }
    }
}

#if DEBUG
#Preview("Rengo 3 vs. 1", traits: .fixedLayout(width: 375, height: 500)) {
    let game = TestData.Rengo3v1
    List([game]) { game in
        GameCell(game: game)
    }
    .listStyle(GroupedListStyle())
    .environmentObject(
        OGSService.previewInstance(user: OGSUser(username: "honganhkhoa", id: 1526))
    )
}

#Preview("Rengo 2 vs. 2 — Compact", traits: .fixedLayout(width: 375, height: 500)) {
    let game = TestData.Rengo2v2
    List([game]) { game in
        GameCell(game: game, displayMode: .compact)
    }
    .listStyle(GroupedListStyle())
    .environmentObject(
        OGSService.previewInstance(user: OGSUser(username: "honganhkhoa", id: 1526))
    )
}

#Preview("Handicap resignation — Dark", traits: .fixedLayout(width: 375, height: 500)) {
    let game = TestData.Resigned19x19HandicappedWithInitialState
    List([game]) { game in
        GameCell(game: game)
    }
    .listStyle(GroupedListStyle())
    .colorScheme(.dark)
    .environmentObject(
        OGSService.previewInstance(user: OGSUser(username: "hhs214", id: 749506))
    )
}

#Preview("Conditional moves — Full", traits: .fixedLayout(width: 390, height: 560)) {
    let game = Game.conditionalMovesPreviewFixture()
    GameCell(
        game: game,
        showsConditionalMoves: true
    )
    .padding()
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(username: "kata-bot", id: 592684),
            activeGames: [game]
        )
    )
}

#Preview("Conditional moves — Compact", traits: .fixedLayout(width: 390, height: 150)) {
    let game = Game.conditionalMovesPreviewFixture()
    GameCell(
        game: game,
        displayMode: .compact,
        showsConditionalMoves: true
    )
    .padding()
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(username: "kata-bot", id: 592684),
            activeGames: [game]
        )
    )
}
#endif
