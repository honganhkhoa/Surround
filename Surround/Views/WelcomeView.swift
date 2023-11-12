//
//  WelcomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/03/2021.
//

import SwiftUI
import Combine

struct WelcomeView: View {
    @EnvironmentObject var ogs: OGSService
    @State var publicGames = [Game]()
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Surround is a client to play Go online with other players on the website Online-Go.com, also known as Online Go Server (OGS).")
                    .leadingAlignedInScrollView()
                Text("To start playing:")
                    .leadingAlignedInScrollView()
                NavigationLink(destination: OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/sign-in")!, showsURLBar: true).navigationBarTitleDisplayMode(.inline)) {
                    Text("Sign in to your OGS account")
                        .foregroundColor(.white)
                        .bold()
                        .frame(maxWidth: 400)
                        .padding(.vertical)
                        .background(Color(.systemIndigo).cornerRadius(10))
                        .padding(.horizontal)
                }
                Text("or")
                NavigationLink(destination: OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/register")!, showsURLBar: true).navigationBarTitleDisplayMode(.inline)) {
                    Text("Register an OGS account")
                        .foregroundColor(.white)
                        .bold()
                        .frame(maxWidth: 400)
                        .padding(.vertical)
                        .background(Color(.systemIndigo).cornerRadius(10))
                        .padding(.horizontal)
                }
                if let liveGames = ogs.sitewiseLiveGamesCount, let correspondenceGames = ogs.sitewiseCorrespondenceGamesCount {
                    (Text(.init(localized: "**\(correspondenceGames) correspondence games** and **\(liveGames) live games** are being played right now.")))
                        .leadingAlignedInScrollView()
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal)
            .padding(.top)
            if publicGames.count > 0 {
                GeometryReader { geometry in
                    if geometry.size.height > 200 {
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: [GridItem(.adaptive(minimum: 300), spacing: 15)], spacing: 15) {
                                ForEach(publicGames) { game in
                                    BoardView(boardPosition: game.currentPosition)
                                        .aspectRatio(contentMode: .fit)
                                }
                            }
                            .padding()
                        }
                    } else {
                        Spacer()
                    }
                }
            } else {
                Spacer()
            }
        }
        .onAppear {
            ogs.ensureConnect {
                ogs.subscribeToGameCount()
                ogs.cyclePublicGames()
            }
        }
        .onDisappear {
            ogs.unsubscribeFromGameCount()
            ogs.cancelPublicGamesCycling()
        }
        .onChange(of: ogs.sortedPublicGames) { games in
            if self.publicGames.count > 0 {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = []
                }
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(2500))) {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = games.shuffled()
                }
            }
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                WelcomeView()
                    .navigationTitle("Welcome")
            }
            NavigationView {
                WelcomeView()
                    .navigationTitle("Welcome")
            }
            .previewDevice("iPhone SE (1st generation)")
        }
        .environmentObject(
            OGSService.previewInstance(
                publicGames: [TestData.Ongoing19x19HandicappedWithNoInitialState, TestData.Ongoing19x19wBot1]
                )
        )
    }
}
