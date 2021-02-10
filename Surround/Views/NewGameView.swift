//
//  NewGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 21/01/2021.
//

import SwiftUI
import URLImage

struct MainActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var label: String
    var disabled = false
    var action: () -> ()
    
    var body: some View {
        Button(action: action) {
            Text(label).bold()
                .foregroundColor(Color(disabled ? UIColor.systemGray5 : UIColor.white))
        }
        .disabled(disabled)
        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(Color.accentColor.opacity(disabled ? 0.7 : 1))
        .cornerRadius(10)
    }
}

struct QuickMatchForm: View {
    @State var boardSizes = Set<Int>([19])
    @State var timeControlSpeed: TimeControlSpeed = .live
    @State var blitz = false
    var eligibleOpenChallenges = [OGSChallenge]()
    
    @EnvironmentObject var ogs: OGSService

    var customChallengesMatchingAutomatchCondition: [OGSChallenge] {
        return Array(ogs.eligibleOpenChallengeById.values.filter { challenge in
            let width = challenge.game.width
            let height = challenge.game.height
            if !boardSizes.contains(width) || !boardSizes.contains(height) {
                return false
            }
            
            if let challengeSpeed = challenge.game.timeControl.speed {
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
        ScrollView {
            VStack(alignment: .leading) {
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
                            Text("Blitz").font(.subheadline)
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
                MainActionButton(label: "Find a game", disabled: boardSizes.count == 0, action: {
                    
                })

                quickMatchOpenChallenges
            }
            .padding()
        }
    }
}

struct CustomGameForm: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    
    @State var challenge: OGSChallenge = {
        var newChallenge = OGSChallenge(
            id: 0,
            game: OGSChallengeGameDetail(
                width: 19,
                height: 19,
                ranked: true,
                isPrivate: false,
                handicap: -1,
                disableAnalysis: false,
                name: "Friendly Match",
                rules: .japanese,
                timeControl: TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            )
        )
        return newChallenge
    }()
    
    @State var gameName = "Friendly Match"
    
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
    
    @State var pauseOnWeekend = true
    
    @State var isOpen = true
    @State var rankRestricted = false
    @State var maxRank = 36
    @State var minRank = 5
    
    @State var opponent: OGSUser?
    @State var selectingOpponent = false
    
    @State var handicap = -1
    @State var automaticColor = true
    @State var yourColor = StoneColor.black
    
    @State var rulesSet = OGSRule.japanese
    @State var komi = 6.5
    
    @State var analysisDisabled = false
    
    func revertToStandardTimeSetting() {
        withAnimation {
            blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
            liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
        }
    }

    var rankRestrictionRange: ClosedRange<Int> {
        guard isRanked, let user = ogs.user else {
            return 5...38
        }
        
        let rank = Int(user.rank())
        
        return max(rank - 9, 5)...min(rank + 9, 38)
    }
    
    func updateForRankedGames() {
        isPrivate = false
        standardBoardSize = true
        if let user = ogs.user {
            let rank = Int(user.rank())
            minRank = max(minRank, rank - 9)
            maxRank = min(maxRank, rank + 9)
        }
        komi = rulesSet.defaultKomi
        handicap = min(handicap, 9)
    }
    
    var opponentOptions: some View {
        GroupBox(label: Text("Opponent")) {
            Picker(selection: $isOpen.animation(), label: Text("Is open")) {
                Text("Open").tag(true)
                Text("vs. Friend").tag(false)
            }.pickerStyle(SegmentedPickerStyle())
            if isOpen {
                Text("Create and show a challenge publicly, then wait for other players to accept.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Toggle(isOn: $rankRestricted.animation()) {
                    Text("Restrict opponent rank")
                        .font(.subheadline)
                }
                if rankRestricted {
                    Stepper(value: $minRank, in: rankRestrictionRange) {
                        (Text("From ") + Text(RankUtils.formattedRank(Double(minRank), longFormat: true)).bold())
                            .font(.subheadline)
                    }
                    Stepper(value: $maxRank, in: rankRestrictionRange) {
                        (Text("To ") + Text(RankUtils.formattedRank(Double(maxRank), longFormat: true)).bold())
                            .font(.subheadline)
                    }
                }
            } else {
                Text("Send a challenge directly to a friend (or a specific player) so they can accept to start a game.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(height: 10)
                Divider()
                NavigationLink(destination: UserSelectionView(user: $opponent, isPresented: $selectingOpponent), isActive: $selectingOpponent) {
                    HStack {
                        if let opponent = opponent, let opponentIconURL = opponent.iconURL(ofSize: 64) {
                            URLImage(opponentIconURL)
                                .frame(width: 64, height: 64)
                                .background(Color.gray)
                                .cornerRadius(10)
                        } else {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 64))
                                .frame(width: 64, height: 64)
                                .cornerRadius(10)
                        }
                        if let opponent = opponent {
                            VStack(alignment: .leading) {
                                Text(opponent.username).bold()
                                Text("[\(opponent.formattedRank)]").font(.subheadline)
                            }
                        } else {
                            (Text("Select your opponent ") + Text(Image(systemName: "chevron.forward")))
                                .font(.subheadline)
                                .bold()
                        }
                        Spacer()
                    }
                }
                Stepper(value: $handicap, in: -1...(isRanked ? 9 : 36)) {
                    (Text("Handicap: ").bold() + Text(
                        handicap == -1 ? "Automatic" :
                        handicap == 0 ? "None" :
                        handicap == 1 ? "1 Stone" : "\(handicap) Stones"
                    ))
                    .font(.subheadline)
                }
                if handicap == -1 {
                    Text("Automatically determine the number of handicap stones based on your and your opponent's rank.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            Toggle(isOn: $automaticColor) {
                Text("Automatically assign stone colors").font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !automaticColor {
                HStack {
                    Text("Your color").font(.subheadline)
                    Picker(selection: $yourColor, label: Text("Your color")) {
                        Text("Black").tag(StoneColor.black)
                        Text("White").tag(StoneColor.white)
                    }.pickerStyle(SegmentedPickerStyle())
                }
            } else {
                (Text("Automatic").bold() + Text(" setting will either assign white to the stronger player, follow your opponent's preference, or just assign randomly."))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: maxRank) { newValue in
            minRank = min(minRank, newValue)
        }
        .onChange(of: minRank) { newValue in
            maxRank = max(maxRank, newValue)
        }
        .onChange(of: isOpen) { newValue in
            if newValue {
                handicap = -1
            }
        }
    }
    
    var boardSizeOptions: some View {
        GroupBox(label: Text("Board size")) {
            Picker(selection: $standardBoardSize.animation(), label: Text("Standard board size")) {
                Text("Standard").tag(true)
                Text("Custom").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .disabled(isRanked)
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
            if isRanked {
                (Text("Custom").bold() + Text(" board sizes are not available in ") + Text("ranked").bold() + Text(" games."))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: standardBoardSize) { standard in
            if standard && (boardWidth != boardHeight || ![9, 13, 19].contains(boardWidth)) {
                self.boardWidth = 19
                self.boardHeight = 19
            }
        }
    }
    
    var gameSpeedOptions: some View {
        GroupBox(label: Text("Game speed")) {
            Picker(selection: $timeControlSpeed.animation(), label: Text("Game speed")) {
                Text("Live").tag(TimeControlSpeed.live)
                Text("Correspondence").tag(TimeControlSpeed.correspondence)
            }
            .pickerStyle(SegmentedPickerStyle())
            if timeControlSpeed == .live {
                Toggle(isOn: $isBlitz) {
                    Text("Blitz").font(.subheadline)
                }
            } else if timeControlSpeed == .correspondence {
                Toggle(isOn: $pauseOnWeekend) {
                    Text("Pause on weekend").font(.subheadline)
                }
            }
            Divider()
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
                    isBlitz: $isBlitz,
                    pauseOnWeekend: $pauseOnWeekend)
            ) {
                (Text("Advanced time settings ") + Text(Image(systemName: "chevron.forward")))
                    .font(.subheadline).bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    var rulesOptions: some View {
        GroupBox(label: Text("Rules")) {
            HStack {
                Text("Rules set: ")
                    .font(.subheadline).padding(.vertical, 10)
                if rulesSet == .japanese || rulesSet == .chinese {
                    Picker(selection: $rulesSet, label: Text("Rule set")) {
                        Text("Japanese").tag(OGSRule.japanese)
                        Text("Chinese").tag(OGSRule.chinese)
                    }.pickerStyle(SegmentedPickerStyle())
                } else {
                    NavigationLink(destination: RulesPickerView(rulesSet: $rulesSet, komi: $komi, isRanked: isRanked)) {
                        (Text("\(rulesSet.fullName) ").bold() + Text(Image(systemName: "chevron.forward")))
                            .font(.subheadline)
                    }
                }
                Spacer()
            }
            (Text(komi == rulesSet.defaultKomi ? "Standard" : "Custom").bold() + Text(" komi: ") + Text(String(format: "%.1f", komi)).bold())
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 10)
            NavigationLink(destination: RulesPickerView(rulesSet: $rulesSet, komi: $komi, isRanked: isRanked)) {
                (Text("Advanced rules settings ") + Text(Image(systemName: "chevron.forward")))
                    .font(.subheadline).bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: rulesSet) { newValue in
            komi = newValue.defaultKomi
        }
    }
    
    var gameTypeOptions: some View {
        GroupBox(label: Text("Game type")) {
            Toggle(isOn: $isRanked) {
                Text("Ranked").font(.subheadline)
            }
            Toggle(isOn: $isPrivate) {
                Text("Private").font(.subheadline)
            }
            .disabled(isRanked)
            (Text("Disable the ") + Text("ranked").bold() + Text(" option above if you don't want the result to count towards your rating. ") + Text("Ranked").bold() + Text(" games cannot be ") + Text("private").bold() + Text(" and have fewer customizing options."))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: isRanked) { newValue in
            if newValue {
                withAnimation {
                    updateForRankedGames()
                }
            }
        }
    }
    
    @State var isEditingGameName = false
    
    var otherOptions: some View {
        GroupBox(label: Text("Others")) {
            Spacer().frame(height: 10)
            if isEditingGameName {
                AutofocusTextField(
                    text: $gameName,
                    isEditing: $isEditingGameName,
                    placeholder: "Friendly Match",
                    textStyle: .subheadline,
                    onEditingDone: {
                        if gameName.count == 0 {
                            gameName = "Friendly Match"
                        }
                    }
                )
            } else {
                Button(action: { isEditingGameName = true }) {
                    (Text("Game name: ") + Text(gameName).bold())
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Toggle(isOn: $analysisDisabled) {
                Text("Disable analysis").font(.subheadline)
            }
            (Text("Analysis mode").bold() + Text(" is currently not available in the app yet. If you or your opponent use the web version during the match, ") + Text("analysis mode").bold() + Text(" is like a separate board where you can test out variations during the game."))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func updateTimeControl() {
        challenge.game.timeControl = finalTimeControl
        if challenge.game.timeControl.speed == .correspondence {
            challenge.game.timeControl.pauseOnWeekends = pauseOnWeekend
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading) {
                    gameTypeOptions
                    opponentOptions
                    boardSizeOptions
                    gameSpeedOptions
                    rulesOptions
                    otherOptions
                    MainActionButton(label: "Create challenge", disabled: false, action: {})
                    Spacer().frame(height: 15)
                    Text("Preview")
                        .font(.title3).bold()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChallengeCell(challenge: challenge)
                        .padding()
                        .background(
                            Color(
                                colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray6
                            ).shadow(radius: 2)
                        )
                }
                .padding()
            }
        }
        .onChange(of: gameName) { challenge.game.name = $0 }
        .onChange(of: isRanked) { challenge.game.ranked = $0 }
        .onChange(of: isPrivate) { challenge.game.isPrivate = $0 }
        .onChange(of: rankRestricted) {
            challenge.game.maxRank = $0 ? maxRank : 1000
            challenge.game.minRank = $0 ? minRank : -1000
        }
        .onChange(of: maxRank) { challenge.game.maxRank = $0 }
        .onChange(of: minRank) { challenge.game.minRank = $0 }
        .onChange(of: handicap) { challenge.game.handicap = $0 }
        .onChange(of: automaticColor) {
            challenge.challengerColor = $0 ? nil : yourColor
            challenge.game.challengerColor = challenge.challengerColor
        }
        .onChange(of: boardWidth) { challenge.game.width = $0 }
        .onChange(of: boardHeight) { challenge.game.height = $0 }
        .onChange(of: timeControlSpeed) { _ in updateTimeControl() }
        .onChange(of: isBlitz) { _ in updateTimeControl() }
        .onChange(of: liveTimeControl) { _ in updateTimeControl() }
        .onChange(of: blitzTimeControl) { _ in updateTimeControl() }
        .onChange(of: correspondenceTimeControl) { _ in updateTimeControl() }
        .onChange(of: pauseOnWeekend) { challenge.game.timeControl.pauseOnWeekends = $0 }
        .onChange(of: rulesSet) { challenge.game.rules = $0 }
        .onChange(of: komi) { challenge.game.komi = $0 }
        .onChange(of: analysisDisabled) { challenge.game.disableAnalysis = $0 }
        .onAppear {
            challenge.challenger = ogs.user
            if isRanked {
                updateForRankedGames()
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
        case openChallenges
    }
    
    var openChallengesForm: some View {
        VStack(alignment: .leading) {
        }
    }
    
    var newGameOptionsPicker: some View {
        VStack() {
            Picker(selection: $newGameOption.animation(), label: Text("New game option")) {
                Text("Quick match").tag(NewGameOption.quickMatch)
                Text("Custom").tag(NewGameOption.custom)
                Text("Waiting (\(ogs.eligibleOpenChallengeById.count))").tag(NewGameOption.openChallenges)
            }
            .pickerStyle(SegmentedPickerStyle())
            switch newGameOption {
            case .quickMatch:
                Text("Automatically match you with another player who is also looking for a game.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .custom:
                Text("Create a game precisely as you want.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .openChallenges:
                Text("Open challenges that you can accept to start a game immediately.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                newGameOptionsPicker.opacity(0)
                if newGameOption == .quickMatch {
                    QuickMatchForm(eligibleOpenChallenges: self.eligibleOpenChallenges)
                } else if newGameOption == .custom {
                    CustomGameForm()
                } else if newGameOption == .openChallenges {
                    openChallengesForm
                }
            }
            newGameOptionsPicker.background(Color(.systemGray6).shadow(radius: 2))
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
//            .colorScheme(.dark)
            .environmentObject(OGSService.previewInstance(user: OGSUser(
                username: "HongAnhKhoa",
                id: 314459,
                ranking: 27
            )))
        }
    }
}
