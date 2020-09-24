//
//  ActiveGamesCarousel.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/9/20.
//

import SwiftUI
import Combine

struct ActiveCorrespondenceGamesCarousel: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @Binding var currentGame: Game
    @Namespace var selectingGame
    var activeGames: [Game]
    @State var scrollTarget: GameID?
    @State var discardNextScrollTarget = false
    @State var renderedCurrentGame: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()
    @State var renderedCurrentGameCollected: AnyPublisher<[Bool], Never> = PassthroughSubject<[Bool], Never>().eraseToAnyPublisher()
    var horizontal = true
    var cellSize: CGFloat = 120.0
    var selectionRingPadding: CGFloat = 5.0
    var padding: CGFloat = 5.0

    func gameCell(game: Game) -> some View {
        VStack(alignment: .trailing) {
            ZStack(alignment: .center) {
                if game.gamePhase == .stoneRemoval {
                    Color(UIColor.systemOrange).cornerRadius(3)
                } else if game.clock?.currentPlayerId == ogs.user?.id {
                    Color(UIColor.systemTeal).cornerRadius(3)
                } else {
                    if colorScheme == .dark {
                        Color(UIColor.systemGray5)
                    } else {
                        Color(UIColor.systemBackground)
                    }
                }
                BoardView(boardPosition: game.currentPosition)
                    .frame(width: cellSize, height: cellSize)
                    .padding(.horizontal, 5)
                    .onTapGesture {
                        withAnimation {
                            discardNextScrollTarget = true
                            currentGame = game
                            scrollTarget = currentGame.ID
                        }
                    }
                if game.ID == currentGame.ID {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .padding(1)
                        .foregroundColor(Color(UIColor.label))
                        .matchedGeometryEffect(id: "selectionIndicator", in: selectingGame)
                }
            }
            .frame(width: cellSize + selectionRingPadding * 2, height: cellSize + selectionRingPadding * 2)
        }
        .padding(horizontal ? .horizontal : .vertical, selectionRingPadding / 2)
        .id(game.ID)
        .onChange(of: currentGame) { _ in
            self.renderedCurrentGame.send(game == currentGame)
        }
    }
    
    var horizontalScrollView: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                LazyHStack(spacing: 0) {
                    ForEach(activeGames) { game in
                        gameCell(game: game)
                    }
                }
                .padding(.horizontal, 5)
                .onChange(of: scrollTarget) { target in
                    if let target = target {
                        if discardNextScrollTarget {
                            discardNextScrollTarget = false
                        } else {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollView.scrollTo(target)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: cellSize + selectionRingPadding * 2 + padding * 2)
    }
    
    var verticalScrollView: some View {
        ScrollView(.vertical) {
            ScrollViewReader { scrollView in
                LazyVStack(spacing: 0) {
                    ForEach(activeGames) { game in
                        gameCell(game: game)
                    }
                }
                .padding(.vertical, 5)
                .onChange(of: scrollTarget) { target in
                    if let target = target {
                        if discardNextScrollTarget {
                            discardNextScrollTarget = false
                        } else {
                            DispatchQueue.main.async {
                                withAnimation {
                                    scrollView.scrollTo(target, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: cellSize + selectionRingPadding * 2 + padding * 2)
    }
    
    var body: some View {
        Group {
            if horizontal {
                horizontalScrollView
            } else {
                verticalScrollView
            }
        }
        .onReceive(renderedCurrentGameCollected) { rendered in
            if rendered.allSatisfy({ !$0 }) {
                if scrollTarget != currentGame.ID {
                    scrollTarget = currentGame.ID
                }
            }
        }
        .onAppear {
            scrollTarget = currentGame.ID
            self.renderedCurrentGameCollected = self.renderedCurrentGame.collect(.byTime(DispatchQueue.main, 1.0)).eraseToAnyPublisher()
        }
    }
}

struct ActiveGamesCarousel_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            ActiveCorrespondenceGamesCarousel(currentGame: .constant(games[0]), activeGames: games)
                .previewLayout(.fixed(width: 350, height: 150))
            ActiveCorrespondenceGamesCarousel(currentGame: .constant(games[0]), activeGames: games, horizontal: false)
                .previewLayout(.fixed(width: 150, height: 350))
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
    }
}
