//
//  WaitingGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 23/02/2021.
//

import SwiftUI

struct AutomatchEntryCell: View {
    @EnvironmentObject var ogs: OGSService
    
    var entry: OGSAutomatchEntry
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Quick match request")
                    .font(.headline)
                Spacer()
                Button(action: { ogs.cancelAutomatch(entry: entry) }) {
                    Text("Withdraw")
                        .bold()
                        .foregroundColor(.red)
                }
            }
            Divider()
            Label(
                entry.sizeOptions.sorted().map { "\($0)×\($0)" }.joined(separator: ", "),
                systemImage: "squareshape.split.3x3"
            ).font(.subheadline)
        }
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
        let liveAutomatchEntries = ogs.autoMatchEntryById.values.filter { $0.timeControlSpeed != .correspondence }
        let correspondenceAutomatchEntries = ogs.autoMatchEntryById.values.filter { $0.timeControlSpeed == .correspondence }
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
        .navigationTitle("Waiting games")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WaitingGamesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WaitingGamesView()
                .navigationTitle("Waiting")
                .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(OGSService.previewInstance(
            user: OGSUser(
                username: "#albatros",
                id: 442873
            ),
            openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge],
            automatchEntries: [OGSAutomatchEntry.sampleEntry]
        ))
    }
}
