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
        #if DEBUG && MAIN_APP
        SurroundAnimationDiagnostics.record(
            "draft.created", focusRequestID: focusRequestID
        )
        #endif
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
    @ObservedObject var session: ChatSessionState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openPlayerProfile) private var openPlayerProfile
    @EnvironmentObject var ogs: OGSService
    var selection: Binding<ChatLogSelection?> = .constant(nil)
    var selectedChannel: Binding<OGSChatSendChannel> = .constant(.main)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var focusInputOnAppear = false
    var onInteraction: () -> Void = {}
    var onVariationShared: () -> Void = {}
    var onCancelVariationSharing: () -> Void = {}
    
    @State private var isVisible = false
    @State private var visibleScrollAnchor: String?

    private func clearSelection() {
        selection.wrappedValue = nil
    }

    private func clearSelectionAndDismissInput() {
        clearSelection()
        session.dismissInput()
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

    var chatLines: some View {
        // Lazy rows can outlive this version of game.chatLog. Capture each
        // line and its neighboring-row metadata together before rendering.
        let rows = ChatLogRow.snapshot(of: game.chatLog)
        return ForEach(rows, id: \.chatLine) { row in
            VStack(spacing: 0) {
                let chatLine = row.chatLine
                if let moveNumber = row.moveDividerNumber {
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
                    showUsername: !row.shouldMerge,
                    horizontalAlignment: ogs.user?.id == chatLine.user.id
                        ? .trailing
                        : .leading,
                    isSelected: selection.wrappedValue?.target == lineTarget,
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameChatLine(chatLine.id),
                    select: {
                        toggleChatLineSelection(chatLine)
                    },
                    openProfile: openPlayerProfile.map { action in
                        { action(chatLine.user) }
                    }
                )
                Spacer().frame(height: 2)
            }
            .id(row.chatLine.id)
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
                            // Observe visibility outside lazy layout evaluation.
                            // Querying this marker's frame inside GeometryReader
                            // can loop layout on iOS 18 when the composer shrinks.
                            Color.clear
                                .frame(width: 10, height: 1)
                                .id("scrollViewBottom")
                                .onScrollVisibilityChange { isVisible in
                                    guard self.isVisible,
                                          session.isAtEndOfChat != isVisible else {
                                        return
                                    }
                                    session.isAtEndOfChat = isVisible
                                    if isVisible {
                                        game.markAllChatAsRead()
                                    }
                                }
                        }
                        .scrollTargetLayout()
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
                            isVisible = true
                            if let anchor = session.scrollAnchor,
                               !session.isAtEndOfChat {
                                // Restore after lazy rows have joined the layout.
                                DispatchQueue.main.async {
                                    guard isVisible else { return }
                                    scrollView.scrollTo(anchor, anchor: .top)
                                }
                            }
                            game.markAllChatAsRead()
                        }
                        .onDisappear { isVisible = false }
                        .onChange(of: game.ID) { _, _ in
                            scrollView.scrollTo("scrollViewBottom")
                        }
                        .onReceive(game.$chatLog) { newChatLog in
                            if !selectionStillExists(in: newChatLog) {
                                clearSelection()
                            }
                            if session.isAtEndOfChat {
                                DispatchQueue.main.async {
                                    scrollView.scrollTo("scrollViewBottom")
                                    game.markAllChatAsRead()
                                }
                            }
                        }
                        .onReceive(SystemPlatformServices.shared.keyboardWillChangeFramePublisher) { _ in
                            session.shouldScrollToEndAfterKeyboardChange =
                                session.isAtEndOfChat
                        }
                        .onReceive(SystemPlatformServices.shared.keyboardDidChangeFramePublisher) { _ in
                            if session.shouldScrollToEndAfterKeyboardChange {
                                DispatchQueue.main.async {
                                    scrollView.scrollTo("scrollViewBottom")
                                    session.shouldScrollToEndAfterKeyboardChange = false
                                }
                            }
                        }
                    }
                }
                .scrollPosition(id: $visibleScrollAnchor, anchor: .top)
                .onChange(of: visibleScrollAnchor) { _, anchor in
                    // Persist the last visible row without publishing scroll
                    // layout changes back through the entire game hierarchy.
                    // A departing view must not erase the replacement's anchor.
                    guard isVisible, let anchor else { return }
                    session.scrollAnchor = anchor
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .coordinateSpace(name: "scrollView")
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameChatLog
                )
            }
            if ogs.user != nil {
                NewChatInput(
                    game: game,
                    session: session,
                    selectedChannel: selectedChannel,
                    variationShareDraft: variationShareDraft,
                    focusInputOnAppear: focusInputOnAppear,
                    onInteraction: onInteraction,
                    onVariationShared: onVariationShared,
                    onCancelVariationSharing: onCancelVariationSharing
                )
                    .id(session.composerPresentationID)
            }
        }
        .background(
            Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.systemGray6)
                .shadow(radius: 2)
        )
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
    var game: Game
    @ObservedObject var session: ChatSessionState
    @EnvironmentObject var ogs: OGSService
    var selectedChannel: Binding<OGSChatSendChannel> = .constant(.main)
    var variationShareDraft: Binding<VariationShareDraft?> = .constant(nil)
    var focusInputOnAppear = false
    var onInteraction: () -> Void = {}
    var onVariationShared: () -> Void = {}
    var onCancelVariationSharing: () -> Void = {}
    @ScaledMetric(relativeTo: .body) private var channelDividerHeight: CGFloat = 28
    
    @FocusState private var isInputFocused: Bool
    @State private var composerID = UUID()
    @State private var isRestoringFocus = false
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    #endif

    private func focusInput() {
        let requestedRevision = session.focusRevision
        #if DEBUG && MAIN_APP
        let requestedFocusID = variationShareDraft.wrappedValue?.focusRequestID
        SurroundAnimationDiagnostics.record(
            "composer.focusQueued", ownerID: animationObservationID,
            focusRequestID: requestedFocusID,
            fields: ["alreadyFocused": String(isInputFocused)]
        )
        #endif
        DispatchQueue.main.async {
            guard session.shouldRestoreInputFocus(
                composerID: composerID, revision: requestedRevision
            ), !isInputFocused else { return }
            #if DEBUG && MAIN_APP
            SurroundAnimationDiagnostics.record(
                "composer.focusExecuting", ownerID: animationObservationID,
                focusRequestID: requestedFocusID,
                fields: [
                    "currentFocusRequest": variationShareDraft.wrappedValue?
                        .focusRequestID.uuidString ?? "none",
                    "alreadyFocused": String(isInputFocused),
                ]
            )
            #endif
            isRestoringFocus = true
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
            onInteraction()
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
                    onInteraction()
                }
            )
        }
        return Binding(
            get: { session.message },
            set: { message in
                session.message = message
                onInteraction()
            }
        )
    }

    private var canSend: Bool {
        variationShareDraft.wrappedValue != nil
            || (!session.message.isEmpty && !session.isSending)
    }

    private func send() {
        onInteraction()
        if let draft = variationShareDraft.wrappedValue {
            session.failure = nil
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
                    session.failure = .invalidVariation
                    onVariationShared()
                case .variationSharingUnavailable:
                    session.failure = .variationUnavailable
                default:
                    session.failure = .variationRetryable
                }
            } catch {
                session.failure = .variationRetryable
            }
            return
        }

        let channel = selectedChannel.wrappedValue.resolved(
            isUserPlaying: game.isUserPlaying
        )
        session.sendMessage { message in
            ogs.sendChat(in: game, channel: channel, body: message)
                .zip(game.$chatLog.setFailureType(to: Error.self))
                .map { _ in () }
                .eraseToAnyPublisher()
        }
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
                    || !session.isSending {
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
            session.composerAppeared(
                id: composerID,
                automaticallyFocus: focusInputOnAppear,
                shareFocusRequestID: variationShareDraft.wrappedValue?.focusRequestID
            )
            if session.wantsInputFocus {
                focusInput()
            } else {
                // A retained navigation destination may still hold its old
                // FocusState even though the game owner suspended input.
                isRestoringFocus = false
                isInputFocused = false
            }
        }
        .onDisappear {
            session.composerDisappeared(id: composerID)
        }
        .onChange(of: variationShareDraft.wrappedValue?.focusRequestID) {
            _, focusRequestID in
            #if DEBUG && MAIN_APP
            SurroundAnimationDiagnostics.record(
                "composer.draftChangeCallback", ownerID: animationObservationID,
                focusRequestID: focusRequestID
            )
            #endif
            session.requestShareFocus(focusRequestID)
            if session.wantsInputFocus {
                focusInput()
            }
        }
        .onChange(of: session.wantsInputFocus) { _, wantsFocus in
            if wantsFocus {
                focusInput()
            } else {
                isInputFocused = false
            }
        }
        .onChange(of: isInputFocused) { _, focused in
            if focused {
                guard session.isActiveComposer(composerID) else { return }
                session.recordInputFocus(true, composerID: composerID)
                if !isRestoringFocus {
                    onInteraction()
                }
                isRestoringFocus = false
            } else {
                // Focus can fall before onDisappear during layout replacement.
                // Record a user dismissal only if this composer remains active.
                let revision = session.focusRevision
                DispatchQueue.main.async {
                    session.recordInputFocus(
                        false, composerID: composerID,
                        expectedRevision: revision
                    )
                }
            }
        }
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "composer", ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        .surroundAnimationState(
            "composer.focusState", value: String(isInputFocused),
            ownerID: animationObservationID,
            focusRequestID: variationShareDraft.wrappedValue?.focusRequestID
        )
        #endif
        .alert(
            Text(session.failure?.title ?? LocalizedStringResource("Couldn’t send message")),
            isPresented: Binding(
                get: { session.failure != nil },
                // Adaptive replacement can dismiss the old alert presenter.
                // Only acknowledging the error discards the retained failure.
                set: { _ in }
            ),
            presenting: session.failure
        ) { failure in
            Button("OK") {
                if session.failure == failure {
                    session.failure = nil
                }
            }
        } message: {
            Text($0.message)
        }
    }
}

#if DEBUG
#Preview("New message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @StateObject var session = ChatSessionState()
    @Previewable @State var selectedChannel = OGSChatSendChannel.main
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, session: session, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New Malkovich message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @StateObject var session = ChatSessionState()
    @Previewable @State var selectedChannel = OGSChatSendChannel.malkovich
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, session: session, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New personal message input", traits: .fixedLayout(width: 350, height: 100)) {
    @Previewable @StateObject var session = ChatSessionState()
    @Previewable @State var selectedChannel = OGSChatSendChannel.personal
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, session: session, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("New personal message input — Accessibility", traits: .fixedLayout(width: 350, height: 140)) {
    @Previewable @StateObject var session = ChatSessionState()
    @Previewable @State var selectedChannel = OGSChatSendChannel.personal
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, session: session, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Variation name input", traits: .fixedLayout(width: 350, height: 180)) {
    @Previewable @StateObject var session = ChatSessionState()
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
        session: session,
        selectedChannel: $selectedChannel,
        variationShareDraft: $variationShareDraft,
        onCancelVariationSharing: {
            variationShareDraft = nil
        }
    )
    .environmentObject(ogs)
}

#Preview("Variation name input — Accessibility", traits: .fixedLayout(width: 350, height: 240)) {
    @Previewable @StateObject var session = ChatSessionState()
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
        session: session,
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
    @Previewable @StateObject var session = ChatSessionState()
    @Previewable @State var selectedChannel = OGSChatSendChannel.main
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "spectator", id: -1)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return NewChatInput(game: game, session: session, selectedChannel: $selectedChannel)
        .environmentObject(ogs)
}

#Preview("Game chat", traits: .fixedLayout(width: 350, height: 400)) {
    @Previewable @StateObject var session = ChatSessionState()
    let ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = ogs
    return ChatLog(game: game, session: session)
        .environmentObject(ogs)
}

#Preview("Game chat — Signed out", traits: .fixedLayout(width: 350, height: 400)) {
    @Previewable @StateObject var session = ChatSessionState()
    let game = TestData.EuropeanChampionshipWithChat
    game.ogs = OGSService.previewInstance(
        user: OGSUser(username: "artem92", id: 655950)
    )
    return ChatLog(game: game, session: session)
        .environmentObject(OGSService.previewInstance())
}
#endif
