//
//  HistoryGameCell.swift
//  Surround
//
//  A row for finished games in the history lists, laid out like Home's game
//  row (canvas "Home Redesign", CHistoryRow): the final board, the opponent,
//  the game's name, and the player's chip in their stone colors carrying the
//  result, as Game Detail's cards do once a game ends.
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
    /// Home's cards inset the row; a grouped panel separates its rows.
    var inCard = false
    var showsSeparator = false
    var retryPreview: (() -> Void)? = nil
    var action: () -> Void
    @EnvironmentObject var ogs: OGSService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @Environment(\.surroundTheme) private var theme
    @ObservedObject var settings = userDefaults
    /// The board stays 120 pt; the text beside it grows with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 140

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

    private var displayGameName: String? {
        guard let gameName = (game.historySummary?.name ?? game.gameName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !gameName.isEmpty else {
            return nil
        }
        return gameName
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

    /// The chip's headline: Won or Lost, or a result that stands alone.
    private var resultTitle: String? {
        if gameOutcome?.lowercased() == "cancellation" {
            return String(localized: "Canceled")
        }
        switch userResult {
        case .win: return String(localized: "Won")
        case .loss: return String(localized: "Lost")
        case .draw:
            return String(localized: "Draw", comment: "HistoryGameCell result for the logged-in player")
        case .annulled: return String(localized: "Annulled")
        case .none: return nil
        }
    }

    /// How the game was decided: the margin, or "by resignation" and the
    /// like. Draws, annulled and canceled games stand alone.
    private var resultDetail: String? {
        guard let outcome = gameOutcome, let userResult, userResult == .win || userResult == .loss else {
            return nil
        }
        if pointDifference != nil {
            return outcomeText
        }
        switch outcome.lowercased() {
        case "resignation", "resign", "r": return String(localized: "by resignation")
        case "timeout": return String(localized: "on time")
        case "disconnection": return String(localized: "by disconnection")
        case "stone removal timeout": return String(localized: "scoring timeout")
        case "disqualification": return String(localized: "by disqualification")
        case "moderator decision": return String(localized: "moderator decision")
        case "abandonment": return String(localized: "by abandonment")
        default: return outcome
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
            PositionBoardView(boardPosition: position).equatable()
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
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
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

    /// Whose result the chip shows: the signed-in player's, or a profile owner's.
    private var perspectiveLabel: String? {
        guard userStoneColor != nil else { return nil }
        let playerID = perspectivePlayerID ?? ogs.user?.id
        if playerID == ogs.user?.id { return String(localized: "You") }
        return playerID.flatMap { game.playerByOGSId[$0]?.username }
            ?? (userStoneColor == .black ? game.blackPlayer : game.whitePlayer)?.username
    }

    private var hidesRank: Bool { settings[.hidesRank] ?? false }

    @ViewBuilder
    private var opponentLine: some View {
        if let opponent {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("vs.", comment: "HistoryGameCell result versus opponent")
                    .font(.subheadline)
                    .modifier(HomeSecondaryText())
                    .fixedSize()
                if opponent.id == ogs.user?.id {
                    Text("You")
                        .font(.callout.weight(.semibold))
                } else {
                    Text(verbatim: opponent.username)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.roleColor(for: opponent, on: panelSurface))
                    if !hidesRank {
                        Text(verbatim: opponent.formattedRank)
                            .font(.subheadline)
                            .modifier(HomeSecondaryText())
                            .fixedSize()
                    }
                }
                if let opponentRengoTeamSize, opponentRengoTeamSize > 1 {
                    Text(verbatim: "+\(opponentRengoTeamSize - 1)")
                        .font(.subheadline.weight(.semibold))
                        .modifier(HomeSecondaryText())
                        .fixedSize()
                }
            }
            .lineLimit(1)
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    private var panelSurface: StoneColor { colorScheme == .dark ? .black : .white }

    /// The player's chip in their stone colors. A detail that does not fit
    /// is dropped whole rather than cut off.
    @ViewBuilder
    private var resultChip: some View {
        let color = userStoneColor ?? .white
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let label = perspectiveLabel
        let title = resultTitle ?? outcomeText
        if label != nil || title != nil {
            let leading = Group {
                if let label {
                    Text(verbatim: label)
                        .font(.caption.weight(.medium))
                        .opacity(0.72)
                        .lineLimit(1)
                }
            }
            let titleText = Group {
                if let title {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    leading
                    Spacer(minLength: 4)
                    titleText
                    if let detail = resultDetail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(theme.identitySecondary(color))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    leading
                    Spacer(minLength: 4)
                    titleText
                }
            }
            .foregroundStyle(theme.identityForeground(color))
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(LinearGradient(colors: theme.identityChipColors(color), startPoint: .top, endPoint: .bottom),
                        in: shape)
            .overlay { shape.strokeBorder(theme.identityChipBorder(color), lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            opponentLine
            if let displayGameName {
                Text(verbatim: displayGameName)
                    .font(.footnote)
                    .modifier(HomeSecondaryText())
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            resultChip
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Accessibility text needs the full row width and its
                    // natural height; the board keeps to 120 pt above it.
                    VStack(alignment: .leading, spacing: 10) {
                        boardPreview
                            .frame(width: 120, height: 120)
                        details
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(inCard ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        boardPreview
                            .frame(width: 120, height: 120)
                            .padding(.vertical, 10)
                        details
                            .padding(.top, 12)
                            .padding(.bottom, 10)
                            .padding(.trailing, inCard ? 12 : 0)
                            .overlay(alignment: .top) {
                                if showsSeparator {
                                    Rectangle()
                                        .fill(GameDetailSurfaceStyle(role: .panelBorder))
                                        .frame(height: 0.5)
                                }
                            }
                    }
                    .padding(.leading, inCard ? 12 : 0)
                    .frame(height: max(rowHeight, 140))
                }
            }
            .contentShape(Rectangle())
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
