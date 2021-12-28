//
//  TestData.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/21/20.
//

import Foundation
import DictionaryCoding

class TestData {
    static var Scored19x19Korean: Game { sampleGame(ogsId: 18759438) }
    static var Resigned19x19HandicappedWithInitialState: Game {
        let game = sampleGame(ogsId: 23871959)
        game.ogsRawData = [
            "players": [
                "black": [
                    "icon": "https://secure.gravatar.com/avatar/7e8d12fdf00911f6b573b6644b518f4d?s=32&d=retro"
                ],
                "white": [
                    "icon": "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/bb1794c4b0538ce0068287464079d02e-32.png"
                ]
            ]
        ]
        return game
    }
    static var Resigned9x9Japanese: Game { sampleGame(ogsId: 25076729) }
    static var Ongoing19x19HandicappedWithNoInitialState: Game { sampleGame(ogsId: 25291907) }
    static var Scored15x17: Game { sampleGame(ogsId: 25758368) }
    static var Ongoing19x19wBot1: Game { sampleGame(ogsId: 26268396) }
    static var Ongoing19x19wBot2: Game { sampleGame(ogsId: 26268404) }
    static var Ongoing19x19wBot3: Game { sampleGame(ogsId: 26269354) }
    static var StoneRemoval9x9: Game { sampleGame(ogsId: 27053412) }
    static var EuropeanChampionshipWithChat: Game { sampleGame(ogsId: 27671778) }
    // surround://publicGames/27671778
    
    static var Rengo2v2: Game { sampleGame(ogsId: 11289, beta: true) }
    static var Rengo3v1: Game { sampleGame(ogsId: 11359, beta: true) }
    
    static func sampleGame(ogsId: Int, beta: Bool = false) -> Game {
        let fileURL = Bundle.main.url(forResource: "game-\(beta ? "beta-" : "")\(ogsId)", withExtension: "json")!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try! decoder.decode(OGSGame.self, from: Data(contentsOf: fileURL))
        let game = Game(ogsGame: ogsGame)
        if let chatURL = Bundle.main.url(forResource: "chat-\(ogsId)", withExtension: "json") {
            if let chatLines = try? JSONSerialization.jsonObject(with: Data(contentsOf: chatURL)) as? [[String: Any]] {
                let dictDecoder = DictionaryDecoder()
                dictDecoder.keyDecodingStrategy = .convertFromSnakeCase
                for chatLine in chatLines {
                    if let line = try? dictDecoder.decode(OGSChatLine.self, from: chatLine) {
                        game.addChatLine(line)
                    }
                }
            }
        }
        return game
    }
}
