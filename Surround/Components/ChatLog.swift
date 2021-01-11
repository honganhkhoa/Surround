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
    @EnvironmentObject var ogs: OGSService

    var body: some View {
        VStack {
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
                                ChatLine(
                                    chatLine: chatLine, showUsername: false,
                                    horizontalAlignment: ogs.user?.id == chatLine.user.id ? .trailing : .leading
                                )
                            } else {
                                ChatLine(
                                    chatLine: chatLine,
                                    horizontalAlignment: ogs.user?.id == chatLine.user.id ? .trailing : .leading)
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
            NewChatInput()
        }
        .background(
            Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6)
                .shadow(radius: 2)
        )
    }
}

struct NewChatInput: View {
    @State var newChat = ""
    
    var body: some View {
        HStack {
            TextField("Say hi!", text: $newChat)
        }
    }
}

struct ChatLog_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NewChatInput()
                .previewLayout(.fixed(width: 350, height: 100))
            ChatLog(game: TestData.EuropeanChampionshipWithChat)
                .previewLayout(.fixed(width: 350, height: 400))
        }
    }
}
