//
//  QuickMatchView.swift
//  Surround
//
//  Created by Codex on 31/08/2026.
//

import SwiftUI

private struct QuickMatchCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

private struct QuickMatchActionArea: View {
    private enum KeyboardFocus: Hashable {
        case find
        case cancel
        case status
    }

    let recap: OGSQuickMatchRecap
    let accessibleRecap: String
    let findTitle: String
    let isSearching: Bool
    let isSubmitting: Bool
    let isCancelling: Bool
    let canFind: Bool
    let canCancel: Bool
    let disabledReason: String?
    let onFind: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var cancelIsFocused: Bool
    @AccessibilityFocusState private var findIsFocused: Bool
    @AccessibilityFocusState private var statusIsFocused: Bool
    @FocusState private var keyboardFocus: KeyboardFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            recapText
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchRecap
                )
                .accessibilityLabel(Text(verbatim: accessibleRecap))
                .accessibilityAddTraits(.updatesFrequently)

            if isSearching {
                HStack(spacing: 10) {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .accessibilityHidden(true)
                    }

                    Text(isCancelling ? "Cancelling…" : "Searching for a game…")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityFocused($statusIsFocused)
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID
                                .quickMatchSearching
                        )

                    if !isCancelling {
                        Button("Withdraw", role: .destructive, action: onCancel)
                            .fontWeight(.bold)
                            .disabled(!canCancel)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Withdraw live game search")
                            .accessibilityFocused($cancelIsFocused)
                            .focused($keyboardFocus, equals: .cancel)
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID.quickMatchCancel
                            )
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.accentColor.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focusable(isCancelling)
                .focused($keyboardFocus, equals: .status)
            } else {
                Button(action: onFind) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            if reduceMotion {
                                Image(systemName: "hourglass")
                                    .accessibilityHidden(true)
                            } else {
                                ProgressView()
                                    .tint(.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text(isSubmitting ? String(localized: "Starting searches…") : findTitle)
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(isSubmitting ? Color.primary : (canFind ? Color.white : Color.secondary))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    canFind
                        ? Color.accentColor
                        : Color(uiColor: .secondarySystemFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!canFind)
                .accessibilityHint(Text(verbatim: isSubmitting ? "" : accessibleRecap))
                .accessibilityFocused($findIsFocused)
                .focused($keyboardFocus, equals: .find)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchFind
                )
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.quickMatchConnectionReason
                    )
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGray6))
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            if isSearching {
                moveFocusToCurrentAction()
            }
        }
        .onChange(of: isSearching) { _, _ in
            moveFocusToCurrentAction()
        }
        .onChange(of: isCancelling) { _, _ in
            moveFocusToCurrentAction()
        }
    }

    @ViewBuilder
    private var recapText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recap.firstLine)
                .fixedSize(horizontal: false, vertical: true)
            if !recap.secondLine.isEmpty {
                Text(recap.secondLine)
                    .foregroundStyle(.secondary)
                    .fontWeight(.regular)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func moveFocusToCurrentAction() {
        Task { @MainActor in
            if isCancelling {
                statusIsFocused = true
                keyboardFocus = .status
            } else if isSearching {
                cancelIsFocused = true
                keyboardFocus = .cancel
            } else {
                findIsFocused = true
                keyboardFocus = .find
            }
        }
    }
}

private extension OGSQuickMatchActivityStatus {
    var quickMatchDescription: String? {
        switch self {
        case .none:
            return nil
        case .popular:
            return String(
                localized: "Popular lately",
                comment: "Quick Match option with many recent matches"
            )
        case .playersWaiting:
            return String(
                localized: "Players waiting",
                comment: "Quick Match option currently requested by compatible players"
            )
        }
    }
}

private struct QuickMatchActivityBadge: View {
    let status: OGSQuickMatchActivityStatus
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch status {
            case .none:
                EmptyView()
            case .popular:
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 2)
                    }
            case .playersWaiting:
                Circle()
                    .fill(Color.green)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Color.primary.opacity(0.45),
                                lineWidth: 1
                            )
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct QuickMatchActivityLegend: View {
    let statuses: [OGSQuickMatchActivityStatus]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                legendItems
            }
            VStack(alignment: .leading, spacing: 7) {
                legendItems
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legendItems: some View {
        ForEach(statuses, id: \.rawValue) { status in
            legendItem(status)
        }
    }

    private func legendItem(
        _ status: OGSQuickMatchActivityStatus
    ) -> some View {
        HStack(spacing: 6) {
            QuickMatchActivityBadge(status: status)
            if let description = status.quickMatchDescription {
                Text(description)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickMatchBoardSizeTile: View {
    let size: Int
    let selected: Bool
    let disabled: Bool
    let activity: OGSQuickMatchActivityStatus
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { selected },
            set: { newValue in
                if newValue != selected {
                    action()
                }
            }
        )) {
            tileLabel
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(activity.quickMatchDescription.map {
            String(localized: "\(size) by \(size), \($0)")
        } ?? String(localized: "\(size) by \(size)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(size)
        )
    }

    private var tileLabel: some View {
        VStack(spacing: 6) {
            BoardView(
                boardPosition: BoardPosition(width: size, height: size)
            )
            .aspectRatio(1, contentMode: .fit)
            .opacity(selected ? 1 : 0.8)

            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(verbatim: "\(size)×\(size)")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? Color.accentColor : .secondary)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    selected ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: selected ? 2 : 1
                )
        }
        .overlay(alignment: .topTrailing) {
            QuickMatchActivityBadge(status: activity)
                .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct QuickMatchPopularityRequestKey: Hashable {
    let enabled: Bool
    let userID: Int?
    let userRank: Double?
    let lowerRankDifference: Int
    let upperRankDifference: Int
}

struct QuickMatchForm: View {
    @Binding var draft: OGSQuickMatchDraft
    @Binding var realtimeClockPreference: OGSQuickMatchClockPreference
    @Binding var realtimeClocks: Set<OGSQuickMatchClockSelection>
    @Binding var correspondenceGameCount: Int
    let activeCorrespondenceSearchCount: Int
    let isSubmitting: Bool
    @State private var advancedIsExpanded = false
    let eligibleOpenChallenges: [OGSSeekgraphChallenge]
    let allowsRemoteActivity: Bool
    let activeLiveEntry: OGSAutomatchEntry?
    let cancellingEntryID: String?
    let isConnected: Bool
    let isRestoringSearches: Bool
    let serverNotice: String?
    let onFind: () -> Void
    let onCancel: (OGSAutomatchEntry) -> Void
    let onShowOpenChallenges: () -> Void

    @EnvironmentObject private var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var activePresentation: OGSActiveQuickMatchPresentation? {
        activeLiveEntry.flatMap(OGSActiveQuickMatchPresentation.init)
    }

    private var displayedDraft: OGSQuickMatchDraft {
        activePresentation?.draft ?? draft
    }

    private var activeSettingsAreDisplayable: Bool {
        activeLiveEntry == nil || activePresentation != nil
    }

    private var recap: OGSQuickMatchRecap {
        guard activeSettingsAreDisplayable else {
            return OGSQuickMatchRecap(
                firstLine: String(localized: "Unable to display match settings"),
                secondLine: ""
            )
        }
        return displayedDraft.quickMatchRecap(userRank: ogs.user?.ranking)
    }

    private var accessibleRecap: String {
        guard activeSettingsAreDisplayable else {
            return String(localized: "Unable to display match settings")
        }
        return displayedDraft.quickMatchAccessibleRecap(userRank: ogs.user?.ranking)
    }

    private var activitySnapshot: OGSQuickMatchActivitySnapshot {
        OGSQuickMatchActivitySnapshot(
            availableEntries: ogs.automatchAvailableEntryByID.values,
            popularity: ogs.quickMatchPopularityStats,
            currentUserID: ogs.user?.id,
            currentRank: ogs.user?.ranking,
            lowerRankDifference: displayedDraft.lowerRankDifference,
            upperRankDifference: displayedDraft.upperRankDifference
        )
    }

    @ViewBuilder
    private var activityLegend: some View {
        let snapshot = activitySnapshot
        let boardStatuses = OGSQuickMatchClockPreset.supportedBoardSizes.map {
            snapshot.status(forBoardSize: $0)
        }
        let visibleSpeeds: [TimeControlSpeed] = displayedDraft.quickMatchIsCorrespondenceOnly
            ? [.correspondence]
            : OGSQuickMatchDraft.quickMatchSpeeds.filter(\.isRealtime)
        let visibleStatuses = boardStatuses + visibleSpeeds.map { speedActivity($0) }
        let legendStatuses = [OGSQuickMatchActivityStatus.playersWaiting, .popular]
            .filter { visibleStatuses.contains($0) }
        if !legendStatuses.isEmpty {
            QuickMatchActivityLegend(statuses: legendStatuses)
        }
    }

    private var popularityRequestKey: QuickMatchPopularityRequestKey {
        QuickMatchPopularityRequestKey(
            enabled: allowsRemoteActivity,
            userID: ogs.user?.id,
            userRank: ogs.user?.ranking,
            lowerRankDifference: displayedDraft.lowerRankDifference,
            upperRankDifference: displayedDraft.upperRankDifference
        )
    }

    private var formIsDisabled: Bool {
        activeLiveEntry != nil
    }

    private var restorationBlocksFind: Bool {
        isRestoringSearches && !draft.quickMatchIsCorrespondenceOnly
    }

    private var findDisabledReason: String? {
        if restorationBlocksFind {
            return String(localized: "Restoring active searches from OGS…")
        }
        if !draft.quickMatchIsValid {
            return String(localized: "Select at least one board size and one speed.")
        }
        if !isConnected {
            return String(localized: "Reconnecting to OGS. Find a game will return when the connection does.")
        }
        return nil
    }

    private var matchingOpenChallenges: [OGSSeekgraphChallenge] {
        let sizes = Set(displayedDraft.quickMatchSelectedBoardSizes)
        let speeds = Set(displayedDraft.quickMatchSelectedClocks.map(\.speed))
        return eligibleOpenChallenges.filter { challenge in
            guard !challenge.rengo else { return false }
            let game = challenge.game
            guard game.width == game.height,
                  sizes.contains(game.width) else {
                return false
            }
            guard let speed = game.timeControl.speed else { return false }
            return speeds.contains(speed)
                || (speed == .live && speeds.contains(.rapid))
                || (speed == .rapid && speeds.contains(.live))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            QuickMatchActionArea(
                recap: recap,
                accessibleRecap: accessibleRecap,
                findTitle: findTitle,
                isSearching: activeLiveEntry != nil,
                isSubmitting: isSubmitting,
                isCancelling: activeLiveEntry.map { cancellingEntryID == $0.uuid } ?? false,
                canFind: draft.quickMatchIsValid
                    && activeLiveEntry == nil
                    && isConnected
                    && !restorationBlocksFind
                    && !isSubmitting,
                canCancel: isConnected && cancellingEntryID == nil,
                disabledReason: activeLiveEntry != nil
                    ? (!isConnected
                        ? String(localized: "Reconnect to OGS to cancel this search.")
                        : nil)
                    : findDisabledReason,
                onFind: onFind,
                onCancel: {
                    if let activeLiveEntry {
                        onCancel(activeLiveEntry)
                    }
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let serverNotice {
                        Label {
                            Text(serverNotice)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .foregroundStyle(.tint)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if activeSettingsAreDisplayable {
                        VStack(alignment: .leading, spacing: 14) {
                            if horizontalSizeClass == .compact {
                                VStack(spacing: 14) {
                                    boardSizeSection
                                    gameSpeedSection
                                    activityLegend
                                    handicapSection
                                }
                            } else {
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(spacing: 14) {
                                        boardSizeSection
                                        handicapSection
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(spacing: 14) {
                                        gameSpeedSection
                                        activityLegend
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            advancedSection

                            if !matchingOpenChallenges.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Button(action: onShowOpenChallenges) {
                                        Text("Alternatively, there are \(matchingOpenChallenges.count) open custom games with similar settings that you can accept to start a game immediately.")
                                            .font(.footnote)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(formIsDisabled)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHint("Show matching open games")
                                    .accessibilityIdentifier(
                                        SurroundUITestContract.AccessibilityID
                                            .quickMatchMatchingChallenges
                                    )

                                    LazyVGrid(
                                        columns: [
                                            GridItem(
                                                .adaptive(minimum: 300),
                                                spacing: 15,
                                                alignment: .top
                                            )
                                        ],
                                        spacing: 15
                                    ) {
                                        ForEach(matchingOpenChallenges) { challenge in
                                            ChallengeCell(challenge: challenge)
                                                .disabled(formIsDisabled || restorationBlocksFind)
                                                .padding()
                                                .background(
                                                    Color(
                                                        colorScheme == .light
                                                            ? UIColor.systemBackground
                                                            : UIColor.systemGray5
                                                    )
                                                    .clipShape(
                                                        RoundedRectangle(
                                                            cornerRadius: 8,
                                                            style: .continuous
                                                        )
                                                    )
                                                    .shadow(radius: 2)
                                                )
                                                .id(challenge.id)
                                                .accessibilityIdentifier(
                                                    SurroundUITestContract.AccessibilityID
                                                        .quickMatchOpenChallenge(challenge.id)
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Label(
                            "Unable to display match settings",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchScroll)
        }
        .tint(.accentColor)
        .onAppear {
            if !draft.quickMatchIsCorrespondenceOnly {
                if !draft.quickMatchSelectedClocks.isEmpty {
                    realtimeClockPreference = draft.quickMatchClockPreference
                }
                realtimeClocks = Set(draft.quickMatchSelectedClocks)
            }
        }
        .onChange(of: draft.quickMatchSelectedClocks) { _, clocks in
            if !draft.quickMatchIsCorrespondenceOnly {
                realtimeClocks = Set(clocks)
                if !clocks.isEmpty {
                    realtimeClockPreference = draft.quickMatchClockPreference
                }
            }
        }
        .task(id: popularityRequestKey) {
            guard allowsRemoteActivity else { return }
            ogs.subscribeToAutomatchAvailability()
            guard let userRank = popularityRequestKey.userRank else { return }
            ogs.refreshQuickMatchPopularityStats(
                userRank: userRank,
                lowerRankDifference: popularityRequestKey.lowerRankDifference,
                upperRankDifference: popularityRequestKey.upperRankDifference
            )
        }
        .onDisappear {
            guard allowsRemoteActivity else { return }
            ogs.unsubscribeFromAutomatchAvailability()
        }
    }

    private var findTitle: String {
        guard draft.quickMatchIsCorrespondenceOnly else { return String(localized: "Find a game") }
        if activeCorrespondenceSearchCount > 0 {
            return correspondenceGameCount == 1
                ? String(localized: "Find 1 more game")
                : String(localized: "Find \(correspondenceGameCount) more games")
        }
        return correspondenceGameCount == 1
            ? String(localized: "Find a game")
            : String(localized: "Find \(correspondenceGameCount) games")
    }

    private var boardSizeSection: some View {
        let selectedSizes = Set(displayedDraft.quickMatchSelectedBoardSizes)
        return QuickMatchCard(
            String(localized: "Board sizes"),
            subtitle: String(localized: "Select any sizes you would play.")
        ) {
            let vertical = dynamicTypeSize >= .accessibility1
            Group {
                if vertical {
                    VStack(spacing: 8) { boardSizeTiles(selectedSizes: selectedSizes) }
                } else {
                    HStack(spacing: 8) { boardSizeTiles(selectedSizes: selectedSizes) }
                }
            }
        }
    }

    @ViewBuilder
    private func boardSizeTiles(selectedSizes: Set<Int>) -> some View {
        ForEach(OGSQuickMatchClockPreset.supportedBoardSizes, id: \.self) { size in
            QuickMatchBoardSizeTile(
                size: size,
                selected: selectedSizes.contains(size),
                disabled: formIsDisabled,
                activity: activitySnapshot.status(
                    forBoardSize: size
                ),
                action: { draft.toggleQuickMatchBoardSize(size) }
            )
        }
    }

    private var gameSpeedSection: some View {
        QuickMatchCard(String(localized: "Game speed")) {
            Picker("Game speed", selection: Binding(
                get: { displayedDraft.quickMatchIsCorrespondenceOnly },
                set: { correspondence in
                    guard correspondence != draft.quickMatchIsCorrespondenceOnly else { return }
                    if correspondence {
                        realtimeClocks = Set(draft.quickMatchSelectedClocks)
                        draft.toggleQuickMatchSpeed(.correspondence)
                    } else {
                        draft.setQuickMatchClocks(realtimeClocks)
                    }
                }
            )) {
                Text("Real-time", comment: "Quick Match speed category containing Blitz, Rapid, and Live games, contrasted with Correspondence.").tag(false)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("live"))
                Text("Correspondence").tag(true)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchSpeedTab("correspondence"))
            }
            .pickerStyle(.segmented)
            .disabled(formIsDisabled)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchSpeedTabs)

            if displayedDraft.quickMatchIsCorrespondenceOnly {
                VStack(alignment: .leading, spacing: 2) {
                    speedDetails(.correspondence)
                    clockValues(.correspondence)
                }
                .frame(minHeight: 44, alignment: .top)
                Stepper(value: $correspondenceGameCount, in: 1...10) {
                    Text("Games to find: \(correspondenceGameCount)")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(formIsDisabled || isSubmitting)
                .accessibilityValue(String(correspondenceGameCount))
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchGameCount)
            } else {
                Text("Select any speeds you would play.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(OGSQuickMatchDraft.quickMatchSpeeds.filter(\.isRealtime), id: \.self) { speed in
                    if speed != .blitz { Divider() }
                    speedToggle(speed)
                }
            }
        }
    }

    private func speedActivity(_ speed: TimeControlSpeed) -> OGSQuickMatchActivityStatus {
        let selectedSystems = displayedDraft.quickMatchSelectedClocks
            .filter { $0.speed == speed }.map(\.system)
        let activitySystems = selectedSystems.isEmpty
            ? (speed == .correspondence ? [.fischer] : displayedClockPreference.systems)
            : selectedSystems
        let statuses = activitySystems.map {
            activitySnapshot.status(for: speed, system: $0, boardSizes: activityBoardSizes)
        }
        return statuses.max { $0.rawValue < $1.rawValue } ?? .none
    }

    private func speedEstimate(_ speed: TimeControlSpeed) -> String {
        let durations = clockPresets(speed: speed, system: .fischer).compactMap(\.estimatedGameDuration)
        return speed == .correspondence
            ? String(localized: "≈ 1 day/move")
            : String(localized: "≈ \(durationRange(durations)) total")
    }

    private func speedDetails(_ speed: TimeControlSpeed) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                speedLabel(speed, activity: speedActivity(speed))
                Spacer(minLength: 4)
                Text(speedEstimate(speed)).font(.footnote).foregroundStyle(.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                speedLabel(speed, activity: speedActivity(speed))
                Text(speedEstimate(speed)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([speed.quickMatchTitle, speedEstimate(speed), speedActivity(speed).quickMatchDescription]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func speedToggle(_ speed: TimeControlSpeed) -> some View {
        let selected = displayedDraft.quickMatchSelectedSpeeds.contains(speed)
        let activity = speedActivity(speed)
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { selected }, set: { value in
                if value != selected {
                    draft.toggleQuickMatchSpeed(speed, clockPreference: realtimeClockPreference)
                }
            })) {
                speedDetails(speed)
            }
            .toggleStyle(.switch)
            .disabled(formIsDisabled)
            .accessibilityLabel(activity.quickMatchDescription.map {
                String(localized: "\(speed.quickMatchTitle), \($0)")
            } ?? speed.quickMatchTitle)
            .accessibilityHint(speedEstimate(speed))
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchSpeed(speed.rawValue))

            clockValues(speed)
        }
        .frame(minHeight: 44, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private func clockValues(_ speed: TimeControlSpeed) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(displayedDraft.quickMatchClockDetailLines(
                for: speed,
                fallbackPreference: displayedClockPreference
            ), id: \.self) { line in
                Text(line)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.leading, dynamicTypeSize >= .accessibility1 ? 0 : 30)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchClockValues(speed.rawValue))
    }

    private func speedLabel(_ speed: TimeControlSpeed, activity: OGSQuickMatchActivityStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: speed.quickMatchSystemImage)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(speed.quickMatchTitle)
                .fixedSize(horizontal: false, vertical: true)
            QuickMatchActivityBadge(status: activity, size: 10)
        }
    }

    private var displayedClockPreference: OGSQuickMatchClockPreference {
        activePresentation != nil ? displayedDraft.quickMatchClockPreference : realtimeClockPreference
    }

    private var activityBoardSizes: [Int] {
        let selected = displayedDraft.quickMatchSelectedBoardSizes
        return selected.isEmpty ? [displayedDraft.boardSize] : selected
    }

    private func clockPresets(
        speed: TimeControlSpeed,
        system: OGSAutomatchClockSystem
    ) -> [OGSQuickMatchClockPreset] {
        let selectedSizes = displayedDraft.quickMatchSelectedBoardSizes
        let sizes = selectedSizes.isEmpty
            ? [displayedDraft.boardSize]
            : selectedSizes
        return sizes.compactMap {
            OGSQuickMatchClockPreset.preset(
                boardSize: $0,
                speed: speed,
                system: system
            )
        }
    }

    private func durationRange(_ values: [Int]) -> String {
        let values = Array(Set(values)).sorted()
        guard let first = values.first, let last = values.last else { return "" }
        let firstDescription = durationString(seconds: first)
        guard first != last else { return firstDescription }
        let lastDescription = durationString(seconds: last)
        return "\(firstDescription)–\(lastDescription)"
    }

    private var handicapSection: some View {
        QuickMatchCard(String(localized: "Handicap")) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Allow handicap games", isOn: Binding(
                    get: { displayedDraft.handicap != .disabled },
                    set: { draft.handicap = $0 ? .standard : .disabled }
                ))
                .toggleStyle(.switch)
                .disabled(formIsDisabled)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchAllowHandicap)
                Text(handicapExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44, alignment: .top)
        }
    }

    private var handicapExplanation: String {
        switch displayedDraft.handicap {
        case .disabled: return String(localized: "Never play with handicap stones.")
        case .standard: return String(localized: "Allows handicap games and even games.")
        case .required: return String(localized: "Require handicaps between players of different ranks.")
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedIsExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                clockSystemSection
                rankSection.disabled(formIsDisabled)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Require handicap", isOn: Binding(
                        get: { displayedDraft.handicap == .required },
                        set: { draft.handicap = $0 ? .required : .standard }
                    ))
                    .font(.body)
                    .toggleStyle(.switch)
                    // DisclosureGroup clips its content; leave room for the
                    // native switch to draw beyond its reported layout frame.
                    .padding(.trailing, 4)
                    .disabled(formIsDisabled || displayedDraft.handicap == .disabled)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchStrictHandicap)
                    Text(displayedDraft.handicap == .disabled
                         ? String(localized: "Unavailable while handicap games are switched off.")
                         : String(localized: "Require handicaps between players of different ranks."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .top)
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced").font(.headline).foregroundStyle(Color.primary)
                if !advancedIsExpanded {
                    Text([displayedDraft.quickMatchIsCorrespondenceOnly ? "" : displayedClockPreference.quickMatchTitle,
                          displayedDraft.quickMatchRankRange(userRank: ogs.user?.ranking)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchAdvanced)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var clockSystemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayedDraft.quickMatchIsCorrespondenceOnly {
                LabeledContent("Clock system", value: String(localized: "Fischer"))
                    .font(.body)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchClockSystem)
                Text("Correspondence always uses a Fischer clock.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Clock system").font(.body)
                if displayedClockPreference == .mixed {
                    Text("This search uses different clock systems at different speeds.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(displayedDraft.quickMatchSelectedSpeeds, id: \.self) { speed in
                        let systems = displayedDraft.quickMatchSelectedClocks
                            .filter { $0.speed == speed }.map { $0.system.quickMatchTitle }
                        Text("\(speed.quickMatchTitle): \(ListFormatter.localizedString(byJoining: systems))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Picker("Clock system", selection: Binding(
                    get: { displayedClockPreference },
                    set: { preference in
                        realtimeClockPreference = preference
                        draft.setQuickMatchClockPreference(preference)
                    }
                )) {
                    ForEach([OGSQuickMatchClockPreference.flexible, .fischer, .byoyomi], id: \.self) { preference in
                        Text(preference.quickMatchTitle)
                            .tag(preference)
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchClockPreference(preference.rawValue))
                    }
                    if displayedClockPreference == .mixed {
                        Text("Mixed clocks").tag(OGSQuickMatchClockPreference.mixed)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(formIsDisabled)
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.quickMatchClockSystem)
                if displayedClockPreference == .flexible {
                    Text("Accepts either Fischer or Byo-Yomi clocks.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Opponent rank").font(.body)
                    Spacer(minLength: 8)
                    rankPickers
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opponent rank").font(.body)
                    rankPickers
                }
            }
            if let userRank = ogs.user?.ranking {
                Text("You are \(OGSQuickMatchDraft.quickMatchRankLabel(userRank)). Widening the range finds a game sooner; narrowing it finds a closer one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Widening the range finds a game sooner; narrowing it finds a closer one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rankPickers: some View {
        HStack(spacing: 6) {
            rankPicker(
                title: String(localized: "Minimum opponent rank"),
                difference: displayedBinding(\.lowerRankDifference),
                subtracts: true
            )
            Text("–")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            rankPicker(
                title: String(localized: "Maximum opponent rank"),
                difference: displayedBinding(\.upperRankDifference),
                subtracts: false
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func displayedBinding<Value>(
        _ keyPath: WritableKeyPath<OGSQuickMatchDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { displayedDraft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func rankPicker(
        title: String,
        difference: Binding<Int>,
        subtracts: Bool
    ) -> some View {
        Picker(title, selection: difference) {
            ForEach(0...9, id: \.self) { value in
                if let rank = ogs.user?.ranking {
                    let computedRank = subtracts
                        ? rank - Double(value)
                        : rank + Double(value)
                    Text(OGSQuickMatchDraft.quickMatchRankLabel(computedRank))
                        .tag(value)
                } else {
                    Text(value == 0 ? String(localized: "Your rank") : "±\(value)")
                        .tag(value)
                }
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
    }
}
