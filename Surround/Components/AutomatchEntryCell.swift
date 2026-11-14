//
//  AutomatchEntryCell.swift
//  Surround
//
//  Created by Anh Khoa Hong on 23/02/2021.
//
//  One Quick Match search as a card: its settings and Withdraw. Activity
//  pushes it, and Withdraw goes through the window's results store
//  (`activityCellActions`), which sends it and settles it.
//

import SwiftUI

struct AutomatchEntryCell: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.activityCellActions) private var activityCellActions

    var entry: OGSAutomatchEntry

    /// While Activity's request is out.
    private var isWithdrawing: Bool {
        activityCellActions?.isPending ?? false
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
        .activityCardAction(activityCellActions, .withdraw)
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
        activityCellActions?.withdrawSearch(entry)
    }
}
