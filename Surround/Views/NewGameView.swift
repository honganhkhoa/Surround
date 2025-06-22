//
//  NewGameView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 21/01/2021.
//

import SwiftUI
import URLImage
import Combine

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
    var eligibleOpenChallenges = [OGSSeekgraphChallenge]()

    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.colorScheme) private var colorScheme

    var finalTimeControlSpeed: TimeControlSpeed {
        if timeControlSpeed == .correspondence {
            return .correspondence
        } else {
            if blitz {
                return .blitz
            } else {
                return timeControlSpeed
            }
        }
    }

    var customChallengesMatchingAutomatchCondition: [OGSSeekgraphChallenge] {
        return Array(ogs.eligibleOpenChallengeById.values.filter { challenge in
            let width = challenge.game.width
            let height = challenge.game.height
            if challenge.rengo || !boardSizes.contains(width) || !boardSizes.contains(height) {
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
        return VStack(alignment: .leading, spacing: 0) {
            if challenges.count > 0 {
                Text("Alternatively, there are \(challenges.count) open custom games matching your preferences that you can accept to start a game immediately.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
                Spacer().frame(height: 15)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                    ForEach(challenges, id: \.id) { challenge in
                        ChallengeCell(challenge: challenge)
                            .padding()
                            .background(
                                Color(
                                    colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                )
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            )
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                GroupBox(label: Text(String(localized: "Board size") + (boardSizes.count == 0 ? " ⚠️" : ": \([9, 13, 19].filter { boardSizes.contains($0) }.map { "\($0)×\($0)" }.joined(separator: ", "))"))) {
                    Text("You can select multiple options.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                    HStack {
                        ForEach([9, 13, 19], id: \.self) { size in
                            VStack {
                                Toggle(isOn: Binding(
                                        get: { boardSizes.contains(size) },
                                        set: { if $0 { boardSizes.insert(size) } else { boardSizes.remove(size) } })) {
                                }
                                BoardView(boardPosition: BoardPosition(width: size, height: size))
                                    .aspectRatio(1, contentMode: .fill)
                                    .opacity(boardSizes.contains(size) ? 1 : 0.2)
                                Text(verbatim: "\(size)×\(size)")
                                    .font(Font.footnote.bold())
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
                GroupBox(label: Text("Game speed: \(finalTimeControlSpeed.localizedString())")) {
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
                        (Text("**Live games** generally finish in one sitting, around 30 seconds per move, or 10 seconds per move in **Blitz** mode."))
                            .font(.subheadline)
                            .leadingAlignedInScrollView()
                    } else if timeControlSpeed == .correspondence {
                        Text("**Correspondence games** are played over many days, around 1 day per move. Players often play multiple correspondence games at the same time.")
                            .font(.subheadline)
                            .leadingAlignedInScrollView()
                    }
                }
                .frame(maxWidth: .infinity)
                MainActionButton(label: String(localized: "Find a game", comment: "New game view"), disabled: boardSizes.count == 0, action: {
                    let automatchEntry = OGSAutomatchEntry(
                        sizeOptions: self.boardSizes,
                        timeControlSpeed: self.finalTimeControlSpeed
                    )
                    userDefaults[.lastAutomatchEntry] = automatchEntry
                    ogs.findAutomatch(entry: automatchEntry)
                    nav.home.showingNewGameView = false
                })

                quickMatchOpenChallenges
            }
            .padding()
        }
        .onAppear {
            if let lastAutomatchEntry = userDefaults[.lastAutomatchEntry] {
                boardSizes = lastAutomatchEntry.sizeOptions
                timeControlSpeed = lastAutomatchEntry.timeControlSpeed == .correspondence ? .correspondence : .live
                blitz = lastAutomatchEntry.timeControlSpeed == .blitz
            }
        }
    }
}

let defaultGameName = String(localized: "Friendly Match", comment: "Default game name")

struct CustomGameForm: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.colorScheme) private var colorScheme
    
    @State var challenge: OGSChallengeTemplate = {
        var newChallenge = OGSChallengeTemplate(
            game: OGSChallengeTemplate.GameDetail(
                width: 19,
                height: 19,
                ranked: true,
                isPrivate: false,
                handicap: 0,
                disableAnalysis: false,
                name: defaultGameName,
                rules: .japanese,
                timeControl: TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            )
        )
        return newChallenge
    }()
    
    @State var gameName = defaultGameName
    
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
    
    @State var handicap = 0
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
        return 5...38
    }
    
    func updateForRankedGames() {
        isPrivate = false
        standardBoardSize = true
        komi = rulesSet.defaultKomi
        handicap = min(handicap, 9)
    }
    
    var opponentOptions: some View {
        GroupBox(label: Text("Opponent")) {
            Picker(selection: $isOpen.animation(), label: Text("Is open")) {
                Text("Open", comment: "Opponent section of NewGameView, 'Open' here means anyone").tag(true)
                Text("vs. Friend", comment: "Opponent section of NewGameView").tag(false)
            }.pickerStyle(SegmentedPickerStyle())
            if isOpen {
                Text("Create and show a challenge publicly, then wait for other players to accept.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
                Divider()
                Toggle(isOn: $rankRestricted.animation()) {
                    Text("Restrict opponent rank")
                        .font(.subheadline)
                }
                if rankRestricted {
                    Stepper(value: $minRank, in: rankRestrictionRange) {
                        Text("From **\(RankUtils.formattedRank(Double(minRank), longFormat: true))**", comment: "Custom game rank restriction")
                            .font(.subheadline)
                    }
                    Stepper(value: $maxRank, in: rankRestrictionRange) {
                        Text("To **\(RankUtils.formattedRank(Double(maxRank), longFormat: true))**", comment: "Custom game rank restriction")
                            .font(.subheadline)
                    }
                }
            } else {
                Text("Send a challenge directly to a friend (or a specific player) so they can accept to start a game.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
                Spacer().frame(height: 10)
                Divider()
                NavigationLink(destination: UserSelectionView(user: $opponent)) {
                    HStack {
                        if let opponent = opponent, let opponentIconURL = opponent.iconURL(ofSize: 64) {
                            URLImage(url: opponentIconURL) { $0.resizable() }
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
                                Text(verbatim: opponent.username).bold()
                                if !Setting(.hidesRank).wrappedValue {
                                    Text(verbatim: "[\(opponent.formattedRank)]").font(.subheadline)
                                }
                            }
                            .foregroundColor(opponent.uiColor)
                        } else {
                            (Text("Select your opponent ") + Text(Image(systemName: "chevron.forward")))
                                .font(.subheadline)
                                .bold()
                        }
                        Spacer()
                    }
                }
            }
            Divider()
            Toggle(isOn: Binding ( get: { handicap == -1 }, set: { handicap = ($0 ? -1 : 0) })) {
                Text("Automatically decide handicap").font(.subheadline)
            }
            if handicap > -1 {
                Stepper(value: $handicap, in: 0...(isRanked ? 9 : 36)) {
                    (Text("Handicap: ").bold() + Text(
                        handicap == -1 ? String(localized: "Automatic", comment: "NewGameView handicap selection, automatic handicap") :
                            handicap == 0 ? String(localized: "No handicap", comment : "NewGameView handicap seletion, no handicap") :
                            String(localized: "\(handicap) Stones", comment: "NewGameView handicap selection - vary for plural")
                    ))
                    .font(.subheadline)
                }
            } else {
                (Text("**Automatic** setting will determine the number of handicap stones based on your and your opponent's rank."))
                    .font(.caption)
                    .leadingAlignedInScrollView()
            }
            Divider()
            Toggle(isOn: $automaticColor) {
                Text("Automatically assign stone colors").font(.subheadline)
                    .leadingAlignedInScrollView()
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
                (Text("**Automatic** setting will either assign white to the stronger player, or just assign randomly."))
                    .font(.caption)
                    .leadingAlignedInScrollView()
            }
        }
        .onChange(of: maxRank) { newValue in
            minRank = min(minRank, newValue)
        }
        .onChange(of: minRank) { newValue in
            maxRank = max(maxRank, newValue)
        }
    }
    
    var boardSizeOptions: some View {
        GroupBox(label: Text("Board size")) {
            Picker(selection: $standardBoardSize.animation(), label: Text("Standard board size")) {
                Text("Standard size", comment: "refers to standard board sizes").tag(true)
                Text("Custom size", comment: "refers to custom board sizes").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .disabled(isRanked)
            HStack(alignment: .top) {
                BoardView(boardPosition: BoardPosition(width: boardWidth, height: boardHeight))
                    .aspectRatio(1, contentMode: .fill)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Width").font(.subheadline).bold()
                    Stepper(
                        value: Binding(
                            get: { standardBoardSize ? ([9, 13, 19].firstIndex(of: boardWidth) ?? 2) : boardWidth },
                            set: {
                                boardWidth = (standardBoardSize ? [9, 13, 19][$0] : $0)
                                if standardBoardSize { boardHeight = boardWidth }
                            }
                        ),
                        in: standardBoardSize ? 0...2 : 2...25, step: 1) {
                            Text(verbatim: "\(boardWidth)")
                    }
                    Spacer().frame(height: 10)
                    Divider()
                    Spacer().frame(height: 10)
                    Text("Height").font(.subheadline).bold()
                    Stepper(
                        value: Binding(
                            get: { standardBoardSize ? ([9, 13, 19].firstIndex(of: boardHeight) ?? 2) : boardHeight },
                            set: {
                                boardHeight = (standardBoardSize ? [9, 13, 19][$0] : $0)
                                if standardBoardSize { boardWidth = boardHeight }
                            }
                        ),
                        in: standardBoardSize ? 0...2 : 2...25, step: 1) {
                            Text(verbatim: "\(boardHeight)")
                    }
                }
            }
            if isRanked {
                (Text("**Custom** board sizes are not available in **ranked** games."))
                    .font(.caption)
                    .leadingAlignedInScrollView()
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
            (Text(verbatim: "\(finalTimeControl.systemName): ").bold() + finalTimeControl.system.descriptionText)
                .font(.subheadline)
                .leadingAlignedInScrollView()
            Spacer().frame(height: 10)
            if finalTimeControl.system != finalTimeControlSpeed.defaultTimeOptions[0] {
                Button(action: revertToStandardTimeSetting) {
                    Text("Revert to standard time setting.")
                        .font(.subheadline).bold()
                        .leadingAlignedInScrollView()
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
                (Text("Advanced time settings") + Text(verbatim: " ") + Text(Image(systemName: "chevron.forward")))
                    .font(.subheadline).bold()
                    .leadingAlignedInScrollView()
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
                        (Text(verbatim: "\(rulesSet.fullName) ").bold() + Text(Image(systemName: "chevron.forward")))
                            .font(.subheadline)
                    }
                }
                Spacer()
            }
            if komi == rulesSet.defaultKomi {
                Text("**Standard** komi: **\(komi, specifier: "%.1f")**")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            } else {
                Text("**Custom** komi: **\(komi, specifier: "%.1f")**")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            }
            Spacer().frame(height: 10)
            NavigationLink(destination: RulesPickerView(rulesSet: $rulesSet, komi: $komi, isRanked: isRanked)) {
                (Text("Advanced rules settings") + Text(verbatim: " ") + Text(Image(systemName: "chevron.forward")))
                    .font(.subheadline).bold()
                    .leadingAlignedInScrollView()
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
            (Text("Disable the **ranked** option above if you don't want the result to count towards your rating. **Ranked** games cannot be **private** and have fewer customizing options."))
                .font(.caption)
                .leadingAlignedInScrollView()
        }
        .onChange(of: isRanked) { newValue in
            if newValue {
                withAnimation {
                    updateForRankedGames()
                }
            }
        }
    }
    
    var otherOptions: some View {
        GroupBox(label: Text("Others", comment: "NewGameView, title for `Others` section")) {
            Spacer().frame(height: 10)
            HStack {
                Text("Game name:")
                    .font(.subheadline)
                TextField(defaultGameName, text: $gameName)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit {
                        if gameName.count == 0 {
                            gameName = defaultGameName
                        }
                    }
            }
            Toggle(isOn: $analysisDisabled) {
                Text("Disable analysis").font(.subheadline)
            }
            (Text("**Analysis mode** allows you and your opponent to test out variations during the game. It's like a separate virtual board where you can try things out."))
                .font(.caption)
                .leadingAlignedInScrollView()
        }
    }

    func updateTimeControl() {
        challenge.game.timeControl = finalTimeControl
        if challenge.game.timeControl.speed == .correspondence {
            challenge.game.timeControl.pauseOnWeekends = pauseOnWeekend
        }
    }
    
    var createButtonDisabled: Bool {
        return !isOpen && opponent == nil
    }
    
    @State var challengeCreatingCancellable: AnyCancellable?
    
    var actionButton: some View {
        VStack(alignment: .leading) {
            if self.challengeCreatingCancellable != nil {
                Spacer().frame(height: 15)
                ProgressView()
            } else {
                MainActionButton(label: String(localized: "Create challenge"), disabled: createButtonDisabled, action: createChallenge)
                if !isOpen && opponent == nil {
                    Text("You need to choose an opponent or make the challenge open.")
                        .font(.caption)
                        .leadingAlignedInScrollView()
                }
            }
            Spacer().frame(height: 15)
        }
    }
    
    func createChallenge() {
        if isOpen || opponent != nil {
            self.challengeCreatingCancellable = ogs.sendChallenge(opponent: isOpen ? nil : opponent, challenge: challenge).sink(
                receiveCompletion: { _ in
                    self.challengeCreatingCancellable = nil
                }, receiveValue: { _ in
                    nav.home.showingNewGameView = false
                })
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
                    actionButton
                    HStack {
                        Text("Preview")
                            .font(.title3).bold()
                        Spacer()
                        Button(action: {}) {
                            Label("Save settings", systemImage: "star")
                        }
                        .tint(.green)
                        .buttonStyle(.bordered)
                    }
                    ChallengeCell(challenge: challenge)
                        .padding()
                        .background(
                            Color(
                                colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                            )
                            .cornerRadius(8)
                            .shadow(radius: 2)
                        )
                    // Workaround for an issue on iOS 14.5 where the NavigationLink pops out by itself.
                    // https://developer.apple.com/forums/thread/677333#672042022
                    NavigationLink(destination: EmptyView()) {
                        EmptyView()
                    }
                }
                .padding()
            }
            .apply {
                if #available(iOS 16.0, *) {
                    $0.scrollDismissesKeyboard(.interactively)
                } else {
                    $0
                }
            }
        }
        .onChange(of: gameName) { challenge.game.name = $0 }
        .onChange(of: isRanked) { challenge.game.ranked = $0 }
        .onChange(of: isPrivate) { challenge.game.isPrivate = $0 }
        .onChange(of: rankRestricted) {
            challenge.game.maxRank = $0 && isOpen ? maxRank : 1000
            challenge.game.minRank = $0 && isOpen ? minRank : -1000
        }
        .onChange(of: isOpen) {
            challenge.game.maxRank = $0 && rankRestricted ? maxRank : 1000
            challenge.game.minRank = $0 && rankRestricted ? minRank : -1000
            if $0 {
                challenge.challenged = nil
            } else {
                challenge.challenged = opponent
            }
        }
        .onChange(of: maxRank) { challenge.game.maxRank = $0 }
        .onChange(of: minRank) { challenge.game.minRank = $0 }
        .onChange(of: handicap) { challenge.game.handicap = $0 }
        .onChange(of: automaticColor) {
            challenge.challengerColor = $0 ? nil : yourColor
        }
        .onChange(of: yourColor) {
            challenge.challengerColor = $0
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
        .onChange(of: opponent) { challenge.challenged = $0 }
        .onAppear {
            challenge.challenger = ogs.user
            if isRanked {
                updateForRankedGames()
            }
        }
    }
}

struct OpenChallengesForm: View {
    @EnvironmentObject var ogs: OGSService
    @Environment(\.colorScheme) private var colorScheme
    var eligibleOpenChallenges: [OGSSeekgraphChallenge] {
        didSet {
            var _challengeIds = [Int]()
            var _rengoIds = [Int]()
            for challenge in eligibleOpenChallenges {
                if challenge.rengo {
                    _rengoIds.append(challenge.id)
                } else {
                    _challengeIds.append(challenge.id)
                }
            }
            challengeIds = _challengeIds
            rengoIds = _rengoIds
        }
    }
    
    @State var challengeIds = [Int]()
    @State var rengoIds = [Int]()
    @State var challengeType: ChallengeType = .standard
    
    enum ChallengeType {
        case standard
        case rengo
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
        var liveGameChallenges = [OGSSeekgraphChallenge]()
        var correspondenceGameChallenges = [OGSSeekgraphChallenge]()
        var liveRengoChallenges = [OGSSeekgraphChallenge]()
        var correspondenceRengoChallenges = [OGSSeekgraphChallenge]()
        for challenge in eligibleOpenChallenges {
            if challenge.rengo {
                if challenge.game.timeControl.speed == .correspondence {
                    correspondenceRengoChallenges.append(challenge)
                } else {
                    liveRengoChallenges.append(challenge)
                }
            } else {
                if challenge.game.timeControl.speed == .correspondence {
                    correspondenceGameChallenges.append(challenge)
                } else {
                    liveGameChallenges.append(challenge)
                }
            }
        }
        let standardCount = liveGameChallenges.count + correspondenceGameChallenges.count
        let rengoCount = liveRengoChallenges.count + correspondenceRengoChallenges.count
        
        return ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 10)
                Picker("Challenge type", selection: $challengeType.animation()) {
                    Text("Standard 1v1 (\(standardCount))").tag(ChallengeType.standard)
                    Text("Rengo (\(rengoCount))", comment: "NewGameView  (rengoCount)").tag(ChallengeType.rengo)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }
            
            if challengeType == .standard {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15, pinnedViews: [.sectionHeaders]) {
                    if liveGameChallenges.count > 0 {
                        Section(header: sectionHeader(title: String(localized: "Live games"))) {
                            Group {
                                ForEach(liveGameChallenges) { challenge in
                                    ChallengeCell(challenge: challenge)
                                        .padding()
                                        .background(
                                            Color(
                                                colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                            )
                                            .shadow(radius: 2)
                                        )
                                        .id(challenge.id)
                                }
                            }
                        }
                    }
                    if correspondenceGameChallenges.count > 0 {
                        Section(header: sectionHeader(title: String(localized: "Correspondence games"))) {
                            ForEach(correspondenceGameChallenges) { challenge in
                                ChallengeCell(challenge: challenge)
                                    .padding()
                                    .background(
                                        Color(
                                            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                        )
                                        .shadow(radius: 2)
                                    )
                                    .id(challenge.id)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .animation(.linear, value: self.challengeIds)
            } else if challengeType == .rengo {
                VStack(spacing: 0) {
                    Text("A **rengo** game is played between two teams, one taking the Black stones and the other taking the White stones. Each player in a team must play in turn.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                    Spacer().frame(height: 10)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15, pinnedViews: [.sectionHeaders]) {
                        if liveRengoChallenges.count > 0 {
                            Section(header: sectionHeader(title: String(localized: "Live rengo games"))) {
                                Group {
                                    ForEach(liveRengoChallenges) { challenge in
                                        ChallengeCell(challenge: challenge)
                                            .padding()
                                            .background(
                                                Color(
                                                    colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                                )
                                                .shadow(radius: 2)
                                            )
                                            .id(challenge.id)
                                    }
                                }
                            }
                        }
                        if correspondenceRengoChallenges.count > 0 {
                            Section(header: sectionHeader(title: String(localized: "Correspondence rengo games"))) {
                                ForEach(correspondenceRengoChallenges) { challenge in
                                    ChallengeCell(challenge: challenge)
                                        .padding()
                                        .background(
                                            Color(
                                                colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                                            )
                                            .shadow(radius: 2)
                                        )
                                        .id(challenge.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .animation(.linear, value: self.rengoIds)
            }
        }
    }
}

struct NewGameView: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @State var newGameOption: NewGameOption = .quickMatch
    @State var eligibleOpenChallenges = [OGSSeekgraphChallenge]()

    enum NewGameOption {
        case quickMatch
        case custom
        case openChallenges
    }
    
    var newGameOptionsPicker: some View {
        let eligibleRengoChallengesCount = ogs.eligibleOpenChallengeById.values.filter { $0.rengo }.count
        let eligibleOpenChallengesCount = ogs.eligibleOpenChallengeById.count
        
        var openChallengesSubheader = String(localized: "There are currently no open challenges.")
        if eligibleOpenChallengesCount > 0 {
            if eligibleOpenChallengesCount > eligibleRengoChallengesCount {
                let standardCount = eligibleOpenChallengesCount - eligibleRengoChallengesCount
                openChallengesSubheader = String(localized: "There are \(standardCount) open challenges that you can accept to start a game immediately.")
                if eligibleRengoChallengesCount > 0 {
                    openChallengesSubheader = String(localized: "There are \(standardCount) open challenges that you can accept to start a game immediately, and \(eligibleRengoChallengesCount) open rengo game.")
                }
            } else {
                openChallengesSubheader = String(localized: "There are \(eligibleRengoChallengesCount) open rengo games.")
            }
        }
        
        return VStack(spacing: 0) {
            if ogs.waitingGames > 0 {
                Spacer().frame(height: 0.5)
                NavigationLink(destination: WaitingGamesView()) {
                    HStack {
                        (Text("Waiting for opponent: \(ogs.waitingGames) games ", comment: "NewGameView - vary for plural") + Text(Image(systemName: "chevron.forward")))
                            .font(.subheadline)
                            .bold()
                            .leadingAlignedInScrollView()
                            .foregroundColor(.white)
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemIndigo))
                .padding(.horizontal, -18)
            }
            if ogs.pendingRengoGames > 0 {
                Spacer().frame(height: 0.5)
                NavigationLink(destination: WaitingGamesView()) {
                    HStack {
                        (Text("\(ogs.pendingRengoGames) pending Rengo games ") + Text(Image(systemName: "chevron.forward")))
                            .font(.subheadline)
                            .bold()
                            .leadingAlignedInScrollView()
                            .foregroundColor(.white)
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemPurple))
                .padding(.horizontal, -18)
            }
            Spacer().frame(height: 10)
            Picker(selection: $newGameOption.animation(), label: Text("New game option")) {
                Text("Quick match", comment: "NewGameView top Picker").tag(NewGameOption.quickMatch)
                Text("Waiting (\(eligibleOpenChallengesCount))", comment: "NewGameView top Picker").tag(NewGameOption.openChallenges)
                Text("Custom", comment: "NewGameView top Picker").tag(NewGameOption.custom)
            }
            .pickerStyle(SegmentedPickerStyle())
            Spacer().frame(height: 10)
            switch newGameOption {
            case .quickMatch:
                Text("Select the board size(s) and time settings you want to play, and let the system match you with another similar ranked player.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            case .custom:
                Text("Create a game precisely as you want.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            case .openChallenges:
                Text(openChallengesSubheader)
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            }
            Spacer().frame(height: 10)
        }
        .padding(.horizontal)
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
                    OpenChallengesForm(eligibleOpenChallenges: self.eligibleOpenChallenges)
                }
            }
            newGameOptionsPicker.background(Color(.systemGray6).shadow(radius: 2))
        }
        .onAppear {
            ogs.subscribeToSeekGraph()
        }
        .onDisappear {
            ogs.unsubscribeFromSeekGraphWhenDone()
        }
        .onReceive(ogs.$eligibleOpenChallengeById) { eligibleOpenChallengesById in
            self.eligibleOpenChallenges = Array(
                eligibleOpenChallengesById.values.sorted(
                    by: { ($0.challenger?.username ?? "") < ($1.challenger?.username ?? "") }
                )
            )
        }
    }
}

struct NewGameView_Previews: PreviewProvider {
    static var previews: some View {
        return Group {
            NavigationView {
                NewGameView(newGameOption: .quickMatch)
                    .navigationBarTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .previewDisplayName("Quick match")
            NavigationView {
                NewGameView(newGameOption: .custom)
                    .navigationBarTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .previewDisplayName("Custom game")
            NavigationView {
                NewGameView(newGameOption: .openChallenges)
                    .navigationBarTitle("New game")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .previewDisplayName("Open challenges")
        }
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(
                    username: "HongAnhKhoa",
                    id: 314459,
                    ranking: 27,
                    icon: "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png"
                ), 
                eligibleOpenChallenges: [OGSChallengeSampleData.sampleOpenChallenge, OGSChallengeSampleData.sampleRengoChallenge],
                openChallengesSent: [OGSChallengeSampleData.sampleOpenChallenge],
                cachedUsers: [
                    OGSUser(
                        username: "hakhoa4", id: 1769,
                        iconUrl: "https://secure.gravatar.com/avatar/7eb7eabbe9bd03c2fc99881d04da9cbd?s=32&d=retro"
                    ),
                    OGSUser(
                        username: "honganhkhoa", id: 1526,
                        iconUrl: "https://secure.gravatar.com/avatar/4d95e45e08111986fd3fe61e1077b67d?s=32&d=retro"
                    )
                ]
            ))
    }
}
