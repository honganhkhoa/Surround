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
    
    @State var atEndOfChat = false

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
                    }
                    .onEnded { _ in
                        hoveredPosition.wrappedValue = nil
                        hoveredVariation.wrappedValue = nil
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
                        }
                        .onReceive(game.$chatLog) { newChatLog in
                            if atEndOfChat {
                                DispatchQueue.main.async {
                                    scrollView.scrollTo("scrollViewBottom")
                                }
                            }
                        }
                    }
                }.coordinateSpace(name: "scrollView")
            }
            if ogs.user != nil {
                NewChatInput(game: game)
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
    @State var newChat = ""
    @EnvironmentObject var ogs: OGSService
    @State var malkovich = false
    
    @State var chatSendingCancellable: AnyCancellable?

    func sendChat() {
        guard self.chatSendingCancellable == nil && newChat.count > 0 else {
            return
        }
        
        let channel: OGSChatChannel = game.isUserPlaying ? (malkovich ? .malkovich : .main) : .spectator
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
        VStack(alignment: .leading) {
            HStack {
                if game.isUserPlaying {
                    Button(action: { malkovich.toggle() }) {
                        Text(malkovich ? "Malkovich" : "Chat")
                    }
                    Divider()
                }
                TextField(
                    malkovich ? "Note to yourself" : "Say hi!",
                    text: $newChat,
                    onCommit: sendChat
                )
                if self.chatSendingCancellable == nil {
                    Button(action: sendChat) {
                        Image(systemName: "arrow.up.circle.fill")
                    }.disabled(newChat.count == 0)
                } else {
                    ProgressView()
                }
            }.fixedSize(horizontal: false, vertical: true)
            if malkovich {
                Text("Malkovich log is hidden from your opponent during game, and always visible to you and observers.")
                    .font(.caption2)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color(malkovich ? .systemGreen : .systemBackground))
    }
}

struct ChatLog_Previews: PreviewProvider {
    static var previews: some View {
        let ogs = OGSService.previewInstance(
            user: OGSUser(username: "artem92", id: 655950)
        )
        let game = TestData.EuropeanChampionshipWithChat
        game.ogs = ogs
        return Group {
            NewChatInput(game: game)
                .previewLayout(.fixed(width: 350, height: 100))
                .environmentObject(ogs)
            ChatLog(game: game)
                .previewLayout(.fixed(width: 350, height: 400))
                .environmentObject(ogs)
            ChatLog(game: game)
                .previewLayout(.fixed(width: 350, height: 400))
                .environmentObject(OGSService.previewInstance())
        }
    }
}
