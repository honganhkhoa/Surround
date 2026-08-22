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
    var isSelected = false
    var accessibilityIdentifier = ""
    var select: () -> Void = {}

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

    private var bubbleColor: Color {
        switch chatLine.channel {
        case .malkovich:
            return Color(.systemGreen).opacity(0.2)
        case .personal:
            return Color(.systemBlue).opacity(0.2)
        case .main, .spectator:
            return Color(.systemGray4)
        }
    }

    @ViewBuilder
    private var channelBadge: some View {
        switch chatLine.channel {
        case .malkovich:
            Label {
                Text("Malkovich", comment: "Name of the game-chat channel whose messages are hidden from the opponent during the game")
            } icon: {
                Image(systemName: "eye.slash.fill")
            }
            .accessibilityValue(
                Text(
                    "Hidden from opponent, visible to spectators",
                    comment: "Malkovich game-chat visibility; used as the channel subtitle and accessibility value"
                )
            )
        case .personal:
            Label {
                Text("Personal", comment: "Name of the private game-chat channel visible only to the message author")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .accessibilityValue(
                Text(
                    "Visible only to you",
                    comment: "Personal game-chat visibility; used as the channel subtitle, message-field placeholder, and accessibility value"
                )
            )
        case .main, .spectator:
            EmptyView()
        }
    }
    
    var body: some View {
        HStack {
            if chatLine.user.id == 0 && chatLine.user.username == "system" {
                Spacer()
                Text(chatLine.body)
                    .font(.callout.bold())
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color.accentColor : .clear,
                                lineWidth: 2
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: select)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .accessibilityAction {
                        select()
                    }
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
                        channelBadge
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        if let variation = chatLine.variation {
                            BoardView(boardPosition: variation.position, variation: variation)
                                .frame(width: 176, height: 176)
                                .padding(.top, 5)
                        }
                        chatBody
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(bubbleColor)
                    .cornerRadius(10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color.accentColor : .clear,
                                lineWidth: 2
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityAction {
                    select()
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

#Preview("Malkovich message", traits: .fixedLayout(width: 300, height: 120)) {
    var chatLine = TestData.EuropeanChampionshipWithChat.chatLog[11]
    chatLine.channel = .malkovich
    return ChatLine(chatLine: chatLine)
}

#Preview("Personal message — Accessibility", traits: .fixedLayout(width: 300, height: 180)) {
    var chatLine = TestData.EuropeanChampionshipWithChat.chatLog[11]
    chatLine.channel = .personal
    return ChatLine(chatLine: chatLine)
        .environment(\.dynamicTypeSize, .accessibility3)
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
