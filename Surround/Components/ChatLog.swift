//
//  ChatLog.swift
//  Surround
//
//  Created by Anh Khoa Hong on 05/01/2021.
//

import SwiftUI
import Combine

struct VariationShareDraft {
    let focusRequestID = UUID()
    let gameID: GameID
    let variation: Variation
    var name: String

    init(
        gameID: GameID,
        variation: Variation,
        name: String = ""
    ) {
        self.gameID = gameID
        self.variation = variation
        self.name = name
    }
}

struct ChatLogSelection: Hashable {
    enum Target: Hashable {
        case move(Int)
        case chatLine(OGSChatLine.ID)
    }

    let target: Target
    let preview: ChatLogSelectionPreview

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(target)
    }
}

struct ChatLogSelectionPreview {
    var position: BoardPosition?
    var variation: Variation?
    var coordinates: [[Int]] = []
}

struct ChatLog: View {
    @ObservedObject var game: Game
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var ogs: OGSService
    var selection: Binding<ChatLogSelection?> = .constant(nil)
    var selectedChannel: Binding<OGSChatSendChannel> = .constant(.main)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var focusInputOnAppear = false
    var onVariationShared: () -> Void = {}
    var onCancelVariationSharing: () -> Void = {}
    
    @State var atEndOfChat = false
    @State var shouldScrollToEndAfterKeyboardChange = false
    @State private var inputDismissalRequest = 0

    func shouldMergeChat(at index: Int) -> Bool {
        return index > 0
            && game.chatLog[index].moveNumber
                == game.chatLog[index - 1].moveNumber
            && game.chatLog[index].user.id == game.chatLog[index - 1].user.id
            && game.chatLog[index].channel == game.chatLog[index - 1].channel
    }

    private func clearSelection() {
        selection.wrappedValue = nil
    }

    private func clearSelectionAndDismissInput() {
        clearSelection()
        inputDismissalRequest += 1
    }

    private func toggleMoveSelection(_ moveNumber: Int) {
        let target = ChatLogSelection.Target.move(moveNumber)
        guard selection.wrappedValue?.target != target else {
            clearSelection()
            return
        }

        selection.wrappedValue = ChatLogSelection(
            target: target,
            preview: ChatLogSelectionPreview(
                position: game.positionByLastMoveNumber[moveNumber]
            )
        )
    }

    private func toggleChatLineSelection(_ line: OGSChatLine) {
        let target = ChatLogSelection.Target.chatLine(line.id)
        guard selection.wrappedValue?.target != target else {
            clearSelection()
            return
        }

        var line = line
        selection.wrappedValue = ChatLogSelection(
            target: target,
            preview: ChatLogSelectionPreview(
                position: line.variation?.position,
                variation: line.variation,
                coordinates: line.coordinates
            )
        )
    }

    static func moveDividerNumbers(for moveNumbers: [Int?]) -> [Int?] {
        var lastMoveNumber: Int?
        return moveNumbers.map { moveNumber -> Int? in
            guard let moveNumber else {
                return nil
            }
            guard moveNumber != lastMoveNumber else {
                return nil
            }
            lastMoveNumber = moveNumber
            return moveNumber
        }
    }

    var chatLines: some View {
        let moveDividerNumbers = Self.moveDividerNumbers(
            for: game.chatLog.map(\.moveNumber)
        )
        return ForEach(
            Array(game.chatLog.enumerated()),
            id: \.1
        ) { index, chatLine in
            if let moveNumber = moveDividerNumbers[index] {
                let moveTarget = ChatLogSelection.Target.move(
                    moveNumber
                )
                Button {
                    toggleMoveSelection(moveNumber)
                } label: {
                    ZStack {
                        Divider()
                            .allowsHitTesting(false)
                        HStack {
                            Spacer()
                            Text("Move \(moveNumber)")
                                .font(.caption2)
                                .padding(.leading, 5)
                                .background {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            Color(
                                                colorScheme == .dark
                                                    ? UIColor.systemBackground
                                                    : UIColor.systemGray6
                                            )
                                        )
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            selection.wrappedValue?.target
                                                == moveTarget
                                                ? Color.accentColor
                                                : .clear,
                                            lineWidth: 2
                                        )
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection.wrappedValue?.target == moveTarget
                        ? .isSelected
                        : []
                )
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameChatMove(
                        moveNumber
                    )
                )
                Spacer().frame(height: 2)
            }
            let lineTarget = ChatLogSelection.Target.chatLine(chatLine.id)
            ChatLine(
                chatLine: chatLine,
                showUsername: !shouldMergeChat(at: index),
                horizontalAlignment: ogs.user?.id == chatLine.user.id
                    ? .trailing
                    : .leading,
                isSelected: selection.wrappedValue?.target == lineTarget,
                accessibilityIdentifier: SurroundUITestContract
                    .AccessibilityID.gameChatLine(chatLine.id),
                select: {
                    toggleChatLineSelection(chatLine)
                }
            )
            Spacer().frame(height: 2)
        }
    }

    private func selectionStillExists(in chatLog: [OGSChatLine]) -> Bool {
        guard let target = selection.wrappedValue?.target else {
            return true
        }

        switch target {
        case .move(let moveNumber):
            return chatLog.contains { $0.moveNumber == moveNumber }
        case .chatLine(let id):
            return chatLog.contains { $0.id == id }
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
//                                    print("scroll \(geometry.frame(in: .named("scrollView")))")
//                                    print("scrollView \(scrollViewGeometry.size)")
                                return AnyView(EmptyView())
                            }.frame(width: 10, height: 1).id("scrollViewBottom")
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 0)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: scrollViewGeometry.size.height,
                            alignment: .top
                        )
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(
                                    perform: clearSelectionAndDismissInput
                                )
                                .accessibilityHidden(true)
                        }
                        .onAppear {
                            scrollView.scrollTo("scrollViewBottom")
                            game.markAllChatAsRead()
                        }
                        .onReceive(game.$chatLog) { newChatLog in
                            if !selectionStillExists(in: newChatLog) {
                                clearSelection()
                            }
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
                }
                .coordinateSpace(name: "scrollView")
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameChatLog
                )
            }
            if ogs.user != nil {
                NewChatInput(
                    game: game,
                    selectedChannel: selectedChannel,
                    variationShareDraft: variationShareDraft,
                    focusInputOnAppear: focusInputOnAppear,
                    inputDismissalRequest: inputDismissalRequest,
                    onVariationShared: onVariationShared,
                    onCancelVariationSharing: onCancelVariationSharing
                )
                    .id(game.ID)
            }
        }
        .background(
            Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6)
                .shadow(radius: 2)
        )
        .onDisappear(perform: clearSelection)
        .onChange(of: game.ID) { _, _ in
            clearSelection()
        }
    }
}

private struct VariationSharePreviewRow: View {
    let variation: Variation
    let channel: OGSChatSendChannel
    let onCancel: () -> Void

    private var title: LocalizedStringResource {
        switch channel {
        case .main:
            return LocalizedStringResource(
                "Sharing variation",
                comment: "Title shown beside a draft variation preview while it is being prepared for public game chat."
            )
        case .malkovich, .personal:
            return LocalizedStringResource(
                "Recording variation",
                comment: "Title shown beside a draft variation preview while it is being prepared for Malkovich or personal chat, where it is recorded privately rather than shared publicly."
            )
        }
    }

    private var accessibilityValue: String {
        let moves = "\(variation.basePosition.lastMoveNumber):"
            + variation.moves.map { $0.toOGSString() }.joined(separator: "-")
        let marks = variation.markups.ogsMarks(
            boardWidth: variation.position.width,
            boardHeight: variation.position.height
        ).sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return marks.isEmpty ? moves : "\(moves)|marks:\(marks)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BoardView(
                boardPosition: variation.position,
                variation: variation,
                markups: .constant(variation.markups)
            )
            .frame(width: 120, height: 120)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID
                    .gameVariationSharePreview
            )
            .accessibilityValue(
                Text(verbatim: accessibilityValue),
                isEnabled: SurroundUITestContract.isEnabled
            )

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(title)
                    .font(Font.title2.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID
                            .gameVariationShareStatus
                    )
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .padding(10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID
                            .gameVariationShareCancel
                    )
            }
            .frame(height: 120)
        }
    }
}

struct NewChatInput: View {
    private enum VariationShareFailure: Hashable, Identifiable {
        case invalidVariation
        case unavailable
        case retryable

        var id: Self { self }

        var message: LocalizedStringResource {
            switch self {
            case .invalidVariation:
                return LocalizedStringResource(
                    "This variation is no longer available.",
                    comment: "Message shown when an analyzed variation can no longer be shared because its branch has changed or been removed."
                )
            case .unavailable:
                return LocalizedStringResource(
                    "This variation cannot be shared right now.",
                    comment: "Message shown after a temporary connection or account-state problem prevents an analyzed variation from being shared."
                )
            case .retryable:
                return LocalizedStringResource("Please try again.")
            }
        }
    }

    var game: Game
    @State private var newChat = ""
    @EnvironmentObject var ogs: OGSService
    var selectedChannel: Binding<OGSChatSendChannel> = .constant(.main)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var focusInputOnAppear = false
    var inputDismissalRequest = 0
    var onVariationShared: () -> Void = {}
    var onCancelVariationSharing: () -> Void = {}
    @ScaledMetric(relativeTo: .body) private var channelDividerHeight: CGFloat = 28
    
    @State private var chatSendingCancellable: AnyCancellable?
    @State private var variationShareFailure: VariationShareFailure?
    @FocusState private var isInputFocused: Bool

    private func focusInput() {
        DispatchQueue.main.async {
            isInputFocused = true
        }
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
        channelTitle(selectedChannel.wrappedValue)
    }

    private var channelPlaceholder: LocalizedStringResource {
        if variationShareDraft.wrappedValue != nil {
            return LocalizedStringResource(
                "Variation name...",
                comment: "Single-line game-chat composer placeholder shown while naming an analyzed variation before sharing it; the field may be left blank for an automatic numeric name."
            )
        }

        switch selectedChannel.wrappedValue {
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
            selectedChannel.wrappedValue = channel
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: selectedChannel.wrappedValue == channel ? "checkmark.circle.fill" : "circle")
            }
            Text(subtitle)
        }
        .accessibilityAddTraits(
            selectedChannel.wrappedValue == channel ? .isSelected : []
        )
        .accessibilityIdentifier(channelAccessibilityIdentifier(channel))
    }

    private func channelAccessibilityIdentifier(
        _ channel: OGSChatSendChannel
    ) -> String {
        switch channel {
        case .main:
            return SurroundUITestContract.AccessibilityID.gameChatChannelMain
        case .malkovich:
            return SurroundUITestContract.AccessibilityID
                .gameChatChannelMalkovich
        case .personal:
            return SurroundUITestContract.AccessibilityID
                .gameChatChannelPersonal
        }
    }

    private var backgroundColor: Color {
        switch selectedChannel.wrappedValue {
        case .main:
            return Color(.systemBackground)
        case .malkovich:
            return Color(.systemGreen).opacity(0.2)
        case .personal:
            return Color(.systemBlue).opacity(0.2)
        }
    }

    private var inputText: Binding<String> {
        if variationShareDraft.wrappedValue != nil {
            return Binding(
                get: {
                    variationShareDraft.wrappedValue?.name ?? ""
                },
                set: { name in
                    guard var draft = variationShareDraft.wrappedValue else {
                        return
                    }
                    draft.name = name
                    variationShareDraft.wrappedValue = draft
                }
            )
        }
        return $newChat
    }

    private var canSend: Bool {
        variationShareDraft.wrappedValue != nil || !newChat.isEmpty
    }

    private func send() {
        if let draft = variationShareDraft.wrappedValue {
            do {
                try ogs.shareVariation(
                    draft.variation,
                    in: game,
                    channel: selectedChannel.wrappedValue,
                    name: draft.name
                )
                onVariationShared()
            } catch let error as OGSServiceError {
                switch error {
                case .invalidVariation:
                    variationShareFailure = .invalidVariation
                    onVariationShared()
                case .variationSharingUnavailable:
                    variationShareFailure = .unavailable
                default:
                    variationShareFailure = .retryable
                }
            } catch {
                variationShareFailure = .retryable
            }
            return
        }

        guard self.chatSendingCancellable == nil && newChat.count > 0 else {
            return
        }
        
        let channel = selectedChannel.wrappedValue.resolved(
            isUserPlaying: game.isUserPlaying
        )
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
        VStack(spacing: 0) {
            if let draft = variationShareDraft.wrappedValue {
                VariationSharePreviewRow(
                    variation: draft.variation,
                    channel: selectedChannel.wrappedValue.resolved(
                        isUserPlaying: game.isUserPlaying
                    ),
                    onCancel: onCancelVariationSharing
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

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
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID
                            .gameChatChannelPicker
                    )
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
                TextField(text: inputText) {
                    EmptyView()
                }
                .focused($isInputFocused)
                .background(alignment: .leading) {
                    if inputText.wrappedValue.isEmpty {
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
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameChatInput
                )
                .layoutPriority(1)
                .submitLabel(.send)
                .onSubmit {
                    self.send()
                }
                if variationShareDraft.wrappedValue != nil
                    || self.chatSendingCancellable == nil {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.gameChatSend
                    )
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
        }
        .background(backgroundColor)
        .onAppear {
            if focusInputOnAppear || variationShareDraft.wrappedValue != nil {
                focusInput()
            }
        }
        .onChange(of: variationShareDraft.wrappedValue?.focusRequestID) {
            _, focusRequestID in
            if focusRequestID != nil {
                focusInput()
            }
        }
        .onChange(of: inputDismissalRequest) {
            isInputFocused = false
        }
        .alert(
            String(
                localized: "Couldn’t share variation",
                comment: "Alert title shown when sending an analyzed variation to game chat fails."
            ),
            isPresented: Binding(
                get: { variationShareFailure != nil },
                set: { isPresented in
                    if !isPresented {
                        variationShareFailure = nil
                    }
                }
            ),
            presenting: variationShareFailure
        ) { _ in
        } message: {
            Text($0.message)
        }
    }
}

#if DEBUG
#Preview("New message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.main
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New Malkovich message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.malkovich
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New personal message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.personal
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New personal message input — Accessibility", traits: .fixedLayout(width: 350, height: 140)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.personal
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Variation name input", traits: .fixedLayout(width: 350, height: 180)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.main
    @Previewable @State var variationShareDraft: VariationShareDraft? = {
        let game = TestData.EuropeanChampionshipWithChat
        return VariationShareDraft(
            gameID: game.ID,
            variation: Variation(
                position: game.currentPosition,
                basePosition: game.initialPosition
            )
        )
    }()
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(
        game: game,
        selectedChannel: $selectedChannel,
        variationShareDraft: $variationShareDraft,
        onCancelVariationSharing: {
            variationShareDraft = nil
        }
    )
    .environmentObject(ogs)
}

#Preview("Variation name input — Accessibility", traits: .fixedLayout(width: 350, height: 240)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.malkovich
    @Previewable @State var variationShareDraft: VariationShareDraft? = {
        let game = TestData.EuropeanChampionshipWithChat
        return VariationShareDraft(
            gameID: game.ID,
            variation: Variation(
                position: game.currentPosition,
                basePosition: game.initialPosition
            )
        )
    }()
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(
        game: game,
        selectedChannel: $selectedChannel,
        variationShareDraft: $variationShareDraft,
        onCancelVariationSharing: {
            variationShareDraft = nil
        }
    )
    .environmentObject(ogs)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("New spectator message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @State var selectedChannel = OGSChatSendChannel.main
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "spectator", id: -1)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, selectedChannel: $selectedChannel)
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
