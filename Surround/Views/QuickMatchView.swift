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

struct QuickMatchRequestFailure: Identifiable {
    enum Operation {
        case start
        case cancel
        case cancelTimedOut
    }

    let operation: Operation
    let entry: OGSAutomatchEntry

    var id: String {
        "\(entry.uuid)-\(String(describing: operation))"
    }
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

extension OGSQuickMatchHandicapPreference {
    var quickMatchTitle: String {
        switch self {
        case .required:
            return String(localized: "Required")
        case .standard:
            return String(localized: "Standard")
        case .disabled:
            return String(localized: "Disabled")
        }
    }

    var quickMatchDescription: String {
        switch self {
        case .required:
            return String(localized: "Require handicaps between players of different ranks.")
        case .standard:
            return String(localized: "Use handicaps by default, but accept games with handicaps off.")
        case .disabled:
            return String(localized: "Never play with handicap stones.")
        }
    }

    var quickMatchPickerDescription: String {
        switch self {
        case .required:
            return String(localized: "Use handicaps when ranks differ.")
        case .standard:
            return String(localized: "Prefer handicaps; allow even games.")
        case .disabled:
            return String(localized: "No handicap stones.")
        }
    }
}

extension OGSAutomatchClockSystem {
    var quickMatchTitle: String {
        switch self {
        case .fischer:
            return String(localized: "Fischer")
        case .byoyomi:
            return String(localized: "Byo-Yomi")
        }
    }
}

extension TimeControlSpeed {
    /// Quick Match distinguishes Rapid from Live even though the rest of the
    /// app intentionally groups both values under `localizedString()`.
    var quickMatchTitle: String {
        switch self {
        case .blitz:
            return String(localized: "Blitz")
        case .rapid:
            return String(localized: "Rapid")
        case .live:
            return String(localized: "Live")
        case .correspondence:
            return String(localized: "Correspondence")
        }
    }

    var quickMatchSystemImage: String {
        switch self {
        case .blitz:
            return "bolt"
        case .rapid:
            return "hare"
        case .live:
            return "clock"
        case .correspondence:
            return "calendar"
        }
    }
}

extension OGSQuickMatchClockPreset {
    var quickMatchShortDescription: String {
        switch timeControl {
        case .Fischer(let initialTime, let timeIncrement, _):
            return "\(durationString(seconds: initialTime)) + \(durationString(seconds: timeIncrement))"
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return "\(durationString(seconds: mainTime)) + \(periods)×\(durationString(seconds: periodTime))"
        default:
            return timeControl.shortDescription
        }
    }

    var quickMatchAccessibleDescription: String {
        switch timeControl {
        case .Fischer(let initialTime, let timeIncrement, _):
            return String(
                localized: "\(system.quickMatchTitle), \(durationString(seconds: initialTime, longFormat: true)) plus \(durationString(seconds: timeIncrement, longFormat: true)) per move"
            )
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return String(
                localized: "\(system.quickMatchTitle), \(durationString(seconds: mainTime, longFormat: true)) plus \(periods) periods of \(durationString(seconds: periodTime, longFormat: true))"
            )
        default:
            return "\(system.quickMatchTitle), \(timeControl.shortDescription)"
        }
    }

    static func quickMatchDisplayDescription(
        for presets: [OGSQuickMatchClockPreset]
    ) -> String {
        guard let first = presets.first else { return "" }
        switch first.timeControl {
        case .Fischer:
            let values = presets.compactMap { preset -> (Int, Int)? in
                guard case .Fischer(let initial, let increment, _) = preset.timeControl else {
                    return nil
                }
                return (initial, increment)
            }
            guard values.count == presets.count,
                  Set(values.map(\.1)).count == 1,
                  let increment = values.first?.1 else {
                return first.quickMatchShortDescription
            }
            return "\(quickMatchDurationRange(values.map(\.0))) + \(durationString(seconds: increment))"
        case .ByoYomi:
            let values = presets.compactMap { preset -> (Int, Int, Int)? in
                guard case .ByoYomi(let main, let periods, let period) = preset.timeControl else {
                    return nil
                }
                return (main, periods, period)
            }
            guard values.count == presets.count,
                  Set(values.map(\.1)).count == 1,
                  Set(values.map(\.2)).count == 1,
                  let periods = values.first?.1,
                  let period = values.first?.2 else {
                return first.quickMatchShortDescription
            }
            return "\(quickMatchDurationRange(values.map(\.0))) + \(periods)×\(durationString(seconds: period))"
        default:
            return first.quickMatchShortDescription
        }
    }

    static func quickMatchAccessibleDescription(
        for presets: [OGSQuickMatchClockPreset]
    ) -> String {
        guard let first = presets.first else { return "" }
        switch first.timeControl {
        case .Fischer:
            let values = presets.compactMap { preset -> (Int, Int)? in
                guard case .Fischer(let initial, let increment, _) = preset.timeControl else {
                    return nil
                }
                return (initial, increment)
            }
            guard values.count == presets.count,
                  Set(values.map(\.1)).count == 1,
                  let increment = values.first?.1 else {
                return first.quickMatchAccessibleDescription
            }
            let initial = quickMatchDurationRange(
                values.map(\.0),
                longFormat: true,
                spoken: true
            )
            return String(
                localized: "\(first.system.quickMatchTitle), \(initial) plus \(durationString(seconds: increment, longFormat: true)) per move"
            )
        case .ByoYomi:
            let values = presets.compactMap { preset -> (Int, Int, Int)? in
                guard case .ByoYomi(let main, let periods, let period) = preset.timeControl else {
                    return nil
                }
                return (main, periods, period)
            }
            guard values.count == presets.count,
                  Set(values.map(\.1)).count == 1,
                  Set(values.map(\.2)).count == 1,
                  let periods = values.first?.1,
                  let period = values.first?.2 else {
                return first.quickMatchAccessibleDescription
            }
            let main = quickMatchDurationRange(
                values.map(\.0),
                longFormat: true,
                spoken: true
            )
            return String(
                localized: "\(first.system.quickMatchTitle), \(main) plus \(periods) periods of \(durationString(seconds: period, longFormat: true))"
            )
        default:
            return first.quickMatchAccessibleDescription
        }
    }

    private static func quickMatchDurationRange(
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
        let clocks = clockDescriptions.joined(
            separator: mode == .flexible
                ? String(localized: " or ")
                : ", "
        )

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
            .joined(separator: ", ")
        let clocks: String
        if mode == .multiple {
            let count = quickMatchSelectedClocks.count
            clocks = count == 1
                ? String(localized: "1 clock option")
                : String(localized: "\(count) clock options")
        } else {
            clocks = quickMatchSelectedClocks.compactMap { selection in
                OGSQuickMatchClockPreset.preset(
                    boardSize: boardSize,
                    speed: selection.speed,
                    system: selection.system
                )?.quickMatchAccessibleDescription
            }
            .joined(separator: String(localized: " or "))
        }

        return [
            sizes,
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
    @AccessibilityFocusState private var cancelIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recap.firstLine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !recap.secondLine.isEmpty {
                    Text(recap.secondLine)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchRecap
                )
                .accessibilityLabel(Text(verbatim: accessibleRecap))

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

                    if !isCancelling {
                        Button("Cancel", role: .destructive, action: onCancel)
                            .fontWeight(.bold)
                            .disabled(!canCancel)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Cancel live game search")
                            .accessibilityFocused($cancelIsFocused)
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
                .background(alignment: .topLeading) {
                    Text(verbatim: "Searching")
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID
                                .quickMatchSearching
                        )
                }
            } else {
                Button(action: onFind) {
                    Text("Find a game", comment: "New game view")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(canFind ? 1 : 0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!canFind)
                .accessibilityHint(Text(verbatim: accessibleRecap))
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
        .onChange(of: isSearching) { _, searching in
            if searching && !isCancelling {
                cancelIsFocused = true
            }
        }
    }
}

private struct QuickMatchBoardSizeTile: View {
    let size: Int
    let selected: Bool
    let multiple: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                BoardView(
                    boardPosition: BoardPosition(width: size, height: size)
                )
                .aspectRatio(1, contentMode: .fit)
                .opacity(selected ? 1 : 0.35)

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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("\(size) by \(size)")
        .accessibilityValue(
            multiple
                ? (selected ? String(localized: "Selected") : String(localized: "Not selected"))
                : ""
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.quickMatchBoardSize(size)
        )
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(Text(verbatim: accessibleDescription))
        .accessibilityValue(
            state == .alsoAccepted
                ? String(localized: "Also accepted")
                : (multiple
                    ? (state.selected ? String(localized: "Selected") : String(localized: "Not selected"))
                    : "")
        )
        .accessibilityAddTraits(state.selected ? .isSelected : [])
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.quickMatchClock(
                speed: preset.speed.rawValue,
                system: preset.system.rawValue
            )
        )
    }
}

struct QuickMatchForm: View {
    @Binding var draft: OGSQuickMatchDraft
    let eligibleOpenChallenges: [OGSSeekgraphChallenge]
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

    private var recap: OGSQuickMatchRecap {
        draft.quickMatchRecap(userRank: ogs.user?.ranking)
    }

    private var accessibleRecap: String {
        draft.quickMatchAccessibleRecap(userRank: ogs.user?.ranking)
    }

    private var formIsDisabled: Bool {
        activeLiveEntry != nil || isRestoringSearches
    }

    private var findDisabledReason: String? {
        if isRestoringSearches {
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
        let sizes = Set(draft.quickMatchSelectedBoardSizes)
        let speeds = Set(draft.quickMatchSelectedClocks.map(\.speed))
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
                    && !isRestoringSearches,
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
                    .opacity(formIsDisabled ? 0.55 : 1)
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
        }
        .background(alignment: .topLeading) {
            Text(verbatim: "Quick match")
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.screenQuickMatch
                )
        }
    }

    private var matchingSection: some View {
        QuickMatchCard(String(localized: "Matching")) {
            Picker(
                "Matching",
                selection: Binding(
                    get: { draft.mode },
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

            Text(draft.mode.quickMatchDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var boardSizeSection: some View {
        let selectedSizes = Set(draft.quickMatchSelectedBoardSizes)
        return QuickMatchCard(draft.quickMatchBoardSizeTitle) {
            if draft.mode == .multiple {
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
                multiple: draft.mode == .multiple,
                disabled: formIsDisabled,
                action: { draft.selectQuickMatchBoardSize(size) }
            )
        }
    }

    private var gameClockSection: some View {
        QuickMatchCard(String(localized: "Game clock")) {
            if draft.mode == .multiple {
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
        let correspondenceDisabled = draft.mode == .multiple
            && speed == .correspondence
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: speed.quickMatchSystemImage)
                    .font(.subheadline)
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

            if draft.mode == .flexible, draft.speed == speed, speed.isRealtime {
                Text("Both clocks accepted — \(draft.system.quickMatchTitle) preferred.")
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
                    multiple: draft.mode == .multiple,
                    disabled: formIsDisabled
                        || (draft.mode == .multiple && speed == .correspondence),
                    action: {
                        draft.selectQuickMatchClock(speed: speed, system: system)
                    }
                )
            }
        }
    }

    private func clockPresets(
        speed: TimeControlSpeed,
        system: OGSAutomatchClockSystem
    ) -> [OGSQuickMatchClockPreset] {
        let selectedSizes = draft.quickMatchSelectedBoardSizes
        let sizes = selectedSizes.isEmpty ? [draft.boardSize] : selectedSizes
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
        if draft.mode == .multiple {
            return draft.multipleClocks.contains(
                OGSQuickMatchClockSelection(speed: speed, system: system)
            ) ? .preferred : .off
        }
        guard draft.speed == speed else { return .off }
        if draft.speed == .correspondence {
            return system == .fischer ? .preferred : .off
        }
        if draft.system == system {
            return .preferred
        }
        return draft.mode == .flexible ? .alsoAccepted : .off
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
                                get: { draft.handicap == option },
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
                        Text(draft.handicap.quickMatchTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .menuOrder(.fixed)
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Handicap")
                .accessibilityValue(draft.handicap.quickMatchTitle)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchHandicap
                )
            }
        ) {
            Text(draft.handicap.quickMatchDescription)
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
                        difference: $draft.lowerRankDifference,
                        subtracts: true
                    )
                    Text("–")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    rankPicker(
                        title: String(localized: "Maximum opponent rank"),
                        difference: $draft.upperRankDifference,
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
