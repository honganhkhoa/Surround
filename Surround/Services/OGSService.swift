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
import WebKit
import WidgetKit

enum OGSServiceError: Error {
    case invalidJSON
    case notLoggedIn
    case loginError(error: String)
}

extension OGSServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Cannot decode server's response"
        case .notLoggedIn:
            return "Login required"
        case .loginError(let error):
            return error
        }
    }
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
    static func previewInstance(
        user: OGSUser? = nil,
        activeGames: [Game] = [],
        publicGames: [Game] = [],
        friends: [OGSUser] = [],
        socketStatus: OGSWebsocketStatus = .connected,
        eligibleOpenChallenges: [OGSChallenge] = [],
        openChallengesSent: [OGSChallenge] = [],
        challengesReceived: [OGSChallenge] = [],
        automatchEntries: [OGSAutomatchEntry] = [],
        cachedUsers: [OGSUser] = []
    ) -> OGSService {
        let ogs = OGSService(forPreview: true)
        ogs.user = user
        ogs.isLoggedIn = user != nil
        
        for game in activeGames {
            ogs.activeGames[game.ogsID!] = game
        }
        ogs.sortActiveGames(activeGames: ogs.activeGames.values)
        ogs.sortedPublicGames = publicGames
        
        ogs.friends = friends
        ogs.socketStatus = socketStatus
        
        for challenge in eligibleOpenChallenges {
            ogs.eligibleOpenChallengeById[challenge.id] = challenge
        }
        for challenge in openChallengesSent {
            ogs.openChallengeSentById[challenge.id] = challenge
        }
        for automatchEntry in automatchEntries {
            ogs.autoMatchEntryById[automatchEntry.uuid] = automatchEntry
        }
        ogs.challengesReceived = challengesReceived
        
        for message in OGSPrivateMessage.sampleData {
            ogs.handlePrivateMessage(message)
        }
//        ogs.superchatPeerIds.insert(OGSPrivateMessage.sampleData.first!.from.id)
        
        if let user = user {
            ogs.cachedUsersById[user.id] = user
        }
        for user in cachedUsers {
            ogs.cachedUsersById[user.id] = user
        }
        
        return ogs
    }

    static let ogsRoot = "https://online-go.com"
//    static let ogsRoot = "https://beta.online-go.com"
    private var ogsRoot = OGSService.ogsRoot

    private let ogsWebsocket: OGSWebsocket
    private var timerCancellable: AnyCancellable?
    private var pingCancellale: AnyCancellable?
    private var drift : Double {
        get { return ogsWebsocket.drift }
    }
    private var latency : Double {
        get { return ogsWebsocket.latency }
    }
    var serverTimeOffset: Double {
        return drift - latency
    }

    @Published var isLoggedIn: Bool = false
    @Published var user: OGSUser? = nil
    @Published private(set) public var socketStatus = OGSWebsocketStatus.disconnected

    private var connectedGames = [Int: Game]()
    private var connectedWithChat = [Int: Bool]()

    @Published private(set) public var activeGames = [Int: Game]()
    @Published private(set) public var sortedActiveCorrespondenceGamesOnUserTurn: [Game] = []
    @Published private(set) public var sortedActiveCorrespondenceGamesNotOnUserTurn: [Game] = []
    @Published private(set) public var sortedActiveCorrespondenceGames: [Game] = []
    @Published private(set) public var liveGames: [Game] = []
    @Published private(set) public var publicGames: [Int: Game] = [:]
    @Published private(set) public var sortedPublicGames: [Game] = []
    private var activeGamesSortingCancellable: AnyCancellable?
    
    @Published private(set) public var challengesReceived = [OGSChallenge]()
    @Published private(set) public var challengesSent = [OGSChallenge]()
    @Published private(set) public var openChallengeSentById = [Int: OGSChallenge]()
    @Published private(set) public var autoMatchEntryById = [String: OGSAutomatchEntry]()
    var waitingGames: Int {
        return challengesSent.count + openChallengeSentById.count + autoMatchEntryById.count
    }
    @Published private(set) public var waitingLiveGames: Int = 0
    private var waitingLiveGamesCancellable: AnyCancellable?
    @Published private(set) public var hostingRengoChallengeById = [Int: OGSChallenge]()
    @Published private(set) public var participatingRengoChallengeById = [Int: OGSChallenge]()
    
    var pendingRengoGames: Int {
        return participatingRengoChallengeById.count
    }

    @Published private(set) public var isLoadingOverview = true
    
    private var openChallengeById: [Int: OGSChallenge] = [:]
    @Published private(set) public var eligibleOpenChallengeById: [Int: OGSChallenge] = [:]
    
    @Published private var cachedUserIds = Set<Int>()
    @Published private(set) public var cachedUsersById = [Int: OGSUser]()
    private var cachedUsersFetchingCancellable: AnyCancellable?
    
    @Published private(set) public var friends = [OGSUser]()
    
    @Published private(set) public var privateMessagesByPeerId = [Int: [OGSPrivateMessage]]()
    @Published private(set) public var privateMessagesUnreadCount: Int = 0
    @Published private(set) public var privateMessagesActivePeerIds = Set<Int>()
    @Published private(set) public var superchatPeerIds = Set<Int>()
    
    @Published private(set) public var chatMessagesByChannel = [String: [OGSChatMessage]]()
    
    var dictionaryDecoder: DictionaryDecoder = {
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func sortActiveGames<T>(activeGames: T) where T: Sequence, T.Element == Game {
        var gamesOnUserTurn: [Game] = []
        var gamesOnOpponentTurn: [Game] = []
        var liveGames: [Game] = []
        for game in activeGames {
            if game.gameData?.timeControl.speed == .correspondence {
                if isOnUserTurn(game: game) {
                    gamesOnUserTurn.append(game)
                } else {
                    gamesOnOpponentTurn.append(game)
                }
            } else if game.gameData?.timeControl.speed == .live || game.gameData?.timeControl.speed == .blitz {
                liveGames.append(game)
            }
        }
        let thinkingTimeLeftIncreasing: (Game, Game) -> Bool =  { game1, game2 in
            if let clock1 = game1.clock, let clock2 = game2.clock, let user = self.user {
                let time1 = game1.stoneColor(of: user) == .black ? clock1.blackTime : clock1.whiteTime
                let time2 = game2.stoneColor(of: user) == .black ? clock2.blackTime : clock2.whiteTime
                let timeLeft1 = time1.thinkingTimeLeft ?? .infinity
                let timeLeft2 = time2.thinkingTimeLeft ?? .infinity
                return timeLeft1 <= timeLeft2
            }
            return false
        }
        self.sortedActiveCorrespondenceGamesOnUserTurn = gamesOnUserTurn.sorted(by: thinkingTimeLeftIncreasing)
        self.sortedActiveCorrespondenceGamesNotOnUserTurn = gamesOnOpponentTurn.sorted(by: thinkingTimeLeftIncreasing)
        self.sortedActiveCorrespondenceGames = self.sortedActiveCorrespondenceGamesOnUserTurn + self.sortedActiveCorrespondenceGamesNotOnUserTurn
        self.liveGames = liveGames
        
        #if MAIN_APP
        UIApplication.shared.applicationIconBadgeNumber = self.sortedActiveCorrespondenceGamesOnUserTurn.count
        #endif
    }
    
    private init(forPreview: Bool = false) {
        ogsWebsocket = OGSWebsocket()
        ogsWebsocket.serverEventCallback = self.onWebsocketServerEvent(name:data:)
        ogsWebsocket.onStatusChanged = {
            DispatchQueue.main.async {
                self.socketStatus = self.ogsWebsocket.status
            }
        }
        
        if forPreview {
            return
        }
        
        ogsWebsocket.connect()
        
        timerCancellable = TimeUtilities.shared.timer.receive(on: RunLoop.main).sink { [self] _ in
            for game in connectedGames.values {
                if game.gameData?.outcome == nil {
                    let isPaused = game.pauseControl?.isPaused() ?? false
                    if game.gamePhase == .stoneRemoval || !isPaused {
                        if let timeControlSystem = game.gameData?.timeControl.system {
                            game.clock?.calculateTimeLeft(with: timeControlSystem, serverTimeOffset: drift - latency, pauseControl: game.pauseControl)
                        }
                    }
                }
            }
        }
        
        activeGamesSortingCancellable = self.$activeGames.collect(.byTime(DispatchQueue.main, 1.0)).receive(on: RunLoop.main).sink(receiveValue: { activeGamesValues in
            if let activeGames = activeGamesValues.last {
                self.sortActiveGames(activeGames: activeGames.values)
                for game in activeGames.values {
                    self.cachedUserIds.formUnion(Set(game.playerByOGSId.keys))
                }
                self.fetchCachedPlayersIfNecessary()
            }
        })
        
        cachedUsersFetchingCancellable = self.$cachedUserIds.collect(.byTime(DispatchQueue.main, 3.0)).receive(on: RunLoop.main).sink(receiveValue: { values in
            if values.last != nil {
                self.fetchCachedPlayersIfNecessary()
            }
        })
        
        waitingLiveGamesCancellable = Publishers.CombineLatest3($challengesSent, $openChallengeSentById, $autoMatchEntryById).receive(on: DispatchQueue.main).sink(receiveValue: { challengesSent, openChallengeSentById, autoMatchEntryById in
            self.waitingLiveGames = (challengesSent + openChallengeSentById.values).filter {
                $0.game.timeControl.speed != .correspondence
            }.count + autoMatchEntryById.values.filter { $0.timeControlSpeed != .correspondence }.count
        })
        
        self.checkLoginStatus()
        
//        self._testSuperChat()
    }
    
//    private func _testSuperChat() {   
//        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(10))) {
//            self.superchatPeerIds.formUnion(self.privateMessagesActivePeerIds)
//            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(10))) {
//                self.superchatPeerIds.removeAll()
//                self._testSuperChat()
//            }
//        }
//    }
//
    private func onWebsocketServerEvent(name eventName: String, data: Any?) {
        switch eventName {
        case "surround/socketClosed":
            self._gamesToBeReconnected = Array(self.connectedGames.values)
        case "surround/socketOpened":
            for game in self._gamesToBeReconnected {
                if case .OGS(let ogsId) = game.ID {
                    if self.connectedGames[ogsId] != nil {
                        self.connectedGames[ogsId] = nil
                    }
                    let withChat = self.connectedWithChat[ogsId] ?? false
                    self.connect(to: game, withChat: withChat)
                }
            }
            self._gamesToBeReconnected = []
        case "surround/socketAuthenticated":
            self.autoMatchEntryById.removeAll()
            ogsWebsocket.emit(command: "automatch/list")
        case "net/pong":
            if let data = data as? [String: Double] {
                let now = Date().timeIntervalSince1970 * 1000
                ogsWebsocket.latency = now - data["client"]!
                ogsWebsocket.drift = (now - ogsWebsocket.latency / 2) - data["server"]!
            }
        case "active_game":
            if let activeGameData = data as? [String: Any] {
                updateActiveGames(withShortGameData: activeGameData)
            }
        case "ui-push":
            if let data = data as? [String: Any] {
                if let event = data["event"] as? String {
                    if event == "challenge-list-updated" {
                        self.loadOverview()
                    }
                }
            }
        case "automatch/entry":
            if let data = data as? [String: Any] {
                if let automatchEntry = OGSAutomatchEntry(data) {
                    self.autoMatchEntryById[automatchEntry.uuid] = automatchEntry
                }
            }
        case "automatch/cancel":
            if let uuid = (data as? [String: Any] ?? [:])["uuid"] as? String {
                self.autoMatchEntryById.removeValue(forKey: uuid)
            }
        case "automatch/start":
            if let uuid = (data as? [String: Any] ?? [:])["uuid"] as? String {
                self.autoMatchEntryById.removeValue(forKey: uuid)
            }
        case "private-message":
            if let messageData = data as? [String: Any] {
                let decoder = DictionaryDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let message = try? decoder.decode(OGSPrivateMessage.self, from: messageData) {
                    self.handlePrivateMessage(message)
                }
            }
        case "private-superchat":
            if let superchatConfig = data as? [String: Any] {
                self.handleSuperchat(config: superchatConfig)
            }
        case "chat-message":
            if let messageData = data as? [String: Any] {
                if let message = try? self.dictionaryDecoder.decode(OGSChatMessage.self, from: messageData) {
                    print(message)
                }
            }
        case "gamelist-count":
            if let gamesCount = data as? [String: Int?] {
                self.sitewiseLiveGamesCount = gamesCount[TimeControlSpeed.live.rawValue, default: nil]
                self.sitewiseCorrespondenceGamesCount = gamesCount[TimeControlSpeed.correspondence.rawValue, default: nil]
            }
        case "seekgraph/global":
            onSeekGraphEvent(data: data)
        case _ where eventName.starts(with: "game/"):
            let components = eventName.split(separator: "/")
            if components.count == 3, let ogsGameId = Int(components[1]) {
                let gameEvent = String(components[2])
                self.onWebsocketServerGameEvent(ogsGameId: ogsGameId, eventName: gameEvent, data: data)
            }
        default:
            break
        }
    }
    
    private func onWebsocketServerGameEvent(ogsGameId: Int, eventName: String, data: Any?) {
        guard let connectedGame = self.connectedGames[ogsGameId] else {
            return
        }
        
        switch eventName {
        case "gamedata":
            if let gameData = data as? [String: Any], let ogsGame = try? dictionaryDecoder.decode(OGSGame.self, from: gameData) {
                connectedGame.gameData = ogsGame
            } else {
                print("Error parsing game: \(data ?? "")")
            }
        case "move":
            if let movedata = data as? [String: Any] {
                if let move = movedata["move"] as? [Any] {
                    if let column = move[0] as? Int, let row = move[1] as? Int {
                        do {
                            try connectedGame.makeMove(move: column == -1 ? .pass : .placeStone(row, column))
                        } catch {
                            print(ogsGameId, movedata, error)
                        }
                        if move.count > 4, let playerUpdate = move[4] as? [String: Any] {
                            connectedGame.latestPlayerUpdate = try? dictionaryDecoder.decode(OGSMoveExtra.self, from: playerUpdate).playerUpdate
                        } else {
                            connectedGame.latestPlayerUpdate = nil
                        }

                        if let _ = self.activeGames[ogsGameId] {
                            userDefaults[.latestOGSOverviewOutdated] = true
                        }
                    }
                }
            }
        case "clock":
            if let clockdata = data as? [String: Any] {
                do {
                    connectedGame.clock = try dictionaryDecoder.decode(OGSClock.self, from: clockdata)
                    if let pauseControl = connectedGame.clock?.pauseControl {
                        connectedGame.pauseControl = pauseControl
                    }
                    if let timeControlSystem = connectedGame.gameData?.timeControl.system {
                        connectedGame.clock?.calculateTimeLeft(with: timeControlSystem, serverTimeOffset: self.drift - self.latency, pauseControl: connectedGame.pauseControl)
                    }
                    if let _ = self.activeGames[ogsGameId] {
                        // Trigger active games publisher to re-sort if necessary
                        self.activeGames[ogsGameId] = connectedGame
                    }
                } catch {
                    print(ogsGameId, error)
                    print(clockdata)
                }
            }
        case "undo_accepted":
            if let moveNumber = data as? Int {
                connectedGame.undoMove(numbered: moveNumber)
            }
        case "undo_requested":
            if let moveNumber = data as? Int {
                connectedGame.undoRequested = moveNumber
            }
        case "removed_stones":
            if let removedStoneData = data as? [String: Any] {
                if let removedString = removedStoneData["all_removed"] as? String {
                    connectedGame.setRemovedStones(removedString: removedString)
                }
            }
        case "removed_stones_accepted":
            if let removedStoneAcceptedData = data as? [String: Any] {
                if let playerId = removedStoneAcceptedData["player_id"] as? Int, let color = connectedGame.stoneColor(ofPlayerWithId: playerId),
                   let stones = removedStoneAcceptedData["stones"] as? String {
                    connectedGame.removedStonesAccepted[color] = BoardPosition.points(fromPositionString: stones)
                }
            }
        case "phase":
            if let phase = OGSGamePhase(rawValue: data as? String ?? "") {
                connectedGame.gamePhase = phase
                if let _ = self.activeGames[ogsGameId] {
                    userDefaults[.latestOGSOverviewOutdated] = true
                }
            }
        case "auto_resign":
            if let autoResignData = data as? [String: Any] {
                if let playerId = autoResignData["player_id"] as? Int, let expiration = autoResignData["expiration"] as? Double {
                    connectedGame.setAutoResign(
                        playerId: playerId,
                        time: expiration // / 1000 + (serverTimeOffset)
                        // serverTimeOffset = drift - latency
                    )
                }
            }
        case "clear_auto_resign":
            if let clearAutoResignData = data as? [String: Any] {
                if let playerId = clearAutoResignData["player_id"] as? Int {
                    connectedGame.clearAutoResign(playerId: playerId)
                }
            }
        case "chat":
            if let chatData = data as? [String: Any] {
                let decoder = DictionaryDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let chatLine = try? decoder.decode(OGSChatLine.self, from: chatData) {
                    connectedGame.addChatLine(chatLine)
                }
            }
        case "reset-chats":
            connectedGame.resetChats()
        case "player_update":
            if let update = data as? [String: Any] {
                let decoder = DictionaryDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let playerUpdate = try? decoder.decode(OGSPlayerUpdate.self, from: update) {
                    connectedGame.latestPlayerUpdate = playerUpdate
                }
            }
        default:
            break
        }
    }
    
    private var _gamesToBeReconnected: [Game] = []
    
    var ogsUIConfig: OGSUIConfig? {
        get {
            return userDefaults[.ogsUIConfig]
        }
        set {
            if newValue?.userJwt != userDefaults[.ogsUIConfig]?.userJwt {
                Session.default.sessionConfiguration.httpCookieStorage?.removeCookies(since: Date.distantPast)
                for game in activeGames.values {
                    self.disconnect(from: game)
                }
                activeGames.removeAll()
                ogsWebsocket.closeThenReconnect()
                _gamesToBeReconnected = []
            }
            userDefaults[.ogsUIConfig] = newValue
            self.updateSessionId()
            checkLoginStatus()
            #if MAIN_APP
            if isLoggedIn && (userDefaults[.notificationEnabled] == true) {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
        }
    }
    
    var uiConfigCancellable: AnyCancellable?
    func updateUIConfig() {
        if uiConfigCancellable == nil {
            uiConfigCancellable = self.fetchUIConfig().sink(
                receiveCompletion: { _ in
                    self.uiConfigCancellable = nil
                },
                receiveValue: { _ in }
            )
        }
    }
    
    func updateSessionId() {
        if let cookies = Session.default.sessionConfiguration.httpCookieStorage?.cookies(for: URL(string: self.ogsRoot)!) {
            for cookie in cookies {
                if cookie.name == "sessionid" {
                    userDefaults[.ogsSessionId] = cookie.value
                }
            }
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
            ).validate().responseData { response in
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
            return config
        }).eraseToAnyPublisher()
    }
    
    func logout() {
        self.ogsUIConfig = nil
        SurroundService.shared.unregisterDevice()
        
        userDefaults.reset(.latestOGSOverview)
        userDefaults.reset(.latestOGSOverviewTime)
        userDefaults.reset(.latestOGSOverviewOutdated)
        userDefaults.reset(.cachedOGSGames)
        userDefaults.reset(.lastSeenChatIdByOGSGameId)
        userDefaults.reset(.lastAutomatchEntry)
        userDefaults.reset(.lastSeenPrivateMessageByOGSUserId)
    }
    
    func fetchUIConfig() -> AnyPublisher<OGSUIConfig, Error> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return Future<Data, Error> { promise in
            AF.request("\(self.ogsRoot)/api/v1/ui/config").validate().responseData { response in
                switch response.result {
                case .success:
                    promise(.success(response.value!))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }.decode(type: OGSUIConfig.self, decoder: jsonDecoder).receive(on: RunLoop.main).map({ config in
            if config.user.anonymous == false {
                self.ogsUIConfig = config
            }
            return config
        }).eraseToAnyPublisher()
    }
    
    private func checkLoginStatus() {
        isLoggedIn = {
            if let ogsUIConfig = self.ogsUIConfig {
                var hasCSRFToken = false
                var hasSessionId = false
                if let cookies = Session.default.sessionConfiguration.httpCookieStorage?.cookies(for: URL(string: ogsRoot)!) {
                    for cookie in cookies {
                        if cookie.name == "csrftoken" {
                            hasCSRFToken = true
                        }
                        if cookie.name == "sessionid" {
                            hasSessionId = true
                        }
                    }
                }
                if (!hasCSRFToken && ogsUIConfig.csrfToken == nil) || (!hasSessionId && userDefaults[.ogsSessionId] == nil) {
                    return false
                }
                let domain = URL(string: ogsRoot)!.host!
                if let csrfToken = ogsUIConfig.csrfToken {
                    if !hasCSRFToken {
                        if let cookie = HTTPCookie(properties: [
                            .name: "csrftoken",
                            .value: csrfToken,
                            .domain: domain,
                            .path: "/"
                        ]) {
                            Session.default.sessionConfiguration.httpCookieStorage?.setCookie(cookie)
                            hasCSRFToken = true
                        }
                    }
                }
                if let sessionId = userDefaults[.ogsSessionId] {
                    if !hasSessionId {
                        if let cookie = HTTPCookie(properties: [
                            .name: "sessionid",
                            .value: sessionId,
                            .domain: domain,
                            .path: "/"
                        ]) {
                            Session.default.sessionConfiguration.httpCookieStorage?.setCookie(cookie)
                            hasSessionId = true
                        }
                    }
                }
                return hasCSRFToken && hasSessionId
            }
            return false
        }()
        if isLoggedIn {
            user = self.ogsUIConfig?.user
            if let user = user {
                self.cachedUserIds.insert(user.id)
                self.cachedUsersById[user.id] = user
            }
        } else {
            user = nil
        }
    }
    
    func fetchPlayerInfo(userIds: [Int]) -> AnyPublisher<[OGSUser], Error> {
        guard userIds.count > 0 else {
            return Just([OGSUser]()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        print("Fetching player info: \(userIds)")
        return Future<[OGSUser], Error> { promise in
            AF.request(
                "\(self.ogsRoot)/termination-api/players",
                parameters: ["ids": userIds.map { String($0) }.joined(separator: ".")]
            ).validate().responseJSON { response in
                switch response.result {
                case .success:
                    let decoder = DictionaryDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    if let usersData = response.value as? [[String: Any]] {
                        do {
                            let users = try usersData.map { try decoder.decode(OGSUser.self, from: $0) }
                            promise(.success(users))
                        } catch {
                            promise(.failure(OGSServiceError.invalidJSON))
                        }
                    } else {
                        promise(.failure(OGSServiceError.invalidJSON))
                    }
                case .failure(let error):
                    print(error)
                    print("xxx")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    private var playerInfoFetchingCancellable: AnyCancellable?
    func fetchCachedPlayersIfNecessary() {
        guard playerInfoFetchingCancellable == nil else {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(1))) {
                self.fetchCachedPlayersIfNecessary()
            }
            return
        }
        let userIdsToFetch = Array(cachedUserIds.subtracting(Set(cachedUsersById.keys)))
        self.performFetchCachedPlayers(withIds: userIdsToFetch)
    }
    
    func performFetchCachedPlayers(withIds ids: [Int]) {
        guard ids.count > 0 else {
            return
        }
        let userIdsBatch = ids.count > 100 ? Array(ids[0..<100]) : ids
        let remainingIds = Array(ids[userIdsBatch.count...])
        playerInfoFetchingCancellable = self.fetchPlayerInfo(userIds: userIdsBatch).receive(on: RunLoop.main).sink(
            receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.playerInfoFetchingCancellable = nil
                    if remainingIds.count > 0 {
                        self.performFetchCachedPlayers(withIds: remainingIds)
                    }
                }
            },
            receiveValue: { users in
                var cachedUsersById = self.cachedUsersById
                for user in users {
                    cachedUsersById[user.id] = user
                }
                self.cachedUsersById = cachedUsersById
                print("Cached users: ", cachedUsersById.keys)
            })
    }
    
    func processOverview(overview: [String: Any]) {
        if let activeGames = overview["active_games"] as? [[String: Any]] {
            var newActiveGames = [Int:Game]()
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            for gameData in activeGames {
                if let gameId = gameData["id"] as? Int {
                    if let game = self.activeGames[gameId] {
                        newActiveGames[gameId] = game
                    } else {
                        if let newGame = self.createGame(fromShortGameData: gameData) {
                            newActiveGames[gameId] = newGame
                            self.connect(to: newGame, withChat: true)
                        }
                    }
                    if let gameData = gameData["json"] as? [String: Any] {
                        if let ogsGame = try? decoder.decode(OGSGame.self, from: gameData) {
                            newActiveGames[gameId]?.gameData = ogsGame
                            newActiveGames[gameId]?.clock?.calculateTimeLeft(with: ogsGame.timeControl.system, serverTimeOffset: self.serverTimeOffset, pauseControl: ogsGame.pauseControl)
                        }
                    }
                }
            }
            self.activeGames = newActiveGames
            self.sortActiveGames(activeGames: self.activeGames.values)
            if let lastSeenChatIdByOGSGameId = userDefaults[.lastSeenChatIdByOGSGameId] {
                var lastSeenChatIdByOGSGameId = lastSeenChatIdByOGSGameId
                var toBeRemovedOGSIds = [Int]()
                for ogsId in lastSeenChatIdByOGSGameId.keys {
                    if newActiveGames[ogsId] == nil {
                        toBeRemovedOGSIds.append(ogsId)
                    }
                }
                for ogsId in toBeRemovedOGSIds {
                    lastSeenChatIdByOGSGameId.removeValue(forKey: ogsId)
                }
                if toBeRemovedOGSIds.count > 0 {
                    userDefaults[.lastSeenChatIdByOGSGameId] = lastSeenChatIdByOGSGameId
                }
            }
        }
        if let challenges = overview["challenges"] as? [[String: Any]] {
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var challengesSent = [OGSChallenge]()
            var challengesReceived = [OGSChallenge]()
            for challengeData in challenges {
                do {
                    let challenge = try decoder.decode(OGSChallenge.self, from: challengeData)
                    if challenge.challenger?.id == self.user?.id {
                        challengesSent.append(challenge)
                    } else {
                        challengesReceived.append(challenge)
                    }
                } catch {
                    print("Error: ", error)
                }
            }
            self.challengesReceived = challengesReceived
            self.challengesSent = challengesSent
        }
    }
    
    var overviewLoadingCancellable: AnyCancellable?
    func loadOverview(allowsCache: Bool = false, finishCallback: (() -> ())? = nil) {
        guard isLoggedIn else {
            return
        }
        
        self.fetchFriends()
        
        isLoadingOverview = true
        overviewLoadingCancellable = SurroundService.shared.getOGSOverview(allowsCache: allowsCache).catch { error in
            return Future<[String: Any], Error> { promise in
                AF.request("\(self.ogsRoot)/api/v1/ui/overview").validate().responseData { response in
                    switch response.result {
                    case .success:
                        if let responseValue = response.value, let data = try? JSONSerialization.jsonObject(with: responseValue) as? [String: Any] {

                            promise(.success(data))
                        }
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            }
        }.receive(on: RunLoop.main).sink(receiveCompletion: { result in
            if case .failure(let error) = result {
                print(error)
                self.logout()
                return
            }
            self.isLoadingOverview = false
            self.overviewLoadingCancellable = nil
            if let finishCallback = finishCallback {
                finishCallback()
            }
        }, receiveValue: { overviewValue in
            if let overviewData = try? JSONSerialization.data(withJSONObject: overviewValue) {
                userDefaults.updateLatestOGSOverview(overviewData: overviewData)
                WidgetCenter.shared.reloadAllTimelines()
            }
            self.processOverview(overview: overviewValue)
        })
    }
    
    func getGameDetailAndConnect(gameID: Int) -> AnyPublisher<Game, Error> {
        return Future<Game, Error> { promise in
            AF.request("\(self.ogsRoot)/api/v1/games/\(gameID)").validate().responseJSON { response in
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
                                    game.ogs = self
                                    self.connect(to: game)
                                    promise(.success(game))
                                }
                                return
                            } catch {
                                promise(.failure(error))
                            }
                        }
                    }
                    promise(.failure(OGSServiceError.invalidJSON))
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
                    gameDetailCancellable[gameId] = self.getGameDetailAndConnect(gameID: gameId).receive(on: RunLoop.main).sink(
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
        
    func ensureConnect(thenExecute callback: (() -> ())? = nil) {
        guard let callback else {
            return
        }
        if ogsWebsocket.opened {
            callback()
        } else {
            ogsWebsocket.onConnectTasks.append(callback)
        }
    }
    
    func disconnect(from game: Game) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }

        self.ogsWebsocket.emit(command: "game/disconnect", data: ["game_id": ogsID])
        self.disconnectChat(from: game)
        connectedGames[ogsID] = nil
        connectedWithChat[ogsID] = nil
    }
    
    func disconnectChat(from game: Game) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }

        self.ogsWebsocket.emit(command: "chat/part", data: ["channel": "game-\(ogsID)"])
    }
    
    func connectChat(in game: Game) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }
        
        self.ogsWebsocket.emit(command: "chat/join", data: ["channel": "game-\(ogsID)"])
    }
    
    func connect(to game: Game, withChat: Bool = false) {
        guard case .OGS(let ogsID) = game.ID else {
            return
        }
        
        guard connectedGames[ogsID] == nil else {
            if connectedWithChat[ogsID] == false && withChat {
                connectedWithChat[ogsID] = true
                self.ogsWebsocket.emit(command: "game/disconnect", data: ["game_id": ogsID])
                self.ogsWebsocket.emit(command: "game/connect", data: ["game_id": ogsID, "chat": true])
                self.ogsWebsocket.emit(command: "chat/join", data: ["channel": "game-\(ogsID)"])
            }
            return
        }

        guard self.ogsWebsocket.opened else {
            self.ogsWebsocket.onConnectTasks.append {
                self.connect(to: game, withChat: withChat)
            }
            return
        }
        
        guard !(game.isUserPlaying && withChat && !self.ogsWebsocket.authenticated) else {
            // If user is one of the players, wait until the socket is authenticated to prevent them from seeing Malkovich log.
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(1))) {
                self.connect(to: game, withChat: withChat)
            }
            return
        }
        
        connectedWithChat[ogsID] = withChat
        connectedGames[ogsID] = game
        self.ogsWebsocket.emit(command: "game/connect", data: ["game_id": ogsID, "chat": withChat ? true : 0])
        if withChat {
            self.ogsWebsocket.emit(command: "chat/join", data: ["channel": "game-\(ogsID)"])
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
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let blackPlayer = try? decoder.decode(OGSUser.self, from: black),
               let whitePlayer = try? decoder.decode(OGSUser.self, from: white) {
                game.blackPlayer = blackPlayer
                game.whitePlayer = whitePlayer
            }
            game.ogs = self
            return game
        }
        return nil
    }
    
    func submitMove(move: Move, forGame game: Game) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            if let gameId = game.gameData?.gameId {
                self.ogsWebsocket.emit(command: "game/move", data: ["game_id": gameId, "move": move.toOGSString()]) { _, _ in
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func toggleRemovedStones(stones: Set<[Int]>, forGame game: Game) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            if let gameId = game.gameData?.gameId {
                var toBeAdded = Set<[Int]>()
                var toBeRemoved = Set<[Int]>()
                for point in stones {
                    if game.currentPosition.removedStones?.contains(point) ?? false {
                        toBeAdded.insert(point)
                    } else {
                        toBeRemoved.insert(point)
                    }
                }
                if toBeAdded.count > 0 {
                    self.ogsWebsocket.emit(command: "game/removed_stones/set", data: ["game_id": gameId, "removed": 0, "stones": BoardPosition.positionString(fromPoints: toBeAdded)])
                }
                if toBeRemoved.count > 0 {
                    self.ogsWebsocket.emit(command: "game/removed_stones/set", data: ["game_id": gameId, "removed": 1, "stones": BoardPosition.positionString(fromPoints: toBeRemoved)])
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }
    
    func acceptRemovedStone(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/removed_stones/accept", data: [
                "game_id": ogsID,
                "stones": BoardPosition.positionString(fromPoints: game.currentPosition.removedStones ?? Set<[Int]>())
            ])
        }
    }
    
    func resumeGameFromStoneRemoval(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/removed_stones/reject", data: ["game_id": ogsID])
        }
    }
    
    func requestUndo(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/undo/request", data: ["game_id": ogsID, "move_number": game.currentPosition.lastMoveNumber])
        }
    }
    
    func acceptUndo(game: Game, moveNumber: Int) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/undo/accept", data: ["game_id": ogsID, "move_number": moveNumber])
        }
    }
    
    func resign(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/resign", data: ["game_id": ogsID])
        }
    }

    func cancel(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/cancel", data: ["game_id": ogsID])
        }
    }

    func pause(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/pause", data: ["game_id": ogsID])
        }
    }
    
    func resume(game: Game) {
        if let ogsID = game.ogsID {
            self.ogsWebsocket.emit(command: "game/resume", data: ["game_id": ogsID])
        }
    }
    
    func fetchPublicGames(from: Int = 0, limit: Int = 30) {
        self.ogsWebsocket.emit(command: "gamelist/query", data: ["list": "live", "sort_by": "rank", "from": from, "limit": limit]) { data, _ in
            if let publicGamesData = (data as? [String: Any] ?? [:])["results"] as? [[String: Any]] {
                var newPublicGames: [Game] = []
                var newPublicGameIds = Set<Int>()
                for publicGameData in publicGamesData {
                    if let gameId = publicGameData["id"] as? Int {
                        newPublicGameIds.insert(gameId)
                        if let newGame = self.createGame(fromShortGameData: publicGameData) {
                            if let connectedGame = self.connectedGames[gameId] {
                                newPublicGames.append(connectedGame)
                            } else {
                                self.connect(to: newGame)
                                newPublicGames.append(newGame)
                            }
                            self.publicGames[gameId] = newPublicGames.last
                        }
                    }
                }
                self.sortedPublicGames = newPublicGames
                for game in newPublicGames {
                    self.cachedUserIds.formUnion(Set(game.playerByOGSId.keys))
                }
                self.fetchCachedPlayersIfNecessary()
                // Disconnect outdated games
                for connectedGame in self.connectedGames.values {
                    if let gameId = connectedGame.ogsID {
                        if !newPublicGameIds.contains(gameId) && self.activeGames[gameId] == nil {
                            self.disconnect(from: connectedGame)
                        }
                    }
                }
            }
        }
    }
    
    var publicGamesCyclingCancellable: AnyCancellable?
    var publicGamesCyclingFrom = 0
    func cyclePublicGames() {
        if publicGamesCyclingCancellable == nil {
            self.fetchPublicGames(from: publicGamesCyclingFrom, limit: 10)
            publicGamesCyclingFrom = 15 - publicGamesCyclingFrom
            publicGamesCyclingCancellable = Timer.publish(every: 20, on: .main, in: .common).autoconnect().sink { _ in
                self.fetchPublicGames(from: self.publicGamesCyclingFrom, limit: 10)
                self.publicGamesCyclingFrom = 15 - self.publicGamesCyclingFrom
            }
        }
    }
    
    func cancelPublicGamesCycling() {
        self.publicGamesCyclingCancellable?.cancel()
        self.publicGamesCyclingCancellable = nil
        self.publicGamesCyclingFrom = 0
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
                    if cookie.name == "sessionid" {
                        userDefaults[.ogsSessionId] = cookie.value
                    }
                }
            }
            return self.fetchUIConfig()
        }
        .switchToLatest()
        .map { config in
            self.loadOverview()
            return config
        }
        .eraseToAnyPublisher()
    }
    
    #if MAIN_APP
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
    #endif
    
    func withdrawOrDeclineChallenge(challenge: OGSChallenge) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let url = challenge.challenged == nil ?
                "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)" :
                "\(self.ogsRoot)/api/v1/me/challenges/\(challenge.id)"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url,
                    method: .delete,
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/overview"]
                ).validate().response { response in
                    switch response.result {
                    case .success:
                        promise(.success(()))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func acceptChallenge(challenge: OGSChallenge) -> AnyPublisher<Int, Error> {
        return Future<Int, Error> { promise in
            let url = challenge.challenged == nil ?
                "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)/accept" :
                "\(self.ogsRoot)/api/v1/me/challenges/\(challenge.id)/accept"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url,
                    method: .post,
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/overview"]
                ).validate().responseJSON { response in
                    switch response.result {
                    case .success:
                        if let data = response.value as? [String: Any] {
                            if let newGameId = data["game"] as? Int {
                                promise(.success(newGameId))
                            }
                        }
                        promise(.failure(OGSServiceError.invalidJSON))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func joinRengoChallenge(challenge: OGSChallenge) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let url = "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)/join"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url, method: .put,
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/play"]
                ).validate().response { response in
                    switch response.result {
                    case .success:
                        promise(.success(()))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func leaveRengoChallenge(challenge: OGSChallenge) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let url = "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)/join"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url, method: .delete,
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/play"]
                ).validate().response { response in
                    switch response.result {
                    case .success:
                        promise(.success(()))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func assignRengoTeam(challenge: OGSChallenge, player: OGSUser, color: StoneColor?) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let url = "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)/team"
            let assignParameter = color == .black ? "assign_black" : color == .white ? "assign_white" : "unassign"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url, method: .put,
                    parameters: [assignParameter: [player.id]],
                    encoder: JSONParameterEncoder(),
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/play"]
                ).validate().response { response in
                    switch response.result {
                    case .success:
                        promise(.success(()))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func startRengoGame(challenge: OGSChallenge) -> AnyPublisher<Int, Error> {
        return Future<Int, Error> { promise in
            let url = "\(self.ogsRoot)/api/v1/challenges/\(challenge.id)/start"
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url, method: .post,
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/play"]
                ).validate().responseJSON { response in
                    switch response.result {
                    case .success:
                        if let data = response.value as? [String: Any] {
                            if let newGameId = data["game"] as? Int {
                                promise(.success(newGameId))
                            }
                        }
                        promise(.failure(OGSServiceError.invalidJSON))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    func sendChat(in game: Game, channel: OGSChatChannel, body: String) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            if let gameId = game.ogsID {
                self.ogsWebsocket.emit(command: "game/chat", data: [
                    "body": body,
                    "game_id": gameId,
                    "move_number": game.currentPosition.lastMoveNumber,
                    "type": channel.rawValue
                ])
            }
            promise(.success(()))
        }.eraseToAnyPublisher()
    }
    
    var playerCacheObservingCancellable: AnyCancellable?
    
    func subscribeToSeekGraph() {
        guard ogsWebsocket.authenticated else {
            return
        }
        
        if seekGraphUnsubscribeCancellable != nil {
            seekGraphUnsubscribeCancellable?.cancel()
            seekGraphUnsubscribeCancellable = nil
        }
        
        self.ogsWebsocket.emit(command: "seek_graph/connect", data: ["channel": "global"])
        
        playerCacheObservingCancellable = self.$cachedUsersById.collect(.byTime(DispatchQueue.main, 0.2)).sink { values in
            if let cachedUsersById = values.last {
                print(cachedUsersById.keys)
                for (id, challenge) in self.eligibleOpenChallengeById {
                    if let challengerId = challenge.challenger?.id {
                        if cachedUsersById[challengerId] != nil {
                            var challenge = challenge
                            challenge.challenger = OGSUser.mergeUserInfoFromCache(user: challenge.challenger, cachedUser: cachedUsersById[challengerId]!)
                            self.eligibleOpenChallengeById[id] = challenge
                        }
                    }
                }
            }
        }
    }
    
    func onSeekGraphEvent(data: Any?) {
        guard let user = self.user else {
            return
        }

        if let challenges = data as? [[String: Any]] {
            let decoder = DictionaryDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            for challengeData in challenges {
                if let challengeId = challengeData["challenge_id"] as? Int {
                    if challengeData["delete"] as? Int == 1 {
                        if let challenge = self.openChallengeById[challengeId] {
                            if challenge.challenger?.id == self.user?.id {
                                self.openChallengeSentById.removeValue(forKey: challengeId)
                            }
                        }
                        self.openChallengeById.removeValue(forKey: challengeId)
                        self.eligibleOpenChallengeById.removeValue(forKey: challengeId)
                        self.hostingRengoChallengeById.removeValue(forKey: challengeId)
                        self.participatingRengoChallengeById.removeValue(forKey: challengeId)
                    } else {
                        if var challenge = try? decoder.decode(OGSChallenge.self, from: challengeData) {
                            if challenge.rengo {
                                if let userId = self.user?.id {
                                    if let challengerId = challenge.challenger?.id, challengerId == userId {
                                        self.hostingRengoChallengeById[challenge.id] = challenge
                                    }
                                    if let participants = challenge.game.rengoParticipants {
                                        if participants.firstIndex(of: userId) != nil {
                                            self.participatingRengoChallengeById[challenge.id] = challenge
                                        } else {
                                            self.participatingRengoChallengeById.removeValue(forKey: challenge.id)
                                        }
                                        self.cachedUserIds.formUnion(Set(participants))
                                    }
                                }
                            } else {
                                if let challengerId = challenge.challenger?.id {
                                    if self.cachedUsersById[challengerId] != nil {
                                        challenge.challenger = OGSUser.mergeUserInfoFromCache(user: challenge.challenger, cachedUser: self.cachedUsersById[challengerId]!)
                                    }
                                    if challengerId == self.user?.id {
                                        self.openChallengeSentById[challenge.id] = challenge
                                    }
                                }
                            }
                            self.openChallengeById[challengeId] = challenge
                            if challenge.isUserEligible(user: user) {
                                self.eligibleOpenChallengeById[challengeId] = challenge
                                if let challengerId = challenge.challenger?.id {
                                    self.cachedUserIds.insert(challengerId)
                                }
                                if challenge.rengo, let participants = challenge.game.rengoParticipants {
                                    self.cachedUserIds.formUnion(Set(participants))
                                }
                            } else {
                                self.eligibleOpenChallengeById.removeValue(forKey: challengeId)
                            }
                        }
                    }
                }
            }
        }
    }
    
    var seekGraphUnsubscribeCancellable: AnyCancellable?
    func unsubscribeFromSeekGraphWhenDone() {
        guard ogsWebsocket.opened else {
            seekGraphUnsubscribeCancellable = nil
            return
        }
        
        guard openChallengeSentById.count + participatingRengoChallengeById.count == 0 else {
            if seekGraphUnsubscribeCancellable == nil {
                seekGraphUnsubscribeCancellable = self.$openChallengeSentById.combineLatest(self.$participatingRengoChallengeById).collect(.byTime(DispatchQueue.global(), 1.0)).sink { _ in
                    DispatchQueue.main.async {
                        self.unsubscribeFromSeekGraphWhenDone()
                    }
                }
            }
            return
        }

        self.ogsWebsocket.emit(command: "seek_graph/disconnect", data: ["channel": "global"])
        
        self.openChallengeById.removeAll()
        self.eligibleOpenChallengeById.removeAll()
        self.participatingRengoChallengeById.removeAll()
        self.hostingRengoChallengeById.removeAll()
        
        playerCacheObservingCancellable?.cancel()
        playerCacheObservingCancellable = nil
        
        seekGraphUnsubscribeCancellable?.cancel()
        seekGraphUnsubscribeCancellable = nil
    }
    
    func fetchFriends() {
        AF.request("\(self.ogsRoot)/api/v1/ui/friends").validate().responseJSON { response in
            if case .success(let data) = response.result {
                if let friends = (data as? [String: Any] ?? [:])["friends"] as? [[String: Any]] {
                    let decoder = DictionaryDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    var result = [OGSUser]()
                    for friend in friends {
                        if let user = try? decoder.decode(OGSUser.self, from: friend) {
                            result.append(user)
                        }
                    }
                    self.friends = result
                }
            }
        }
    }
    
    func searchByUsername(keyword: String) -> AnyPublisher<[OGSUser], Error> {
        return Future<[OGSUser], Error> { promise in
            AF.request("\(self.ogsRoot)/api/v1/ui/omniSearch", parameters: ["q": keyword])
                .validate().responseJSON { response in
                    switch response.result {
                    case .success(let data):
                        if let players = (data as? [String: Any] ?? [:])["players"] as? [[String: Any]] {
                            let decoder = DictionaryDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            var result = [OGSUser]()
                            for player in players {
                                if let user = try? decoder.decode(OGSUser.self, from: player) {
                                    result.append(user)
                                }
                            }
                            promise(.success(result))
                        } else {
                            promise(.failure(OGSServiceError.invalidJSON))
                        }
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
        }.eraseToAnyPublisher()
    }
    
    var sendingKeepAliveSignal = false
    func sendKeepAliveSignalForOpenLiveChallenges() {
        guard sendingKeepAliveSignal else {
            return
        }
        
        guard ogsWebsocket.opened else {
            return
        }
        
        let challenges = openChallengeSentById.values.filter { $0.game.timeControl.speed != .correspondence }
        guard challenges.count > 0 else {
            sendingKeepAliveSignal = false
            return
        }
        
        for challenge in challenges {
            ogsWebsocket.emit(command: "challenge/keepalive", data: ["challenge_id": challenge.id, "game_id": challenge.game.id])
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(1))) {
            self.sendKeepAliveSignalForOpenLiveChallenges()
        }
    }
    
    func sendChallenge(opponent: OGSUser?, challenge: OGSChallenge) -> AnyPublisher<OGSChallenge, Error> {
        return Future<OGSChallenge, Error> { promise in
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            var url = "\(self.ogsRoot)/api/v1/challenges"
            if let opponentId = opponent?.id {
                url = "\(self.ogsRoot)/api/v1/players/\(opponentId)/challenge"
            }
            if let csrfToken = self.ogsUIConfig?.csrfToken {
                AF.request(
                    url,
                    method: .post,
                    parameters: challenge,
                    encoder: JSONParameterEncoder(encoder: encoder),
                    headers: ["x-csrftoken": csrfToken, "referer": "\(self.ogsRoot)/play"]
                ).validate().responseJSON { response in
                    switch response.result {
                    case .success(let data):
                        if let result = data as? [String: Any] {
                            if result["status"] as? String == "ok" {
                                if let challengeId = result["challenge"] as? Int, let gameId = result["game"] as? Int {
                                    var challenge = challenge
                                    challenge.id = challengeId
                                    challenge.game.id = gameId
                                    promise(.success(challenge))
                                    if opponent == nil && !self.sendingKeepAliveSignal {
                                        self.sendingKeepAliveSignal = true
                                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(1))) {
                                            self.sendKeepAliveSignalForOpenLiveChallenges()
                                        }
                                    }
                                    return
                                }
                            }
                        }
                        promise(.failure(OGSServiceError.invalidJSON))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                    print(response.result)
                }
            } else {
                promise(.failure(OGSServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }

    func isOnUserTurn(game: Game) -> Bool {
        if game.gamePhase == .stoneRemoval {
            if let userColor = game.userStoneColor {
                if game.removedStonesAccepted[userColor] == nil || game.removedStonesAccepted[userColor] != game.currentPosition.removedStones {
                    return true
                } else {
                    return false
                }
            }
        } else if game.gamePhase != .finished {
            if let clock = game.clock {
                if clock.currentPlayerId == self.user?.id {
                    return true
                } else {
                    return false
                }
            }
        }
        return false
    }
    
    func findAutomatch(entry: OGSAutomatchEntry) {
        guard ogsWebsocket.opened else {
            return
        }
        
        ogsWebsocket.emit(command: "automatch/find_match", data: entry.jsonObject)
    }
    
    func cancelAutomatch(entry: OGSAutomatchEntry) {
        guard ogsWebsocket.opened else {
            return
        }
        
        ogsWebsocket.emit(command: "automatch/cancel", data: ["uuid": entry.uuid])
    }
    
    private var _receivedMessagesKeysByPeerId = [Int: Set<String>]()
    private var _privateMessagesUIDByPeerId = [Int: [Int]]()
    func handlePrivateMessage(_ message: OGSPrivateMessage) {
        let otherPlayerId = message.from.id == self.user?.id ? message.to.id : message.from.id
        
        setUpNewPeerIfNecessary(peerId: otherPlayerId)
                
        guard _receivedMessagesKeysByPeerId[otherPlayerId]?.contains(message.messageKey) == false else {
            return
        }
        
        _receivedMessagesKeysByPeerId[otherPlayerId]?.insert(message.messageKey)
        privateMessagesByPeerId[otherPlayerId]?.append(message)
        
        _calculatePrivateMessageUnreadCount()
    }
    
    func setUpNewPeerIfNecessary(peerId: Int) {
        if _receivedMessagesKeysByPeerId[peerId] == nil {
            _receivedMessagesKeysByPeerId[peerId] = Set<String>()
            privateMessagesByPeerId[peerId] = [OGSPrivateMessage]()
            _privateMessagesUIDByPeerId[peerId] = [Int.random(in: 0..<100000), 0]
            privateMessagesActivePeerIds.insert(peerId)
            cachedUserIds.insert(peerId)
            ogsWebsocket.emit(command: "chat/pm/load", data: ["player_id": peerId])
        }
    }
    
    func handleSuperchat(config: [String: Any]) {
        if let moderatorId = config["moderator_id"] as? Int, let enabled = config["enable"] as? Bool {
            setUpNewPeerIfNecessary(peerId: moderatorId)
            if enabled {
                superchatPeerIds.insert(moderatorId)
            } else {
                superchatPeerIds.remove(moderatorId)
            }
        }
    }

    private func _calculatePrivateMessageUnreadCount() {
        privateMessagesUnreadCount = privateMessagesByPeerId.keys.filter { peerId in
            if let lastSeen = userDefaults[.lastSeenPrivateMessageByOGSUserId]?[peerId] {
                if let lastInThread = privateMessagesByPeerId[peerId]?.last {
                    return lastInThread.content.timestamp > lastSeen
                } else {
                    return false
                }
            } else {
                return true
            }
        }.count
    }
    
    func sendPrivateMessage(to peer: OGSUser, message: String) -> AnyPublisher<OGSPrivateMessage, Error> {
        if _privateMessagesUIDByPeerId[peer.id] == nil {
            _privateMessagesUIDByPeerId[peer.id] = [Int.random(in: 0..<100000), 0]
        }

        return Future<OGSPrivateMessage, Error> { promise in
            var uid = self._privateMessagesUIDByPeerId[peer.id]!
            uid[1] += 1
            self._privateMessagesUIDByPeerId[peer.id] = uid
            self.ogsWebsocket.emit(command: "chat/pm", data: [
                "player_id": peer.id,
                "username": peer.username,
                "uid": "\(String(uid[0], radix: 36)).\(uid[1])",
                "message": message
            ]) { data, _ in
                if let messageData = data as? [String: Any] {
                    if let message = try? self.dictionaryDecoder.decode(OGSPrivateMessage.self, from: messageData) {
                        self.handlePrivateMessage(message)
                        promise(.success(message))
                        return
                    }
                }
                promise(.failure(OGSServiceError.invalidJSON))
            }
        }.eraseToAnyPublisher()
    }
    
    func markPrivateMessageThreadAsRead(peerId: Int) {
        if let lastMessage = privateMessagesByPeerId[peerId]?.last {
            if var lastSeen = userDefaults[.lastSeenPrivateMessageByOGSUserId] {
                lastSeen[peerId] = lastMessage.content.timestamp
                userDefaults[.lastSeenPrivateMessageByOGSUserId] = lastSeen
                _calculatePrivateMessageUnreadCount()
            }
        }
    }
    
    func joinChatChannel(_ channel: String) {
        guard ogsWebsocket.opened else {
            ogsWebsocket.onConnectTasks.append {
                self.joinChatChannel(channel)
            }
            return
        }
        
        ogsWebsocket.emit(command: "chat/join", data: ["channel": channel])
    }
    
    func leaveChatChannel(_ channel: String) {
        guard ogsWebsocket.opened else {
            return
        }
        
        ogsWebsocket.emit(command: "chat/part", data: ["channel": channel])
    }
    
    @Published private(set) public var sitewiseLiveGamesCount: Int?
    @Published private(set) public var sitewiseCorrespondenceGamesCount: Int?
    
    func subscribeToGameCount() {
        guard ogsWebsocket.opened else {
            ogsWebsocket.onConnectTasks.append {
                self.subscribeToGameCount()
            }
            return
        }
        
        ogsWebsocket.emit(command: "gamelist/count/subscribe", data: ["channel": ""])
    }
    
    func unsubscribeFromGameCount() {
        guard ogsWebsocket.opened else {
            return
        }
        
        ogsWebsocket.emit(command: "gamelist/count/unsubscribe")
        sitewiseLiveGamesCount = nil
        sitewiseCorrespondenceGamesCount = nil
    }
}
