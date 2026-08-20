//
//  ChatLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/01/2021.
//

import SwiftUI
import Combine

struct ChatLog: View {
    @ObservedObject var game: Game
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    var hoveredPosition: Binding<BoardPosition?> = .constant(nil)
    var hoveredVariation: Binding<Variation?> = .constant(nil)
    var hoveredCoordinates: Binding<[[Int]]> = .constant([])
    
    @State var atEndOfChat = false
    @State var shouldScrollToEndAfterKeyboardChange = false

    func shouldMergeChat(at index: Int) -> Bool {
        return index > 0 && game.chatLog[index].moveNumber == game.chatLog[index - 1].moveNumber && game.chatLog[index].user.id == game.chatLog[index - 1].user.id
    }
    
    var chatLines: some View {
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
                .onTapGesture {
                    // https://stackoverflow.com/questions/57700396/adding-a-drag-gesture-in-swiftui-to-a-view-inside-a-scrollview-blocks-the-scroll#answer-60015111
                }
                .gesture(
                    LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second = value {
                                hoveredPosition.wrappedValue = game.positionByLastMoveNumber[chatLine.moveNumber]
                            }
                        }
                        .onEnded { _ in
                            hoveredPosition.wrappedValue = nil
                        }
                )
                Spacer().frame(height: 2)
            }
            ChatLine(
                chatLine: chatLine,
                showUsername: !shouldMergeChat(at: index),
                horizontalAlignment: ogs.user?.id == chatLine.user.id ? .trailing : .leading
            )
            .onTapGesture {
                // https://stackoverflow.com/questions/57700396/adding-a-drag-gesture-in-swiftui-to-a-view-inside-a-scrollview-blocks-the-scroll#answer-60015111
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if let position = chatLine.variation?.position {
                            if case .second = value {
                                hoveredPosition.wrappedValue = position
                                hoveredVariation.wrappedValue = chatLine.variation
                            }
                        }
                        var chatLine = chatLine
                        hoveredCoordinates.wrappedValue = chatLine.coordinates
                    }
                    .onEnded { _ in
                        hoveredPosition.wrappedValue = nil
                        hoveredVariation.wrappedValue = nil
                        hoveredCoordinates.wrappedValue = []
                    }
            )
            Spacer().frame(height: 2)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { scrollViewGeometry in
                ScrollView {
                    ScrollViewReader { scrollView in
                        LazyVStack(spacing: 0) {
                            chatLines
                            Spacer().frame(height: 8)
                            GeometryReader { geometry -> AnyView in
                                let endOfChatFrame = geometry.frame(in: .named(AnyHashable("scrollView")))
                                if endOfChatFrame.origin.y >= 0 && endOfChatFrame.origin.y <= scrollViewGeometry.size.height {
                                    if !self.atEndOfChat {
                                        DispatchQueue.main.async {
                                            self.atEndOfChat = true
                                            game.markAllChatAsRead()
                                        }
                                    }
                                } else {
                                    if self.atEndOfChat {
                                        DispatchQueue.main.async {
                                            self.atEndOfChat = false
                                        }
                                    }
                                }
//                                print("scroll \(geometry.frame(in: .named("scrollView")))")
//                                print("scrollView \(scrollViewGeometry.size)")
                                return AnyView(EmptyView())
                            }.frame(width: 10, height: 1).id("scrollViewBottom")
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 0)
                        .onAppear {
                            scrollView.scrollTo("scrollViewBottom")
                            game.markAllChatAsRead()
                        }
                        .onReceive(game.$chatLog) { newChatLog in
                            if atEndOfChat {
                                DispatchQueue.main.async {
                                    scrollView.scrollTo("scrollViewBottom")
                                    game.markAllChatAsRead()
                                }
                            }
                        }
                        .onReceive(SystemPlatformServices.shared.keyboardWillChangeFramePublisher) { _ in
                            self.shouldScrollToEndAfterKeyboardChange = self.atEndOfChat
                        }
                        .onReceive(SystemPlatformServices.shared.keyboardDidChangeFramePublisher) { _ in
                            if self.shouldScrollToEndAfterKeyboardChange {
                                DispatchQueue.main.async {
                                    scrollView.scrollTo("scrollViewBottom")
                                    self.shouldScrollToEndAfterKeyboardChange = false
                                }                                
                            }
                        }
                    }
                }.coordinateSpace(name: "scrollView")
            }
            if ogs.user != nil {
                NewChatInput(game: game)
                    .id(game.ID)
            }
        }
        .background(
            Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6)
                .shadow(radius: 2)
        )
    }
}

struct NewChatInput: View {
    var game: Game
    @State private var newChat = ""
    @EnvironmentObject var ogs: OGSService
    @State private var selectedChannel: OGSChatSendChannel
    @ScaledMetric(relativeTo: .body) private var channelDividerHeight: CGFloat = 28
    
    @State private var chatSendingCancellable: AnyCancellable?

    init(game: Game, selectedChannel: OGSChatSendChannel = .main) {
        self.game = game
        _selectedChannel = State(initialValue: selectedChannel)
    }

    private func channelTitle(_ channel: OGSChatSendChannel) -> LocalizedStringResource {
        switch channel {
        case .main:
            return LocalizedStringResource("Chat")
        case .malkovich:
            return LocalizedStringResource(
                "Malkovich",
                comment: "Name of the game-chat channel whose messages are hidden from the opponent during the game"
            )
        case .personal:
            return LocalizedStringResource(
                "Personal",
                comment: "Name of the private game-chat channel visible only to the message author"
            )
        }
    }

    private var selectedChannelTitle: LocalizedStringResource {
        channelTitle(selectedChannel)
    }

    private var channelPlaceholder: LocalizedStringResource {
        switch selectedChannel {
        case .main:
            return LocalizedStringResource("Say hi!")
        case .malkovich:
            return LocalizedStringResource(
                "Hidden from opponent during the game",
                comment: "Malkovich game-chat visibility; used as the message-field placeholder"
            )
        case .personal:
            return personalVisibilityDescription
        }
    }

    private var personalVisibilityDescription: LocalizedStringResource {
        LocalizedStringResource(
            "Visible only to you",
            comment: "Personal game-chat visibility; used as the channel subtitle, message-field placeholder, and accessibility value"
        )
    }

    private func channelMenuButton(
        _ channel: OGSChatSendChannel,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource
    ) -> some View {
        Button {
            selectedChannel = channel
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: selectedChannel == channel ? "checkmark.circle.fill" : "circle")
            }
            Text(subtitle)
        }
        .accessibilityAddTraits(selectedChannel == channel ? .isSelected : [])
    }

    private var backgroundColor: Color {
        switch selectedChannel {
        case .main:
            return Color(.systemBackground)
        case .malkovich:
            return Color(.systemGreen).opacity(0.2)
        case .personal:
            return Color(.systemBlue).opacity(0.2)
        }
    }

    func sendChat() {
        guard self.chatSendingCancellable == nil && newChat.count > 0 else {
            return
        }
        
        let channel = selectedChannel.resolved(isUserPlaying: game.isUserPlaying)
        self.chatSendingCancellable = ogs.sendChat(in: game, channel: channel, body: newChat)
            .zip(game.$chatLog.setFailureType(to: Error.self))
            .sink(receiveCompletion: { _ in
                DispatchQueue.main.async {
                    self.chatSendingCancellable = nil
                    self.newChat = ""
                }
            }, receiveValue: { _ in
                DispatchQueue.main.async {
                    self.chatSendingCancellable?.cancel()
                }
            })
    }
    
    var body: some View {
        HStack {
            if game.isUserPlaying {
                Menu {
                    channelMenuButton(
                        .main,
                        title: channelTitle(.main),
                        subtitle: LocalizedStringResource(
                            "Visible to everyone",
                            comment: "Subtitle for the public game-chat channel"
                        )
                    )
                    channelMenuButton(
                        .malkovich,
                        title: channelTitle(.malkovich),
                        subtitle: LocalizedStringResource(
                            "Hidden from opponent, visible to spectators",
                            comment: "Malkovich game-chat visibility; used as the channel subtitle and accessibility value"
                        )
                    )
                    channelMenuButton(
                        .personal,
                        title: channelTitle(.personal),
                        subtitle: personalVisibilityDescription
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedChannelTitle)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.bold())
                    }
                }
                .layoutPriority(1)
                .accessibilityLabel(
                    Text(
                        "Chat channel",
                        comment: "Accessibility label for the menu that selects who can see a game-chat message"
                    )
                )
                .accessibilityValue(Text(selectedChannelTitle))
                Divider()
                    .frame(height: channelDividerHeight)
            }
            TextField(text: $newChat) {
                EmptyView()
            }
            .background(alignment: .leading) {
                if newChat.isEmpty {
                    Text(channelPlaceholder)
                        .foregroundStyle(Color(.placeholderText))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(
                Text(channelPlaceholder)
            )
            .layoutPriority(1)
            .submitLabel(.send)
            .onSubmit {
                self.sendChat()
            }
            if self.chatSendingCancellable == nil {
                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .disabled(newChat.count == 0)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(backgroundColor)
    }
}

#if DEBUG
#Preview("New message input", traits: .fixedLayout(width: 350, height: 100)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game)
        .environmentObject(ogs)
}

#Preview("New Malkovich message input", traits: .fixedLayout(width: 350, height: 100)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: .malkovich)
        .environmentObject(ogs)
}

#Preview("New personal message input", traits: .fixedLayout(width: 350, height: 100)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: .personal)
        .environmentObject(ogs)
}

#Preview("New personal message input — Accessibility", traits: .fixedLayout(width: 350, height: 140)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: .personal)
        .environmentObject(ogs)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("New spectator message input", traits: .fixedLayout(width: 350, height: 100)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "spectator", id: -1)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game)
        .environmentObject(ogs)
}

#Preview("Game chat", traits: .fixedLayout(width: 350, height: 400)) {
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return ChatLog(game: game)
        .environmentObject(ogs)
}

#Preview("Game chat — Signed out", traits: .fixedLayout(width: 350, height: 400)) {
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    return ChatLog(game: game)
        .environmentObject(OGSService.previewInstance())
}
#endif
