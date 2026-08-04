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

    var chatBody: Text {
        Text(chatBodyAttributedString())
    }

    private func chatBodyAttributedString() -> AttributedString {
        var result = AttributedString()
        var index = chatLine.body.startIndex
        var mutableSelf = self
        for coordinateRange in mutableSelf.chatLine.coordinatesRanges {
            let coordinateStartIndex = chatLine.body.index(chatLine.body.startIndex, offsetBy: coordinateRange.location)
            let coordinateEndIndex = chatLine.body.index(coordinateStartIndex, offsetBy: coordinateRange.length)
            result.append(AttributedString(String(chatLine.body[index..<coordinateStartIndex])))
            var highlighted = AttributedString(String(chatLine.body[coordinateStartIndex..<coordinateEndIndex]))
            highlighted.foregroundColor = Color(.systemIndigo)
            highlighted.font = .callout.bold()
            result.append(highlighted)
            index = coordinateEndIndex
        }
        result.append(AttributedString(String(chatLine.body[index..<chatLine.body.endIndex])))
        return result
    }
    
    var body: some View {
        HStack {
            if chatLine.user.id == 0 && chatLine.user.username == "system" {
                Spacer()
                Text(chatLine.body)
                    .font(.callout.bold())
                Spacer()
            } else {
                if case .trailing = horizontalAlignment {
                    Spacer()
                }
                VStack(alignment: horizontalAlignment, spacing: 2) {
                    if showUsername {
                        Text(verbatim: "\(chatLine.user.usernameAndRank)")
                            .font(.caption2).bold()
                            .foregroundColor(chatLine.user.uiColor)
                    }
                    VStack(alignment: horizontalAlignment, spacing: 2) {
                        if let variation = chatLine.variation {
                            BoardView(boardPosition: variation.position, variation: variation)
                                .frame(width: 176, height: 176)
                                .padding(.top, 5)
                        }
                        chatBody
                            .font(.callout)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color(chatLine.channel == .malkovich ? UIColor.systemGreen : UIColor.systemGray4)
                            .opacity(chatLine.channel == .malkovich ? 0.8 : 1)
                    )
                    .cornerRadius(10)
                }
                if case .leading = horizontalAlignment {
                    Spacer()
                }
            }
        }
    }
}

#if DEBUG
#Preview("Analysis variation", traits: .fixedLayout(width: 300, height: 250)) {
    ChatLine(chatLine: TestData.EuropeanChampionshipWithChat.chatLog[36])
}

#Preview("Spectator message", traits: .fixedLayout(width: 300, height: 100)) {
    ChatLine(chatLine: TestData.EuropeanChampionshipWithChat.chatLog[30])
}

#Preview("Trailing message — Dark", traits: .fixedLayout(width: 300, height: 100)) {
    ChatLine(
        chatLine: TestData.EuropeanChampionshipWithChat.chatLog[11],
        horizontalAlignment: .trailing
    )
    .colorScheme(.dark)
}

#Preview("Moderator message", traits: .fixedLayout(width: 300, height: 100)) {
    let game = TestData.EuropeanChampionshipWithChat
    ChatLine(chatLine: game.chatLog[game.chatLog.count - 1])
}

#Preview("Professional player message", traits: .fixedLayout(width: 300, height: 100)) {
    let game = TestData.EuropeanChampionshipWithChat
    ChatLine(chatLine: game.chatLog[game.chatLog.count - 9])
}
#endif
