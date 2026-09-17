import SwiftUI

extension View {
    /// Inset the content, leaving section backgrounds free to span the page.
    /// Keep text and cards readable on wide iPad and Catalyst windows.
    func profileContentMargins() -> some View {
        padding(.horizontal, 16)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

struct PlayerProfileSectionHeader: View {
    let title: LocalizedStringKey
    var count: Int? = nil

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let count { Text(count, format: .number).foregroundStyle(.secondary) }
        }
        .profileContentMargins()
        .padding(.vertical, 6)
        .background(Color(.systemGray3).shadow(radius: 2))
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ProfileNavigationRow: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.indigo)
    }
}

/// The preview owns its history request and keeps its results while a game or
/// full list covers the profile. The full profile response supplies the rest.
struct PlayerProfileGames: View {
    @EnvironmentObject private var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    @EnvironmentObject private var nav: NavigationService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let profile: OGSPlayerProfile
    let refreshID: Int

    private struct HistoryIdentity: Equatable {
        let playerID: Int
        let viewerID: Int?
        let refreshID: Int
        let attempt: Int
    }

    @State private var history: [Game] = []
    @State private var historyStatus: GameHistoryLoadStatus? = .loading
    @State private var historyAttempt = 0
    @State private var loadedHistory: HistoryIdentity?
    @State private var isWide = false
    @State private var activeGames: ProfileActiveGames?
    @State private var versus: OGSProfileVersus?
    @State private var historyHasNextPage = false
    @State private var headToHeadAttempt = 0
    @State private var activeGamesAttempt = 0
    @State private var loadingHeadToHead = false
    @State private var loadingActiveGames = false
    @State private var completedHeadToHeadRetry: HistoryIdentity?
    @State private var completedActiveGamesRetry: HistoryIdentity?

    private enum ProfileSection { case headToHead, activeGames }

    init(
        profile: OGSPlayerProfile,
        activeGames: ProfileActiveGames?,
        refreshID: Int
    ) {
        self.profile = profile
        self.refreshID = refreshID
        _activeGames = State(initialValue: activeGames)
        _versus = State(initialValue: profile.versus)
    }

    private var historyIdentity: HistoryIdentity {
        HistoryIdentity(playerID: profile.id, viewerID: ogs.user?.id,
                        refreshID: refreshID, attempt: historyAttempt)
    }

    private var headToHeadIdentity: HistoryIdentity {
        HistoryIdentity(playerID: profile.id, viewerID: ogs.user?.id,
                        refreshID: refreshID, attempt: headToHeadAttempt)
    }

    private var activeGamesIdentity: HistoryIdentity {
        HistoryIdentity(playerID: profile.id, viewerID: ogs.user?.id,
                        refreshID: refreshID, attempt: activeGamesAttempt)
    }

    private var previewLimit: Int { usesTwoColumns ? 4 : 2 }
    private var usesTwoColumns: Bool { isWide && !dynamicTypeSize.isAccessibilitySize }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: usesTwoColumns ? 2 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if profile.id != ogs.user?.id {
                if ogs.isLoggedIn, ogs.user != nil { headToHead }
                activeSection
            }
            historySection
        }
        .onGeometryChange(for: Bool.self) { $0.size.width - 32 >= 650 } action: { isWide = $0 }
        .task(id: historyIdentity) { await loadHistory(for: historyIdentity) }
        .task(id: headToHeadIdentity) {
            if headToHeadAttempt > 0 {
                await reloadSection(.headToHead, for: headToHeadIdentity)
            }
        }
        .task(id: activeGamesIdentity) {
            if activeGamesAttempt > 0 {
                await reloadSection(.activeGames, for: activeGamesIdentity)
            }
        }
    }

    private var headToHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayerProfileSectionHeader(title: "Head-to-head")
            VStack(alignment: .leading, spacing: 8) {
                Text("Your record against \(profile.user.username)")
                    .font(.subheadline)
                if loadingHeadToHead {
                    ProgressView().frame(maxWidth: .infinity).padding()
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHeadToHeadLoading)
                } else if let versus {
                    if versus.totalGames == 0 {
                        Text("No games together yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wins: \(versus.wins) · Losses: \(versus.losses) · Draws: \(versus.draws)")
                            .font(.subheadline)
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHeadToHeadSummary)
                        recordBar(versus)
                        if !versus.history.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { recentResults(versus) }
                                VStack(alignment: .leading, spacing: 8) { recentResults(versus) }
                            }
                        }
                        ProfileNavigationRow(title: "See all games") {
                            navigation.openHistory(for: profile.user, opponentID: ogs.user?.id)
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHeadToHeadHistory)
                    }
                } else {
                    unavailable("Couldn’t load head-to-head record",
                                retryID: SurroundUITestContract.AccessibilityID.profileHeadToHeadRetry) {
                        headToHeadAttempt += 1
                    }
                }
            }.profileContentMargins()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHeadToHead)
    }

    private func recordBar(_ record: OGSProfileVersus) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array([record.wins, record.losses, record.draws].enumerated()), id: \.offset) { index, count in
                    if count > 0 {
                        Rectangle()
                            .fill([Color.green, .red, .gray][index])
                            .frame(width: geometry.size.width * CGFloat(count) / CGFloat(record.totalGames))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 16)
        // The preceding localized counts carry the same information without color.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func recentResults(_ record: OGSProfileVersus) -> some View {
        Text("Most recent").font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 6) {
            ForEach(Array(record.history.prefix(5).enumerated()), id: \.offset) { _, game in
                let label: String = switch game.result {
                case .win: String(localized: "W", comment: "Short head-to-head win result")
                case .loss: String(localized: "L", comment: "Short head-to-head loss result")
                case .draw: String(localized: "D", comment: "Short head-to-head draw result")
                case .unknown: "—"
                }
                let name: String = switch game.result {
                case .win: String(localized: "Win")
                case .loss: String(localized: "Loss")
                case .draw: String(localized: "Draw")
                case .unknown: String(localized: "Result unavailable")
                }
                let color: Color = switch game.result {
                case .win: .green
                case .loss: .red
                case .draw, .unknown: .secondary
                }
                Text(verbatim: label)
                    .font(.caption.bold())
                    .frame(minWidth: 26, minHeight: 26)
                    .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel(Text(verbatim: name))
                    .accessibilityValue(Text(verbatim: game.date?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHeadToHeadRecent(game.gameID))
            }
        }
    }

    private var activeSection: some View {
        Group {
            if let activeGames {
                ProfileActiveGamesPreview(player: profile.user, games: activeGames, columns: columns)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    PlayerProfileSectionHeader(title: "Active games")
                    if loadingActiveGames {
                        ProgressView().frame(maxWidth: .infinity).padding()
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileActiveGamesLoading)
                    } else {
                        unavailable("Couldn’t load active games",
                                    retryID: SurroundUITestContract.AccessibilityID.profileActiveGamesRetry) {
                            activeGamesAttempt += 1
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileActiveGames)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayerProfileSectionHeader(title: "Game history")
            if let historyStatus {
                GameHistoryLoadStatusView(status: historyStatus, accessibilityIdentifiers: .init(
                    loading: SurroundUITestContract.AccessibilityID.gameHistoryLoading,
                    error: SurroundUITestContract.AccessibilityID.gameHistoryError,
                    retry: SurroundUITestContract.AccessibilityID.gameHistoryRetry,
                    empty: SurroundUITestContract.AccessibilityID.gameHistoryEmpty
                ), emptyVerticalPadding: 12, retry: { historyAttempt += 1 })
                .profileContentMargins()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(history.prefix(previewLimit))) { game in
                        HistoryGameCell(game: game, perspectivePlayerID: profile.id) {
                            navigation.openGame(game, using: nav)
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileHistoryGame(game.ogsID ?? 0))
                    }
                }.profileContentMargins()
                if historyHasNextPage || history.count > previewLimit {
                    ProfileNavigationRow(title: "See all games") {
                        navigation.openHistory(for: profile.user)
                    }
                    .profileContentMargins()
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileAllHistory)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileGameHistory)
    }

    private func unavailable(_ message: LocalizedStringKey, retryID: String,
                             retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(message).foregroundStyle(.secondary)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(retryID)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// OGS supplies both sections through /full. Retry that request while
    /// applying only the requested section, retaining identity, ratings,
    /// history, selected category and the other section's state.
    private func reloadSection(_ section: ProfileSection, for identity: HistoryIdentity) async {
        let completed = section == .headToHead ? completedHeadToHeadRetry : completedActiveGamesRetry
        guard completed != identity else { return }
        switch section {
        case .headToHead: loadingHeadToHead = true
        case .activeGames: loadingActiveGames = true
        }
        defer {
            let current = section == .headToHead ? headToHeadIdentity : activeGamesIdentity
            if identity == current {
                switch section {
                case .headToHead:
                    loadingHeadToHead = false
                    if !Task.isCancelled { completedHeadToHeadRetry = identity }
                case .activeGames:
                    loadingActiveGames = false
                    if !Task.isCancelled { completedActiveGamesRetry = identity }
                }
            }
        }
        do {
            for try await refreshed in ogs.fetchPlayerProfile(playerId: identity.playerID).values {
                try Task.checkCancellation()
                let current = section == .headToHead ? headToHeadIdentity : activeGamesIdentity
                guard identity == current else { return }
                switch section {
                case .headToHead: versus = refreshed.versus
                case .activeGames: activeGames = ogs.profileActiveGames(from: refreshed)
                }
                return
            }
        } catch {
            // Keep this section's error and the rest of the profile intact.
        }
    }

    private func loadHistory(for identity: HistoryIdentity) async {
        guard loadedHistory != identity else { return }
        historyStatus = .loading
        do {
            for try await page in ogs.fetchHydratedFinishedGames(
                playerId: identity.playerID, page: 1, pageSize: 4,
                botGames: profile.user.isBot == true
            ).values {
                try Task.checkCancellation()
                guard identity == historyIdentity else { return }
                history = page.games
                historyHasNextPage = page.hasNextPage
                historyStatus = page.games.isEmpty ? .empty : nil
                loadedHistory = identity
                return
            }
            if !Task.isCancelled { historyStatus = .failed }
        } catch {
            if !Task.isCancelled { historyStatus = .failed }
        }
    }
}

private struct ProfileActiveGamesPreview: View {
    let player: OGSUser
    @ObservedObject var games: ProfileActiveGames
    let columns: [GridItem]
    @EnvironmentObject private var navigation: StackRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayerProfileSectionHeader(title: "Active games", count: games.entries.count)
            if games.entries.isEmpty {
                Text("No active games")
                    .foregroundStyle(.secondary)
                    .profileContentMargins()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(games.entries.prefix(3))) { entry in
                        ProfileActiveGameRow(entry: entry, games: games)
                    }
                }.profileContentMargins()
                if games.entries.count > 3 {
                    ProfileNavigationRow(title: "See all \(games.entries.count) games") {
                        navigation.openActiveGames(games, for: player)
                    }
                    .profileContentMargins()
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileAllActiveGames)
                }
            }
        }
        .onAppear { games.refreshMembership() }
    }
}

/// Creating a row is cheap; only a displayed row asks for its replayed board.
/// The profile and full list share their cache, including live game updates.
private struct ProfileActiveGameRow: View {
    let entry: OGSProfileActiveGame
    let games: ProfileActiveGames
    @EnvironmentObject private var navigation: StackRouter
    @EnvironmentObject private var nav: NavigationService
    @State private var game: Game?

    var body: some View {
        Group {
            if let game {
                GameCell(game: game, displayMode: .compact, opensGame: {
                    navigation.openGame(game, using: nav)
                }, navigationAccessibilityIdentifier: SurroundUITestContract.AccessibilityID.profileActiveGame(entry.id))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: entry.id) { game = games.game(for: entry) }
    }
}

struct PlayerActiveGamesView: View {
    let player: OGSUser
    @ObservedObject var games: ProfileActiveGames

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: player.username).font(.headline)
                if games.entries.isEmpty {
                    Text("No active games").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 16) {
                        ForEach(games.entries) { entry in
                            ProfileActiveGameRow(entry: entry, games: games)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Active games")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenProfileActiveGames)
        .onAppear { games.refreshMembership() }
    }
}
