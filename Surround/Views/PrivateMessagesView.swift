//
//  PrivateMessagesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/03/2021.
//

import SwiftUI
import URLImage

struct PrivateMessagesView: View {
    @EnvironmentObject var ogs: OGSService

    private let privateMessagesOverride: [OGSPrivateMessage]?
    private let unreadPeerIdsOverride: Set<Int>?
    private let marksThreadsAsRead: Bool

    init(
        privateMessages: [OGSPrivateMessage]? = nil,
        unreadPeerIds: Set<Int>? = nil,
        marksThreadsAsRead: Bool = true
    ) {
        privateMessagesOverride = privateMessages
        unreadPeerIdsOverride = unreadPeerIds
        self.marksThreadsAsRead = marksThreadsAsRead
    }

    private var privateMessagesByPeerId: [Int: [OGSPrivateMessage]] {
        guard let privateMessagesOverride else {
            return ogs.privateMessagesByPeerId
        }
        guard let currentUserId = ogs.user?.id else {
            return [:]
        }
        return Dictionary(grouping: privateMessagesOverride) { message in
            message.from.id == currentUserId ? message.to.id : message.from.id
        }
    }

    private var activePeerIds: Set<Int> {
        if privateMessagesOverride != nil {
            return Set(privateMessagesByPeerId.keys)
        }
        return ogs.privateMessagesActivePeerIds
    }

    func user(id userId: Int) -> OGSUser? {
        if let user = ogs.cachedUsersById[userId] {
            return user
        } else {
            if let firstMessage = privateMessagesByPeerId[userId]?.first {
                if firstMessage.from.id == userId {
                    return firstMessage.from
                } else {
                    return firstMessage.to
                }
            }
        }
        return nil
    }
    
    var data: [(peer: OGSUser, lastMessage: OGSPrivateMessage)] {
        var result = [(peer: OGSUser, lastMessage: OGSPrivateMessage)]()
        for peerId in activePeerIds {
            if let user = user(id: peerId), let lastMessage = privateMessagesByPeerId[peerId]?.last {
                result.append((peer: user, lastMessage: lastMessage))
            }
        }
        result.sort(by: { $0.lastMessage.content.timestamp > $1.lastMessage.content.timestamp })
        return result
    }

    private func hasUnreadMessage(
        from peer: OGSUser,
        lastMessage: OGSPrivateMessage
    ) -> Bool {
        if let unreadPeerIdsOverride {
            return unreadPeerIdsOverride.contains(peer.id)
        }
        return userDefaults[.lastSeenPrivateMessageByOGSUserId]?[peer.id] ?? 0
            < lastMessage.content.timestamp
    }

    var body: some View {
        List {
            Section(footer: Text("Private messages are only stored for a few days, so please make sure to save any important information somewhere else.").font(.caption)) {
                ForEach(data, id: \.peer.id) { peer, lastMessage in
                    NavigationLink(destination:
                                    PrivateMessageLog(
                                        peer: peer,
                                        messages: privateMessagesOverride == nil
                                            ? nil
                                            : privateMessagesByPeerId[peer.id],
                                        marksThreadAsRead: marksThreadsAsRead
                                    )
                                    .navigationBarTitle(peer.username)
                                    .navigationBarTitleDisplayMode(.inline)
                    ) {
                        HStack {
                            if let iconURL = peer.iconURL(ofSize: 64) {
                                URLImage(url: iconURL) { $0.resizable() }
                                    .frame(width: 48, height: 48)
                            } else {
                                Text(verbatim: "\(String(peer.username.first!))")
                                    .font(.system(size: 32)).bold()
                                    .frame(width: 48, height: 48)
                                    .background(Color.gray)
                            }
                            let hasUnread = hasUnreadMessage(
                                from: peer,
                                lastMessage: lastMessage
                            )
                            VStack(alignment: .leading) {
                                Text(peer.username)
                                    .foregroundColor(peer.uiColor)
                                    .font(hasUnread ? Font.body.bold() : .body)
                                Text(lastMessage.content.message)
                                    .font(hasUnread ? Font.subheadline.bold() : .subheadline)
                                    .foregroundColor(Color(.secondaryLabel))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitle("Private messages")
    }
}

#if DEBUG
#Preview("Private messages — Populated inbox") {
    let nav = NavigationService()
    nav.main.rootView = .privateMessages
    return NavigationStack {
        PrivateMessagesView(
            privateMessages: OGSPrivateMessage.sampleData,
            unreadPeerIds: [314459, 955348],
            marksThreadsAsRead: false
        )
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            privateMessages: []
        )
    )
    .environmentObject(nav)
    .environment(\.surroundAllowsRemoteActivity, false)
}

#Preview("Private messages — Empty inbox") {
    let nav = NavigationService()
    nav.main.rootView = .privateMessages
    return NavigationStack {
        PrivateMessagesView(
            privateMessages: [],
            unreadPeerIds: [],
            marksThreadsAsRead: false
        )
            .modifier(RootViewSwitchingMenu())
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(username: "hakhoa", id: 765826),
            privateMessages: []
        )
    )
    .environmentObject(nav)
    .environment(\.surroundAllowsRemoteActivity, false)
}
#endif
