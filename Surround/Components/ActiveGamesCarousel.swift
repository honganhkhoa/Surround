//
//  ActiveGamesCarousel.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/9/20.
//

import SwiftUI
import Combine

struct ActiveGamesCarousel: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    var currentGame: Binding<Game?>
    @Namespace var selectingGame
    var activeGames: [Game]
    @State var scrollTarget: GameID?
    @State var discardNextScrollTarget = false
    @State var renderedCurrentGame: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()
    @State var renderedCurrentGameCollected: AnyPublisher<[Bool], Never> = PassthroughSubject<[Bool], Never>().eraseToAnyPublisher()
    var cellSize: CGFloat = 120.0
    var selectionRingPadding: CGFloat = 5.0
    var padding: CGFloat = 5.0
    var showsToggleButton = false

    var showsActiveGamesCarouselSetting = Setting(.showsActiveGamesCarousel).binding

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
                            currentGame.wrappedValue = game
                            scrollTarget = currentGame.wrappedValue?.ID
                        }
                    }
                if game.ID == currentGame.wrappedValue?.ID {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .padding(1)
                        .foregroundColor(Color(UIColor.label))
                        .matchedGeometryEffect(id: "selectionIndicator", in: selectingGame)
                }
            }
            .frame(width: cellSize + selectionRingPadding * 2, height: cellSize + selectionRingPadding * 2)
        }
        .padding(.horizontal, selectionRingPadding / 2)
        .id(game.ID)
        .onChange(of: currentGame.wrappedValue) { _ in
            self.renderedCurrentGame.send(game == currentGame.wrappedValue)
        }
        .contentShape(Rectangle())
        .hoverEffect(.lift)
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                LazyHStack(alignment: .bottom, spacing: 0) {
                    if showsToggleButton {
                        Button(action: { withAnimation { showsActiveGamesCarouselSetting.wrappedValue.toggle() }}) {
                            Label("Toggle thumbnails", systemImage: "squares.below.rectangle")
                                .labelStyle(IconOnlyLabelStyle())
                        }
                        .foregroundColor(showsActiveGamesCarouselSetting.wrappedValue ? Color.white : Color.accentColor)
                        .padding(5)
                        .background(
                            Group {
                                if showsActiveGamesCarouselSetting.wrappedValue { Color.accentColor } else { Color.clear }
                            }
                            .cornerRadius(5)
                        )
                        .padding(.trailing, 5)
                    }
                    if showsActiveGamesCarouselSetting.wrappedValue {
                        ForEach(activeGames) { game in
                            gameCell(game: game)
                        }
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
        .frame(height: showsActiveGamesCarouselSetting.wrappedValue ? cellSize + selectionRingPadding * 2 + padding * 2 : showsToggleButton ? 44 : 0)
        .onReceive(renderedCurrentGameCollected) { rendered in
            if rendered.allSatisfy({ !$0 }) {
                if scrollTarget != currentGame.wrappedValue?.ID {
                    scrollTarget = currentGame.wrappedValue?.ID
                }
            }
        }
        .onAppear {
            scrollTarget = currentGame.wrappedValue?.ID
            self.renderedCurrentGameCollected = self.renderedCurrentGame.collect(.byTime(DispatchQueue.main, 1.0)).eraseToAnyPublisher()
        }
    }
}

struct ActiveGamesCarousel_Previews: PreviewProvider {
    static var previews: some View {
        let games = [TestData.Ongoing19x19wBot1, TestData.Ongoing19x19wBot2, TestData.Ongoing19x19wBot3]
        return Group {
            ActiveGamesCarousel(currentGame: .constant(games[0]), activeGames: games, showsToggleButton: true)
                .previewLayout(.fixed(width: 350, height: 150))
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "kata-bot", id: 592684),
                activeGames: games
            )
        )
    }
}
