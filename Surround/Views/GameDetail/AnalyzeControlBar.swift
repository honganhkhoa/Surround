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

    @State private var preferredNextPositionByPosition =
        [ObjectIdentifier: BoardPosition]()
    @State private var showingDeleteConfirmation = false

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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlBarContent(
                showsAdjacentBranches: true,
                conditionalMoveQuickActionPresentation: .labeled
            )
            controlBarContent(
                showsAdjacentBranches: false,
                conditionalMoveQuickActionPresentation: .labeled
            )
            controlBarContent(
                showsAdjacentBranches: false,
                conditionalMoveQuickActionPresentation: .iconOnly
            )
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.gameAnalyzeControlBar
        )
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
            ConditionalMoveQuickActionPresentation
    ) -> some View {
        HStack(spacing: 2) {
            if analysisAvailable {
                actionsMenu
                if selectedPosition != nil {
                    MarkerToolMenu(
                        markups: markups,
                        tool: $boardTool
                    )
                    conditionalMoveQuickAction(
                        presentation: conditionalMoveQuickActionPresentation
                    )
                }
            }
            Spacer(minLength: 8)
            if analysisAvailable && showsAdjacentBranches {
                controlButton(
                    "Previous branch",
                    systemImage: "arrow.up",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzePreviousBranch,
                    destination: previousBranch
                )
                controlButton(
                    "Next branch",
                    systemImage: "arrow.down",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeNextBranch,
                    destination: nextBranch
                )
            }
            if analysisAvailable {
                controlButton(
                    "Back to fork",
                    systemImage: "arrow.turn.left.up",
                    accessibilityIdentifier: SurroundUITestContract
                        .AccessibilityID.gameAnalyzeBackToFork,
                    destination: nearestForkDestination
                )
            }
            controlButton(
                "Previous",
                systemImage: "chevron.left",
                accessibilityIdentifier: SurroundUITestContract
                    .AccessibilityID.gameAnalyzePrevious,
                destination: previousPosition,
                remembersCurrentPosition: true
            )
            controlButton(
                "Next",
                systemImage: "chevron.right",
                accessibilityIdentifier: SurroundUITestContract
                    .AccessibilityID.gameAnalyzeNext,
                destination: nextPosition
            )
        }
    }

    private var actionsMenu: some View {
        Menu {
            Section {
                Button(action: shareVariation) {
                    Label("Share variation in chat", systemImage: "message")
                }
                .disabled(!canShareVariation)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameAnalyzeShare
                )
            }

            Section {
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
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete branch", systemImage: "trash")
                }
                .disabled(!canDeleteSelectedBranch)
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.gameAnalyzeDeleteBranch
                )
            }
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
