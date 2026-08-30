//
//  ChatLine.swift
//  Surround
//
//  Created by Anh Khoa Hong on 30/12/2020.
//

import SwiftUI

private func gameChatReviewLabel(reviewID: Int) -> Text {
    Text(
        "Review: #\(String(reviewID))",
        comment: "Link and accessibility label for a game review shared in chat. The number is the OGS review ID."
    )
}

struct ChatLine: View {
    @Environment(\.openURL) private var openURL

    var chatLine: OGSChatLine
    var showUsername = true
    var horizontalAlignment: HorizontalAlignment = .leading
    var isSelected = false
    var accessibilityIdentifier = ""
    var select: () -> Void = {}

    private var isThirdPerson: Bool {
        chatLine.isPlainTextBody && chatLine.body.hasPrefix("/me ")
    }

    private var displayedBody: String {
        isThirdPerson ? String(chatLine.body.dropFirst(4)) : chatLine.body
    }

    private var reviewURL: URL? {
        guard let reviewID = chatLine.reviewID else { return nil }
        return URL(string: "\(OGSService.ogsRoot)/review/\(reviewID)")
    }

    var chatBody: Text {
        Text(chatBodyAttributedString())
    }

    private func chatBodyAttributedString() -> AttributedString {
        var result = AttributedString()
        let body = displayedBody
        let coordinateRanges = OGSChatLine.coordinatesRegex.matches(
            in: body,
            range: NSRange(body.startIndex..., in: body)
        ).compactMap { Range($0.range, in: body) }
        var index = body.startIndex
        for coordinateRange in coordinateRanges {
            result.append(AttributedString(String(body[index..<coordinateRange.lowerBound])))
            var highlighted = AttributedString(String(body[coordinateRange]))
            highlighted.foregroundColor = Color(.systemIndigo)
            highlighted.font = .callout.bold()
            result.append(highlighted)
            index = coordinateRange.upperBound
        }
        result.append(AttributedString(String(body[index..<body.endIndex])))
        return result
    }

    @ViewBuilder
    private var username: some View {
        let username = Text(verbatim: "\(chatLine.user.usernameAndRank)")
        if isThirdPerson {
            username.italic()
        } else {
            username
        }
    }

    @ViewBuilder
    private var renderedChatBody: some View {
        if let reviewID = chatLine.reviewID,
           let reviewURL {
            Link(destination: reviewURL) {
                gameChatReviewLabel(reviewID: reviewID)
            }
        } else if chatLine.isAnalysis {
            Text(
                "Variation: \(displayedBody)",
                comment: "Label for a variation shared in game chat"
            )
        } else if isThirdPerson {
            chatBody.italic()
        } else {
            chatBody
        }
    }

    private var bubbleColor: Color {
        switch chatLine.channel {
        case .malkovich:
            return Color(.systemGreen).opacity(0.2)
        case .personal:
            return Color(.systemBlue).opacity(0.2)
        case .hidden:
            return Color(.systemPurple).opacity(0.2)
        case .main, .spectator, .shadowban:
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
        case .hidden:
            Label {
                Text(
                    "Moderator-only",
                    comment: "Badge on a game-chat message visible only to moderators"
                )
            } icon: {
                Image(systemName: "eye.slash.fill")
            }
            .accessibilityValue(
                Text(
                    "Visible only to moderators",
                    comment: "Hidden game-chat visibility; used as an accessibility value"
                )
            )
        case .main, .spectator, .shadowban:
            EmptyView()
        }
    }
    
    var body: some View {
        HStack {
            if chatLine.user.id == 0 && chatLine.user.username == "system" {
                Spacer()
                renderedChatBody
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
                    .accessibilityAddTraits(
                        reviewURL == nil ? .isButton : .isLink
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .reviewAccessibilityLabel(reviewID: chatLine.reviewID)
                    .accessibilityAction {
                        if let reviewURL {
                            openURL(reviewURL)
                        } else {
                            select()
                        }
                    }
                Spacer()
            } else {
                if case .trailing = horizontalAlignment {
                    Spacer()
                }
                VStack(alignment: horizontalAlignment, spacing: 2) {
                    if showUsername {
                        username
                            .font(.caption2).bold()
                            .foregroundColor(chatLine.user.uiColor)
                    }
                    VStack(alignment: horizontalAlignment, spacing: 2) {
                        channelBadge
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        if let variation = chatLine.variation {
                            BoardView(
                                boardPosition: variation.position,
                                variation: variation,
                                markups: .constant(variation.markups)
                            )
                                .frame(width: 176, height: 176)
                                .padding(.top, 5)
                        }
                        renderedChatBody
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
                .accessibilityAddTraits(
                    reviewURL == nil ? .isButton : .isLink
                )
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(accessibilityIdentifier)
                .reviewAccessibilityLabel(reviewID: chatLine.reviewID)
                .accessibilityAction {
                    if let reviewURL {
                        openURL(reviewURL)
                    } else {
                        select()
                    }
                }
                if case .leading = horizontalAlignment {
                    Spacer()
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func reviewAccessibilityLabel(reviewID: Int?) -> some View {
        if let reviewID {
            accessibilityLabel(
                gameChatReviewLabel(reviewID: reviewID)
            )
        } else {
            self
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
