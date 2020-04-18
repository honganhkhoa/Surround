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

class OGSWebSocket {
    static let shared = OGSWebSocket()
    let manager: SocketManager
    let socket: SocketIOClient
    var connectedGames = [Int: Game]()
    var timerCancellable: AnyCancellable?
    
    init() {
        manager = SocketManager(socketURL: URL(string: "https://online-go.com")!, config: [
            .log(false), .compress, .secure(true), .forceWebsockets(true), .reconnects(true), .reconnectWait(750), .reconnectWaitMax(10000)
        ])
        socket = manager.defaultSocket
        socket.onAny { event in
            print(event.event)
            print(event.items ?? [])
        }
        
        timerCancellable = TimeUtilities.shared.timer.sink { _ in
            for game in self.connectedGames.values {
                if game.gameData?.outcome == nil && !(game.gameData?.pauseControl?.isPaused() ?? false) {
                    if let timeControlSystem = game.gameData?.timeControl.system {
                        game.clock?.calculateTimeLeft(with: timeControlSystem)
                    }
                }
            }
        }
    }
    
    func connect() {
        socket.connect()
    }
    
    func disconnect(from game: Game) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }

        self.socket.emit("game/disconnect", ["game_id": ogsID])
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
    }
    
    func getPublicGames(callback: @escaping ([Game]) -> Void) {
        guard self.socket.status == .connected else {
            socket.once(clientEvent: .connect, callback: {_,_ in
                self.getPublicGames(callback: callback)
            })
            return
        }
        
        self.socket.emitWithAck("gamelist/query", ["list": "live", "sort_by": "rank", "from": 0, "limit": 9]).timingOut(after: 3) { data in
//            print(data)
            if data.count > 0 {
                if let gamesData = (data[0] as? [String: Any] ?? [:])["results"] as? [[String: Any]] {
                    var results = [Game]()
                    for gameData in gamesData {
                        if let black = gameData["black"] as? [String: Any],
                                let white = gameData["white"] as? [String: Any],
                                let boardSize = gameData["width"] as? Int,
                                let gameId = gameData["id"] as? Int {
                            let game = Game(
                                boardSize: boardSize,
                                blackName: black["username"] as? String ?? "",
                                whiteName: white["username"] as? String ?? "",
                                gameId: .OGS(gameId)
                            )
                            results.append(game)
                        }
                    }
                    callback(results)
                    return
                }
            }
            callback([])
        }
    }
}
