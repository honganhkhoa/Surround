//
//  AnalyzeControlBar.swift
//  Surround
//

import SwiftUI

struct AnalyzeControlBar: View {
    private enum ConditionalMoveQuickActionPresentation {
        case labeled
        case iconOnly
    }

    @ObservedObject var moveTree: MoveTree
    @Binding var selectedPosition: BoardPosition?
    @Binding var preferredNextPositionByPosition: [ObjectIdentifier: BoardPosition]
    @Binding var boardTool: AnalyzeBoardTool
    var markups: BoardMarkups
    var analysisAvailable: Bool
    var canShareVariation: Bool
    var canAddConditionalMoves: Bool
    var addReplacesConditionalVariations: Bool
    var canRemoveConditionalMoves: Bool
    var showsConditionalMoveQuickAction: Bool
    var canDeleteSelectedBranch: Bool
    var deletesConditionalVariations: Bool
    var shareVariation: () -> Void
    var addToConditionalMoves: () -> Void
    var removeFromConditionalMoves: () -> Void
    var deleteBranch: (BoardPosition) -> Void
    var verticalTree = false
    var currentPosition: BoardPosition? = nil

    @State private var showingDeleteConfirmation = false
    #if DEBUG && MAIN_APP
    @State private var animationObservationID = UUID()
    #endif

    private var previousPosition: BoardPosition? {
        guard let selectedPosition,
              selectedPosition !== moveTree.initialPosition,
              moveTree.indexByBoardPosition[ObjectIdentifier(selectedPosition)] != nil,
              let previousPosition = selectedPosition.previousPosition,
              moveTree.indexByBoardPosition[ObjectIdentifier(previousPosition)] != nil else {
            return nil
        }
        return previousPosition
    }

    private var nextPosition: BoardPosition? {
        guard let selectedPosition else {
            return nil
        }

        let selectedIdentifier = ObjectIdentifier(selectedPosition)
        let nextPositions = (
            moveTree.nextPositionsByPosition[selectedIdentifier] ?? []
        ).filter {
            $0.previousPosition === selectedPosition
                && moveTree.indexByBoardPosition[ObjectIdentifier($0)] != nil
        }
        guard !nextPositions.isEmpty else {
            return nil
        }

        if let mainPosition = nextPositions.first(where: {
            moveTree.indexByBoardPosition[ObjectIdentifier($0)] == 0
        }) {
            return mainPosition
        }

        if let preferredPosition =
            preferredNextPositionByPosition[selectedIdentifier],
           nextPositions.contains(where: { $0 === preferredPosition }) {
            return preferredPosition
        }

        return nextPositions.first
    }

    private var nearestForkDestination: BoardPosition? {
        guard let selectedPosition else {
            return nil
        }
        return moveTree.nearestParentWithMultipleChildren(
            for: selectedPosition
        )
    }

    private var previousBranch: BoardPosition? {
        guard let selectedPosition else {
            return nil
        }
        return moveTree.adjacentBranch(
            from: selectedPosition,
            direction: .previous
        )
    }

    private var nextBranch: BoardPosition? {
        guard let selectedPosition else {
            return nil
        }
        return moveTree.adjacentBranch(
            from: selectedPosition,
            direction: .next
        )
    }

    private var livePosition: BoardPosition? {
        guard let currentPosition, selectedPosition !== currentPosition,
              moveTree.indexByBoardPosition[ObjectIdentifier(currentPosition)] != nil else { return nil }
        return currentPosition
    }

    var body: some View {
        // ViewThatFits picks the first row whose ideal width fits, then gives
        // it the whole bar, so the row's spacer keeps the editing tools at the
        // leading edge and navigation at the trailing edge. Fixing the rows'
        // width would collapse that spacer and centre every control together.
        ViewThatFits(in: .horizontal) {
            if analysisAvailable {
                if showsConditionalMoveQuickAction && selectedPosition != nil
                    && (canAddConditionalMoves || canRemoveConditionalMoves) {
                    // Measure the complete row rather than impose width
                    // thresholds. Shorten the conditional label before hiding
                    // branch navigation, so a 400pt bar retains every arrow.
                    controlBarContent(
                        showsAdjacentBranches: true,
                        conditionalMoveQuickActionPresentation: .labeled,
                        showsLiveButton: false
                    )
                    controlBarContent(
                        showsAdjacentBranches: true,
                        conditionalMoveQuickActionPresentation: .iconOnly,
                        showsLiveButton: false
                    )
                    controlBarContent(
                        showsAdjacentBranches: false,
                        conditionalMoveQuickActionPresentation: .labeled,
                        showsLiveButton: false
                    )
                    controlBarContent(
                        showsAdjacentBranches: false,
                        conditionalMoveQuickActionPresentation: .iconOnly,
                        showsLiveButton: false
                    )
                } else {
                    controlBarContent(
                        showsAdjacentBranches: true,
                        conditionalMoveQuickActionPresentation: .labeled,
                        showsLiveButton: false,
                        showsConditionalShortcut: false
                    )
                }
                // At the absolute 254pt minimum, the conditional action remains
                // in More and the five essential targets retain their width.
                controlBarContent(
                    showsAdjacentBranches: false,
                    conditionalMoveQuickActionPresentation: .labeled,
                    showsLiveButton: false,
                    showsConditionalShortcut: false
                )
            } else {
                controlBarContent(
                    showsAdjacentBranches: false,
                    conditionalMoveQuickActionPresentation: .labeled
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 52)
        .modifier(AnalyzeControlBarSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar
        )
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "analyze.controlBar", ownerID: animationObservationID
        )
        #endif
        .onReceive(moveTree.objectWillChange) {
            DispatchQueue.main.async {
                prunePreferredNextPositions()
            }
        }
        .confirmationDialog(
            "Delete branch?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete branch", role: .destructive) {
                deleteSelectedBranch()
            }
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameAnalyzeConfirmDelete
            )
            Button("Cancel", role: .cancel) {}
        } message: {
            if deletesConditionalVariations {
                Text("This removes the selected move and every move after it in this branch. Conditional-move variations in this branch will also be removed.")
            } else {
                Text("This removes the selected move and every move after it in this branch.")
            }
        }
    }

    private func controlBarContent(
        showsAdjacentBranches: Bool,
        conditionalMoveQuickActionPresentation:
            ConditionalMoveQuickActionPresentation,
        showsLiveButton: Bool = true,
        showsConditionalShortcut: Bool = true
    ) -> some View {
        HStack(spacing: 2) {
            if analysisAvailable {
                actionsMenu
                    #if DEBUG && MAIN_APP
                    .surroundAnimationObservation(
                        "analyze.actionsMenu", ownerID: animationObservationID,
                        context: "\(showsAdjacentBranches ? "adjacent" : "basic").\(conditionalMoveQuickActionPresentation)"
                    )
                    #endif
                if selectedPosition != nil {
                    MarkerToolMenu(
                        markups: markups,
                        tool: $boardTool
                    )
                    if showsConditionalShortcut {
                        conditionalMoveQuickAction(
                            presentation: conditionalMoveQuickActionPresentation
                        )
                    }
                }
            }
            Spacer(minLength: 8)
            if analysisAvailable && showsAdjacentBranches {
                controlButton(
                    "Previous branch",
                    systemImage: verticalTree ? "arrow.left" : "arrow.up",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzePreviousBranch,
                    destination: previousBranch
                )
                controlButton(
                    "Next branch",
                    systemImage: verticalTree ? "arrow.right" : "arrow.down",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeNextBranch,
                    destination: nextBranch
                )
            }
            if analysisAvailable {
                controlButton(
                    "Back to fork",
                    systemImage: verticalTree ? "arrow.turn.up.left" : "arrow.turn.left.up",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeBackToFork,
                    destination: nearestForkDestination
                )
            }
            controlButton(
                "Previous",
                systemImage: verticalTree ? "chevron.up" : "chevron.left",
                accessibilityIdentifier: SurroundUITestContract
                    .AccessibilityID.gameAnalyzePrevious,
                destination: previousPosition,
                remembersCurrentPosition: true
            )
            controlButton(
                "Next",
                systemImage: verticalTree ? "chevron.down" : "chevron.right",
                accessibilityIdentifier: SurroundUITestContract
                    .AccessibilityID.gameAnalyzeNext,
                destination: nextPosition
            )
            if showsLiveButton {
                controlButton("Back to live", systemImage: "forward.end",
                              accessibilityIdentifier: "game.analyze.live",
                              destination: livePosition)
            }
        }
        #if DEBUG && MAIN_APP
        .surroundAnimationObservation(
            "analyze.variant", ownerID: animationObservationID,
            context: "\(showsAdjacentBranches ? "adjacent" : "basic").\(conditionalMoveQuickActionPresentation)"
        )
        #endif
    }

    // Group these actions with Divider rather than Section. iOS 27 drops the
    // accessibility identifier and value of every Menu item wrapped in a
    // Section, leaving only its localized label, which no longer identifies an
    // action across the App Store capture's thirteen languages. Divider draws
    // the same separators in the same places and keeps the identifiers.
    private var actionsMenu: some View {
        Menu {
            Button {
                if let livePosition { selectedPosition = livePosition }
            } label: {
                Label("Back to live", systemImage: "forward.end")
            }
            .disabled(livePosition == nil)
            .accessibilityIdentifier("game.analyze.live.menu")

            Button(action: shareVariation) {
                Label("Share variation in chat", systemImage: "message")
            }
            .disabled(!canShareVariation)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameAnalyzeShare
            )

            Divider()

            Button(action: addToConditionalMoves) {
                Label(
                    "Add to conditional moves",
                    image: "custom.envelope.and.arrow.trianglehead.branch.badge.plus"
                )
                if addReplacesConditionalVariations {
                    Text("Replaces conflicting variations")
                }
            }
            .disabled(!canAddConditionalMoves)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameAnalyzeAddConditional
            )
            .accessibilityLabel(
                Text("Add to conditional moves")
                    + Text(verbatim: ", ")
                    + Text("Replaces conflicting variations"),
                isEnabled: addReplacesConditionalVariations
            )

            Button(action: removeFromConditionalMoves) {
                Label(
                    "Remove from conditional moves",
                    image: "custom.envelope.and.arrow.trianglehead.branch.badge.minus"
                )
            }
            .disabled(!canRemoveConditionalMoves)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameAnalyzeRemoveConditional
            )

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete branch", systemImage: "trash")
            }
            .disabled(!canDeleteSelectedBranch)
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.gameAnalyzeDeleteBranch
            )
        } label: {
            Label("More analysis actions", systemImage: "ellipsis.circle")
                .labelStyle(IconOnlyLabelStyle())
                .frame(width: 44, height: 44)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.highlight)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameAnalyzeActionsMenu
        )
    }

    @ViewBuilder
    private func conditionalMoveQuickAction(
        presentation: ConditionalMoveQuickActionPresentation
    ) -> some View {
        if showsConditionalMoveQuickAction {
            if canRemoveConditionalMoves {
                conditionalMoveQuickActionButton(
                    "Remove from conditional moves",
                    shortTitle: "Remove",
                    image: "custom.envelope.and.arrow.trianglehead.branch.badge.minus",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeQuickRemoveConditional,
                    presentation: presentation,
                    action: removeFromConditionalMoves
                )
            } else if canAddConditionalMoves {
                conditionalMoveQuickActionButton(
                    "Add to conditional moves",
                    shortTitle: "Add",
                    image: "custom.envelope.and.arrow.trianglehead.branch.badge.plus",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeQuickAddConditional,
                    presentation: presentation,
                    includesReplacementWarning:
                        addReplacesConditionalVariations,
                    action: addToConditionalMoves
                )
            }
        }
    }

    private func conditionalMoveQuickActionButton(
        _ title: LocalizedStringKey,
        shortTitle: LocalizedStringKey,
        image: String,
        accessibilityIdentifier: String,
        presentation: ConditionalMoveQuickActionPresentation,
        includesReplacementWarning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            switch presentation {
            case .labeled:
                Label(shortTitle, image: image)
                    .labelStyle(TitleAndIconLabelStyle())
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
            case .iconOnly:
                Label(shortTitle, image: image)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.highlight)
        .foregroundStyle(Color.conditionalMoveHighlight)
        .help(Text(title))
        .accessibilityLabel(
            includesReplacementWarning
                ? Text(title)
                    + Text(verbatim: ", ")
                    + Text("Replaces conflicting variations")
                : Text(title)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func controlButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        accessibilityIdentifier: String,
        destination: BoardPosition?,
        remembersCurrentPosition: Bool = false
    ) -> some View {
        Button {
            guard let destination else {
                return
            }
            if remembersCurrentPosition, let selectedPosition {
                preferredNextPositionByPosition[ObjectIdentifier(destination)] =
                    selectedPosition
            }
            self.selectedPosition = destination
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(IconOnlyLabelStyle())
                .frame(width: 44, height: 44)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.highlight)
        .disabled(destination == nil)
        .help(Text(title))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func deleteSelectedBranch() {
        guard let selectedPosition else {
            return
        }
        deleteBranch(selectedPosition)
    }

    private func prunePreferredNextPositions() {
        let registeredPositionIdentifiers = Set(
            moveTree.indexByBoardPosition.keys
        )
        let retainedPreferences = preferredNextPositionByPosition.filter {
            identifier, position in
            registeredPositionIdentifiers.contains(identifier)
                && registeredPositionIdentifiers.contains(
                    ObjectIdentifier(position)
                )
        }
        if retainedPreferences.count != preferredNextPositionByPosition.count {
            preferredNextPositionByPosition = retainedPreferences
        }
    }
}

private struct MarkerToolMenu: View {
    var markups: BoardMarkups
    @Binding var tool: AnalyzeBoardTool

    var body: some View {
        Menu {
            Picker("Board editing tool", selection: $tool) {
                ForEach(AnalyzeBoardTool.allCases, id: \.self) { option in
                    Label(toolTitle(option), systemImage: toolSystemImage(option))
                        .tag(option)
                        .accessibilityIdentifier(
                            SurroundUITestContract.AccessibilityID
                                .gameAnalyzeMarkerTool(option.rawValue)
                        )
                }
            }
        } label: {
            Group {
                if tool == .letters || tool == .numbers {
                    Text(verbatim: currentLiteral)
                        .font(.body.bold().monospaced())
                } else {
                    Image(systemName: toolSystemImage(tool))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundColor(tool == .moves ? .primary : .accentColor)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        tool == .moves
                            ? Color.clear
                            : Color.accentColor.opacity(0.14)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.highlight)
        .help("Board editing tool")
        .accessibilityLabel("Board editing tool")
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameAnalyzeMarkerMenu
        )
    }

    private var currentLiteral: String {
        tool == .letters
            ? markups.nextBoardLetter
            : markups.nextBoardNumber
    }

    private var accessibilityValue: String {
        switch tool {
        case .letters, .numbers:
            return String(localized: toolTitle(tool))
                + ", "
                + String(
                    localized: "Next label: \(currentLiteral)",
                    comment: "Accessibility value announcing the next automatic letter or number that the Analyze board marker tool will place."
                )
        default:
            return String(localized: toolTitle(tool))
        }
    }

    private func toolTitle(_ tool: AnalyzeBoardTool) -> LocalizedStringResource {
        switch tool {
        case .moves: LocalizedStringResource("Add moves")
        case .letters: LocalizedStringResource("Letters")
        case .numbers: LocalizedStringResource("Numbers")
        case .triangle: LocalizedStringResource("Triangle")
        case .square: LocalizedStringResource("Square")
        case .circle: LocalizedStringResource("Circle")
        case .cross: LocalizedStringResource("X")
        case .eraser: LocalizedStringResource("Eraser")
        }
    }

    private func toolSystemImage(_ tool: AnalyzeBoardTool) -> String {
        switch tool {
        case .moves: "circle.tophalf.filled"
        case .letters: "character"
        case .numbers: "number"
        case .triangle: "triangle"
        case .square: "square"
        case .circle: "circle"
        case .cross: "xmark"
        case .eraser: "eraser"
        }
    }
}

private struct AnalyzeControlBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GameDetailAppearance.panel, ignoresSafeAreaEdges: [])
            .overlay {
                Rectangle().stroke(GameDetailAppearance.panelBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}
