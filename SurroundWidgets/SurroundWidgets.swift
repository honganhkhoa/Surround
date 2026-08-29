//
//  SurroundWidgets.swift
//  SurroundWidgets
//
//  Created by Anh Khoa Hong on 10/15/20.
//

import WidgetKit
import SwiftUI
import Alamofire
import DictionaryCoding
import Combine

class Provider: TimelineProvider {
#if DEBUG
    func appStoreScreenshotEntry(in _: Context) -> CorrespondenceGamesEntry? {
        guard let fixture = userDefaults[.appStoreScreenshotWidgetFixture],
              fixture.isValid,
              let overview = try? JSONSerialization.jsonObject(
                with: fixture.overviewData
              ) as? [String: Any],
              var entry = getEntry(
                fromOverviewJSON: overview,
                userID: fixture.userID,
                localeIdentifier: fixture.localeIdentifier,
                usesStaticClock: true
              ) else {
            return nil
        }

        entry.screenshotFixtureValidUntil = fixture.validUntil
        entry.screenshotExpectedGameCount = fixture.expectedGameCount
        entry.screenshotAppStoreProofToken = fixture.appStoreProofToken
        entry.screenshotCompatibilityProofToken =
            fixture.compatibilityProofToken
        return entry
    }
#endif

    var isLoggedIn: Bool {
        return userDefaults[.ogsUIConfig]?.csrfToken != nil && userDefaults[.ogsSessionId] != nil
    }
    
    var notLoggedInEntry: CorrespondenceGamesEntry {
        CorrespondenceGamesEntry(
            date: Date(),
            noGamesMessage: String(localized: "Sign in to your online-go.com account to see your games here.", comment: "Correspondence Games Widget error")
        )
    }
    
    func placeholder(in context: Context) -> CorrespondenceGamesEntry {
        CorrespondenceGamesEntry(date: Date(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CorrespondenceGamesEntry) -> ()) {
#if DEBUG
        if let entry = appStoreScreenshotEntry(in: context) {
            completion(entry)
            return
        }
#endif

        if !isLoggedIn {
            completion(notLoggedInEntry)
            return
        }
        
        if let overviewData = userDefaults[.latestOGSOverview] {
            if let data = try? JSONSerialization.jsonObject(with: overviewData) as? [String: Any] {
                if let entry = getEntry(fromOverviewJSON: data) {
                    completion(entry)
                    return
                }
            }
        }
        let entry = CorrespondenceGamesEntry(date: Date(), isPlaceholder: true)
        completion(entry)
    }
    
    func getEntry(
        fromOverviewJSON overviewJSON: [String: Any],
        userID: Int? = nil,
        localeIdentifier: String? = nil,
        usesStaticClock: Bool = false
    ) -> CorrespondenceGamesEntry? {
        if let activeGames = overviewJSON["active_games"] as? [[String: Any]] {
            let resolvedUserID = userID ?? userDefaults[.ogsUIConfig]?.user.id ?? -1
            let games = parseAndSortActiveGames(
                fromData: activeGames,
                userID: resolvedUserID,
                usesStaticClock: usesStaticClock
            )
            return CorrespondenceGamesEntry(
                date: Date(),
                games: games,
                userID: resolvedUserID,
                noGamesMessage: localizedNoGamesMessage(
                    localeIdentifier: localeIdentifier
                ),
                localeIdentifier: localeIdentifier,
                usesStaticClock: usesStaticClock
            )
        }
        return nil
    }

    private func localizedNoGamesMessage(
        localeIdentifier: String?
    ) -> String {
        let explicitLocale = localeIdentifier.map(Locale.init(identifier:))
        let locale = explicitLocale ?? .current
        return String(
            localized: "You don't have any correspondence games at the moment.",
            bundle: LocalizationBundleResolver.bundle(for: explicitLocale),
            locale: locale,
            comment: "Correspondence Games Widget error"
        )
    }
    
    func parseAndSortActiveGames(
        fromData activeGamesData: [[String: Any]],
        userID: Int? = nil,
        usesStaticClock: Bool = false
    ) -> [Game] {
        var decodedGames = [Game]()
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for gameData in activeGamesData {
            if let jsonData = gameData["json"] as? [String: Any] {
                if let ogsGame = try? decoder.decode(OGSGame.self, from: jsonData) {
                    let game = Game(ogsGame: ogsGame)
                    if usesStaticClock {
                        // Game initialization advances a running clock from
                        // its fixture timestamp to wall-clock time. Restore
                        // the decoded snapshot before sorting and rendering so
                        // compatibility captures cannot drift between OS runs.
                        game.clock = game.gameData?.clock
                    }
                    decodedGames.append(game)
                }
            }
        }
        
        let userId = userID ?? userDefaults[.ogsUIConfig]?.user.id ?? -1
        return CorrespondenceWidgetContentPolicy.sortedCorrespondenceGames(
            decodedGames,
            isCorrespondence: {
                $0.gameData?.timeControl.speed == .correspondence
            },
            isUserTurn: {
                $0.clock?.currentPlayerId == userId
            },
            timeLeft: { game in
                guard let clock = game.clock else { return .infinity }
                let thinkingTime = game.stoneColor(
                    ofPlayerWithId: userId
                ) == .black ? clock.blackTime : clock.whiteTime
                return thinkingTime.thinkingTimeLeft ?? .infinity
            }
        )
    }

    var overviewLoadingCancellable: AnyCancellable?
    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CorrespondenceGamesEntry>) -> Void
    ) {
#if DEBUG
        if let fixture = userDefaults[.appStoreScreenshotWidgetFixture],
           fixture.isValid,
           let entry = appStoreScreenshotEntry(in: context) {
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(fixture.validUntil)
                )
            )
            return
        }
#endif

        if !(userDefaults[.latestOGSOverviewOutdated] ?? false) {
            if let lastOverviewUpdate = userDefaults[.latestOGSOverviewTime] {
                let currentDate = Date()
                if currentDate.timeIntervalSince(lastOverviewUpdate) < 60 && isLoggedIn {
                    if let overviewData = userDefaults[.latestOGSOverview] {
                        if let data = try? JSONSerialization.jsonObject(with: overviewData) as? [String: Any] {
                            if let entry = getEntry(fromOverviewJSON: data) {
                                let nextReloadDate = currentDate.advanced(by: 15 * 60)
                                completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                                return
                            }
                        }
                    }
                }
            }
        }
        
        overviewLoadingCancellable = SurroundService.shared.getOGSOverview().catch { error in
            return Future<[String: Any], Error> { promise in
                if let csrfToken = userDefaults[.ogsCsrfCookie] ?? userDefaults[.ogsUIConfig]?.csrfToken, let sessionId = userDefaults[.ogsSessionId] {
                    let ogsDomain = URL(string: OGSService.ogsRoot)!.host!
                    let csrfCookie = HTTPCookie(properties: [.name: "csrftoken", .value: csrfToken, .domain: ogsDomain, .path: "/"])
                    let sessionIdCookie = HTTPCookie(properties: [.name: "sessionid", .value: sessionId, .domain: ogsDomain, .path: "/"])
                    if let csrfCookie = csrfCookie, let sessionIdCookie = sessionIdCookie {
                        Session.default.sessionConfiguration.httpCookieStorage?.setCookie(csrfCookie)
                        Session.default.sessionConfiguration.httpCookieStorage?.setCookie(sessionIdCookie)
                        AF.request("\(OGSService.ogsRoot)/api/v1/ui/overview").validate().responseData { response in
                            var overviewData = response.value
                            if case .failure = response.result {
                                overviewData = userDefaults[.latestOGSOverview]
                            }
                            
                            if let overviewData = overviewData {
                                if let overviewValue = try? JSONSerialization.jsonObject(with: overviewData) as? [String: Any] {
                                    promise(.success(overviewValue))
                                    return
                                }
                            }
                            promise(.failure(OGSServiceError.invalidJSON))
                        }
                    } else {
                        promise(.failure(OGSServiceError.notLoggedIn))
                    }
                } else {
                    promise(.failure(OGSServiceError.notLoggedIn))
                }
            }.eraseToAnyPublisher()
        }.sink(receiveCompletion: { result in
            if case .failure(let error) = result {
                let currentDate = Date()
                let nextReloadDate = currentDate.advanced(by: 15 * 60)

                if case OGSServiceError.notLoggedIn = error {
                    completion(Timeline(entries: [self.notLoggedInEntry], policy: .after(nextReloadDate)))
                } else {
                    let entry = CorrespondenceGamesEntry(
                        date: currentDate,
                        noGamesMessage: String(localized: "Failed to load your correspondence games.", comment: "Correspondence Games Widget error")
                    )
                    completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                }
            }
        }, receiveValue: { overviewValue in
            let overviewData = try? JSONSerialization.data(withJSONObject: overviewValue)
            let currentDate = Date()
            let nextReloadDate = currentDate.advanced(by: 15 * 60)

            if let oldOverviewData = userDefaults[.latestOGSOverview], let overviewData = overviewData {
                SurroundNotificationService.shared.scheduleNotificationsIfNecessary(withOldOverviewData: oldOverviewData, newOverviewData: overviewData, completionHandler: { _ in
                    if let entry = self.getEntry(fromOverviewJSON: overviewValue) {
                        completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                    }
                })
                userDefaults.updateLatestOGSOverview(overviewData: overviewData)
                return
            } else {
                if let overviewData = overviewData {
                    userDefaults.updateLatestOGSOverview(overviewData: overviewData)
                }
                if let entry = self.getEntry(fromOverviewJSON: overviewValue) {
                    completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                    return
                }
            }
        })
    }
}

struct CorrespondenceGamesEntry: TimelineEntry {
    var date: Date
    var games: [Game] = []
    var userID: Int?
    var noGamesMessage: String?
    var debugMessage: String?
    var isPlaceholder = false
    var localeIdentifier: String?
    var usesStaticClock = false
    #if DEBUG
    var screenshotFixtureValidUntil: Date?
    var screenshotExpectedGameCount: Int?
    var screenshotAppStoreProofToken: String?
    var screenshotCompatibilityProofToken: String?
    #endif
}

struct CorrespondenceGamesWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var entry: Provider.Entry
    var previewFamily: WidgetFamily? = nil
    var previewRenderingMode: WidgetRenderingMode? = nil

    private var resolvedFamily: WidgetFamily {
        previewFamily ?? widgetFamily
    }

    private var resolvedRenderingMode: WidgetRenderingMode {
        previewRenderingMode ?? widgetRenderingMode
    }

    private var gamesCapacity: Int {
        CorrespondenceWidgetGridLayout.maximumGameCount(for: resolvedFamily)
    }

    private var gamesToDisplay: [Game] {
        if entry.isPlaceholder {
            let placeholderGame = Game(
                width: 19,
                height: 19,
                blackName: "",
                whiteName: "",
                gameId: .OGS(-1)
            )
            return Array(repeating: placeholderGame, count: gamesCapacity)
        }
        return Array(entry.games.prefix(gamesCapacity))
    }

    private var userId: Int {
        entry.userID ?? userDefaults[.ogsUIConfig]?.user.id ?? -1
    }

    private var numberOfGamesOnUserTurn: Int {
        CorrespondenceWidgetContentPolicy.pendingCount(in: entry.games) {
            $0.clock?.currentPlayerId == userId
        }
    }

    private var homeDestination: URL? {
        NavigationService.appURL(rootView: .home)
    }

    private func destination(for game: Game) -> URL? {
        guard let gameID = game.ogsID, gameID > 0 else {
            return nil
        }
        return NavigationService.appURL(rootView: .home, ogsGameId: gameID)
    }

    private var widgetDestination: URL? {
        switch CorrespondenceWidgetContentPolicy.primaryDestination(
            displayedGameIDs: gamesToDisplay.map(\.ogsID),
            isPlaceholder: entry.isPlaceholder
        ) {
        case .home:
            return homeDestination
        case .game(let gameID):
            return NavigationService.appURL(
                rootView: .home,
                ogsGameId: gameID
            )
        }
    }

    #if DEBUG
    private var screenshotReadinessIdentifier: String {
        let family: String
        switch resolvedFamily {
        case .systemSmall:
            family = "small"
        case .systemMedium:
            family = "medium"
        case .systemLarge:
            family = "large"
        case .systemExtraLarge:
            family = "extra-large"
        default:
            family = "unsupported"
        }

        let expectedGameCount = entry.screenshotExpectedGameCount
            ?? SurroundUITestContract.compatibilityWidgetGameCount
        let actualGameCount = entry.games.count
        let actualDisplayedGameCount = gamesToDisplay.count

        if let proofToken = entry.screenshotAppStoreProofToken {
            let expectedGameCount = entry.screenshotExpectedGameCount
                ?? SurroundUITestContract.appStoreScreenshotWidgetGameCount
            let expectedDisplayedGameCount = min(
                gamesCapacity,
                expectedGameCount
            )
            guard family == "medium",
                  entry.usesStaticClock,
                  !entry.isPlaceholder,
                  entry.debugMessage == nil,
                  actualGameCount == expectedGameCount,
                  actualDisplayedGameCount == expectedDisplayedGameCount,
                  let localeIdentifier = entry.localeIdentifier,
                  !localeIdentifier.isEmpty,
                  let validUntil = entry.screenshotFixtureValidUntil,
                  resolvedRenderingMode == .fullColor else {
                return [
                    "surround.appstore.widget.unready",
                    family,
                    "games-\(actualGameCount)",
                    "expected-\(expectedGameCount)",
                    "displaying-\(actualDisplayedGameCount)",
                    "expected-display-\(expectedDisplayedGameCount)",
                ].joined(separator: ".")
            }
            return [
                "surround.appstore.widget.ready",
                family,
                "games-\(expectedGameCount)",
                "displaying-\(expectedDisplayedGameCount)",
                "rendering-fullColor",
                "token-\(proofToken)",
                "locale-\(localeIdentifier)",
                "expires-\(Int(validUntil.timeIntervalSince1970))",
            ].joined(separator: ".")
        }

        let expectedDisplayedGameCount = min(gamesCapacity, expectedGameCount)
        guard entry.usesStaticClock,
              !entry.isPlaceholder,
              entry.debugMessage == nil,
              actualGameCount == expectedGameCount,
              actualDisplayedGameCount == expectedDisplayedGameCount,
              let validUntil = entry.screenshotFixtureValidUntil,
              let proofToken = entry.screenshotCompatibilityProofToken,
              resolvedRenderingMode == .fullColor else {
            return [
                "surround.compatibility.widget.unready",
                family,
                "games-\(actualGameCount)",
                "expected-\(expectedGameCount)",
                "displaying-\(actualDisplayedGameCount)",
                "expected-display-\(expectedDisplayedGameCount)",
            ].joined(separator: ".")
        }
        return [
            "surround.compatibility.widget.ready",
            family,
            "games-\(expectedGameCount)",
            "rendering-fullColor",
            "token-\(proofToken)",
            "expires-\(Int(validUntil.timeIntervalSince1970))",
        ].joined(separator: ".")
    }
    #endif

    @ViewBuilder
    private func applyingScreenshotReadinessIdentifier<Content: View>(
        to content: Content
    ) -> some View {
        #if DEBUG
        content
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(screenshotReadinessIdentifier)
        #else
        content
        #endif
    }

    private var suddenDeathLabel: String {
        let explicitLocale = entry.localeIdentifier.map(Locale.init(identifier:))
        let locale = explicitLocale ?? .current
        return String(
            localized: "SD",
            bundle: LocalizationBundleResolver.bundle(for: explicitLocale),
            locale: locale
        )
    }
    
    private func timer(game: Game) -> some View {
        if let clock = game.clock, let timeControlSystem = game.gameData?.timeControl.system {
            let thinkingTime = clock.blackPlayerId == userId ? clock.blackTime : clock.whiteTime
            var timeLeft = thinkingTime.thinkingTimeLeft
            var auxiliaryLabel = ""
            let suddenDeathAuxiliaryLabel = " (\(suddenDeathLabel))"
            switch timeControlSystem {
            case .ByoYomi:
                if thinkingTime.thinkingTime! > 0 {
                    auxiliaryLabel = " (\(thinkingTime.periods!))"
                } else {
                    timeLeft = thinkingTime.periodTimeLeft
                    if thinkingTime.periodsLeft! > 1 {
                        auxiliaryLabel = " (\(thinkingTime.periodsLeft!))"
                    } else {
                        auxiliaryLabel = suddenDeathAuxiliaryLabel
                    }
                }
            case .Canadian:
                if thinkingTime.thinkingTime == 0 {
                    timeLeft = thinkingTime.blockTimeLeft
                    auxiliaryLabel = "/\(thinkingTime.movesLeft!)"
                }
            default:
                break
            }
            return AnyView(HStack(spacing: 0) {
                Spacer()
                if let timeLeft = timeLeft {
                    if entry.usesStaticClock
                        || (game.pauseControl?.isPaused() ?? false)
                        || game.clock?.currentPlayerId != userId {
                        Text(
                            timeString(
                                timeLeft: timeLeft,
                                locale: entry.localeIdentifier.map(
                                    Locale.init(identifier:)
                                )
                            )
                        )
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(Date().addingTimeInterval(timeLeft), style: .timer)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                if auxiliaryLabel == suddenDeathAuxiliaryLabel {
                    Text(auxiliaryLabel).foregroundColor(.red)
                } else {
                    Text(auxiliaryLabel)
                }
            }.font(Font.caption2.monospacedDigit().bold()))
        }
        return AnyView(EmptyView())
    }
    
    private func gameCell(game: Game, boardSize: CGFloat) -> some View {
        return VStack(spacing: 0) {
            ZStack {
                if game.clock?.currentPlayerId == userId {
                    if resolvedRenderingMode == .fullColor {
                        Color(.systemTeal)
                            .frame(
                                width: boardSize
                                    + CorrespondenceWidgetGridLayout.boardChrome,
                                height: boardSize
                                    + CorrespondenceWidgetGridLayout.boardChrome
                            )
                            .cornerRadius(10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.clear)
                            .stroke(.primary)
                            .frame(
                                width: boardSize
                                    + CorrespondenceWidgetGridLayout.boardChrome,
                                height: boardSize
                                    + CorrespondenceWidgetGridLayout.boardChrome
                            )
                    }
                }
                // Render the board directly into WidgetKit's view tree.
                // ImageRenderer can return a non-nil but transparent UIImage
                // in a real widget, which suppresses a nil-only fallback and
                // leaves just the turn-highlight backing visible.
                BoardView(
                    widgetRenderingMode: resolvedRenderingMode,
                    boardPosition: game.currentPosition,
                    cornerRadius: 10
                )
                .frame(width: boardSize, height: boardSize)
                .padding(CorrespondenceWidgetGridLayout.boardChrome / 2)
            }
            HStack {
                timer(game: game)
                if let pauseReason = game.pauseControl?.pauseReason(playerId: userId) {
                    Text(pauseReason)
                        .font(Font.caption2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(
                width: boardSize
                    + CorrespondenceWidgetGridLayout.boardChrome,
                height: CorrespondenceWidgetGridLayout.timerHeight
            )
        }
        .frame(
            width: boardSize + CorrespondenceWidgetGridLayout.boardChrome,
            height: boardSize + CorrespondenceWidgetGridLayout.boardChrome
                + CorrespondenceWidgetGridLayout.timerHeight
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func displayedGameCell(game: Game, boardSize: CGFloat) -> some View {
        if !entry.isPlaceholder,
           gamesToDisplay.count > 1,
           let destination = destination(for: game) {
            Link(destination: destination) {
                gameCell(game: game, boardSize: boardSize)
            }
            .buttonStyle(.plain)
        } else {
            gameCell(game: game, boardSize: boardSize)
        }
    }

    @ViewBuilder
    private func gameRow(
        row: Int,
        layout: CorrespondenceWidgetGridLayout,
        boardSize: CGFloat
    ) -> some View {
        let startIndex = row * layout.columns
        let endIndex = min(startIndex + layout.columns, gamesToDisplay.count)
        HStack(spacing: CorrespondenceWidgetGridLayout.columnSpacing) {
            ForEach(startIndex..<endIndex, id: \.self) { index in
                displayedGameCell(
                    game: gamesToDisplay[index],
                    boardSize: boardSize
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var boards: some View {
        GeometryReader { geometry in
            let layout = CorrespondenceWidgetGridLayout.make(
                family: resolvedFamily,
                gameCount: gamesToDisplay.count,
                availableSize: geometry.size
            )
            let boardSize = layout.boardSize(in: geometry.size)
            VStack(spacing: CorrespondenceWidgetGridLayout.rowSpacing) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    gameRow(row: row, layout: layout, boardSize: boardSize)
                }
            }
            .padding(CorrespondenceWidgetGridLayout.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var turnRailBackground: some View {
        let emphasis = CorrespondenceWidgetContentPolicy.railEmphasis(
            pendingCount: numberOfGamesOnUserTurn
        )
        if resolvedRenderingMode == .fullColor {
            if emphasis == .pending {
                Color(.systemIndigo)
            } else {
                Color(.systemGray)
            }
        } else if resolvedRenderingMode == .accented {
            Color.white
                .opacity(emphasis == .pending ? 0.75 : 0.3)
                .luminanceToAlpha()
        } else {
            Color.primary.opacity(emphasis == .pending ? 0.45 : 0.18)
        }
    }

    private var turnRailLabel: some View {
        GeometryReader { geometry in
            ViewThatFits(in: .horizontal) {
                Text(
                    "Your turn: \(numberOfGamesOnUserTurn)/\(entry.games.count)",
                    comment: "On Correspondence Games Widget"
                )
                .fixedSize()
                Text(verbatim: "\(numberOfGamesOnUserTurn)/\(entry.games.count)")
                    .fixedSize()
            }
            .font(.subheadline.bold())
            .foregroundStyle(
                resolvedRenderingMode == .fullColor ? Color.white : Color.primary
            )
            .lineLimit(1)
            .frame(width: geometry.size.height, height: geometry.size.width)
            .rotationEffect(.degrees(-90))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    var body: some View {
        let widgetContent = HStack(alignment: .center, spacing: 0) {
            if gamesToDisplay.count > 0 {
                boards
            } else {
                Text(entry.noGamesMessage ?? String(localized: "Failed to load your correspondence games.", comment: "Correspondence Games Widget error"))
                    .font(.subheadline)
                    .minimumScaleFactor(0.7)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            ZStack {
                turnRailBackground
                if entry.games.count > 0 {
                    turnRailLabel
                }
            }
            .frame(width: CorrespondenceWidgetGridLayout.turnRailWidth)
            .frame(maxHeight: .infinity)
        }
        .widgetURL(widgetDestination)
        .containerBackground(for: .widget) {
            Color(.secondarySystemBackground)
        }

        return applyingScreenshotReadinessIdentifier(to: widgetContent)
    }
}

@main
struct SurroundWidgets: Widget {
    let kind = SurroundWidgetContract.correspondenceGamesKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CorrespondenceGamesWidgetView(entry: entry)
                .transformEnvironment(\.locale) { locale in
                    if let localeIdentifier = entry.localeIdentifier {
                        locale = Locale(identifier: localeIdentifier)
                    }
                }
        }
        .configurationDisplayName(String(localized: "Correspondence Games", comment: "Correspondence Games Widget name"))
        .description(String(localized: "This Widget display a summary of your correspondence games on online-go.com.", comment: "Correspondence Games Widget description"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
        ])
        .contentMarginsDisabled()
    }
}

#if DEBUG
private func populatedWidgetPreviewEntry(gameCount: Int) -> CorrespondenceGamesEntry {
    let previewGames = [
        TestData.Ongoing19x19wBot1,
        TestData.Ongoing19x19wBot2,
        TestData.Ongoing19x19wBot3,
    ]
    return CorrespondenceGamesEntry(
        date: Date(),
        games: (0..<gameCount).map { previewGames[$0 % previewGames.count] },
        userID: 592684,
        usesStaticClock: true
    )
}

private func boardSizeWidgetPreviewEntry(
    localeIdentifier: String? = nil
) -> CorrespondenceGamesEntry {
    let thirteenByThirteen = Game(
        width: 13,
        height: 13,
        blackName: "Black",
        whiteName: "White",
        gameId: .OGS(13_013)
    )
    return CorrespondenceGamesEntry(
        date: Date(),
        games: [
            TestData.Resigned9x9Japanese,
            thirteenByThirteen,
            TestData.Ongoing19x19wBot1,
        ],
        userID: 592684,
        localeIdentifier: localeIdentifier,
        usesStaticClock: true
    )
}

private func emptyWidgetPreviewEntry() -> CorrespondenceGamesEntry {
    CorrespondenceGamesEntry(
        date: Date(),
        userID: 592684,
        noGamesMessage: String(
            localized: "You don't have any correspondence games at the moment."
        )
    )
}

#Preview("Correspondence games — Populated small", as: .systemSmall) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 1)
}

#Preview("Correspondence games — Populated medium", as: .systemMedium) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 2)
}

#Preview("Correspondence games — Single medium", as: .systemMedium) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 1)
}

#Preview("Correspondence games — Single large", as: .systemLarge) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 1)
}

#Preview("Correspondence games — Populated large", as: .systemLarge) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 4)
}

#Preview("Correspondence games — Populated extra large", as: .systemExtraLarge) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 6)
}

#Preview("Correspondence games — Single extra large", as: .systemExtraLarge) {
    SurroundWidgets()
} timeline: {
    populatedWidgetPreviewEntry(gameCount: 1)
}

#Preview("Correspondence games — Empty small", as: .systemSmall) {
    SurroundWidgets()
} timeline: {
    emptyWidgetPreviewEntry()
}

#Preview("Correspondence games — Empty large", as: .systemLarge) {
    SurroundWidgets()
} timeline: {
    emptyWidgetPreviewEntry()
}

#Preview("Correspondence games — Empty extra large", as: .systemExtraLarge) {
    SurroundWidgets()
} timeline: {
    emptyWidgetPreviewEntry()
}

#Preview("Correspondence games — Empty", as: .systemMedium) {
    SurroundWidgets()
} timeline: {
    CorrespondenceGamesEntry(
        date: Date(),
        userID: 592684,
        noGamesMessage: String(
            localized: "You don't have any correspondence games at the moment."
        )
    )
}


#Preview("Correspondence games — 9×9, 13×13, and 19×19") {
    CorrespondenceGamesWidgetView(
        entry: boardSizeWidgetPreviewEntry(),
        previewFamily: .systemLarge,
        previewRenderingMode: .fullColor
    )
        .frame(width: 338, height: 354)
}

#Preview("Correspondence games — Long locale, dark") {
    CorrespondenceGamesWidgetView(
        entry: boardSizeWidgetPreviewEntry(localeIdentifier: "de-DE"),
        previewFamily: .systemLarge,
        previewRenderingMode: .fullColor
    )
    .environment(\.colorScheme, .dark)
    .frame(width: 338, height: 354)
}

#Preview("Correspondence games — Accented") {
    CorrespondenceGamesWidgetView(
        entry: populatedWidgetPreviewEntry(gameCount: 2),
        previewFamily: .systemMedium,
        previewRenderingMode: .accented
    )
        .frame(width: 338, height: 158)
}

#Preview("Correspondence games — Vibrant") {
    CorrespondenceGamesWidgetView(
        entry: populatedWidgetPreviewEntry(gameCount: 2),
        previewFamily: .systemMedium,
        previewRenderingMode: .vibrant
    )
        .frame(width: 338, height: 158)
}

#Preview("Correspondence games — Placeholder", as: .systemMedium) {
    SurroundWidgets()
} timeline: {
    CorrespondenceGamesEntry(
        date: Date(),
        isPlaceholder: true
    )
}

#Preview("Correspondence games — Signed out", as: .systemMedium) {
    SurroundWidgets()
} timeline: {
    CorrespondenceGamesEntry(
        date: Date(),
        noGamesMessage: String(
            localized: "Sign in to your online-go.com account to see your games here."
        )
    )
}
#endif
