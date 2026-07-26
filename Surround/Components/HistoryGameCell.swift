//
//  HistoryGameCell.swift
//  Surround
//
//  A row for finished games in the history lists. Laid out like GameCell's
//  compact mode (square board on the leading edge), but the board is shown
//  without the result overlay — the outcome is spelled out beside it instead,
//  together with the opponent and the handicap.
//

import SwiftUI
import Combine

struct HistoryGameCell: View {
    @ObservedObject var game: Game
    var action: () -> Void
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var settings = userDefaults

    @State private var loadCancellable: AnyCancellable?

    /// The colour the opponent played. `nil` while the game detail is still
    /// loading, or for a game the user did not take part in.
    var opponentStoneColor: StoneColor? {
        return game.userStoneColor?.opponentColor()
    }

    var opponent: OGSUser? {
        guard let opponentStoneColor else {
            return nil
        }
        return game.currentPlayer(with: opponentStoneColor)
    }

    var handicapStones: Int {
        return game.gameData?.handicap ?? 0
    }

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                HStack(alignment: .top) {
                    BoardView(boardPosition: game.currentPosition)
                        .frame(width: geometry.size.height, height: geometry.size.height, alignment: .center)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Stone(color: opponentStoneColor, shadowRadius: 1)
                                .frame(width: 15, height: 15)
                            if let opponent {
                                Text(verbatim: opponent.usernameAndRank)
                                    .font(.subheadline).bold()
                                    .lineLimit(1)
                                    .foregroundColor(opponent.uiColor)
                            }
                        }
                        if game.gameData?.outcome != nil {
                            Text(game.status)
                                .font(.subheadline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if handicapStones > 0 {
                            Text("\(handicapStones) handicap stones ", comment: "HistoryGameCell - vary for plural")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            loadDetailIfNeeded()
        }
    }

    private func loadDetailIfNeeded() {
        guard game.gameData == nil, let gameID = game.ogsID, loadCancellable == nil else {
            return
        }
        loadCancellable = ogs.loadFinishedGameData(gameID: gameID)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in
                    loadCancellable = nil
                },
                receiveValue: { detail in
                    // The players we already have came from the history listing
                    // fetched just now; the detail payload may be a cache entry
                    // from days ago, and assigning ogsRawData re-decodes players
                    // out of it. Keep the fresher ranks — assigning gameData
                    // afterwards merges onto them rather than replacing them.
                    let listedBlackPlayer = game.blackPlayer
                    let listedWhitePlayer = game.whitePlayer
                    // Setting ogsRawData too means opening this game's detail
                    // view reuses what we already loaded instead of firing a
                    // second REST request that bypasses the cache.
                    game.ogsRawData = detail.rawData
                    if let listedBlackPlayer {
                        game.blackPlayer = listedBlackPlayer
                    }
                    if let listedWhitePlayer {
                        game.whitePlayer = listedWhitePlayer
                    }
                    // didSet replays the moves and computes the final position.
                    game.gameData = detail.ogsGame
                }
            )
    }
}

#Preview(traits: .fixedLayout(width: 402, height: 300)) {
    List([TestData.Resigned19x19HandicappedWithInitialState]) { game in
        HistoryGameCell(game: game) {}
    }
    .environmentObject(OGSService.previewInstance(user: OGSUser(username: "hhs214", id: 749506)))
}

#Preview(traits: .fixedLayout(width: 402, height: 300)) {
    List([TestData.Scored15x17]) { game in
        HistoryGameCell(game: game) {}
    }
    .environmentObject(OGSService.previewInstance(user: OGSUser(username: "honganhkhoa", id: 1526)))
}
