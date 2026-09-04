//
//  QuickMatchView.swift
//  Surround
//
//  Created by Codex on 31/08/2026.
//

import SwiftUI

struct OGSQuickMatchRecap: Equatable {
    let firstLine: String
    let secondLine: String
}

extension OGSQuickMatchMode {
    var quickMatchTitle: String {
        switch self {
        case .exact:
            return String(localized: "Exact")
        case .flexible:
            return String(localized: "Flexible")
        case .multiple:
            return String(localized: "Multiple")
        }
    }

    var quickMatchDescription: String {
        switch self {
        case .exact:
            return String(localized: "One board size, one clock. Matched on exactly that.")
        case .flexible:
            return String(localized: "One board size, either clock at that pace.")
        case .multiple:
            return String(localized: "Every board size and clock you select below.")
        }
    }

}

extension OGSQuickMatchDraft {
    var quickMatchSelectedBoardSizes: [Int] {
        if mode == .multiple {
            return multipleBoardSizes
                .intersection(Set(OGSQuickMatchClockPreset.supportedBoardSizes))
                .sorted()
        }
        return OGSQuickMatchClockPreset.supportedBoardSizes.contains(boardSize)
            ? [boardSize]
            : []
    }

    var quickMatchSelectedClocks: [OGSQuickMatchClockSelection] {
        if mode == .multiple {
            return multipleClocks
                .intersection(Set(OGSQuickMatchClockSelection.allRealtime))
                .sorted { lhs, rhs in
                    let all = OGSQuickMatchClockSelection.allRealtime
                    return (all.firstIndex(of: lhs) ?? .max)
                        < (all.firstIndex(of: rhs) ?? .max)
                }
        }

        let preferred = OGSQuickMatchClockSelection(
            speed: speed,
            system: speed == .correspondence ? .fischer : system
        )
        guard mode == .flexible, speed.isRealtime else {
            return [preferred]
        }
        return [
            preferred,
            OGSQuickMatchClockSelection(
                speed: speed,
                system: preferred.system.alternate
            ),
        ]
    }

    var quickMatchIsValid: Bool {
        !quickMatchSelectedBoardSizes.isEmpty && !quickMatchSelectedClocks.isEmpty
    }

    mutating func selectQuickMatchMode(_ newMode: OGSQuickMatchMode) {
        guard mode != newMode else { return }
        if newMode == .multiple {
            if speed == .correspondence {
                speed = .rapid
                system = .fischer
            }
            if multipleBoardSizes.isEmpty {
                multipleBoardSizes = [boardSize]
            }
            if multipleClocks.isEmpty {
                let preferred = OGSQuickMatchClockSelection(
                    speed: speed,
                    system: system
                )
                multipleClocks = [preferred]
                if mode == .flexible {
                    multipleClocks.insert(
                        OGSQuickMatchClockSelection(
                            speed: speed,
                            system: system.alternate
                        )
                    )
                }
            }
        } else if mode == .multiple {
            if let selectedSize = quickMatchSelectedBoardSizes.last {
                boardSize = selectedSize
            }
            if let selectedClock = quickMatchSelectedClocks.first {
                speed = selectedClock.speed
                system = selectedClock.system
            }
        }
        mode = newMode
    }

    mutating func selectQuickMatchBoardSize(_ size: Int) {
        guard OGSQuickMatchClockPreset.supportedBoardSizes.contains(size) else {
            return
        }
        if mode == .multiple {
            if multipleBoardSizes.contains(size) {
                multipleBoardSizes.remove(size)
            } else {
                multipleBoardSizes.insert(size)
            }
        } else {
            boardSize = size
        }
    }

    mutating func selectQuickMatchClock(
        speed selectedSpeed: TimeControlSpeed,
        system selectedSystem: OGSAutomatchClockSystem
    ) {
        if mode == .multiple {
            guard selectedSpeed.isRealtime else { return }
            let selection = OGSQuickMatchClockSelection(
                speed: selectedSpeed,
                system: selectedSystem
            )
            if multipleClocks.contains(selection) {
                multipleClocks.remove(selection)
            } else {
                multipleClocks.insert(selection)
            }
        } else {
            speed = selectedSpeed
            system = selectedSpeed == .correspondence ? .fischer : selectedSystem
        }
    }

    func quickMatchRecap(userRank: Double?) -> OGSQuickMatchRecap {
        guard quickMatchIsValid else {
            return OGSQuickMatchRecap(
                firstLine: String(localized: "Nothing selected"),
                secondLine: ""
            )
        }

        let sizes = quickMatchSelectedBoardSizes
            .map { "\($0)×\($0)" }
            .joined(separator: ", ")
        let selectedSizes = quickMatchSelectedBoardSizes
        let clockDescriptions = quickMatchSelectedClocks.compactMap {
            selection -> String? in
            let presets = selectedSizes.compactMap {
                OGSQuickMatchClockPreset.preset(
                    boardSize: $0,
                    speed: selection.speed,
                    system: selection.system
                )
            }
            guard presets.count == selectedSizes.count else { return nil }
            return OGSQuickMatchClockPreset.quickMatchDisplayDescription(
                for: presets
            )
        }
        let clocks: String
        if mode == .flexible, clockDescriptions.count == 2 {
            clocks = String(
                localized: "\(clockDescriptions[0]) or \(clockDescriptions[1])",
                comment: "Two alternative Quick Match clock values"
            )
        } else {
            clocks = ListFormatter.localizedString(
                byJoining: clockDescriptions
            )
        }

        return OGSQuickMatchRecap(
            firstLine: [sizes, clocks]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            secondLine: [
                String(localized: "\(handicap.quickMatchTitle) handicap"),
                quickMatchRankRange(userRank: userRank),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        )
    }

    var quickMatchBoardSizeTitle: String {
        let sizes = quickMatchSelectedBoardSizes
            .map { "\($0)×\($0)" }
            .joined(separator: ", ")
        guard !sizes.isEmpty else { return String(localized: "Board size") }
        return String(localized: "Board size: \(sizes)")
    }

    func quickMatchAccessibleRecap(userRank: Double?) -> String {
        guard quickMatchIsValid else {
            return String(localized: "Nothing selected")
        }

        let sizes = quickMatchSelectedBoardSizes
            .map { String(localized: "\($0) by \($0)") }
        let sizeDescription = ListFormatter.localizedString(byJoining: sizes)
        let clocks: String
        if mode == .multiple {
            let count = quickMatchSelectedClocks.count
            clocks = count == 1
                ? String(localized: "1 clock option")
                : String(localized: "\(count) clock options")
        } else {
            let descriptions = quickMatchSelectedClocks.compactMap { selection in
                OGSQuickMatchClockPreset.preset(
                    boardSize: boardSize,
                    speed: selection.speed,
                    system: selection.system
                )?.quickMatchAccessibleDescription
            }
            if mode == .flexible, descriptions.count == 2 {
                clocks = String(
                    localized: "\(descriptions[0]) or \(descriptions[1])",
                    comment: "Two alternative spoken Quick Match clocks"
                )
            } else {
                clocks = ListFormatter.localizedString(
                    byJoining: descriptions
                )
            }
        }

        return [
            sizeDescription,
            clocks,
            String(localized: "\(handicap.quickMatchTitle) handicap"),
            quickMatchAccessibleRankRange(userRank: userRank),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    func quickMatchRankRange(userRank: Double?) -> String {
        guard let userRank else {
            return String(
                localized: "\(lowerRankDifference) ranks below to \(upperRankDifference) ranks above"
            )
        }
        return "\(Self.quickMatchRankLabel(userRank - Double(lowerRankDifference)))–\(Self.quickMatchRankLabel(userRank + Double(upperRankDifference)))"
    }

    func quickMatchAccessibleRankRange(userRank: Double?) -> String {
        guard let userRank else {
            return String(
                localized: "\(lowerRankDifference) ranks below to \(upperRankDifference) ranks above"
            )
        }
        let lower = Self.quickMatchAccessibleRankLabel(
            userRank - Double(lowerRankDifference)
        )
        let upper = Self.quickMatchAccessibleRankLabel(
            userRank + Double(upperRankDifference)
        )
        return String(localized: "Opponent rank from \(lower) to \(upper)")
    }

    static func quickMatchRankLabel(_ rank: Double) -> String {
        let boundedRank = min(max(rank, 5), 38)
        if boundedRank < 30 {
            return "\(Int(ceil(30 - boundedRank)))k"
        }
        return "\(Int(floor(boundedRank - 29)))d"
    }

    static func quickMatchAccessibleRankLabel(_ rank: Double) -> String {
        RankUtils.formattedRank(rank, longFormat: true)
    }
}

private struct QuickMatchCard<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    cardTitle
                    Spacer(minLength: 8)
                    accessory
                }

                VStack(alignment: .leading, spacing: 8) {
                    cardTitle
                    accessory
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var cardTitle: some View {
        Text(title)
            .font(.headline)
            .layoutPriority(1)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension QuickMatchCard where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
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
    let isSearching: Bool
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
                        Button("Cancel", role: .destructive, action: onCancel)
                            .fontWeight(.bold)
                            .disabled(!canCancel)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Cancel live game search")
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
                    Text("Find a game", comment: "New game view")
                        .font(.body.weight(.bold))
                        .foregroundStyle(
                            canFind ? Color.white : Color.secondary
                        )
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(
                    canFind
                        ? Color.accentColor
                        : Color(uiColor: .secondarySystemFill)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!canFind)
                .accessibilityHint(Text(verbatim: accessibleRecap))
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
            if dynamicTypeSize.isAccessibilitySize {
                Text(recap.firstLine)
                    .fixedSize(horizontal: false, vertical: true)
                if !recap.secondLine.isEmpty {
                    Text(recap.secondLine)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(recap.firstLine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !recap.secondLine.isEmpty {
                    Text(recap.secondLine)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                legendItem(.playersWaiting)
                legendItem(.popular)
            }
            VStack(alignment: .leading, spacing: 7) {
                legendItem(.playersWaiting)
                legendItem(.popular)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let multiple: Bool
    let disabled: Bool
    let activity: OGSQuickMatchActivityStatus
    let action: () -> Void

    var body: some View {
        Group {
            if multiple {
                Toggle(
                    isOn: Binding(
                        get: { selected },
                        set: { newValue in
                            if newValue != selected {
                                action()
                            }
                        }
                    )
                ) {
                    tileLabel
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("\(size) by \(size)")
                .accessibilityHint(
                    Text(verbatim: activity.quickMatchDescription ?? "")
                )
            } else {
                Button(action: action) {
                    tileLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(size) by \(size)")
                .accessibilityValue(activity.quickMatchDescription ?? "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
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
            .opacity(selected ? 1 : 0.55)

            HStack(spacing: 4) {
                if multiple {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .accessibilityHidden(true)
                }
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

private enum QuickMatchClockButtonState: Equatable {
    case off
    case preferred
    case alsoAccepted

    var selected: Bool {
        self != .off
    }
}

private struct QuickMatchClockButton: View {
    let preset: OGSQuickMatchClockPreset
    let displayDescription: String
    let accessibleDescription: String
    let state: QuickMatchClockButtonState
    let multiple: Bool
    let disabled: Bool
    let activity: OGSQuickMatchActivityStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(preset.system.quickMatchTitle.uppercased())
                    .font(.caption2)
                    .foregroundStyle(state.selected ? Color.accentColor : Color.secondary)
                Text(displayDescription)
                    .font(.subheadline.weight(state == .preferred ? .semibold : .regular))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(state.selected ? Color.accentColor : .primary)
            .background(state.selected ? Color.accentColor.opacity(0.12) : Color(uiColor: .systemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        state.selected ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(
                            lineWidth: state == .preferred ? 2 : 1,
                            dash: state == .alsoAccepted ? [5, 3] : []
                        )
                    )
            }
            .overlay(alignment: .topTrailing) {
                QuickMatchActivityBadge(status: activity, size: 12)
                    .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(
            String(
                localized: "\(preset.speed.quickMatchTitle), \(accessibleDescription)",
                comment: "Accessible Quick Match clock including speed and values"
            )
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state.selected ? .isSelected : [])
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.quickMatchClock(
                speed: preset.speed.rawValue,
                system: preset.system.rawValue
            )
        )
    }

    private var accessibilityValue: String {
        var values = [String]()
        if state == .alsoAccepted {
            values.append(String(localized: "Also accepted"))
        } else if multiple {
            values.append(
                state.selected
                    ? String(localized: "Selected")
                    : String(localized: "Not selected")
            )
        }
        if let activityDescription = activity.quickMatchDescription {
            values.append(activityDescription)
        }
        return ListFormatter.localizedString(byJoining: values)
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
        activeLiveEntry != nil || restorationBlocksDraft
    }

    private var restorationBlocksDraft: Bool {
        isRestoringSearches && !draft.quickMatchIsCorrespondenceOnly
    }

    private var findDisabledReason: String? {
        if restorationBlocksDraft {
            return String(localized: "Restoring active searches from OGS…")
        }
        if !draft.quickMatchIsValid {
            return String(localized: "Select at least one board size and one clock.")
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
                isSearching: activeLiveEntry != nil,
                isCancelling: activeLiveEntry.map { cancellingEntryID == $0.uuid } ?? false,
                canFind: draft.quickMatchIsValid
                    && activeLiveEntry == nil
                    && isConnected
                    && !restorationBlocksDraft,
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
                            matchingSection

                            if horizontalSizeClass == .compact {
                                VStack(spacing: 14) {
                                    boardSizeSection
                                    gameClockSection
                                    handicapSection
                                    rankSection
                                }
                            } else {
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(spacing: 14) {
                                        boardSizeSection
                                        handicapSection
                                        rankSection
                                    }
                                    .frame(maxWidth: .infinity)

                                    gameClockSection
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            QuickMatchActivityLegend()

                            if !matchingOpenChallenges.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Button(action: onShowOpenChallenges) {
                                        Text("Alternatively, there are \(matchingOpenChallenges.count) open custom games matching your preferences that you can accept to start a game immediately.")
                                            .font(.footnote)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
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
                        .disabled(formIsDisabled)
                    } else {
                        Label(
                            "Unable to display match settings",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(uiColor: .systemGray6))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
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

    private var matchingSection: some View {
        QuickMatchCard(String(localized: "Matching")) {
            Picker(
                "Matching",
                selection: Binding(
                    get: { displayedDraft.mode },
                    set: { draft.selectQuickMatchMode($0) }
                )
            ) {
                ForEach(OGSQuickMatchMode.allCases, id: \.self) { mode in
                    Text(mode.quickMatchTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.quickMatchMode
            )

            Text(displayedDraft.mode.quickMatchDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var boardSizeSection: some View {
        let selectedSizes = Set(displayedDraft.quickMatchSelectedBoardSizes)
        return QuickMatchCard(displayedDraft.quickMatchBoardSizeTitle) {
            if displayedDraft.mode == .multiple {
                Text("Select every size you would accept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
                multiple: displayedDraft.mode == .multiple,
                disabled: formIsDisabled,
                activity: activitySnapshot.status(
                    forBoardSize: size
                ),
                action: { draft.selectQuickMatchBoardSize(size) }
            )
        }
    }

    private var gameClockSection: some View {
        QuickMatchCard(String(localized: "Game clock")) {
            if displayedDraft.mode == .multiple {
                Text("Select every clock you would accept. Correspondence is available in Exact or Flexible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                [TimeControlSpeed.blitz, .rapid, .live, .correspondence],
                id: \.self
            ) { speed in
                clockSpeedRow(speed)
            }
        }
    }

    @ViewBuilder
    private func clockSpeedRow(_ speed: TimeControlSpeed) -> some View {
        let correspondenceDisabled = displayedDraft.mode == .multiple
            && speed == .correspondence
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: speed.quickMatchSystemImage)
                    // This symbol is decorative. Keeping it at a stable size
                    // preserves the aligned title column when Dynamic Type
                    // makes the adjacent speed name much larger.
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 20)
                    .foregroundStyle(
                        correspondenceDisabled ? .secondary : .primary
                    )
                    .accessibilityHidden(true)
                Text(speed.quickMatchTitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        correspondenceDisabled ? .secondary : .primary
                    )
                Spacer()
                let durations = clockPresets(
                    speed: speed,
                    system: .fischer
                ).compactMap(\.estimatedGameDuration)
                if !durations.isEmpty {
                    Text("≈ \(durationRange(durations))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if speed == .correspondence {
                    Text("About a day a move")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { clockButtons(speed) }
                VStack(spacing: 8) { clockButtons(speed) }
            }

            if displayedDraft.mode == .flexible,
               displayedDraft.speed == speed,
               speed.isRealtime {
                Text("Both clocks accepted — \(displayedDraft.system.quickMatchTitle) preferred.")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func clockButtons(_ speed: TimeControlSpeed) -> some View {
        let systems: [OGSAutomatchClockSystem] = speed == .correspondence
            ? [.fischer]
            : OGSAutomatchClockSystem.allCases
        ForEach(systems, id: \.self) { system in
            let presets = clockPresets(speed: speed, system: system)
            if let preset = presets.last {
                QuickMatchClockButton(
                    preset: preset,
                    displayDescription: OGSQuickMatchClockPreset
                        .quickMatchDisplayDescription(for: presets),
                    accessibleDescription: OGSQuickMatchClockPreset
                        .quickMatchAccessibleDescription(for: presets),
                    state: clockButtonState(speed: speed, system: system),
                    multiple: displayedDraft.mode == .multiple,
                    disabled: formIsDisabled
                        || (displayedDraft.mode == .multiple
                            && speed == .correspondence),
                    activity: activitySnapshot.status(
                        for: speed,
                        system: system,
                        boardSizes: activityBoardSizes
                    ),
                    action: {
                        draft.selectQuickMatchClock(speed: speed, system: system)
                    }
                )
            }
        }
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

    private func durationRange(
        _ values: [Int],
        longFormat: Bool = false,
        spoken: Bool = false
    ) -> String {
        let values = Array(Set(values)).sorted()
        guard let first = values.first, let last = values.last else { return "" }
        let firstDescription = durationString(
            seconds: first,
            longFormat: longFormat
        )
        guard first != last else { return firstDescription }
        let lastDescription = durationString(
            seconds: last,
            longFormat: longFormat
        )
        return spoken
            ? "\(firstDescription) to \(lastDescription)"
            : "\(firstDescription)–\(lastDescription)"
    }

    private func clockButtonState(
        speed: TimeControlSpeed,
        system: OGSAutomatchClockSystem
    ) -> QuickMatchClockButtonState {
        if displayedDraft.mode == .multiple {
            return displayedDraft.multipleClocks.contains(
                OGSQuickMatchClockSelection(speed: speed, system: system)
            ) ? .preferred : .off
        }
        guard displayedDraft.speed == speed else { return .off }
        if displayedDraft.speed == .correspondence {
            return system == .fischer ? .preferred : .off
        }
        if displayedDraft.system == system {
            return .preferred
        }
        return displayedDraft.mode == .flexible ? .alsoAccepted : .off
    }

    private var handicapSection: some View {
        QuickMatchCard(
            String(localized: "Handicap"),
            accessory: {
                Menu {
                    ForEach(
                        OGSQuickMatchHandicapPreference.allCases,
                        id: \.self
                    ) { option in
                        Toggle(
                            isOn: Binding(
                                get: { displayedDraft.handicap == option },
                                set: { selected in
                                    if selected {
                                        draft.handicap = option
                                    }
                                }
                            )
                        ) {
                            Text(option.quickMatchTitle)
                            Text(option.quickMatchPickerDescription)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(displayedDraft.handicap.quickMatchTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Handicap")
                .accessibilityValue(displayedDraft.handicap.quickMatchTitle)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchHandicap
                )
            }
        ) {
            Text(displayedDraft.handicap.quickMatchDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var rankSection: some View {
        QuickMatchCard(
            String(localized: "Opponent rank"),
            accessory: {
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
        ) {
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
