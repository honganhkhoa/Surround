//
//  PrivateMessageLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 03/03/2021.
//

import SwiftUI

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
                if let fromUser = ogs.user?.id == message.from.id {
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
                }
            }.padding(.horizontal)
        }
    }
}

struct PrivateMessageLog: View {
    var messages: [OGSPrivateMessage]
    
    @State var atEndOfChat = false
    @State var shouldScrollToEndAfterKeyboardChange = false

    var body: some View {
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
                    .onAppear {
                        scrollView.scrollTo("scrollViewBottom")
                    }
                    .onChange(of: messages) { _ in
                        if atEndOfChat {
                            scrollView.scrollTo("scrollViewBottom")
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                        self.shouldScrollToEndAfterKeyboardChange = self.atEndOfChat
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
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
}

struct PrivateMessageLog_Previews: PreviewProvider {
    static var previews: some View {
        PrivateMessageLog(messages: OGSPrivateMessage.sampleData)
            .previewLayout(.fixed(width: 300, height: 400))
            .environmentObject(OGSService.previewInstance(user: OGSUser(username: "hakhoa", id: 765826)))
    }
}
