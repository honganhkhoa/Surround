//
//  GameCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/1/20.
//

import SwiftUI

struct PlayerInfoLine: View {
    @ObservedObject var game: Game
    var color: StoneColor
    var displayMode: GameCell.CellDisplayMode
    @EnvironmentObject var ogs: OGSService

    var isUser: Bool {
        guard let user = ogs.user else {
            return false
        }
        if game.rengo {
            return game.gameData?.rengoTeams?[color].firstIndex(where: { $0.id == user.id }) != nil
        } else {
            return (color == .black && user.id == game.blackId) || (color == .white && user.id == game.whiteId)
        }
    }
    
    var body: some View {
        if displayMode == .full {
            HStack {
                Stone(color: color, shadowRadius: 1).frame(width: 15, height: 15)
                HStack(alignment: .firstTextBaseline) {
                    Group {
                        if isUser {
                            Text("You").font(Font.subheadline.bold())
                                .padding(.horizontal, 3)
                                .background(Color(UIColor.systemTeal).cornerRadius(5))
                                .offset(x: -3)
                        } else {
                            if let player = color == .black ? game.blackPlayer : game.whitePlayer {
                                (Text(player.username).font(.subheadline) + Text(" [\(player.formattedRank)]").font(.caption))
                                    .bold().lineLimit(1)
                                    .foregroundColor(player.uiColor)
                            }
                        }
                    }
                    if game.rengo, let rengoTeam = game.gameData?.rengoTeams?[color], rengoTeam.count > 1 {
                        (Text("+ \(rengoTeam.count - 1)×") + Text(Image(systemName: "person.fill")))
                            .font(.subheadline)
                    }
                    Spacer()
                    InlineTimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color, pauseControl: game.pauseControl)
                }
            }
        } else {
            HStack(alignment: .top) {
                Stone(color: color, shadowRadius: 1).frame(width: 15, height: 15)
                    .offset(y: 2)
                VStack(alignment: .leading) {
                    HStack {
                        Group {
                            if isUser {
                                Text("You").font(Font.subheadline.bold())
                                    .padding(.horizontal, 3)
                                    .background(Color(UIColor.systemTeal).cornerRadius(5))
                                    .offset(x: -3)
                            } else {
                                if let player = color == .black ? game.blackPlayer : game.whitePlayer {
                                    (Text(player.username).font(.subheadline) + Text(" [\(player.formattedRank)]").font(.caption))
                                        .bold().lineLimit(1)
                                        .foregroundColor(player.uiColor)
                                }
                            }
                        }
                        if game.rengo, let rengoTeam = game.gameData?.rengoTeams?[color], rengoTeam.count > 1 {
                            (Text("+ \(rengoTeam.count - 1)×") + Text(Image(systemName: "person.fill")))
                                .font(.subheadline)
                        }
                    }
                    InlineTimerView(timeControl: game.gameData?.timeControl, clock: game.clock, player: color, pauseControl: game.pauseControl)
                }
                Spacer()
            }
        }
    }
}

struct GameCell: View {
    @ObservedObject var game: Game
    var displayMode: CellDisplayMode = .full
    @EnvironmentObject var ogs: OGSService

    enum CellDisplayMode: String, Codable {
        case full
        case compact
    }
    
    var gameOutCome: some View {
        VStack {
            if game.gameData?.winner == game.gameData?.players.black.id {
                Text("B+").font(.title).bold()
            } else {
                Text("W+").font(.title).bold()
            }
            Text(game.gameData?.outcome ?? "")
        }
        .padding()
        .background(Color.gray.opacity(0.9))
        .cornerRadius(5)
    }
    
    var isUserInGame: Bool {
        guard let user = ogs.user else {
            return false
        }
        
        return game.blackId == user.id || game.whiteId == user.id
    }
    
    var body: some View {
        if displayMode == .full {
            VStack {
                PlayerInfoLine(game: game, color: .black, displayMode: displayMode)
                ZStack {
                    BoardView(
                        boardPosition: game.currentPosition
                    )
                    .scaledToFit()
                    if game.gameData?.outcome != nil {
                        gameOutCome
                    }
                }
                .frame(maxHeight: .infinity)
                PlayerInfoLine(game: game, color: .white, displayMode: displayMode)
            }
            .contentShape(Rectangle())
        } else {
            GeometryReader { geometry in
                HStack {
                    BoardView(boardPosition: game.currentPosition)
                        .frame(width: geometry.size.height, height: geometry.size.height, alignment: .center)
                    VStack {
                        PlayerInfoLine(game: game, color: .black, displayMode: displayMode)
                        PlayerInfoLine(game: game, color: .white, displayMode: displayMode)
                    }
                }
            }
            .frame(minHeight: 120)
            .contentShape(Rectangle())
        }
    }
}

struct GameCell_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        return Group{
            List([game]) { _ in
                GameCell(game: TestData.Rengo3v1)
            }
            .listStyle(GroupedListStyle())
            .environmentObject(OGSService.previewInstance(user: OGSUser(username: "honganhkhoa", id: 1526)))
            List([game]) { _ in
                GameCell(game: TestData.Rengo2v2, displayMode: .compact)
            }
            .listStyle(GroupedListStyle())
            .environmentObject(OGSService.previewInstance(user: OGSUser(username: "honganhkhoa", id: 1526)))
            List([game]) { _ in
                GameCell(game: TestData.Resigned19x19HandicappedWithInitialState)
            }
            .listStyle(GroupedListStyle()).colorScheme(.dark)
            .environmentObject(OGSService.previewInstance(user: OGSUser(username: "hhs214", id: 749506)))
        }
        .previewLayout(.fixed(width: 375, height: 500))
    }
}
