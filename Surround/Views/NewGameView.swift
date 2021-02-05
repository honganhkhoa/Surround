//
//  NewGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 21/01/2021.
//

import SwiftUI

struct QuickMatchForm: View {
    @State var boardSizes = Set<Int>([19])
    @State var timeControlSpeed: TimeControlSpeed = .live
    @State var blitz = false
    var eligibleOpenChallenges = [OGSChallenge]()
    
    @EnvironmentObject var ogs: OGSService

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
                Text("Alternatively, there \(challenges.count == 1 ? "is" : "are") \(challenges.count) open custom \(challenges.count == 1 ? "game" : "games") matching your preferences that you can accept to start a game immediately.")
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

    var body: some View {
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
                        Text("Blitz")
                    })
                    (Text("Live games").bold() + Text(" generally finish in one sitting, around 30 seconds per move, or 10 seconds per move in ") + Text("Blitz").bold() + Text(" mode."))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if timeControlSpeed == .correspondence {
                    (Text("Correspondence games").bold() + Text(" are played over many days, around 1 day per move. Players often play multiple correspondence games at the same time."))
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
    }
}

struct CustomGameForm: View {
    var eligibleOpenChallenges = [OGSChallenge]()
    
    @State var gameName = ""
    @State var isPrivate = false
    @State var isRanked = true
    
    @State var boardWidth = 19
    @State var boardHeight = 19
    @State var standardBoardSize = true
    
    @State var timeControlSpeed = TimeControlSpeed.live
    @State var isBlitz = false
    var finalTimeControlSpeed: TimeControlSpeed {
        if timeControlSpeed == .correspondence {
            return .correspondence
        } else {
            if isBlitz {
                return .blitz
            } else {
                return timeControlSpeed
            }
        }
    }

    @State var blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
    @State var liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
    @State var correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
    var finalTimeControl: TimeControl {
        switch finalTimeControlSpeed {
        case .blitz:
            return blitzTimeControl
        case .live:
            return liveTimeControl
        case .correspondence:
            return correspondenceTimeControl
        }
    }
    
    func revertToStandardTimeSetting() {
        withAnimation {
            blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
            liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
        }
    }
    
    @EnvironmentObject var ogs: OGSService

    var body: some View {
        VStack(alignment: .leading) {
            Text("Create a game precisely as you want and display it publicly for anyone with an eligible rank to accept.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            GroupBox(label: Text("General")) {
                TextField("Game name", text: $gameName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Toggle(isOn: $isRanked) {
                    Text("Ranked")
                }
                Toggle(isOn: $isPrivate) {
                    Text("Private")
                }
            }
            GroupBox(label: Text("Board size")) {
                Picker(selection: $standardBoardSize.animation(), label: Text("Standard board size")) {
                    Text("Standard").tag(true)
                    Text("Custom").tag(false)
                }.pickerStyle(SegmentedPickerStyle())
                if standardBoardSize {
                    HStack {
                        ForEach([9, 13, 19], id: \.self) { size in
                            VStack {
                                BoardView(boardPosition: BoardPosition(width: size, height: size))
                                    .aspectRatio(1, contentMode: .fill)
                                HStack {
                                    if boardWidth == size && boardHeight == size {
                                        Image(systemName: "checkmark.square.fill")
                                            .font(Font.footnote.bold())
                                    }
                                    Text("\(size)×\(size)")
                                        .font(Font.footnote.bold())
                                }
                                .padding(5)
                                .background(boardWidth == size && boardHeight == size ? Color(.systemBackground) : Color.clear)
                                .cornerRadius(5)
                            }
                            .onTapGesture {
                                withAnimation {
                                    self.boardWidth = size
                                    self.boardHeight = size
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        BoardView(boardPosition: BoardPosition(width: boardWidth, height: boardHeight))
                            .aspectRatio(1, contentMode: .fill)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Width").font(.subheadline).bold()
                            Stepper(value: $boardWidth, in: 1...25, step: 1) {
                                Text("\(boardWidth)")
                            }
                            Spacer().frame(height: 10)
                            Divider()
                            Spacer().frame(height: 10)
                            Text("Height").font(.subheadline).bold()
                            Stepper(value: $boardHeight, in: 1...25, step: 1) {
                                Text("\(boardHeight)")
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
                if timeControlSpeed == .live {
                    Toggle(isOn: $isBlitz) {
                        Text("Blitz")
                    }
                }
                (Text("\(finalTimeControl.systemName): ").bold() + finalTimeControl.system.descriptionText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(height: 10)
                if finalTimeControl.system != finalTimeControlSpeed.defaultTimeOptions[0] {
                    Button(action: revertToStandardTimeSetting) {
                        Text("Revert to standard time setting.")
                            .font(.subheadline).bold()
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer().frame(height: 10)
                NavigationLink(
                    destination: TimeSystemPickerView(
                        blitzTimeControl: $blitzTimeControl,
                        liveTimeControl: $liveTimeControl,
                        correspondenceTimeControl: $correspondenceTimeControl,
                        timeControlSpeed: $timeControlSpeed,
                        isBlitz: $isBlitz)
                ) {
                    (Text("Advanced time settings ") + Text(Image(systemName: "chevron.forward")))
                        .font(.subheadline).bold()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.onChange(of: standardBoardSize) { standard in
            if standard && (boardWidth != boardHeight || ![9, 13, 19].contains(boardWidth)) {
                self.boardWidth = 19
                self.boardHeight = 19
            }
        }
    }
}

struct NewGameView: View {
    @State var newGameOption: NewGameOption = .quickMatch
    @State var eligibleOpenChallenges = [OGSChallenge]()
    @EnvironmentObject var ogs: OGSService

    enum NewGameOption {
        case quickMatch
        case custom
        case direct
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
                    QuickMatchForm(eligibleOpenChallenges: self.eligibleOpenChallenges)
                } else if newGameOption == .custom {
                    CustomGameForm(eligibleOpenChallenges: self.eligibleOpenChallenges)
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
        .onReceive(ogs.$eligibleOpenChallengeById) { eligibleOpenChallengesById in
            withAnimation {
                self.eligibleOpenChallenges = Array(
                    eligibleOpenChallengesById.values.sorted(
                        by: { ($0.challenger?.username ?? "") < ($1.challenger?.username ?? "") }
                    )
                )
            }
        }
    }
}

struct NewGameView_Previews: PreviewProvider {
    static var previews: some View {

        return Group {
            NavigationView {
                NewGameView(newGameOption: .custom)
                    .navigationBarTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(OGSService.previewInstance())
        }
    }
}
