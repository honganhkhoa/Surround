//
//  ChatLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/01/2021.
//

import SwiftUI

struct ChatLog: View {
    @ObservedObject var game: Game
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                LazyVStack(spacing: 2) {
                    ForEach(Array(game.chatLog.enumerated()), id: \.1) { index, chatLine in
                        if index == 0 || game.chatLog[index - 1].moveNumber != chatLine.moveNumber {
                            ZStack {
                                Divider()
                                HStack {
                                    Spacer()
                                    Text("Move \(chatLine.moveNumber)")
                                        .font(.caption2)
                                        .padding(.leading, 5)
                                        .background(Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6))
                                }
//                                BoardView(boardPosition: game.positionByLastMoveNumber[chatLine.moveNumber]!)
//                                    .frame(width: 80, height: 80)
                            }
                        }
                        if index > game.chatLog.startIndex &&
                            game.chatLog[index - 1].user.id == chatLine.user.id &&
                            game.chatLog[index - 1].moveNumber == chatLine.moveNumber {
                            ChatLine(chatLine: chatLine, showUsername: false)
                        } else {
                            ChatLine(chatLine: chatLine)
                        }
                    }
                }
                .padding(10)
                .onAppear {
                    if let lastLine = game.chatLog.last {
                        scrollView.scrollTo(lastLine)
                    }
                }
            }
        }
        .background(
            Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6)
                .shadow(radius: 2)
        )
    }
}

struct ChatLog_Previews: PreviewProvider {
    static var previews: some View {
        ChatLog(game: TestData.EuropeanChampionshipWithChat)
            .previewLayout(.fixed(width: 350, height: 400))
    }
}
