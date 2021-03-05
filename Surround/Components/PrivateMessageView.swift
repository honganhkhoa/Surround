//
//  PrivateMessageView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 04/03/2021.
//

import SwiftUI
import URLImage

struct PrivateMessageView: View {
    @EnvironmentObject var ogs: OGSService
    
    @State var selectedUserId = -1
    @State var newChat = ""
    
    func user(id userId: Int) -> OGSUser? {
        if let user = ogs.cachedUsersById[userId] {
            return user
        } else {
            if let firstMessage = ogs.privateMessagesByUserId[userId]?.first {
                if firstMessage.from.id == userId {
                    return firstMessage.from
                } else {
                    return firstMessage.to
                }
            }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal]) {
                HStack(spacing: 10) {
                    ForEach(ogs.privateMessagesActiveUserIds.sorted(), id: \.self) { userId in
                        if let user = user(id: userId) {
                            VStack(spacing: 0) {
                                ZStack {
                                    if let iconURL = user.iconURL(ofSize: 64) {
                                        URLImage(url: iconURL) { image in
                                            image.resizable()
                                        }
                                        .frame(width: 48, height: 48)
                                    } else {
                                        Text("\(String(user.username.first!))")
                                            .font(.system(size: 32)).bold()
                                            .frame(width: 48, height: 48)
                                            .background(Color.gray)
                                    }
                                }
                                .border(Color.blue, width: userId == selectedUserId ? 2 : 0)
                                .padding(5)
                                Text(user.username)
                                    .font(userId == selectedUserId ? Font.subheadline.bold() : .subheadline)
                                    .minimumScaleFactor(0.4)
                                    .foregroundColor(user.uiColor)
                                    .frame(maxWidth: 100)
                            }
                        }
                    }
                }.padding(.vertical, 5)
            }
            .padding(.horizontal)
            .background(Color(.systemGray4))
            if selectedUserId != -1 {
                Divider()
                VStack(spacing: 0) {
                    PrivateMessageLog(messages: ogs.privateMessagesByUserId[selectedUserId] ?? [])
                    Divider()
                    HStack {
                        TextField("Aa", text: $newChat)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            selectedUserId = ogs.privateMessagesActiveUserIds.sorted().first ?? -1
        }
    }
}

struct PrivateMessageView_Previews: PreviewProvider {
    static var previews: some View {
        PrivateMessageView()
            .environmentObject(OGSService.previewInstance(
                user: OGSUser(username: "hakhoa", id: 765826)
            ))
            .previewLayout(.fixed(width: 300, height: 500))
    }
}
