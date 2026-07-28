//
//  HistoryGameCell.swift
//  Surround
//
//  A row for finished games in the history lists. Laid out like GameCell's
//  compact mode (square board on the leading edge), but the board is shown
//  without the result overlay — the outcome is spelled out beside it instead,
//  together with the opponent and any unusual game settings.
//

import SwiftUI

struct HistoryGameCell: View {
    private enum UserResult {
        case win
        case loss
        case draw
    }

    @ObservedObject var game: Game
    var action: () -> Void
    @EnvironmentObject var ogs: OGSService
    @ObservedObject var settings = userDefaults

    /// Derive the user's colour from the injected service instead of
    /// `game.userStoneColor`, whose weak service reference is intentionally
    /// absent from standalone preview fixtures.
    private var userStoneColor: StoneColor? {
        guard let user = ogs.user else {
            return nil
        }
        return game.stoneColor(of: user)
    }

    /// The colour the opponent played. `nil` for a game the user did not take
    /// part in (or while Rengo detail is still loading).
    var opponentStoneColor: StoneColor? {
        return userStoneColor?.opponentColor()
    }

    var opponent: OGSUser? {
        guard let opponentStoneColor else {
            return nil
        }
        return game.currentPlayer(with: opponentStoneColor)
    }

    private var opponentRengoTeamSize: Int? {
        guard game.rengo, let opponentStoneColor else {
            return nil
        }
        return game.orderedRengoTeam[opponentStoneColor]?.count
    }

    private var rengoTeamSizes: (black: Int, white: Int)? {
        guard game.rengo, let rengoTeams = game.gameData?.rengoTeams else {
            return nil
        }
        return (black: rengoTeams.black.count, white: rengoTeams.white.count)
    }

    var handicapStones: Int {
        return game.gameData?.handicap ?? 0
    }

    private var displayGameName: String? {
        guard let gameName = game.gameName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !gameName.isEmpty else {
            return nil
        }
        return gameName
    }

    /// OGS uses the fractional part of a ruleset's normal komi for handicap
    /// games: 0.5 for every supported ruleset except New Zealand, which uses 0.
    var nonstandardKomi: Double? {
        guard let gameData = game.gameData else {
            return nil
        }
        let standardKomi = gameData.handicap > 0
            ? gameData.rules.defaultKomi.truncatingRemainder(dividingBy: 1)
            : gameData.rules.defaultKomi
        return gameData.komi == standardKomi ? nil : gameData.komi
    }

    private var gameNameLineLimit: Int {
        let hasUnusualSettings = handicapStones > 0 || nonstandardKomi != nil
        return !game.rengo && !hasUnusualSettings ? 2 : 1
    }

    private var userResult: UserResult? {
        guard game.gameData?.outcome != nil, let winnerID = game.gameData?.winner else {
            return nil
        }
        guard winnerID != 0 else {
            return .draw
        }
        guard let userStoneColor,
              let winnerStoneColor = game.stoneColor(ofPlayerWithId: winnerID) else {
            return nil
        }
        return winnerStoneColor == userStoneColor ? .win : .loss
    }

    private var userResultText: String? {
        switch userResult {
        case .win:
            return String(localized: "Win", comment: "HistoryGameCell result for the logged-in player")
        case .loss:
            return String(localized: "Loss", comment: "HistoryGameCell result for the logged-in player")
        case .draw:
            return String(localized: "Draw", comment: "HistoryGameCell result for the logged-in player")
        case .none:
            return nil
        }
    }

    private var userResultColor: Color? {
        switch userResult {
        case .win:
            return .green
        case .loss:
            return .red
        case .draw:
            return .secondary
        case .none:
            return nil
        }
    }

    /// Returns the numeric margin only for OGS's "<number> point(s)" outcome
    /// format. Other outcomes can contain numbers that are not score margins.
    private var pointDifference: Double? {
        guard let outcome = game.gameData?.outcome else {
            return nil
        }
        let components = outcome.split(separator: " ")
        guard components.count >= 2,
              components[1].lowercased().hasPrefix("point"),
              let difference = Double(components[0]) else {
            return nil
        }
        return abs(difference)
    }

    private var outcomeText: String? {
        guard let outcome = game.gameData?.outcome else {
            return nil
        }
        if let pointDifference {
            switch userResult {
            case .win:
                return String(
                    localized: "+\(pointDifference, specifier: "%.1f") points",
                    comment: "HistoryGameCell point difference when the logged-in player won"
                )
            case .loss:
                return String(
                    localized: "-\(pointDifference, specifier: "%.1f") points",
                    comment: "HistoryGameCell point difference when the logged-in player lost"
                )
            case .draw, .none:
                return String(
                    localized: "\(pointDifference, specifier: "%.1f") points",
                    comment: "HistoryGameCell point difference without a win or loss perspective"
                )
            }
        }

        switch outcome.lowercased() {
        case "resignation", "resign", "r":
            return String(localized: "Resignation", comment: "HistoryGameCell game outcome")
        case "disconnection":
            return String(localized: "Disconnection", comment: "HistoryGameCell game outcome")
        case "stone removal timeout":
            return String(localized: "Stone Removal Timeout", comment: "HistoryGameCell game outcome")
        case "timeout":
            return String(localized: "Timeout", comment: "HistoryGameCell game outcome")
        case "cancellation":
            return String(localized: "Cancellation", comment: "HistoryGameCell game outcome")
        case "disqualification":
            return String(localized: "Disqualification", comment: "HistoryGameCell game outcome")
        case "moderator decision":
            return String(localized: "Moderator Decision", comment: "HistoryGameCell game outcome")
        case "abandonment":
            return String(localized: "Abandonment", comment: "HistoryGameCell game outcome")
        default:
            return outcome
        }
    }

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                HStack(alignment: .top) {
                    BoardView(boardPosition: game.currentPosition)
                        .saturation(0.8)
                        .opacity(0.85)
                        .frame(width: geometry.size.height, height: geometry.size.height, alignment: .center)
                    VStack(alignment: .leading, spacing: 4) {
                        if userResultText != nil || opponent != nil {
                            HStack(spacing: 6) {
                                if let userResultText, let userResultColor {
                                    Text(userResultText)
                                        .bold()
                                        .foregroundStyle(userResultColor)
                                }
                                if let opponentStoneColor, let opponent {
                                    Text("vs.", comment: "HistoryGameCell result versus opponent")
                                    Stone(color: opponentStoneColor, shadowRadius: 1)
                                        .frame(width: 15, height: 15)
                                    HStack(spacing: 2) {
                                        Text(verbatim: opponent.usernameAndRank)
                                            .bold()
                                            .lineLimit(1)
                                            .foregroundColor(opponent.uiColor)
                                        if let opponentRengoTeamSize, opponentRengoTeamSize > 1 {
                                            Text(verbatim: " + \(opponentRengoTeamSize - 1)×")
                                            Image(systemName: "person.fill")
                                        }
                                    }
                                }
                            }
                            .font(.subheadline)
                        }
                        if let outcomeText {
                            Text(outcomeText)
                                .font(.subheadline)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if handicapStones > 0 {
                            Text("\(handicapStones) handicap stones", comment: "HistoryGameCell - vary for plural")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let nonstandardKomi {
                            Text("Komi: \(nonstandardKomi, specifier: "%.1f")", comment: "HistoryGameCell nonstandard komi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let rengoTeamSizes {
                            Label {
                                Text(
                                    "Rengo (\(rengoTeamSizes.black) vs. \(rengoTeamSizes.white))",
                                    comment: "HistoryGameCell Rengo team sizes, black versus white"
                                )
                            } icon: {
                                Image(systemName: "person.2.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        if let displayGameName {
                            Text(verbatim: displayGameName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(gameNameLineLimit)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func historyGameCellPreview(game: Game, user: OGSUser) -> some View {
    List([game]) { game in
        HistoryGameCell(game: game) {}
    }
    .environmentObject(OGSService.previewInstance(user: user))
}

private func rengoHistoryGameCellPreview() -> some View {
    let game = TestData.Rengo3v1
    if var gameData = game.gameData {
        gameData.outcome = "Resignation"
        gameData.winner = gameData.players.black.id
        game.gameData = gameData
    }
    return historyGameCellPreview(
        game: game,
        user: OGSUser(username: "hakhoa4", id: 1769)
    )
}

#Preview("Win with handicap", traits: .fixedLayout(width: 402, height: 220)) {
    historyGameCellPreview(
        game: TestData.Resigned19x19HandicappedWithInitialState,
        user: OGSUser(username: "hhs214", id: 749506)
    )
}

#Preview("Win by points", traits: .fixedLayout(width: 402, height: 220)) {
    historyGameCellPreview(
        game: TestData.Scored19x19Korean,
        user: OGSUser(username: "HongAnhKhoa", id: 314459)
    )
}

#Preview("Loss by points", traits: .fixedLayout(width: 402, height: 220)) {
    historyGameCellPreview(
        game: TestData.Scored15x17,
        user: OGSUser(username: "Kevin052601", id: 435826)
    )
}

#Preview("Nonstandard komi", traits: .fixedLayout(width: 402, height: 220)) {
    historyGameCellPreview(
        game: TestData.Resigned9x9Japanese,
        user: OGSUser(username: "Youngparist", id: 298971)
    )
}

#Preview("Rengo 3 vs. 1", traits: .fixedLayout(width: 402, height: 220)) {
    rengoHistoryGameCellPreview()
}
