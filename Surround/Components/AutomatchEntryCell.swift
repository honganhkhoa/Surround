//
//  AutomatchEntryCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 23/02/2021.
//
//  One Quick Match search as a card: its settings and Withdraw. In a card
//  that Activity pushed, Withdraw goes through the window's results store
//  (`activityCellActions`), which settles it; elsewhere the cell sends it and
//  waits 8 s for OGS to confirm.
//

import SwiftUI

struct AutomatchEntryCell: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.activityCellActions) private var activityCellActions
    @State private var isCancelling = false
    @State private var cancellationFailed = false
    
    var entry: OGSAutomatchEntry

    /// Activity's request, or the cell's own.
    private var isWithdrawing: Bool {
        (activityCellActions?.isPending ?? false) || isCancelling
    }

    private var presentation: AutomatchEntryPresentation? {
        AutomatchEntryPresentation(entry: entry, userRank: ogs.user?.ranking)
    }

    private var quickMatchDraft: OGSQuickMatchDraft? {
        guard let presentation = OGSActiveQuickMatchPresentation(entry: entry),
              presentation.draft.quickMatchClockPreference != .mixed else {
            return nil
        }
        return presentation.draft
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            requestHeader
            Divider()
            if let draft = quickMatchDraft, let presentation {
                let recap = draft.quickMatchRecap(userRank: ogs.user?.ranking)
                Label(
                    recap.firstLine,
                    systemImage: "squareshape.split.3x3"
                )
                clockSummary(presentation)
                Label(
                    presentation.handicap,
                    systemImage: "square.grid.3x3.topleft.filled"
                )
                Label(
                    draft.quickMatchRankRange(userRank: ogs.user?.ranking),
                    systemImage: "arrow.up.and.down.square"
                )
                .accessibilityLabel(
                    draft.quickMatchAccessibleRankRange(userRank: ogs.user?.ranking)
                )
            } else if let presentation {
                Label(
                    presentation.boardAndSpeed,
                    systemImage: "squareshape.split.3x3"
                )

                clockSummary(presentation)
                Label(
                    presentation.rankRange,
                    systemImage: "arrow.up.and.down.square"
                )

                Label(
                    presentation.handicap,
                    systemImage: "square.grid.3x3.topleft.filled"
                )

                if let rules = presentation.rules {
                    Label(rules, systemImage: "doc.text")
                }
            } else {
                Label(
                    "Unable to display match settings",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID
                .waitingGamesAutomatchEntry(entry.uuid)
        )
        .task(id: isCancelling) {
            guard isCancelling else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  ogs.autoMatchEntryById[entry.uuid] != nil else {
                return
            }
            isCancelling = false
            cancellationFailed = true
        }
        .alert(
            "Couldn’t cancel the search",
            isPresented: $cancellationFailed
        ) {
            Button("Retry", action: requestCancellation)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("OGS did not confirm the cancellation. The search is still shown so you can try again.")
        }
    }

    private func clockSummary(
        _ presentation: AutomatchEntryPresentation
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(
                    Array(presentation.clockLines.enumerated()),
                    id: \.offset
                ) { _, clockLine in
                    Text(clockLine)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: "clock")
        }
    }

    private var requestHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                requestTitle
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                cancellationButton
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                requestTitle
                    .fixedSize(horizontal: false, vertical: true)
                cancellationButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var requestTitle: some View {
        Text("Quick match request")
            .font(.headline)
    }

    private var cancellationButton: some View {
        Button(action: requestCancellation) {
            HStack(spacing: 6) {
                if isWithdrawing {
                    ProgressView()
                        .accessibilityHidden(true)
                }
                Text("Withdraw")
                    .bold()
                    .foregroundColor(.red)
            }
        }
        .disabled(isWithdrawing)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            isWithdrawing
                ? String(localized: "Withdrawing quick match search")
                : String(localized: "Withdraw quick match search")
        )
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID
                .waitingGamesAutomatchWithdraw(entry.uuid)
        )
    }

    private func requestCancellation() {
        if let activityCellActions {
            // The store sends it and settles it: no 8 s alert here.
            activityCellActions.withdrawSearch(entry)
            return
        }
        guard !isCancelling else { return }
        guard ogs.cancelAutomatch(entry: entry) else {
            cancellationFailed = true
            return
        }
        isCancelling = true
    }
}
