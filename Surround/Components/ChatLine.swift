//
//  ChatLine.swift
//  Surround
//
//  Created by Anh Khoa Hong on 30/12/2020.
//

import SwiftUI

struct ChatLine: View {
    var chatLine: OGSChatLine
    var showUsername = true
    var horizontalAlignment: HorizontalAlignment = .leading
    
    var body: some View {
        HStack {
            if case .trailing = horizontalAlignment {
                Spacer()
            }
            VStack(alignment: horizontalAlignment, spacing: 2) {
                if showUsername {
                    Text("\(chatLine.user.username) [\(chatLine.user.formattedRank)]")
                        .font(.caption2).bold()
                        .foregroundColor(chatLine.user.uiColor)
                }
                VStack(alignment: horizontalAlignment, spacing: 2) {
                    if let variation = chatLine.variation {
                        BoardView(boardPosition: variation.position, variation: variation)
                            .frame(width: 176, height: 176)
                            .padding(.top, 5)
                    }
                    Text(chatLine.body)
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(chatLine.channel == .malkovich ? UIColor.systemGreen : UIColor.systemGray4))
                .opacity(chatLine.channel == .malkovich ? 0.8 : 1)
                .cornerRadius(10)
            }
            if case .leading = horizontalAlignment {
                Spacer()
            }
        }
    }
}

struct ChatLine_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.EuropeanChampionshipWithChat
        return Group {
            ChatLine(chatLine: game.chatLog[31])
                .previewLayout(.fixed(width: 300, height: 250))
            Group {
                ChatLine(chatLine: game.chatLog[0])
                ChatLine(chatLine: game.chatLog[11], horizontalAlignment: .trailing)
                    .colorScheme(.dark)
                ChatLine(chatLine: game.chatLog[game.chatLog.count - 1])
                ChatLine(chatLine: game.chatLog[game.chatLog.count - 9])
            }
            .previewLayout(.fixed(width: 300, height: 100))
        }
    }
}
