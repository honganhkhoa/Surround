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

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CorrespondenceGamesEntry {
        CorrespondenceGamesEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CorrespondenceGamesEntry) -> ()) {
        let entry = CorrespondenceGamesEntry(date: Date())
        completion(entry)
    }
    
    func parseAndSortActiveGames(fromData activeGamesData: [[String: Any]]) -> [Game] {
        var result = [Game]()
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for gameData in activeGamesData {
            if let jsonData = gameData["json"] as? [String: Any] {
                if let ogsGame = try? decoder.decode(OGSGame.self, from: jsonData) {
                    let game = Game(ogsGame: ogsGame)
                    game.clock?.calculateTimeLeft(with: ogsGame.timeControl.system, pauseControl: game.pauseControl)
                    result.append(game)
                }
            }
        }
        
        let userId = userDefaults[.ogsUIConfig]?.user.id ?? -1
        let isGamesInIncreasingOrder: (Game, Game) -> Bool = { game1, game2 in
            if let clock1 = game1.clock, let clock2 = game2.clock {
                let isGame1OnUserTurn = clock1.currentPlayerId == userId
                let isGame2OnUserTurn = clock2.currentPlayerId == userId
                if isGame1OnUserTurn != isGame2OnUserTurn {
                    return isGame1OnUserTurn
                }

                let time1 = game1.blackId == userId ? clock1.blackTime : clock1.whiteTime
                let time2 = game2.blackId == userId ? clock2.blackTime : clock2.whiteTime
                let timeLeft1 = time1.thinkingTimeLeft ?? .infinity
                let timeLeft2 = time2.thinkingTimeLeft ?? .infinity
                return timeLeft1 <= timeLeft2
            }
            return false
        }
        
        return result.sorted(by: isGamesInIncreasingOrder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let nextReloadDate = currentDate.advanced(by: 15 * 60)

        if let csrfToken = userDefaults[.ogsUIConfig]?.csrfToken, let sessionId = userDefaults[.ogsSessionId] {
            let ogsDomain = URL(string: OGSService.ogsRoot)!.host!
            let csrfCookie = HTTPCookie(properties: [.name: "csrftoken", .value: csrfToken, .domain: ogsDomain, .path: "/"])
            let sessionIdCookie = HTTPCookie(properties: [.name: "sessionid", .value: sessionId, .domain: ogsDomain, .path: "/"])
            if let csrfCookie = csrfCookie, let sessionIdCookie = sessionIdCookie {
                Session.default.sessionConfiguration.httpCookieStorage?.setCookie(csrfCookie)
                Session.default.sessionConfiguration.httpCookieStorage?.setCookie(sessionIdCookie)
                AF.request("\(OGSService.ogsRoot)/api/v1/ui/overview").responseJSON { response in
                    let currentDate = Date()
                    let nextReloadDate = currentDate.advanced(by: 15 * 60)
                    switch response.result {
                    case .success:
                        if let data = response.value as? [String: Any] {
                            if let activeGames = data["active_games"] as? [[String: Any]] {
                                let games = parseAndSortActiveGames(fromData: activeGames)
                                let entry = CorrespondenceGamesEntry(
                                    date: currentDate,
                                    games: games,
                                    widgetFamily: context.family,
                                    noGamesMessage: "You don't have any correspondence games at the moment."
                                )
                                completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                                return
                            }
                        }
                    case .failure:
                        break
                    }
                    
                    let entry = CorrespondenceGamesEntry(date: currentDate, noGamesMessage: "Failed to load your correspondence games.")
                    completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
                }
            }
        } else {
            let entry = CorrespondenceGamesEntry(date: currentDate, noGamesMessage: "Sign in to your online-go.com account to see your correspondence games here.")
            completion(Timeline(entries: [entry], policy: .after(nextReloadDate)))
        }
    }
}

struct CorrespondenceGamesEntry: TimelineEntry {
    var date: Date
    var games: [Game] = []
    var widgetFamily: WidgetFamily = .systemSmall
    var noGamesMessage: String?
    var debugMessage: String?
}

struct CorrespondenceGamesWidgetView : View {
    var entry: Provider.Entry

    var gamesCount: Int {
        switch entry.widgetFamily {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        case .systemLarge:
            return 4
        @unknown default:
            return 1
        }
    }
    
    func timer(game: Game) -> some View {
        let userId = userDefaults[.ogsUIConfig]?.user.id
        if let clock = game.clock, let timeControlSystem = game.gameData?.timeControl.system {
            let thinkingTime = clock.blackPlayerId == userId ? clock.blackTime : clock.whiteTime
            var timeLeft = thinkingTime.thinkingTimeLeft
            var auxiliaryLabel = ""
            switch timeControlSystem {
            case .ByoYomi:
                if thinkingTime.thinkingTime! > 0 {
                    auxiliaryLabel = " (\(thinkingTime.periods!))"
                } else {
                    timeLeft = thinkingTime.periodTimeLeft
                    if thinkingTime.periodsLeft! > 1 {
                        auxiliaryLabel = " (\(thinkingTime.periodsLeft!))"
                    } else {
                        auxiliaryLabel = " (SD)"
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
                    if (game.pauseControl?.isPaused() ?? false) || game.clock?.currentPlayerId != userId {
                        Text(timeString(timeLeft: timeLeft))
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(Date().addingTimeInterval(timeLeft), style: .timer)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if auxiliaryLabel == " (SD)" {
                    Text(auxiliaryLabel).foregroundColor(.red)
                } else {
                    Text(auxiliaryLabel)
                }
            }.font(Font.caption2.monospacedDigit().bold()))
        }
        return AnyView(EmptyView())
    }
    
    func gameCell(game: Game, boardSize: CGFloat) -> some View {
        let userId = userDefaults[.ogsUIConfig]?.user.id

        return VStack(spacing: 0) {
            ZStack {
                if game.clock?.currentPlayerId == userId || true {
                    Color(.systemTeal)
                        .frame(width: boardSize + 6, height: boardSize + 6)
                        .cornerRadius(10)
                }
                BoardView(boardPosition: game.currentPosition, cornerRadius: 10)
                    .frame(width: boardSize, height: boardSize)
                    .padding(3)
            }
            HStack {
                timer(game: game)
                if let userId = userId {
                    if let pauseReason = game.pauseControl?.pauseReason(playerId: userId) {
                        Text(pauseReason).font(Font.caption2.bold())
                    }
                }
            }.frame(width: boardSize)
        }
    }
    
    var boards: some View {
        let games = entry.games[0..<min(self.gamesCount, entry.games.count)]

        return GeometryReader { geometry -> AnyView in
            var boardMaxHeight = geometry.size.height - 15
            if entry.widgetFamily == .systemLarge && games.count > 1 {
                boardMaxHeight = (boardMaxHeight - 20) / 2
            }
            var boardMaxWidth = geometry.size.width - 20
            if entry.widgetFamily != .systemSmall {
                boardMaxWidth = (boardMaxWidth - 20) / 2
            }
            let boardSize = min(boardMaxWidth, boardMaxHeight - 15)
            return AnyView(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        gameCell(game: games[0], boardSize: boardSize)
                        Spacer(minLength: 0)
                        if games.count > 1 {
                            gameCell(game: games[1], boardSize: boardSize)
                            Spacer(minLength: 0)
                        }
                    }
                    Spacer(minLength: 0)
                    if games.count > 2 {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            gameCell(game: games[2], boardSize: boardSize)
                            Spacer(minLength: 0)
                            if games.count > 3 {
                                gameCell(game: games[3], boardSize: boardSize)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            )
        }
    }
    
    var body: some View {
        let games = entry.games[0..<min(self.gamesCount, entry.games.count)]
        let userId = userDefaults[.ogsUIConfig]?.user.id
        var numberOfGamesOnUserTurn = 0
        for game in entry.games {
            if game.clock?.currentPlayerId == userId {
                numberOfGamesOnUserTurn += 1
            }
        }

        return ZStack {
            Color(UIColor.systemGray4)
            if games.count > 0 {
                HStack(alignment: .center, spacing: 0) {
                    boards
                        .padding(.vertical, 5)
                    ZStack {
                        Color(.systemIndigo)
                            .frame(width: 25)
                        Text("Your turn: \(numberOfGamesOnUserTurn)/\(entry.games.count)")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                    }
                    .frame(width: 25)
                }
            } else {
                Text(entry.noGamesMessage ?? "Failed to load your correspondence games.")
                    .font(.subheadline)
                    .padding()
            }
        }
    }
}

@main
struct SurroundWidgets: Widget {
    let kind: String = "com.honganhkhoa.Surround.CorrespondenceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CorrespondenceGamesWidgetView(entry: entry)
        }
        .configurationDisplayName("Correspondence Games Widget")
        .description("This Widget display a summary of your correspondence games on online-go.com.")
    }
}

struct SurroundWidgets_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            ForEach(0..<3) { familyId in
                let family = [
                    0: WidgetFamily.systemSmall,
                    1: WidgetFamily.systemMedium,
                    2: WidgetFamily.systemLarge
                ][familyId]!
                CorrespondenceGamesWidgetView(
                    entry: CorrespondenceGamesEntry(
                        date: Date(),
                        games: [
                            TestData.Ongoing19x19wBot1,
                            TestData.Ongoing19x19wBot2,
                            TestData.Ongoing19x19wBot3
                        ],
                        widgetFamily: family
                    )
                )
                .previewContext(WidgetPreviewContext(family: family))
            }
        }
    }
}
