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

    func user(id userId: Int) -> OGSUser? {
        if let user = ogs.cachedUsersById[userId] {
            return user
        } else {
            if let firstMessage = ogs.privateMessagesByPeerId[userId]?.first {
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
        for peerId in ogs.privateMessagesActivePeerIds {
            if let user = user(id: peerId), let lastMessage = ogs.privateMessagesByPeerId[peerId]?.last {
                result.append((peer: user, lastMessage: lastMessage))
            }
        }
        result.sort(by: { $0.lastMessage.content.timestamp > $1.lastMessage.content.timestamp })
        return result
    }

    var body: some View {
        List {
            Section(footer: Text("Private messages are only stored for a few days, so please make sure to save any important information somewhere else.").font(.caption)) {
                ForEach(data, id: \.peer.id) { peer, lastMessage in
                    NavigationLink(destination:
                                    PrivateMessageLog(peer: peer)
                                    .navigationBarTitle(peer.username)
                                    .navigationBarTitleDisplayMode(.inline)
                    ) {
                        HStack {
                            if let iconURL = peer.iconURL(ofSize: 64) {
                                URLImage(url: iconURL) { $0.resizable() }
                                    .frame(width: 48, height: 48)
                            } else {
                                Text("\(String(peer.username.first!))")
                                    .font(.system(size: 32)).bold()
                                    .frame(width: 48, height: 48)
                                    .background(Color.gray)
                            }
                            if let hasUnread = userDefaults[.lastSeenPrivateMessageByOGSUserId]?[peer.id] ?? 0 < lastMessage.content.timestamp {
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
        }
        .navigationBarTitle("Private messages")
        .modifier(RootViewSwitchingMenu())
    }
}

struct PrivateMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationService.shared.main.rootView = .privateMessages
        return NavigationView {
            PrivateMessagesView()
                .environmentObject(OGSService.previewInstance(
                    user: OGSUser(username: "hakhoa", id: 765826)
                ))
                .environmentObject(NavigationService.shared)
        }
    }
}
