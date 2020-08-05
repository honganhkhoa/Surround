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

enum ServiceError: Error {
    case invalidJSON
    case notLoggedIn
}

class OGSService {
    static let shared = OGSService()
    private let ogsRoot = "https://online-go.com"
    var ogsUIConfig: OGSUIConfig? {
        get {
            return UserDefaults.standard[.ogsUIConfig]
        }
        set {
            UserDefaults.standard[.ogsUIConfig] = newValue
        }
    }
    
    func login(username: String, password: String) -> AnyPublisher<OGSUIConfig, Error> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return Future<Data, Error> { promise in
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
            UserDefaults.standard[.ogsUIConfig] = config
            return config
        }).eraseToAnyPublisher()
    }
    
    func logout() {
        UserDefaults.standard[.ogsUIConfig] = nil
        Session.default.sessionConfiguration.httpCookieStorage?.removeCookies(since: Date.distantPast)
    }
    
    func isLoggedIn() -> Bool {
        if UserDefaults.standard[.ogsUIConfig] == nil {
            return false
        }
        return true
    }
    
    func loadOverview() {
        AF.request("\(self.ogsRoot)/api/v1/ui/overview").responseJSON { response in
            switch response.result {
            case .success:
                if let data = response.value as? [String: Any] {
                    if let activeGames = data["active_games"] as? [[String: Any]] {
                        for game in activeGames {
                            OGSWebSocket.shared.updateActiveGames(withShortGameData: game)
                        }
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
                                if let game = OGSWebSocket.shared.connectedGames[ogsGame.gameId] {
                                    game.ogsRawData = data
                                    promise(.success(game))
                                } else {
                                    let game = Game(ogsGame: ogsGame)
                                    game.ogsRawData = data
                                    OGSWebSocket.shared.connect(to: game)
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
}
