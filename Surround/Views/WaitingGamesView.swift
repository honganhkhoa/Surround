//
//  WaitingGamesView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 23/02/2021.
//

import SwiftUI

struct WaitingGamesView: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme

    @State var liveChallenges: [OGSChallenge] = []
    @State var correspondenceChallenges: [OGSChallenge] = []
    
    func updateWaitingGamesList() {
        var liveChallenges = [OGSChallenge]()
        var correspondenceChallenges = [OGSChallenge]()
        for challenge in ogs.challengesSent + ogs.openChallengeSentById.values {
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

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15, pinnedViews: [.sectionHeaders]) {
                if self.liveChallenges.count > 0 {
                    Section(header: sectionHeader(title: "Live games")) {
                        Group {
                            ForEach(self.liveChallenges) { challenge in
                                ChallengeCell(challenge: challenge)
                                    .padding()
                                    .background(
                                        Color(
                                            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                        )
                                        .shadow(radius: 2)
                                    )
                            }
                        }
                    }
                }
                if self.correspondenceChallenges.count > 0 {
                    Section(header: sectionHeader(title: "Correspondence games")) {
                        ForEach(self.correspondenceChallenges) { challenge in
                            ChallengeCell(challenge: challenge)
                                .padding()
                                .background(
                                    Color(
                                        colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                    )
                                    .shadow(radius: 2)
                                )
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
            openChallengesSent: [OGSChallenge.sampleOpenChallenge]
        ))
    }
}
