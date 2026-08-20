//
//  AnalyzeControlBar.swift
//  Surround
//

import SwiftUI

struct AnalyzeControlBar: View {
    @ObservedObject var moveTree: MoveTree
    @Binding var selectedPosition: BoardPosition?
    var analysisAvailable: Bool
    var canShareVariation: Bool
    var canAddConditionalMoves: Bool
    var addReplacesConditionalVariations: Bool
    var canRemoveConditionalMoves: Bool
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
        HStack(spacing: 2) {
            if analysisAvailable {
                actionsMenu
            }
            Spacer(minLength: 8)
            if analysisAvailable {
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
