//
//  OGSWebSocket.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/23/20.
//

import Foundation
import Combine
import SocketIO
import DictionaryCoding

enum OGSWebSocketError: Error {
    case notConnected
    case notLoggedIn
}

class OGSWebSocket {
    static let shared = OGSWebSocket()
    let manager: SocketManager
    let socket: SocketIOClient
    var timerCancellable: AnyCancellable?
    var pingCancellale: AnyCancellable?
    var drift = 0.0
    var latency = 0.0
    private(set) public var connectedGames = [Int: Game]()

    private(set) public var activeGames = OGSActiveGames()
    
    init() {
        manager = SocketManager(socketURL: URL(string: "https://online-go.com")!, config: [
            .log(false), .compress, .secure(true), .forceWebsockets(true), .reconnects(true), .reconnectWait(750), .reconnectWaitMax(10000)
        ])
        socket = manager.defaultSocket
        socket.onAny { event in
            if event.event != "active-bots" {
                print(event)
            }
        }
                
        socket.on(clientEvent: .connect) { [self] _, _ in
            pingCancellale = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { _ in
                socket.emit("net/ping", ["client": Date().timeIntervalSince1970 * 1000, "drift": drift, "latency": latency])
            }
            self.authenticateIfLoggedIn()

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
        
        timerCancellable = TimeUtilities.shared.timer.sink { [self] _ in
            for game in connectedGames.values {
                if game.gameData?.outcome == nil && !(game.gameData?.pauseControl?.isPaused() ?? false) {
                    if let timeControlSystem = game.gameData?.timeControl.system {
                        game.clock?.calculateTimeLeft(with: timeControlSystem, serverTimeOffset: drift - latency)
                    }
                }
            }
        }
    }
    
    func updateActiveGames(withShortGameData gameData: [String: Any]) {
        if let gameId = gameData["id"] as? Int {
            if self.activeGames[gameId] == nil {
                if let game = self.createGame(fromShortGameData: gameData) {
                    self.activeGames[gameId] = game
                    self.connect(to: game)
                }
            }
        }
    }
    
    func authenticateIfLoggedIn() {
        guard socket.status == .connected else {
            return
        }
      
        guard OGSService.shared.isLoggedIn(), let uiconfig = UserDefaults.standard[.ogsUIConfig] else {
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
        self.socket.emit("game/connect", ["game_id": ogsID, "player_id": UserDefaults.standard[.ogsUIConfig]?.user.id ?? 0, "chat": withChat ? true : 0])
        self.socket.on("game/\(ogsID)/gamedata") { gamedata, ack in
            if let gameId = (gamedata[0] as? [String: Any] ?? [:])["game_id"] as? Int, let connectedGame = self.connectedGames[gameId] {
                let decoder = DictionaryDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do {
    //                print(gamedata[0])
                    let ogsGame = try decoder.decode(OGSGame.self, from: gamedata[0] as? [String: Any] ?? [:])
                    connectedGame.gameData = ogsGame
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
        guard let ogsUIConfig = UserDefaults.standard[.ogsUIConfig] else {
            return Fail(error: OGSWebSocketError.notLoggedIn).eraseToAnyPublisher()
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
        if let ogsID = game.ogsID, let ogsUIConfig = OGSService.shared.ogsUIConfig {
            self.socket.emit("game/undo/request", ["game_id": ogsID, "player_id": ogsUIConfig.user.id, "move_number": game.currentPosition.lastMoveNumber])
        }
    }
    
    func acceptUndo(game: Game, moveNumber: Int) {
        if let ogsID = game.ogsID, let ogsUIConfig = OGSService.shared.ogsUIConfig {
            self.socket.emit("game/undo/accept", ["game_id": ogsID, "player_id": ogsUIConfig.user.id, "move_number": moveNumber])
        }
    }
    
    func resign(game: Game) {
        if let ogsID = game.ogsID, let ogsUIConfig = OGSService.shared.ogsUIConfig {
            self.socket.emit("game/resign", ["game_id": ogsID, "player_id": ogsUIConfig.user.id])
        }
    }
    
    func getPublicGamesAndConnect() -> AnyPublisher<[Game], Error> {
        
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
}
