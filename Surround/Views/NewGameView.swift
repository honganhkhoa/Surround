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
                        HStack(spacing: 4) {
                            Text("Waiting for opponent: \(ogs.waitingGames) games ", comment: "NewGameView - vary for plural")
                            Image(systemName: "chevron.forward")
                        }
                        .font(.subheadline)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(Color.white)
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.white))
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
                        HStack(spacing: 4) {
                            Text("\(ogs.pendingRengoGames) pending Rengo games ")
                            Image(systemName: "chevron.forward")
                        }
                        .font(.subheadline)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(Color.white)
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.white))
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
