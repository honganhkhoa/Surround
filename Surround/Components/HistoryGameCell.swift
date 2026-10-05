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
        case annulled
    }

    @ObservedObject var game: Game
    var perspectivePlayerID: Int? = nil
    var retryPreview: (() -> Void)? = nil
    var action: () -> Void
    @EnvironmentObject var ogs: OGSService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @ObservedObject var settings = userDefaults

    /// Profile history uses its owner's perspective; Home defaults to the
    /// signed-in player. Neither depends on the game's weak service reference.
    private var userStoneColor: StoneColor? {
        guard let playerID = perspectivePlayerID ?? ogs.user?.id else {
            return nil
        }
        if let summary = game.historySummary {
            return summary.stoneColor(ofPlayerWithID: playerID)
        }
        return game.stoneColor(ofPlayerWithId: playerID)
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
        if game.historySummary != nil {
            return opponentStoneColor == .black ? game.blackPlayer : game.whitePlayer
        }
        return game.currentPlayer(with: opponentStoneColor)
    }

    private var isRengo: Bool { game.historySummary?.rengo ?? game.rengo }

    private var opponentRengoTeamSize: Int? {
        guard isRengo, let opponentStoneColor else {
            return nil
        }
        if let summary = game.historySummary {
            return opponentStoneColor == .black
                ? summary.rengoBlackTeamIDs?.count : summary.rengoWhiteTeamIDs?.count
        }
        return game.orderedRengoTeam[opponentStoneColor]?.count
    }

    private var rengoTeamSizes: (black: Int, white: Int)? {
        guard isRengo else { return nil }
        if let summary = game.historySummary,
           let black = summary.rengoBlackTeamIDs, let white = summary.rengoWhiteTeamIDs {
            return (black.count, white.count)
        }
        guard let rengoTeams = game.gameData?.rengoTeams else {
            return nil
        }
        return (black: rengoTeams.black.count, white: rengoTeams.white.count)
    }

    var handicapStones: Int {
        return game.historySummary?.handicap ?? game.gameData?.handicap ?? 0
    }

    private var displayGameName: String? {
        guard let gameName = (game.historySummary?.name ?? game.gameName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !gameName.isEmpty else {
            return nil
        }
        return gameName
    }

    /// OGS uses the fractional part of a ruleset's normal komi for handicap
    /// games: 0.5 for every supported ruleset except New Zealand, which uses 0.
    var nonstandardKomi: Double? {
        guard let rules = game.historySummary?.rules ?? game.gameData?.rules,
              let komi = game.historySummary?.komi ?? game.gameData?.komi else {
            return nil
        }
        let standardKomi = handicapStones > 0
            ? rules.defaultKomi.truncatingRemainder(dividingBy: 1)
            : rules.defaultKomi
        return komi == standardKomi ? nil : komi
    }

    private var gameNameLineLimit: Int {
        let hasUnusualSettings = handicapStones > 0 || nonstandardKomi != nil
        return !isRengo && !hasUnusualSettings ? 2 : 1
    }

    private var userResult: UserResult? {
        if let summary = game.historySummary {
            if summary.annulled == true { return .annulled }
            guard let playerID = perspectivePlayerID ?? ogs.user?.id else { return nil }
            switch summary.result(for: playerID) {
            case .win: return .win
            case .loss: return .loss
            case .draw: return .draw
            case .annulled: return .annulled
            case .unknown: return nil
            }
        }
        if game.historyAnnulled ?? (game.ogsRawData?["annulled"] as? Bool) ?? false {
            return .annulled
        }
        guard let userStoneColor else { return nil }
        guard game.gameData?.outcome != nil, let winnerID = game.gameData?.winner else {
            return nil
        }
        guard winnerID != 0 else {
            guard gameOutcome?.lowercased() != "cancellation" else { return nil }
            return .draw
        }
        guard let winnerStoneColor = game.stoneColor(ofPlayerWithId: winnerID) else {
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
        case .annulled:
            return String(localized: "Annulled")
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
        case .draw, .annulled:
            return .secondary
        case .none:
            return nil
        }
    }

    /// Returns the numeric margin only for OGS's "<number> point(s)" outcome
    /// format. Other outcomes can contain numbers that are not score margins.
    private var pointDifference: Double? {
        guard let outcome = gameOutcome else {
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
        guard let outcome = gameOutcome else {
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
            case .draw, .annulled, .none:
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

    private var gameOutcome: String? { game.historySummary?.outcome ?? game.gameData?.outcome }

    /// A lightweight listing has no replay yet. Never depict its initial empty
    /// position as the final board, or a shared game's selected review move.
    @ViewBuilder
    private var boardPreview: some View {
        if let position = game.finishedHistoryPosition {
            BoardView(boardPosition: position)
                .saturation(0.8)
                .opacity(0.85)
        } else {
            VStack(spacing: 8) {
                if game.historyDetailState == .unavailable {
                    Image(systemName: "exclamationmark.circle")
                    Text("Board unavailable")
                } else {
                    ProgressView()
                    Text("Loading board")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(game.historyDetailState == .unavailable
                ? SurroundUITestContract.AccessibilityID.gameHistoryBoardUnavailable(game.ogsID ?? 0)
                : SurroundUITestContract.AccessibilityID.gameHistoryBoardLoading(game.ogsID ?? 0))
        }
    }

    private var profilePlayers: [OGSUser] {
        var seen = Set<Int>()
        return [StoneColor.black, .white].flatMap { color -> [OGSUser] in
            if isRengo {
                if let summary = game.historySummary {
                    let ids = color == .black ? summary.rengoBlackTeamIDs : summary.rengoWhiteTeamIDs
                    if let ids, !ids.isEmpty {
                        let knownPlayers = ids.compactMap { game.playerByOGSId[$0] }
                        if !knownPlayers.isEmpty { return knownPlayers }
                    }
                } else if let team = game.orderedRengoTeam[color] ?? game.gameData?.rengoTeams?[color],
                          !team.isEmpty {
                    return team
                }
            }
            return (color == .black ? game.blackPlayer : game.whitePlayer).map { [$0] } ?? []
        }
        .filter { $0.id > 0 && $0.id != ogs.user?.id && seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private var historyMenu: some View {
        if let openPlayerProfile, let gameID = game.ogsID, gameID > 0 {
            ForEach(profilePlayers, id: \.id) { player in
                Button {
                    openPlayerProfile(player)
                } label: {
                    Label("View Profile", systemImage: "person.crop.circle")
                    Text(verbatim: player.usernameAndRank)
                }
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.profileGameMenuEntry(gameID, player.id)
                )
            }
        }
        if game.historyDetailState == .unavailable, let retryPreview {
            Button(action: retryPreview) {
                Label("Retry Board Preview", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameHistoryBoardRetry(game.ogsID ?? 0)
            )
        }
    }

    @ViewBuilder
    private func opponentLabel(_ opponent: OGSUser) -> some View {
        if opponent.id == ogs.user?.id {
            Text("You")
                .bold()
                .foregroundStyle(.primary)
                .padding(.horizontal, 3)
                .background(Color(UIColor.systemTeal), in: RoundedRectangle(cornerRadius: 5))
                .offset(x: -3)
        } else {
            Text(verbatim: opponent.usernameAndRank)
                .bold()
                .foregroundStyle(opponent.uiColor)
        }
    }

    /// Accessibility text needs the full row width and its natural height.
    /// Keep the board small so it does not compete with the result or names.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            boardPreview
                .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 8) {
                if let userResultText, let userResultColor {
                    Text(userResultText)
                        .bold()
                        .foregroundStyle(userResultColor)
                }
                if let outcomeText {
                    Text(verbatim: outcomeText)
                }
                if let opponentStoneColor, let opponent {
                    HStack(spacing: 6) {
                        Text("vs.", comment: "HistoryGameCell result versus opponent")
                        Stone(color: opponentStoneColor, shadowRadius: 1)
                            .frame(width: 15, height: 15)
                    }
                    opponentLabel(opponent)
                    if let opponentRengoTeamSize, opponentRengoTeamSize > 1 {
                        HStack(spacing: 2) {
                            Text(verbatim: "+ \(opponentRengoTeamSize - 1)×")
                            Image(systemName: "person.fill")
                        }
                    }
                }
            }
            .font(.subheadline)
            if handicapStones > 0 {
                Text("\(handicapStones) handicap stones", comment: "HistoryGameCell - vary for plural")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let nonstandardKomi {
                Text("Komi: \(nonstandardKomi, specifier: "%.1f")", comment: "HistoryGameCell nonstandard komi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            }
            if let displayGameName {
                Text(verbatim: displayGameName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(nil)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        Button(action: action) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .top) {
                        boardPreview
                            .frame(width: geometry.size.height, height: geometry.size.height, alignment: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            if userResultText != nil || outcomeText != nil {
                                HStack(spacing: 4) {
                                    if let userResultText, let userResultColor {
                                        Text(userResultText)
                                            .bold()
                                            .foregroundStyle(userResultColor)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    if let outcomeText {
                                        Text(verbatim: userResultText == nil ? outcomeText : "(\(outcomeText))")
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                .font(.subheadline)
                            }
                            if let opponentStoneColor, let opponent {
                                HStack(spacing: 6) {
                                    Text("vs.", comment: "HistoryGameCell result versus opponent")
                                        .fixedSize(horizontal: true, vertical: false)
                                    Stone(color: opponentStoneColor, shadowRadius: 1)
                                        .frame(width: 15, height: 15)
                                    HStack(spacing: 2) {
                                        opponentLabel(opponent)
                                            .lineLimit(1)
                                        if let opponentRengoTeamSize, opponentRengoTeamSize > 1 {
                                            Text(verbatim: " + \(opponentRengoTeamSize - 1)×")
                                            Image(systemName: "person.fill")
                                        }
                                    }
                                }
                                .font(.subheadline)
                                .lineLimit(1)
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
        }
        .buttonStyle(.plain)
        .contextMenu { historyMenu }
    }
}

extension View {
    /// Lazy grids may create offscreen rows. Replay demand follows the scroll
    /// viewport instead of creation, while surviving covered-screen reentry.
    func historyPreviewDemand<Query: Equatable>(
        for game: Game,
        loader: FinishedGamePreviewLoader,
        using service: OGSService,
        query: Query,
        screenIsVisible: Bool
    ) -> some View {
        modifier(HistoryPreviewDemand(
            game: game, loader: loader, service: service,
            query: query, screenIsVisible: screenIsVisible
        ))
    }
}

private struct HistoryPreviewDemand<Query: Equatable>: ViewModifier {
    private struct ServiceContext: Equatable {
        let serviceID: ObjectIdentifier
        let authenticationGeneration: UInt
        let viewerID: Int?
    }

    let game: Game
    let loader: FinishedGamePreviewLoader
    @ObservedObject var service: OGSService
    let query: Query
    let screenIsVisible: Bool
    @State private var viewportVisible = false
    @State private var hasAppeared = false

    private var serviceContext: ServiceContext {
        ServiceContext(serviceID: ObjectIdentifier(service),
                       authenticationGeneration: service.finishedGamePreviewAuthenticationGeneration,
                       viewerID: service.user?.id)
    }

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                viewportVisible = visible
                updateDemand()
            }
            .onAppear {
                hasAppeared = true
                updateDemand()
            }
            .onDisappear {
                hasAppeared = false
                loader.removeDemand(for: game)
            }
            .onChange(of: screenIsVisible) { _, _ in updateDemand() }
            .onChange(of: query) { _, _ in updateDemand() }
            .onChange(of: serviceContext) { _, _ in updateDemand() }
    }

    private func updateDemand() {
        if hasAppeared && screenIsVisible && viewportVisible {
            loader.load(games: [game], using: service)
        } else {
            loader.removeDemand(for: game)
        }
    }
}

#if DEBUG
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
#endif
