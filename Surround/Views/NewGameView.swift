//
//  NewGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 21/01/2021.
//

import SwiftUI

struct NewGameView: View {
    @State var newGameOption: NewGameOption = .quickMatch
    @State var boardSizes = Set<Int>([19])
    @State var timeControlSpeed: TimeControlSpeed = .live
    @State var blitz = false
    
    @EnvironmentObject var ogs: OGSService
    
    enum NewGameOption {
        case quickMatch
        case custom
        case direct
    }
    
    @State var eligibleOpenChallenges = [OGSChallenge]()
    
    var customChallengesMatchingAutomatchCondition: [OGSChallenge] {
        return Array(ogs.eligibleOpenChallengeById.values.filter { challenge in
            if let width = challenge.game?.width, let height = challenge.game?.height {
                if !boardSizes.contains(width) || !boardSizes.contains(height) {
                    return false
                }
            }
            
            if let challengeSpeed = challenge.game?.timeControl?.speed {
                switch challengeSpeed {
                case .correspondence:
                    return timeControlSpeed == .correspondence
                case .live:
                    return timeControlSpeed == .live && !blitz
                case .blitz:
                    return timeControlSpeed == .live && blitz
                }
            }
            
            return true
        })
    }
    
    var quickMatchOpenChallenges: some View {
        let challenges = customChallengesMatchingAutomatchCondition
        return VStack(alignment: .leading) {
            if challenges.count > 0 {
                Text("Alternatively, there \(challenges.count == 1 ? "is" : "are") \(challenges.count) open custom \(challenges.count == 1 ? "game" : "games") matching your preference that you can accept to start a game immediately.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                ForEach(challenges, id: \.id) { challenge in
                    ChallengeCell(challenge: challenge)
                        .padding()
                        .background(Color(UIColor.systemBackground).shadow(radius: 2))
                }
            }
        }
    }

    var quickMatchForm: some View {
        VStack(alignment: .leading) {
            Text("Automatically match you with another player who is also looking for a game.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            GroupBox(label: Text("Board size" + (boardSizes.count == 0 ? " ⚠️" : ""))) {
                HStack {
                    ForEach([9, 13, 19], id: \.self) { size in
                        VStack {
                            BoardView(boardPosition: BoardPosition(width: size, height: size))
                                .aspectRatio(1, contentMode: .fill)
                            HStack {
                                if boardSizes.contains(size) {
                                    Image(systemName: "checkmark.square.fill")
                                        .font(Font.footnote.bold())
                                }
                                Text("\(size)×\(size)")
                                    .font(Font.footnote.bold())
                            }
                            .padding(5)
                            .background(boardSizes.contains(size) ? Color(.systemBackground) : Color.clear)
                            .cornerRadius(5)
                        }
                        .onTapGesture {
                            withAnimation {
                                if boardSizes.contains(size) {
                                    boardSizes.remove(size)
                                } else {
                                    boardSizes.insert(size)
                                }
                            }
                        }
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
            GroupBox(label: Text("Game speed")) {
                Picker(selection: $timeControlSpeed.animation(), label: Text("Game speed")) {
                    Text("Live").tag(TimeControlSpeed.live)
                    Text("Correspondence").tag(TimeControlSpeed.correspondence)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: .infinity)
                if timeControlSpeed == .live {
                    Toggle(isOn: $blitz, label: {
                        VStack {
                            Text("Blitz")
                        }
                    })
                    Text("Live games generally finish in one sitting, around 30 seconds per move, or 10 seconds per move in Blitz mode.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if timeControlSpeed == .correspondence {
                    Text("Correspondence games are played over many days, around 1 day per move. Players often play multiple correspondence games at the same time.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Find a game").bold()
                    .foregroundColor(boardSizes.count == 0 ? .gray : .white)
            }
            .disabled(boardSizes.count == 0)
            .padding(.vertical, 10)
            .padding(.horizontal, 15)
            .background(Color.accentColor.opacity(boardSizes.count == 0 ? 0.8 : 1))
            .cornerRadius(10)

            quickMatchOpenChallenges
        }
        .onReceive(ogs.$eligibleOpenChallengeById) { eligibleOpenChallengesById in
            self.eligibleOpenChallenges = Array(
                eligibleOpenChallengesById.values.sorted(
                    by: { ($0.challenger?.username ?? "") < ($1.challenger?.username ?? "") }
                )
            )
        }
    }
    
    var customForm: some View {
        VStack(alignment: .leading) {
            Text("Create a game precisely as you want and display it publicly for anyone with an eligible rank to accept.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var directForm: some View {
        VStack(alignment: .leading) {
            Text("Challenge a friend (or a specific player) directly.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
        
    var body: some View {
        ScrollView {
            VStack {
                Picker(selection: $newGameOption.animation(), label: Text("New game option")) {
                    Text("Quick match").tag(NewGameOption.quickMatch)
                    Text("Custom").tag(NewGameOption.custom)
                    Text("vs. Friend").tag(NewGameOption.direct)
                }.pickerStyle(SegmentedPickerStyle())
                if newGameOption == .quickMatch {
                    quickMatchForm
                } else if newGameOption == .custom {
                    customForm
                } else if newGameOption == .direct {
                    directForm
                }
            }.padding()
        }
        .onAppear {
            ogs.subscribeToOpenChallenges()
        }
        .onDisappear {
            ogs.unsubscribeFromOpenChallenges()
        }
    }
}

struct NewGameView_Previews: PreviewProvider {
    static var previews: some View {
//        NewGameView()
        NavigationView {
            NewGameView()
                .navigationBarTitle("Create a new game")
                .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(OGSService.previewInstance())
    }
}
