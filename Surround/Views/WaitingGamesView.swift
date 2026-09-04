//
//  WaitingGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 23/02/2021.
//

import SwiftUI

struct AutomatchEntryCell: View {
    @EnvironmentObject var ogs: OGSService
    @State private var isCancelling = false
    @State private var cancellationFailed = false
    
    var entry: OGSAutomatchEntry

    private var presentation: AutomatchEntryPresentation? {
        AutomatchEntryPresentation(entry: entry, userRank: ogs.user?.ranking)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            requestHeader
            Divider()
            if let presentation {
                Label(
                    presentation.boardAndSpeed,
                    systemImage: "squareshape.split.3x3"
                )

                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(
                            Array(presentation.clockLines.enumerated()),
                            id: \.offset
                        ) { _, clockLine in
                            Text(clockLine)
                        }
                    }
                } icon: {
                    Image(systemName: "clock")
                }
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
            if isCancelling {
                ProgressView()
                    .accessibilityLabel("Cancelling quick match search")
            } else {
                Text("Withdraw")
                    .bold()
                    .foregroundColor(.red)
            }
        }
        .disabled(isCancelling)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            isCancelling
                ? String(localized: "Cancelling quick match search")
                : String(localized: "Cancel quick match search")
        )
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID
                .waitingGamesAutomatchWithdraw(entry.uuid)
        )
    }

    private func requestCancellation() {
        guard !isCancelling else { return }
        guard ogs.cancelAutomatch(entry: entry) else {
            cancellationFailed = true
            return
        }
        isCancelling = true
    }
}

struct WaitingGamesView: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme

    @State var liveChallenges: [any OGSSubmittedChallenge] = []
    @State var correspondenceChallenges: [any OGSSubmittedChallenge] = []
    
    func updateWaitingGamesList() {
        var liveChallenges = [any OGSSubmittedChallenge]()
        var correspondenceChallenges = [any OGSSubmittedChallenge]()
        for challenge in ogs.challengesSent {
            if challenge.game.timeControl.speed == .correspondence {
                correspondenceChallenges.append(challenge)
            } else {
                liveChallenges.append(challenge)
            }
        }
        for challenge in ogs.openChallengeSentById.values {
            if challenge.game.timeControl.speed == .correspondence {
                correspondenceChallenges.append(challenge)
            } else {
                liveChallenges.append(challenge)
            }
        }
        self.liveChallenges = liveChallenges
        self.correspondenceChallenges = correspondenceChallenges
    }
    
    func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(Font.title3.bold())
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray3).shadow(radius: 2))
        .padding(.horizontal, -15)
    }

    var cardBackground: some View {
        Color(
            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
        )
        .shadow(radius: 2)
    }
    
    var body: some View {
        let liveAutomatchEntries = ogs.autoMatchEntryById.values
            .filter { !$0.isCorrespondence }
            .sorted { $0.uuid < $1.uuid }
        let correspondenceAutomatchEntries = ogs.autoMatchEntryById.values
            .filter(\.isCorrespondence)
            .sorted { $0.uuid < $1.uuid }
        let liveRengoChallenges = ogs.participatingRengoChallengeById.values.filter { $0.game.timeControl.speed != .correspondence }
        let correspondenceRengoChallenges = ogs.participatingRengoChallengeById.values.filter { $0.game.timeControl.speed == .correspondence }
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15, pinnedViews: [.sectionHeaders]) {
                if self.liveChallenges.count + liveAutomatchEntries.count + liveRengoChallenges.count > 0 {
                    Section(header: sectionHeader(title: String(localized: "Live games"))) {
                        ForEach(liveRengoChallenges) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(cardBackground)
                        }
                        ForEach(liveAutomatchEntries, id: \.uuid) { entry in
                            AutomatchEntryCell(entry: entry)
                                .padding()
                                .background(cardBackground)
                        }
                        ForEach(self.liveChallenges, id: \.id) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(cardBackground)
                        }
                    }
                }
                if self.correspondenceChallenges.count + correspondenceAutomatchEntries.count + correspondenceRengoChallenges.count > 0 {
                    Section(header: sectionHeader(title: String(localized: "Correspondence games"))) {
                        ForEach(correspondenceRengoChallenges) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(cardBackground)
                        }
                        ForEach(correspondenceAutomatchEntries, id: \.uuid) { entry in
                            AutomatchEntryCell(entry: entry)
                                .padding()
                                .background(cardBackground)
                        }
                        ForEach(self.correspondenceChallenges, id: \.id) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(cardBackground)
                        }
                    }
                }
                if ogs.challengesReceived.count > 0 {
                    Section(header: sectionHeader(title: String(localized: "Challenges received"))) {
                        ForEach(ogs.challengesReceived) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(cardBackground)
                        }
                    }
                }
            }.padding(.horizontal)
        }
        .onAppear() {
            updateWaitingGamesList()
        }
        .onReceive(ogs.$challengesSent) { _ in
            DispatchQueue.main.async {
                updateWaitingGamesList()
            }
        }
        .onReceive(ogs.$openChallengeSentById) { _ in
            DispatchQueue.main.async {
                updateWaitingGamesList()
            }
        }
        .navigationTitle("Searching for games")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
private func waitingGamesPreview(
    openChallenges: [OGSSeekgraphChallenge],
    automatchEntries: [OGSAutomatchEntry]
) -> some View {
    NavigationStack {
        WaitingGamesView()
            .navigationTitle("Waiting")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(
                username: "#albatros",
                id: 442873
            ),
            openChallengesSent: openChallenges,
            automatchEntries: automatchEntries
        )
    )
}

#Preview("Waiting games — Requests") {
    waitingGamesPreview(
        openChallenges: [OGSChallengeSampleData.sampleOpenChallenge],
        automatchEntries: [OGSAutomatchEntry.sampleEntry]
    )
}

#Preview("Waiting games — Empty") {
    waitingGamesPreview(openChallenges: [], automatchEntries: [])
}
#endif
