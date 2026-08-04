//
//  PrivateMessageLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 03/03/2021.
//

import SwiftUI
import Combine

struct PrivateMessageLine: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme

    var message: OGSPrivateMessage
    var lastMessage: OGSPrivateMessage?
    
    var body: some View {
        VStack {
            if lastMessage == nil || (message.content.dateString != lastMessage?.content.dateString) {
                ZStack {
                    Divider()
                    Text(message.content.dateString)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .background(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                }
            }
            HStack {
                let fromUser = ogs.user?.id == message.from.id
                if fromUser {
                    Spacer()
                }
                VStack(alignment: fromUser ? .trailing : .leading, spacing: 2) {
                    if lastMessage == nil || message.content.dateString != lastMessage?.content.dateString || message.from.id != lastMessage?.from.id {
                        Text(message.from.username).font(.caption2).bold()
                        .foregroundColor(message.from.uiColor)
                    }
                    Text(message.content.message).font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.systemGray4))
                .cornerRadius(10)
                if !fromUser {
                    Spacer()
                }
            }.padding(.horizontal)
        }
    }
}

struct PrivateMessageLog: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @EnvironmentObject var ogs: OGSService
    var peer: OGSUser

    private let messagesOverride: [OGSPrivateMessage]?
    private let marksThreadAsRead: Bool

    init(
        peer: OGSUser,
        messages: [OGSPrivateMessage]? = nil,
        marksThreadAsRead: Bool = true
    ) {
        self.peer = peer
        messagesOverride = messages
        self.marksThreadAsRead = marksThreadAsRead
    }

    var messages: [OGSPrivateMessage] {
        messagesOverride ?? ogs.privateMessagesByPeerId[peer.id] ?? []
    }

    @State var atEndOfChat = false
    @State var shouldScrollToEndAfterKeyboardChange = false
    @State var newChat = ""
    @State var chatSendingCancellable: AnyCancellable?
    
    func sendMessage() {
        guard allowsRemoteActivity else { return }
        if newChat.count > 0 {
            chatSendingCancellable = ogs.sendPrivateMessage(to: peer, message: newChat).sink(
                receiveCompletion: { _ in
                    self.chatSendingCancellable = nil
                },
                receiveValue: { _ in }
            )
            newChat = ""
        }
    }

    func markThreadAsRead() {
        guard marksThreadAsRead else { return }
        ogs.markPrivateMessageThreadAsRead(peerId: peer.id)
    }

    var messagesScrollView: some View {
        GeometryReader { scrollViewGeometry in
            ScrollView {
                ScrollViewReader { scrollView in
                    LazyVStack(spacing: 2) {
                        ForEach(Array(messages.enumerated()), id: \.1.messageKey) { index, message in
                            PrivateMessageLine(
                                message: message,
                                lastMessage: index == 0 ? nil : messages[index - 1]
                            )
                        }
                        GeometryReader { geometry -> AnyView in
                            let endOfChatFrame = geometry.frame(in: .named(AnyHashable("scrollView")))
                            if endOfChatFrame.origin.y >= 0 && endOfChatFrame.origin.y <= scrollViewGeometry.size.height {
                                if !self.atEndOfChat {
                                    DispatchQueue.main.async {
                                        self.atEndOfChat = true
                                        markThreadAsRead()
                                    }
                                }
                            } else {
                                if self.atEndOfChat {
                                    DispatchQueue.main.async {
                                        self.atEndOfChat = false
                                    }
                                }
                            }
                            return AnyView(EmptyView())
                        }.frame(width: 10, height: 1).id("scrollViewBottom")
                    }
                    .padding(.vertical, 5)
                    .onAppear {
                        ogs.setUpNewPeerIfNecessary(peerId: peer.id)
                        scrollView.scrollTo("scrollViewBottom")
                        markThreadAsRead()
                    }
                    .onChange(of: messages) {
                        if atEndOfChat {
                            scrollView.scrollTo("scrollViewBottom")
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            messagesScrollView
            Divider()
            HStack {
                TextField(String("Aa"), text: $newChat, onCommit: sendMessage)
                if self.chatSendingCancellable == nil {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                    }.disabled(newChat.count == 0)
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

#if DEBUG
#Preview("Private messages — Conversation", traits: .fixedLayout(width: 300, height: 600)) {
    let peer = OGSPrivateMessage.sampleData.first!.from
    let messages = OGSPrivateMessage.sampleData.filter {
        $0.from.id == peer.id || $0.to.id == peer.id
    }
    PrivateMessageLog(
        peer: peer,
        messages: messages,
        marksThreadAsRead: false
    )
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826),
                privateMessages: []
            )
        )
        .environment(\.surroundAllowsRemoteActivity, false)
}
#endif
