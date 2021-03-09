//
//  PrivateMessageView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 04/03/2021.
//

import SwiftUI
import URLImage
import Combine

struct PrivateMessageNotificationView: View {
    @EnvironmentObject var ogs: OGSService
    @State var selectedPeerId = -1
    @Namespace var selectingPeer
    
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
    
    var sortedPeers: [OGSUser] {
        var result = [OGSUser]()
        for peerId in ogs.privateMessagesActivePeerIds {
            if let user = user(id: peerId) {
                result.append(user)
            }
        }
        result.sort(by: {
            ogs.privateMessagesByPeerId[$0.id]?.last?.content.timestamp ?? 0 >
                ogs.privateMessagesByPeerId[$1.id]?.last?.content.timestamp ?? 0
        })
        return result
    }
    
    func selectPeer(id: Int) {
        guard ogs.superchatPeerIds.count == 0 || ogs.superchatPeerIds.contains(id) else {
            return
        }
        withAnimation {
            selectedPeerId = id
        }
    }
        
    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal]) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(sortedPeers, id: \.id) { peer in
                        Button(action: { selectPeer(id: peer.id) }) {
                            VStack(spacing: 0) {
                                ZStack {
                                    if peer.id == selectedPeerId {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [3]))
                                            .frame(width: 58, height: 58)
                                            .matchedGeometryEffect(id: "selectionIndicator", in: selectingPeer)
                                    }
                                    if let iconURL = peer.iconURL(ofSize: 64) {
                                        URLImage(url: iconURL) { image in
                                            image.resizable()
                                        }
                                        .frame(width: 48, height: 48)
                                        .padding(5)
                                    } else {
                                        Text("\(String(peer.username.first!))")
                                            .font(.system(size: 32)).bold()
                                            .frame(width: 48, height: 48)
                                            .background(Color.gray)
                                            .padding(5)
                                    }
                                }
                                Text(peer.username)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .foregroundColor(peer.uiColor)
                                    .frame(width: 90)
                            }
                        }
                    }
                }.padding(.vertical, 5)
            }
            .padding(.horizontal)
            .background(Color(.systemGray4))
            if selectedPeerId != -1, let peer = user(id: selectedPeerId) {
                Divider()
                if ogs.superchatPeerIds.contains(selectedPeerId) {
                    Text("⚠️ OGS Moderator's official message. Please respond.")
                        .font(.subheadline).bold()
                        .leadingAlignedInScrollView()
                        .padding(.horizontal)
                        .padding(.vertical, 5)
                        .foregroundColor(.white)
                        .background(Color.purple)
                    Divider()
                }
                PrivateMessageLog(peer: peer)
            }
        }
        .onAppear {
            selectedPeerId = ogs.superchatPeerIds.first ?? sortedPeers.first?.id ?? -1
        }
        .onChange(of: ogs.superchatPeerIds) { superchatPeerIds in
            if superchatPeerIds.count > 0, let firstPeerId = superchatPeerIds.first {
                if !superchatPeerIds.contains(selectedPeerId) {
                    DispatchQueue.main.async {
                        withAnimation {
                            self.selectedPeerId = firstPeerId
                        }
                    }
                }
            }
        }
    }
}

struct PrivateMessageView_Previews: PreviewProvider {
    static var previews: some View {
        PrivateMessageNotificationView()
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826)
            ))
            .previewLayout(.fixed(width: 300, height: 500))
    }
}
