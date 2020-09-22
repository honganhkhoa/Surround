//
//  OGSService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation
import Combine
import Alamofire
import DictionaryCoding
import SocketIO
import WebKit

enum ServiceError: Error {
    case invalidJSON
    case notLoggedIn
}

class OGSService: ObservableObject {
    static var instances = [String: OGSService]()

    static func instance(forSceneWithID sceneID: String) -> OGSService {
        if let result = instances[sceneID] {
            return result
        } else {
            let result = OGSService()
            instances[sceneID] = result
            return result
        }
    }
    static func previewInstance(user: OGSUser? = nil, activeGames: [Game] = []) -> OGSService {
        let ogs = OGSService(forPreview: true)
        ogs.user = user
        ogs.isLoggedIn = user != nil
        
        for game in activeGames {
            ogs.activeGames[game.ogsID!] = game
        }
        ogs.sortActiveGames(activeGames: ogs.activeGames.values)

        return ogs
    }

    static let ogsRoot = "https://online-go.com"
    private var ogsRoot = OGSService.ogsRoot

    private let socketManager: SocketManager
    private let socket: SocketIOClient
    private var timerCancellable: AnyCancellable?
    private var pingCancellale: AnyCancellable?
    private var drift = 0.0
    private var latency = 0.0
    private(set) public var connectedGames = [Int: Game]()

    @Published private(set) public var activeGames = [Int: Game]()
    @Published private(set) public var unsortedActiveGames: [Game] = []
    @Published var isLoggedIn: Bool = false
    @Published var user: OGSUser? = nil
    @Published private(set) public var sortedActiveCorrespondenceGamesOnUserTurn: [Game] = []
    @Published private(set) public var sortedActiveCorrespondenceGamesNotOnUserTurn: [Game] = []
    @Published private(set) public var sortedActiveCorrespondenceGames: [Game] = []
    @Published private(set) public var liveGames: [Game] = []
    
    private var activeGamesSortingCancellable: AnyCancellable?
    
    private func sortActiveGames<T>(activeGames: T) where T: Sequence, T.Element == Game {
        var gamesOnUserTurn: [Game] = []
        var gamesOnOppornentTurn: [Game] = []
        var liveGames: [Game] = []
        for game in activeGames {
            if game.gameData?.timeControl.speed == .correspondence {
                if game.gameData?.phase == .stoneRemoval {
                    gamesOnUserTurn.append(game)
                } else {
                    if let clock = game.clock {
                        if clock.currentPlayerId == self.user?.id {
                            gamesOnUserTurn.append(game)
                        } else {
                            gamesOnOppornentTurn.append(game)
                        }
                    }
                }
            } else {
                liveGames.append(game)
            }
        }
        let thinkingTimeLeftIncreasing: (Game, Game) -> Bool =  { game1, game2 in
            if let clock1 = game1.clock, let clock2 = game2.clock {
                let time1 = game1.blackId == self.user?.id ? clock1.blackTime : clock1.whiteTime
                let time2 = game2.blackId == self.user?.id ? clock2.blackTime : clock2.whiteTime
                return time1.thinkingTimeLeft! <= time2.thinkingTimeLeft!
            }
            return false
        }
        self.sortedActiveCorrespondenceGamesOnUserTurn = gamesOnUserTurn.sorted(by: thinkingTimeLeftIncreasing)
        self.sortedActiveCorrespondenceGamesNotOnUserTurn = gamesOnOppornentTurn.sorted(by: thinkingTimeLeftIncreasing)
        self.sortedActiveCorrespondenceGames = self.sortedActiveCorrespondenceGamesOnUserTurn + self.sortedActiveCorrespondenceGamesNotOnUserTurn
        self.liveGames = liveGames
    }
    
    private init(forPreview: Bool = false) {
        socketManager = SocketManager(socketURL: URL(string: ogsRoot)!, config: [
            .log(false), .compress, .secure(true), .forceWebsockets(true), .reconnects(true), .reconnectWait(750), .reconnectWaitMax(10000)
        ])
        socket = socketManager.defaultSocket
        
        if forPreview {
            return
        }
        
        self.setUpSocketEventListeners()
        
        timerCancellable = TimeUtilities.shared.timer.sink { [self] _ in
            for game in connectedGames.values {
                if game.gameData?.outcome == nil && !(game.gameData?.pauseControl?.isPaused() ?? false) {
                    if let timeControlSystem = game.gameData?.timeControl.system {
                        game.clock?.calculateTimeLeft(with: timeControlSystem, serverTimeOffset: drift - latency, pauseControl: game.gameData?.pauseControl)
                    }
                }
            }
        }
        
        activeGamesSortingCancellable = self.$activeGames.collect(.byTime(DispatchQueue.main, 1.0)).sink(receiveValue: { activeGamesValues in
            if let activeGames = activeGamesValues.last {
                self.sortActiveGames(activeGames: activeGames.values)
            }
        })
        
        self.checkLoginStatus()
        self.ensureConnect()
        if isLoggedIn {
            self.updateUIConfig()
            self.loadOverview()
        }
    }
    
    private func setUpSocketEventListeners() {
        socket.onAny { event in
            if event.event != "active-bots" {
                print(event)
            }
        }
                
        socket.on(clientEvent: .connect) { [self] _, _ in
            pingCancellale = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { _ in
                socket.emit("net/ping", ["client": Date().timeIntervalSince1970 * 1000, "drift": drift, "latency": latency])
            }
            self.authenticateSocketIfLoggedIn()

            let previouslyConnectedGames = Array(connectedGames.values)
            connectedGames = [:]
            for game in previouslyConnectedGames {
                if case .OGS(let ogsID) = game.ID {
                    self.socket.off("game/\(ogsID)/gamedata")
                    self.socket.off("game/\(ogsID)/move")
                    self.socket.off("game/\(ogsID)/clock")
                    self.connect(to: game)
                }
            }
        }
        
        socket.on("net/pong") { [self] data, ack in
            if let data = data[0] as? [String:Double] {
                let now = Date().timeIntervalSince1970 * 1000
                latency = now - data["client"]!
                drift = (now - latency / 2) - data["server"]!
                print(drift, latency)
            }
        }
        
        socket.on("active_game") { gameData, ack in
            if let activeGameData = gameData[0] as? [String: Any] {
                self.updateActiveGames(withShortGameData: activeGameData)
            }
        }
    }
    
    var ogsUIConfig: OGSUIConfig? {
        get {
            return UserDefaults.standard[.ogsUIConfig]
        }
        set {
            UserDefaults.standard[.ogsUIConfig] = newValue
            if newValue == nil {
                Session.default.sessionConfiguration.httpCookieStorage?.removeCookies(since: Date.distantPast)
                for game in activeGames.values {
                    self.disconnect(from: game)
                }
                activeGames.removeAll()
            }
            checkLoginStatus()
        }
    }
    
    var uiConfigCancellable: AnyCancellable?
    func updateUIConfig() {
        if uiConfigCancellable == nil {
            uiConfigCancellable = self.fetchUIConfig().sink(
                receiveCompletion: { _ in },
                receiveValue: { uiConfig in
                    self.ogsUIConfig = uiConfig
                    self.uiConfigCancellable = nil
                })
        }
    }
    
    func login(username: String, password: String) -> AnyPublisher<OGSUIConfig, Error> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return Future<Data, Error> { promise in
            Session.default.sessionConfiguration.httpCookieStorage?.removeCookies(since: Date.distantPast)
            AF.request("\(self.ogsRoot)/api/v0/login",
                method: .post,
                parameters: ["username": username, "password": password],
                encoder: JSONParameterEncoder.default
            ).responseData { response in
                switch response.result {
                case .success:
                    promise(.success(response.value!))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }.decode(type: OGSUIConfig.self, decoder: jsonDecoder).receive(on: RunLoop.main).map({ config in
            self.ogsUIConfig = config
            self.loadOverview()
            self.authenticateSocketIfLoggedIn()
            return config
        }).eraseToAnyPublisher()
    }
    
    func logout() {
        self.ogsUIConfig = nil
    }
    
    func fetchUIConfig() -> AnyPublisher<OGSUIConfig, Error> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return Future<Data, Error> { promise in
            AF.request("\(self.ogsRoot)/api/v1/ui/config").responseData { response in
                switch response.result {
                case .success:
                    promise(.success(response.value!))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }.decode(type: OGSUIConfig.self, decoder: jsonDecoder).receive(on: RunLoop.main).map({ config in
            self.ogsUIConfig = config
            return config
        }).eraseToAnyPublisher()
    }
    
    private func checkLoginStatus() {
        isLoggedIn = {
            if let ogsUIConfig = self.ogsUIConfig {
                if let csrfToken = ogsUIConfig.csrfToken {
                    if let cookies = Session.default.sessionConfiguration.httpCookieStorage?.cookies(for: URL(string: ogsRoot)!) {
                        for cookie in cookies {
                            if cookie.name == "csrftoken" {
                                return true
                            }
                        }
                    }
                    
                    if let domain = URL(string: ogsRoot)?.host {
                        if let cookie = HTTPCookie(properties: [
                            .name: "csrftoken",
                            .value: csrfToken,
                            .domain: domain,
                            .path: "/"
                        ]) {
                            Session.default.sessionConfiguration.httpCookieStorage?.setCookie(cookie)
                            return true
                        }
                    }
                    return false
                } else {
                    return false
                }
            } else {
                return false
            }
        }()
        if isLoggedIn {
            user = self.ogsUIConfig?.user
        } else {
            user = nil
        }
    }
    
    func authenticateSocketIfLoggedIn() {
        guard socket.status == .connected else {
            return
        }
      
        guard self.isLoggedIn, let uiconfig = self.ogsUIConfig else {
            return
        }
        
        socket.emit("notification/connect", [
            "player_id": uiconfig.user.id,
            "auth": uiconfig.notificationAuth ?? ""
        ])
        socket.emit("authenticate", [
            "auth": uiconfig.chatAuth ?? "",
            "jwt": uiconfig.userJwt ?? "",
            "player_id": uiconfig.user.id,
            "username": uiconfig.user.username
        ])
    }

    
    func loadOverview() {
        guard isLoggedIn else {
            return
        }
        
        AF.request("\(self.ogsRoot)/api/v1/ui/overview").responseJSON { response in
            switch response.result {
            case .success:
                if let data = response.value as? [String: Any] {
                    if let activeGames = data["active_games"] as? [[String: Any]] {
                        var newActiveGames = [Int:Game]()
                        var unsortedActiveGames = [Game]()
                        for gameData in activeGames {
                            if let gameId = gameData["id"] as? Int {
                                if let game = self.activeGames[gameId] {
                                    newActiveGames[gameId] = game
                                    unsortedActiveGames.append(game)
                                } else {
                                    if let newGame = self.createGame(fromShortGameData: gameData) {
                                        newActiveGames[gameId] = newGame
                                        unsortedActiveGames.append(newGame)
                                        self.connect(to: newGame)
                                    }
                                }
                            }
                        }
                        self.unsortedActiveGames = unsortedActiveGames
                        self.activeGames = newActiveGames
                    }
                }
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func getGameDetailAndConnect(gameID: Int) -> AnyPublisher<Game, Error> {
        return Future<Game, Error> { promise in
            AF.request("\(self.ogsRoot)/api/v1/games/\(gameID)").responseJSON { response in
                switch response.result {
                case .success:
                    if let data = response.value as? [String: Any] {
                        if let gameData = data["gamedata"] as? [String: Any] {
                            let decoder = DictionaryDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            do {
                                let ogsGame = try decoder.decode(OGSGame.self, from: gameData)
                                if let game = self.connectedGames[ogsGame.gameId] {
                                    game.ogsRawData = data
                                    promise(.success(game))
                                } else {
                                    let game = Game(ogsGame: ogsGame)
                                    game.ogsRawData = data
                                    self.connect(to: game)
                                    promise(.success(game))
                                }
                                return
                            } catch {
                                promise(.failure(error))
                            }
                        }
                    }
                    promise(.failure(ServiceError.invalidJSON))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    var gameDetailCancellable = [Int: AnyCancellable]()
    func updateDetailsOfConnectedGame(game: Game) {
        if let gameId = game.ogsID {
            if connectedGames[gameId] != nil {
                if gameDetailCancellable[gameId] == nil {
                    gameDetailCancellable[gameId] = self.getGameDetailAndConnect(gameID: gameId).sink(
                        receiveCompletion: { _ in
                            self.gameDetailCancellable.removeValue(forKey: gameId)
                        },
                        receiveValue: { _ in })
                }
            }
        }
    }
    
    func updateActiveGames(withShortGameData gameData: [String: Any]) {
        if let gameId = gameData["id"] as? Int {
            if let game = self.activeGames[gameId] {
                // Trigger $activeGames publisher
                self.activeGames[gameId] = game
            } else {
                if let game = self.createGame(fromShortGameData: gameData) {
                    self.activeGames[gameId] = game
                    self.connect(to: game)
                }
            }
        }
    }
        
    func ensureConnect() {
        guard socket.status != .connected && socket.status != .connecting else {
            return
        }
        
        socket.connect()
    }
    
    func disconnect(from game: Game) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }

        self.socket.emit("game/disconnect", ["game_id": ogsID])
        self.socket.off("game/\(ogsID)/gamedata")
        self.socket.off("game/\(ogsID)/move")
        self.socket.off("game/\(ogsID)/clock")
        self.socket.off("game/\(ogsID)/undo_accepted")
        self.socket.off("game/\(ogsID)/undo_requested")
        self.socket.off("game/\(ogsID)/removed_stones")
        
        connectedGames[ogsID] = nil
    }
    
    func connect(to game: Game, withChat: Bool = false) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }
        
        guard connectedGames[ogsID] == nil else {
            return
        }

        guard self.socket.status == .connected else {
            socket.once(clientEvent: .connect, callback: {_,_ in
                self.connect(to: game, withChat: withChat)
            })
            return
        }

        connectedGames[ogsID] = game
        self.socket.emit("game/connect", ["game_id": ogsID, "player_id": self.ogsUIConfig?.user.id ?? 0, "chat": withChat ? true : 0])

        self.socket.on("game/\(ogsID)/gamedata") { gamedata, ack in
            if let gameId = (gamedata[0] as? [String: Any] ?? [:])["game_id"] as? Int, let connectedGame = self.connectedGames[gameId] {
                let decoder = DictionaryDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do {
    //                print(gamedata[0])
                    let ogsGame = try decoder.decode(OGSGame.self, from: gamedata[0] as? [String: Any] ?? [:])
                    connectedGame.gameData = ogsGame
                    if ogsGame.outcome != nil {
                        self.disconnect(from: connectedGame)
                    }
    //                print(ogsGame)
                } catch {
                    print(gameId, error)
                }
            }
        }
        self.socket.on("game/\(ogsID)/move") { movedata, ack in
            if let movedata = movedata[0] as? [String: Any] {
                if let move = movedata["move"] as? [Int], let gameId = movedata["game_id"] as? Int, let connectedGame = self.connectedGames[gameId] {
                    do {
                        try connectedGame.makeMove(move: move[0] == -1 ? .pass : .placeStone(move[1], move[0]))
                    } catch {
                        print(gameId, movedata, error)
                    }
                }
            }
        }
        self.socket.on("game/\(ogsID)/clock") { clockdata, ack in
            if let clockdata = clockdata[0] as? [String: Any] {
                if let gameId = clockdata["game_id"] as? Int, let connectedGame = self.connectedGames[gameId] {
                    let decoder = DictionaryDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    do {
                        connectedGame.clock = try decoder.decode(Clock.self, from: clockdata)
                        if let timeControlSystem = connectedGame.gameData?.timeControl.system {
                            connectedGame.clock?.calculateTimeLeft(with: timeControlSystem, serverTimeOffset: self.drift - self.latency, pauseControl: connectedGame.gameData?.pauseControl)
                        }
                        if let _ = self.activeGames[gameId] {
                            // Trigger active games publisher
                            self.activeGames[gameId] = connectedGame
                        }
                    } catch {
                        print(gameId, error)
                        print(clockdata)
                    }
                }
            }
        }
        self.socket.on("game/\(ogsID)/undo_accepted") { undoData, ack in
            if let moveNumber = undoData[0] as? Int {
                if let connectedGame = self.connectedGames[ogsID] {
                    connectedGame.undoMove(numbered: moveNumber)
                }
            }
        }
        self.socket.on("game/\(ogsID)/undo_requested") { undoData, ack in
            if let moveNumber = undoData[0] as? Int {
                if let connectedGame = self.connectedGames[ogsID] {
                    connectedGame.undoRequested = moveNumber
                }
            }
        }
        self.socket.on("game/\(ogsID)/removed_stones") { removedStoneData, ack in
            if let removedStoneData = removedStoneData[0] as? [String: Any] {
                if let removedString = removedStoneData["all_removed"] as? String {
                    if let connectedGame = self.connectedGames[ogsID] {
                        connectedGame.setRemovedStones(removedString: removedString)
                    }
                }
            }
        }
    }
    
    func createGame(fromShortGameData gameData: [String: Any]) -> Game? {
        if let black = gameData["black"] as? [String: Any],
                let white = gameData["white"] as? [String: Any],
                let width = gameData["width"] as? Int,
                let height = gameData["height"] as? Int,
                let gameId = gameData["id"] as? Int {
            let game = Game(
                width: width,
                height: height,
                blackName: black["username"] as? String ?? "",
                whiteName: white["username"] as? String ?? "",
                gameId: .OGS(gameId)
            )
            return game
        }
        return nil
    }
    
    func submitMove(move: Move, forGame game: Game) -> AnyPublisher<Void, Error> {
        guard let ogsUIConfig = self.ogsUIConfig else {
            return Fail(error: ServiceError.notLoggedIn).eraseToAnyPublisher()
        }
        
        return Future<Void, Error> { promise in
            if let gameId = game.gameData?.gameId {
                let userId = ogsUIConfig.user.id
                self.socket.emitWithAck("game/move", ["game_id": gameId, "player_id": userId, "move": move.toOGSString()]).timingOut(after: 3) { _ in
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func requestUndo(game: Game) {
        if let ogsID = game.ogsID, let user = self.user {
            self.socket.emit("game/undo/request", ["game_id": ogsID, "player_id": user.id, "move_number": game.currentPosition.lastMoveNumber])
        }
    }
    
    func acceptUndo(game: Game, moveNumber: Int) {
        if let ogsID = game.ogsID, let user = self.user {
            self.socket.emit("game/undo/accept", ["game_id": ogsID, "player_id": user.id, "move_number": moveNumber])
        }
    }
    
    func resign(game: Game) {
        if let ogsID = game.ogsID, let user = self.user {
            self.socket.emit("game/resign", ["game_id": ogsID, "player_id": user.id])
        }
    }
    
    func fetchAndConnectToPublicGames() -> AnyPublisher<[Game], Error> {
        
        func queryPublicGames(promise: @escaping Future<[Game], Error>.Promise) {
            self.socket.emitWithAck("gamelist/query", ["list": "live", "sort_by": "rank", "from": 0, "limit": 18]).timingOut(after: 3) { data in
    //            print(data)
                if data.count > 0 {
                    if let gamesData = (data[0] as? [String: Any] ?? [:])["results"] as? [[String: Any]] {
                        var results = [Game]()
                        for gameData in gamesData {
                            if let game = self.createGame(fromShortGameData: gameData) {
                                if let connectedGame = self.connectedGames[gameData["id"] as? Int ?? -1] {
                                    results.append(connectedGame)
                                } else {
                                    self.connect(to: game)
                                    results.append(game)
                                }
                            }
                        }
                        promise(.success(results))
                        return
                    }
                }
            }
        }
        
        return Future<[Game], Error> { promise in
            if self.socket.status != .connected {
                self.socket.once(clientEvent: .connect) { _, _ in
                    queryPublicGames(promise: promise)
                }
            } else {
                queryPublicGames(promise: promise)
            }
        }.eraseToAnyPublisher()
    }
    
    func isOGSDomain(url: URL) -> Bool {
        return url.absoluteString.lowercased().starts(with: ogsRoot)
    }
    
    func isOGSDomain(cookie: HTTPCookie) -> Bool {
        return cookie.domain == URL(string: ogsRoot)!.host
    }
    
    func thirdPartyLogin(cookieStore: WKHTTPCookieStore) -> AnyPublisher<OGSUIConfig, Error> {
        return Future<[HTTPCookie], Error> { promise in
            cookieStore.getAllCookies { cookies in
                promise(.success(cookies))
            }
        }.map { cookies -> AnyPublisher<OGSUIConfig, Error> in
            let host = URL(string: self.ogsRoot)!.host
            for cookie in cookies {
                if cookie.domain == host {
                    Session.default.sessionConfiguration.httpCookieStorage?.setCookie(cookie)
                }
            }
            return self.fetchUIConfig()
        }
        .switchToLatest()
        .map { config in
            self.loadOverview()
            self.authenticateSocketIfLoggedIn()
            return config
        }
        .eraseToAnyPublisher()
    }
    
    static func thirdPartyLoginURL(type: ThirdPartyLoginWebView.ThirdParty) -> URL {
        switch type {
        case .facebook:
            return URL(string: "\(OGSService.ogsRoot)/login/facebook/")!
        case .google:
            return URL(string: "\(OGSService.ogsRoot)/login/google-oauth2/")!
        case .twitter:
            return URL(string: "\(OGSService.ogsRoot)/login/twitter/")!
        }
    }
}
