//
//  CustomGameForm.swift
//  Surround
//

import SwiftUI
import URLImage
import Combine

let defaultGameName = String(localized: "Friendly Match", comment: "Default game name")

struct CustomGameForm: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    enum Mode {
        case createChallenge
        case createPreferredSetting
        case editPreferredSetting(original: OGSChallengeTemplate)
    }
    
    static var defaultChallengeTemplate: OGSChallengeTemplate {
        OGSChallengeTemplate(
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
    }
    
    let mode: Mode
    
    @State var challenge: OGSChallengeTemplate
    
    @State var gameName: String
    
    @State var isPrivate: Bool
    @State var isRanked: Bool
    
    @State var boardWidth: Int
    @State var boardHeight: Int
    @State var standardBoardSize: Bool
    
    @State var timeControlSpeed: TimeControlSpeed
    @State var isBlitz: Bool
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

    @State var blitzTimeControl: TimeControl
    @State var liveTimeControl: TimeControl
    @State var correspondenceTimeControl: TimeControl
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
    
    @State var pauseOnWeekend: Bool
    
    @State var isOpen: Bool
    @State var rankRestricted: Bool
    @State var maxRank: Int
    @State var minRank: Int
    
    @State var opponent: OGSUser?
    @State var selectingOpponent: Bool
    
    @State var handicap: Int
    @State var automaticColor: Bool
    @State var yourColor: StoneColor
    
    @State var rulesSet: OGSRule
    @State var komi: Double
    
    @State var analysisDisabled: Bool
    
    init(initialChallenge: OGSChallengeTemplate? = nil, mode: Mode = .createChallenge) {
        self.mode = mode
        
        let baseChallenge = initialChallenge ?? Self.defaultChallengeTemplate
        let ruleSet = baseChallenge.game.rules
        let gameName = baseChallenge.game.name.isEmpty ? defaultGameName : baseChallenge.game.name
        
        let boardWidth = baseChallenge.game.width
        let boardHeight = baseChallenge.game.height
        let standardBoardSize = boardWidth == boardHeight && [9, 13, 19].contains(boardWidth)
        
        let timeControl = baseChallenge.game.timeControl
        let speed = timeControl.speed
        let timeControlSpeed: TimeControlSpeed = speed == .correspondence ? .correspondence : .live
        let isBlitz = speed == .blitz
        var blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
        var liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
        var correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
        switch speed {
        case .blitz:
            blitzTimeControl = timeControl
        case .live:
            liveTimeControl = timeControl
        case .correspondence:
            correspondenceTimeControl = timeControl
        default:
            liveTimeControl = timeControl
        }
        
        let isOpen = baseChallenge.challenged == nil
        let restrictedMin = baseChallenge.game.minRank ?? -1000
        let restrictedMax = baseChallenge.game.maxRank ?? 1000
        let rankRestricted = isOpen && (restrictedMin != -1000 || restrictedMax != 1000)
        let minRank = rankRestricted ? min(max(restrictedMin, 5), 38) : 5
        let maxRank = rankRestricted ? min(max(restrictedMax, 5), 38) : 36
        
        let automaticColor = baseChallenge.challengerColor == nil
        let yourColor = baseChallenge.challengerColor ?? .black
        
        _challenge = State(initialValue: baseChallenge)
        _gameName = State(initialValue: gameName)
        _isPrivate = State(initialValue: baseChallenge.game.isPrivate)
        _isRanked = State(initialValue: baseChallenge.game.ranked)
        _boardWidth = State(initialValue: boardWidth)
        _boardHeight = State(initialValue: boardHeight)
        _standardBoardSize = State(initialValue: standardBoardSize)
        _timeControlSpeed = State(initialValue: timeControlSpeed)
        _isBlitz = State(initialValue: isBlitz)
        _blitzTimeControl = State(initialValue: blitzTimeControl)
        _liveTimeControl = State(initialValue: liveTimeControl)
        _correspondenceTimeControl = State(initialValue: correspondenceTimeControl)
        _pauseOnWeekend = State(initialValue: timeControl.pauseOnWeekends ?? true)
        _isOpen = State(initialValue: isOpen)
        _rankRestricted = State(initialValue: rankRestricted)
        _maxRank = State(initialValue: maxRank)
        _minRank = State(initialValue: minRank)
        _opponent = State(initialValue: baseChallenge.challenged)
        _selectingOpponent = State(initialValue: false)
        _handicap = State(initialValue: baseChallenge.game.handicap)
        _automaticColor = State(initialValue: automaticColor)
        _yourColor = State(initialValue: yourColor)
        _rulesSet = State(initialValue: ruleSet)
        _komi = State(initialValue: baseChallenge.game.komi ?? ruleSet.defaultKomi)
        _analysisDisabled = State(initialValue: baseChallenge.game.disableAnalysis)
    }

    private struct ChangeHandlersBase: ViewModifier {
        @Binding var challenge: OGSChallengeTemplate
        @Binding var gameName: String
        @Binding var isRanked: Bool
        @Binding var isPrivate: Bool
        @Binding var rankRestricted: Bool
        @Binding var isOpen: Bool
        @Binding var maxRank: Int
        @Binding var minRank: Int
        @Binding var handicap: Int
        @Binding var automaticColor: Bool
        @Binding var yourColor: StoneColor
        @Binding var boardWidth: Int
        @Binding var boardHeight: Int
        @Binding var opponent: OGSUser?

        func body(content: Content) -> some View {
            content
                .onChange(of: gameName) { _, newValue in challenge.game.name = newValue }
                .onChange(of: isRanked) { _, newValue in challenge.game.ranked = newValue }
                .onChange(of: isPrivate) { _, newValue in challenge.game.isPrivate = newValue }
                .onChange(of: rankRestricted) { _, newValue in
                    challenge.game.maxRank = newValue && isOpen ? maxRank : 1000
                    challenge.game.minRank = newValue && isOpen ? minRank : -1000
                }
                .onChange(of: isOpen) { _, newValue in
                    challenge.game.maxRank = newValue && rankRestricted ? maxRank : 1000
                    challenge.game.minRank = newValue && rankRestricted ? minRank : -1000
                    if newValue {
                        challenge.challenged = nil
                    } else {
                        challenge.challenged = opponent
                    }
                }
                .onChange(of: maxRank) { _, newValue in challenge.game.maxRank = newValue }
                .onChange(of: minRank) { _, newValue in challenge.game.minRank = newValue }
                .onChange(of: handicap) { _, newValue in challenge.game.handicap = newValue }
                .onChange(of: automaticColor) { _, newValue in
                    challenge.challengerColor = newValue ? nil : yourColor
                }
                .onChange(of: yourColor) { _, newValue in
                    challenge.challengerColor = newValue
                }
                .onChange(of: boardWidth) { _, newValue in challenge.game.width = newValue }
                .onChange(of: boardHeight) { _, newValue in challenge.game.height = newValue }
                .onChange(of: opponent) { _, newValue in challenge.challenged = newValue }
        }
    }

    private struct ChangeHandlersTime: ViewModifier {
        @Binding var challenge: OGSChallengeTemplate
        @Binding var timeControlSpeed: TimeControlSpeed
        @Binding var isBlitz: Bool
        @Binding var liveTimeControl: TimeControl
        @Binding var blitzTimeControl: TimeControl
        @Binding var correspondenceTimeControl: TimeControl
        @Binding var pauseOnWeekend: Bool
        let updateTimeControl: () -> Void

        func body(content: Content) -> some View {
            content
                .onChange(of: timeControlSpeed) { updateTimeControl() }
                .onChange(of: isBlitz) { updateTimeControl() }
                .onChange(of: liveTimeControl) { updateTimeControl() }
                .onChange(of: blitzTimeControl) { updateTimeControl() }
                .onChange(of: correspondenceTimeControl) { updateTimeControl() }
                .onChange(of: pauseOnWeekend) { _, newValue in challenge.game.timeControl.pauseOnWeekends = newValue }
        }
    }

    private struct ChangeHandlersRules: ViewModifier {
        @Binding var challenge: OGSChallengeTemplate
        @Binding var rulesSet: OGSRule
        @Binding var komi: Double
        @Binding var analysisDisabled: Bool

        func body(content: Content) -> some View {
            content
                .onChange(of: rulesSet) { _, newValue in challenge.game.rules = newValue }
                .onChange(of: komi) { _, newValue in challenge.game.komi = newValue }
                .onChange(of: analysisDisabled) { _, newValue in challenge.game.disableAnalysis = newValue }
        }
    }
    
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

    private func handicapAttributedLabel(handicap: Int) -> AttributedString {
        var label = AttributedString(String(localized: "Handicap: "))
        label.font = .subheadline.bold()
        let value = handicap == -1
            ? String(localized: "Automatic", comment: "NewGameView handicap selection, automatic handicap")
            : handicap == 0
            ? String(localized: "No handicap", comment: "NewGameView handicap seletion, no handicap")
            : String(localized: "\(handicap) Stones", comment: "NewGameView handicap selection - vary for plural")
        var valueAttributedString = AttributedString(value)
        valueAttributedString.font = .subheadline
        label.append(valueAttributedString)
        return label
    }
    
    var opponentOptions: some View {
        GroupBox(label: Text("Opponent")) {
            if !isPreferredSettingMode {
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
                                HStack(spacing: 4) {
                                    Text("Select your opponent ")
                                    Image(systemName: "chevron.forward")
                                }
                                .font(.subheadline)
                                .bold()
                            }
                            Spacer()
                        }
                    }
                }
                Divider()
            }
            Toggle(isOn: Binding ( get: { handicap == -1 }, set: { handicap = ($0 ? -1 : 0) })) {
                Text("Automatically decide handicap").font(.subheadline)
            }
            if handicap > -1 {
                Stepper(value: $handicap, in: 0...(isRanked ? 9 : 36)) {
                    Text(handicapAttributedLabel(handicap: handicap))
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
        .onChange(of: maxRank) { _, newValue in
            minRank = min(minRank, newValue)
        }
        .onChange(of: minRank) { _, newValue in
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
        .onChange(of: standardBoardSize) { _, standard in
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
            Text("**\(finalTimeControl.systemName):** \(finalTimeControl.system.descriptionText)")
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
                HStack(spacing: 4) {
                    Text("Advanced time settings")
                    Image(systemName: "chevron.forward")
                }
                .font(.subheadline).bold()
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
                        HStack(spacing: 4) {
                            Text(verbatim: "\(rulesSet.fullName) ").bold()
                            Image(systemName: "chevron.forward")
                        }
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
                HStack(spacing: 4) {
                    Text("Advanced rules settings")
                    Image(systemName: "chevron.forward")
                }
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: rulesSet) { _, newValue in
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
        .onChange(of: isRanked) { _, newValue in
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
    
    var isEditingPreferredSetting: Bool {
        if case .editPreferredSetting = mode {
            return true
        }
        return false
    }
    
    var isCreatingPreferredSetting: Bool {
        if case .createPreferredSetting = mode {
            return true
        }
        return false
    }
    
    var isPreferredSettingMode: Bool {
        isEditingPreferredSetting || isCreatingPreferredSetting
    }
    
    var isChallengeCreationMode: Bool {
        if case .createChallenge = mode {
            return true
        }
        return false
    }
    
    var originalPreferredSetting: OGSChallengeTemplate? {
        if case .editPreferredSetting(let original) = mode {
            return original
        }
        return nil
    }
    
    @State var challengeCreatingCancellable: AnyCancellable?
    @State var createPreferredSettingCancellable: AnyCancellable?
    @State var editPreferredSettingCancellable: AnyCancellable?
    
    var actionButton: some View {
        VStack(alignment: .leading) {
            if self.challengeCreatingCancellable != nil {
                Spacer().frame(height: 15)
                ProgressView()
            } else {
                if isChallengeCreationMode {
                    MainActionButton(label: String(localized: "Create challenge"), disabled: createButtonDisabled, action: createChallenge)
                }
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
    
    func saveEditedPreferredSetting() {
        guard self.editPreferredSettingCancellable == nil else {
            return
        }
        guard let originalPreferredSetting else {
            return
        }
        
        self.editPreferredSettingCancellable = ogs.replacePreferredGameSetting(
            oldChallenge: originalPreferredSetting,
            newChallenge: challenge
        ).sink(
            receiveCompletion: { _ in
                self.editPreferredSettingCancellable = nil
            },
            receiveValue: { _ in
                dismiss()
            }
        )
    }
    
    func createPreferredSetting() {
        guard self.createPreferredSettingCancellable == nil else {
            return
        }
        
        self.createPreferredSettingCancellable = ogs.addPreferredGameSetting(challenge: challenge).sink(
            receiveCompletion: { _ in
                self.createPreferredSettingCancellable = nil
            },
            receiveValue: { _ in
                dismiss()
            }
        )
    }
    
    @ViewBuilder
    var previewSection: some View {
        ChallengeCell(challenge: challenge, hidePlayerDetails: isPreferredSettingMode)
            .padding()
            .background(
                Color(
                    colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
                )
                .cornerRadius(8)
                .shadow(radius: 2)
            )
    }

    @ViewBuilder
    var scrollContent: some View {
        VStack(alignment: .leading) {
            gameTypeOptions
            opponentOptions
            boardSizeOptions
            gameSpeedOptions
            rulesOptions
            otherOptions
            actionButton
            if !isPreferredSettingMode {
                previewSection
            }
            // Workaround for an issue on iOS 14.5 where the NavigationLink pops out by itself.
            // https://developer.apple.com/forums/thread/677333#672042022
            NavigationLink(destination: EmptyView()) {
                EmptyView()
            }
        }
        .padding()
    }

    var body: some View {
        VStack(spacing: 0) {
            if isPreferredSettingMode {
                previewSection
                    .padding()
                    .background(Color(.systemGray6).shadow(radius: 2))
            }
            ScrollView {
                scrollContent
            }
            .apply {
                if #available(iOS 16.0, *) {
                    $0.scrollDismissesKeyboard(.interactively)
                } else {
                    $0
                }
            }
        }
        .modifier(ChangeHandlersBase(
            challenge: $challenge,
            gameName: $gameName,
            isRanked: $isRanked,
            isPrivate: $isPrivate,
            rankRestricted: $rankRestricted,
            isOpen: $isOpen,
            maxRank: $maxRank,
            minRank: $minRank,
            handicap: $handicap,
            automaticColor: $automaticColor,
            yourColor: $yourColor,
            boardWidth: $boardWidth,
            boardHeight: $boardHeight,
            opponent: $opponent
        ))
        .modifier(ChangeHandlersTime(
            challenge: $challenge,
            timeControlSpeed: $timeControlSpeed,
            isBlitz: $isBlitz,
            liveTimeControl: $liveTimeControl,
            blitzTimeControl: $blitzTimeControl,
            correspondenceTimeControl: $correspondenceTimeControl,
            pauseOnWeekend: $pauseOnWeekend,
            updateTimeControl: updateTimeControl
        ))
        .modifier(ChangeHandlersRules(
            challenge: $challenge,
            rulesSet: $rulesSet,
            komi: $komi,
            analysisDisabled: $analysisDisabled
        ))
        .onAppear {
            if !isPreferredSettingMode {
                challenge.challenger = ogs.user
                if isRanked {
                    updateForRankedGames()
                }
            }
        }
        .toolbar {
            if isPreferredSettingMode {
                ToolbarItem(placement: .confirmationAction) {
                    if self.editPreferredSettingCancellable != nil || self.createPreferredSettingCancellable != nil {
                        ProgressView()
                    } else {
                        Button("Save", action: isEditingPreferredSetting ? saveEditedPreferredSetting : createPreferredSetting)
                            .disabled(createButtonDisabled)
                    }
                }
            }
        }
    }
}
