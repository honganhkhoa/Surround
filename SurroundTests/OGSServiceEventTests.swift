//
//  OGSServiceEventTests.swift
//  SurroundTests
//

import XCTest

final class OGSServiceEventTests: XCTestCase {
    private class FakeWebsocket: OGSWebsocketProtocol {
        struct Emission {
            let command: String
            let data: Any
        }

        var serverEventCallback: ((String, Any?) -> Void)?
        var onConnectTasks: [() -> Void] = []
        var onStatusChanged: (() -> Void)?
        var authenticationConfigProvider: () -> OGSUIConfig? = { nil }
        var authenticated = true
        var opened = true
        var status = OGSWebsocketStatus.connected
        var drift = 0.0
        var latency = 0.0
        var emissions = [Emission]()

        func connect() {
            opened = true
            status = .connected
            onStatusChanged?()
        }

        func close() {
            opened = false
            authenticated = false
            status = .disconnected
            onStatusChanged?()
        }

        func reconnectIfNeeded() { connect() }
        func closeThenReconnect() { connect() }

        func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
            emissions.append(.init(command: command, data: data))
            resultCallback?(nil, nil)
        }

        func deliver(name: String, data: Any? = nil) {
            serverEventCallback?(name, data)
        }
    }

    private var preferenceSuite: String!

    override func tearDown() {
        if let preferenceSuite {
            UserDefaults.standard.removePersistentDomain(forName: preferenceSuite)
        }
        super.tearDown()
    }

    func testGameEventsUpdateConnectedGameAndReconnectSubscription() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let gameData = try makeEmptyGameData(id: 42)
        let game = Game(ogsGame: gameData)
        game.ogs = service

        service.connect(to: game)
        XCTAssertEqual(socket.emissions.map(\.command), ["game/connect"])

        socket.deliver(name: "game/42/move", data: ["move": [0, 0, 125, false]])
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 1)
        XCTAssertEqual(game.currentPosition.lastMove, .placeStone(0, 0))
        XCTAssertEqual(game.currentPosition[0, 0], .hasStone(.black))

        socket.deliver(name: "game/42/undo_requested", data: 1)
        XCTAssertEqual(game.undoRequested, 1)

        socket.deliver(name: "game/42/undo_accepted", data: 1)
        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)

        socket.deliver(name: "game/42/phase", data: "stone removal")
        XCTAssertEqual(game.gamePhase, .stoneRemoval)

        socket.deliver(name: "surround/socketClosed")
        socket.deliver(name: "surround/socketOpened")
        XCTAssertEqual(socket.emissions.filter { $0.command == "game/connect" }.count, 2)
    }

    func testMalformedAndUnknownGameEventsAreIgnored() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 77))
        game.ogs = service
        service.connect(to: game)

        socket.deliver(name: "game/not-an-id/move", data: ["move": [0, 0]])
        socket.deliver(name: "game/77/move", data: ["move": []])
        socket.deliver(name: "game/77/move", data: ["move": ["bad", "data"]])
        socket.deliver(name: "game/77/not-a-real-event", data: ["anything": true])
        socket.deliver(name: "net/pong", data: [String: Double]())

        XCTAssertEqual(game.currentPosition.lastMoveNumber, 0)
        XCTAssertNil(game.currentPosition.lastMove)
    }

    func testMoveAcknowledgementErrorBecomesPublisherFailure() throws {
        final class RejectingWebsocket: FakeWebsocket {
            override func emit(command: String, data: Any, resultCallback: OGSWebsocketResultCallback?) {
                emissions.append(.init(command: command, data: data))
                resultCallback?(nil, ["move": "illegal move"])
            }
        }

        let socket = RejectingWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 88))
        game.ogs = service
        let completed = expectation(description: "move rejected")
        var receivedError: Error?
        let cancellable = service.submitMove(move: .placeStone(0, 0), forGame: game).sink(
            receiveCompletion: {
                if case .failure(let error) = $0 { receivedError = error }
                completed.fulfill()
            },
            receiveValue: { XCTFail("Rejected move must not succeed") }
        )

        wait(for: [completed], timeout: 1)
        withExtendedLifetime(cancellable) {}
        XCTAssertEqual(receivedError?.localizedDescription, "move: illegal move")
    }

    func testStoneAcceptanceIncludesTheRequiredStrictSekiFlag() throws {
        let socket = FakeWebsocket()
        let service = makeService(socket: socket)
        let game = Game(ogsGame: try makeEmptyGameData(id: 99))

        service.acceptRemovedStone(game: game)

        let emission = try XCTUnwrap(socket.emissions.last)
        XCTAssertEqual(emission.command, "game/removed_stones/accept")
        let data = try XCTUnwrap(emission.data as? [String: Any])
        XCTAssertEqual(data["game_id"] as? Int, 99)
        XCTAssertEqual(data["stones"] as? String, "")
        XCTAssertEqual(data["strict_seki_mode"] as? Bool, false)
    }

    private func makeService(socket: OGSWebsocketProtocol) -> OGSService {
        preferenceSuite = "com.honganhkhoa.Surround.EventTests.\(UUID().uuidString)"
        let environment = OGSEnvironment(rootURL: URL(string: "https://ogs.test")!)
        return OGSService(
            environment: environment,
            httpClient: AlamofireOGSHTTPClient.isolated(),
            preferences: UserDefaults(suiteName: preferenceSuite)!,
            ogsWebsocket: socket,
            connectsAutomatically: false,
            usesSurroundOverviewService: false,
            enablesAppSideEffects: false,
            startsTimers: false
        )
    }

    private func makeEmptyGameData(id: Int) throws -> OGSGame {
        let bundle = Bundle(for: OGSServiceEventTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "game-25076729", withExtension: "json"))
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["game_id"] = id
        object["game_name"] = "event-test-\(id)"
        object["width"] = 5
        object["height"] = 5
        object["moves"] = []
        object["phase"] = "play"
        object["outcome"] = NSNull()
        object["winner"] = NSNull()
        let fixture = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OGSGame.self, from: fixture)
    }
}
