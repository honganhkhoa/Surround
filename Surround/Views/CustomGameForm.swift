//
//  CustomGameForm.swift
//  Surround
//

import SwiftUI
import URLImage
import Combine

struct CustomGameForm: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @EnvironmentObject private var stackRouter: StackRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    enum Mode {
        case createChallenge
        case rematch
        case createPreferredSetting
        case editPreferredSetting(original: OGSChallengeTemplate)
    }
    
    static var defaultChallengeTemplate: OGSChallengeTemplate {
        ChallengeDraft.defaultChallengeTemplate
    }

    let mode: Mode
    private let onChallengeCreated: (() -> Void)?
    private let onChooseOpponent: (() -> Void)?
    @StateObject private var draft: ChallengeDraft

    init(
        initialChallenge: OGSChallengeTemplate? = nil,
        mode: Mode = .createChallenge,
        onChallengeCreated: (() -> Void)? = nil,
        draft: ChallengeDraft? = nil,
        onChooseOpponent: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onChallengeCreated = onChallengeCreated
        self.onChooseOpponent = onChooseOpponent
        _draft = StateObject(wrappedValue: draft ?? ChallengeDraft(initialChallenge: initialChallenge))
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
            draft.blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
            draft.liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
            draft.correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
        }
    }

    var rankRestrictionRange: ClosedRange<Int> {
        return 5...38
    }
    
    func updateForRankedGames() {
        draft.isPrivate = false
        draft.standardBoardSize = true
        draft.komi = draft.rulesSet.defaultKomi
        draft.handicap = min(draft.handicap, 9)
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
    
    var opponentRankOptions: some View {
        Group {
            Toggle(isOn: $draft.rankRestricted.animation()) {
                Text("Restrict opponent rank")
                    .font(.subheadline)
            }
            if draft.rankRestricted {
                Stepper(value: $draft.minRank, in: rankRestrictionRange) {
                    Text("From **\(RankUtils.formattedRank(Double(draft.minRank), longFormat: true))**", comment: "Custom game rank restriction")
                        .font(.subheadline)
                }
                Stepper(value: $draft.maxRank, in: rankRestrictionRange) {
                    Text("To **\(RankUtils.formattedRank(Double(draft.maxRank), longFormat: true))**", comment: "Custom game rank restriction")
                        .font(.subheadline)
                }
            }
        }
    }
    
    var opponentOptions: some View {
        GroupBox(label: Text("Opponent")) {
            if !isPreferredSettingMode {
                if !isRematchMode {
                    Picker(selection: $draft.isOpen.animation(), label: Text("Is open")) {
                        Text("Open", comment: "Opponent section of NewGameView, 'Open' here means anyone").tag(true)
                        Text("vs. Friend", comment: "Opponent section of NewGameView").tag(false)
                    }.pickerStyle(SegmentedPickerStyle())
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.customGameOpponentMode)
                }
                if draft.isOpen && !isRematchMode {
                    Text("Create and show a challenge publicly, then wait for other players to accept.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                    Divider()
                    opponentRankOptions
                } else {
                    Text("Send a challenge directly to a friend (or a specific player) so they can accept to start a game.")
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                    Spacer().frame(height: 10)
                    Divider()
                    if isRematchMode {
                        selectedOpponentRow
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID
                                    .gameRematchOpponent
                            )
                    } else if let onChooseOpponent {
                        Button(action: onChooseOpponent) {
                            selectedOpponentRow
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.customGameOpponent)
                    } else {
                        Button {
                            stackRouter.openOpponentPicker(for: draft)
                        } label: {
                            selectedOpponentRow
                        }
                        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.customGameOpponent)
                    }
                }
                Divider()
            } else {
                opponentRankOptions
            }
            Toggle(isOn: Binding ( get: { draft.handicap == -1 }, set: { draft.handicap = ($0 ? -1 : 0) })) {
                Text("Automatically decide handicap").font(.subheadline)
            }
            if draft.handicap > -1 {
                Stepper(value: $draft.handicap, in: 0...(draft.isRanked ? 9 : 36)) {
                    Text(handicapAttributedLabel(handicap: draft.handicap))
                }
            } else {
                (Text("**Automatic** setting will determine the number of handicap stones based on your and your opponent's rank."))
                    .font(.caption)
                    .leadingAlignedInScrollView()
            }
            Divider()
            Toggle(isOn: $draft.automaticColor) {
                Text("Automatically assign stone colors").font(.subheadline)
                    .leadingAlignedInScrollView()
            }
            if !draft.automaticColor {
                HStack {
                    Text("Your color").font(.subheadline)
                    Picker(selection: $draft.yourColor, label: Text("Your color")) {
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
        .onChange(of: draft.maxRank) { _, newValue in
            draft.minRank = min(draft.minRank, newValue)
        }
        .onChange(of: draft.minRank) { _, newValue in
            draft.maxRank = max(draft.maxRank, newValue)
        }
    }

    var selectedOpponentRow: some View {
        HStack {
            if let opponent = draft.opponent, let opponentIconURL = opponent.iconURL(ofSize: 64) {
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
            if let opponent = draft.opponent {
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
    
    var boardSizeOptions: some View {
        GroupBox(label: Text("Board size")) {
            Picker(selection: $draft.standardBoardSize.animation(), label: Text("Standard board size")) {
                Text("Standard size", comment: "refers to standard board sizes").tag(true)
                Text("Custom size", comment: "refers to custom board sizes").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .disabled(draft.isRanked)
            HStack(alignment: .top) {
                BoardView(boardPosition: BoardPosition(width: draft.boardWidth, height: draft.boardHeight))
                    .aspectRatio(1, contentMode: .fill)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Width").font(.subheadline).bold()
                    Stepper(
                        value: Binding(
                            get: { draft.standardBoardSize ? ([9, 13, 19].firstIndex(of: draft.boardWidth) ?? 2) : draft.boardWidth },
                            set: {
                                draft.boardWidth = (draft.standardBoardSize ? [9, 13, 19][$0] : $0)
                                if draft.standardBoardSize { draft.boardHeight = draft.boardWidth }
                            }
                        ),
                        in: draft.standardBoardSize ? 0...2 : 2...25, step: 1) {
                            Text(verbatim: "\(draft.boardWidth)")
                    }
                    Spacer().frame(height: 10)
                    Divider()
                    Spacer().frame(height: 10)
                    Text("Height").font(.subheadline).bold()
                    Stepper(
                        value: Binding(
                            get: { draft.standardBoardSize ? ([9, 13, 19].firstIndex(of: draft.boardHeight) ?? 2) : draft.boardHeight },
                            set: {
                                draft.boardHeight = (draft.standardBoardSize ? [9, 13, 19][$0] : $0)
                                if draft.standardBoardSize { draft.boardWidth = draft.boardHeight }
                            }
                        ),
                        in: draft.standardBoardSize ? 0...2 : 2...25, step: 1) {
                            Text(verbatim: "\(draft.boardHeight)")
                    }
                }
            }
            if draft.isRanked {
                (Text("**Custom** board sizes are not available in **ranked** games."))
                    .font(.caption)
                    .leadingAlignedInScrollView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: draft.standardBoardSize) { _, standard in
            if standard && (draft.boardWidth != draft.boardHeight || ![9, 13, 19].contains(draft.boardWidth)) {
                draft.boardWidth = 19
                draft.boardHeight = 19
            }
        }
    }
    
    var gameSpeedOptions: some View {
        GroupBox(label: Text("Game speed")) {
            Picker(selection: $draft.timeControlSpeed.animation(), label: Text("Game speed")) {
                Text("Live").tag(TimeControlSpeed.live)
                Text("Correspondence").tag(TimeControlSpeed.correspondence)
            }
            .pickerStyle(SegmentedPickerStyle())
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.customGameSpeed)
            if draft.timeControlSpeed == .live {
                Toggle(isOn: $draft.isBlitz) {
                    Text("Blitz").font(.subheadline)
                }
            } else if draft.timeControlSpeed == .correspondence {
                Toggle(isOn: $draft.pauseOnWeekend) {
                    Text("Pause on weekend").font(.subheadline)
                }
            }
            Divider()
            Text("**\(draft.finalTimeControl.systemName):** \(draft.finalTimeControl.system.descriptionText)")
                .font(.subheadline)
                .leadingAlignedInScrollView()
            Spacer().frame(height: 10)
            if draft.finalTimeControl.system != draft.finalTimeControlSpeed.defaultTimeOptions[0] {
                Button(action: revertToStandardTimeSetting) {
                    Text("Revert to standard time setting.")
                        .font(.subheadline).bold()
                        .leadingAlignedInScrollView()
                }
            }
            Spacer().frame(height: 10)
            NavigationLink(
                destination: TimeSystemPickerView(
                    blitzTimeControl: $draft.blitzTimeControl,
                    liveTimeControl: $draft.liveTimeControl,
                    correspondenceTimeControl: $draft.correspondenceTimeControl,
                    timeControlSpeed: $draft.timeControlSpeed,
                    isBlitz: $draft.isBlitz,
                    pauseOnWeekend: $draft.pauseOnWeekend)
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
                if draft.rulesSet == .japanese || draft.rulesSet == .chinese {
                    Picker(selection: $draft.rulesSet, label: Text("Rule set")) {
                        Text("Japanese").tag(OGSRule.japanese)
                        Text("Chinese").tag(OGSRule.chinese)
                    }.pickerStyle(SegmentedPickerStyle())
                } else {
                    NavigationLink(destination: RulesPickerView(rulesSet: $draft.rulesSet, komi: $draft.komi, isRanked: draft.isRanked)) {
                        HStack(spacing: 4) {
                            Text(verbatim: "\(draft.rulesSet.fullName) ").bold()
                            Image(systemName: "chevron.forward")
                        }
                        .font(.subheadline)
                    }
                }
                Spacer()
            }
            if draft.komi == draft.rulesSet.defaultKomi {
                Text("**Standard** komi: **\(draft.komi, specifier: "%.1f")**")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            } else {
                Text("**Custom** komi: **\(draft.komi, specifier: "%.1f")**")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
            }
            Spacer().frame(height: 10)
            NavigationLink(destination: RulesPickerView(rulesSet: $draft.rulesSet, komi: $draft.komi, isRanked: draft.isRanked)) {
                HStack(spacing: 4) {
                    Text("Advanced rules settings")
                    Image(systemName: "chevron.forward")
                }
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: draft.rulesSet) { _, newValue in
            draft.komi = newValue.defaultKomi
        }
    }
    
    var gameTypeOptions: some View {
        GroupBox(label: Text("Game type")) {
            Toggle(isOn: $draft.isRanked) {
                Text("Ranked").font(.subheadline)
            }
            Toggle(isOn: $draft.isPrivate) {
                Text("Private").font(.subheadline)
            }
            .disabled(draft.isRanked)
            (Text("Disable the **ranked** option above if you don't want the result to count towards your rating. **Ranked** games cannot be **private** and have fewer customizing options."))
                .font(.caption)
                .leadingAlignedInScrollView()
        }
        .onChange(of: draft.isRanked) { _, newValue in
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
                TextField(defaultGameName, text: $draft.gameName)
                    .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.customGameName)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit {
                        if draft.gameName.count == 0 {
                            draft.gameName = defaultGameName
                        }
                    }
            }
            Toggle(isOn: $draft.analysisDisabled) {
                Text("Disable analysis").font(.subheadline)
            }
            (Text("**Analysis mode** allows you and your opponent to test out variations during the game. It's like a separate virtual board where you can try things out."))
                .font(.caption)
                .leadingAlignedInScrollView()
        }
    }

    func updateTimeControl() {
        draft.challenge.game.timeControl = draft.finalTimeControl
        if draft.challenge.game.timeControl.speed == .correspondence {
            draft.challenge.game.timeControl.pauseOnWeekends = draft.pauseOnWeekend
        }
    }
    
    var createButtonDisabled: Bool {
        return !draft.isOpen && draft.opponent == nil
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
        switch mode {
        case .createChallenge, .rematch:
            true
        case .createPreferredSetting, .editPreferredSetting:
            false
        }
    }

    var isRematchMode: Bool {
        if case .rematch = mode {
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
                    MainActionButton(
                        label: isRematchMode
                            ? String(localized: "Send challenge")
                            : String(localized: "Create challenge"),
                        disabled: createButtonDisabled,
                        action: createChallenge
                    )
                }
                if !draft.isOpen && draft.opponent == nil {
                    Text("You need to choose an opponent or make the challenge open.")
                        .font(.caption)
                        .leadingAlignedInScrollView()
                }
            }
            Spacer().frame(height: 15)
        }
    }
    
    func createChallenge() {
        if draft.isOpen || draft.opponent != nil {
            self.challengeCreatingCancellable = ogs.sendChallenge(opponent: draft.isOpen ? nil : draft.opponent, challenge: draft.challenge).sink(
                receiveCompletion: { _ in
                    self.challengeCreatingCancellable = nil
                }, receiveValue: { _ in
                    if let onChallengeCreated {
                        onChallengeCreated()
                    } else if isRematchMode {
                        dismiss()
                    } else {
                        nav.home.showingNewGameView = false
                    }
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
            newChallenge: draft.challenge
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
        
        self.createPreferredSettingCancellable = ogs.addPreferredGameSetting(challenge: draft.challenge).sink(
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
        ChallengeCell(challenge: draft.challenge, hidePlayerDetails: isPreferredSettingMode)
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
            .scrollDismissesKeyboard(.interactively)
        }
        .modifier(ChangeHandlersBase(
            challenge: $draft.challenge,
            gameName: $draft.gameName,
            isRanked: $draft.isRanked,
            isPrivate: $draft.isPrivate,
            rankRestricted: $draft.rankRestricted,
            isOpen: $draft.isOpen,
            maxRank: $draft.maxRank,
            minRank: $draft.minRank,
            handicap: $draft.handicap,
            automaticColor: $draft.automaticColor,
            yourColor: $draft.yourColor,
            boardWidth: $draft.boardWidth,
            boardHeight: $draft.boardHeight,
            opponent: $draft.opponent
        ))
        .modifier(ChangeHandlersTime(
            challenge: $draft.challenge,
            timeControlSpeed: $draft.timeControlSpeed,
            isBlitz: $draft.isBlitz,
            liveTimeControl: $draft.liveTimeControl,
            blitzTimeControl: $draft.blitzTimeControl,
            correspondenceTimeControl: $draft.correspondenceTimeControl,
            pauseOnWeekend: $draft.pauseOnWeekend,
            updateTimeControl: updateTimeControl
        ))
        .modifier(ChangeHandlersRules(
            challenge: $draft.challenge,
            rulesSet: $draft.rulesSet,
            komi: $draft.komi,
            analysisDisabled: $draft.analysisDisabled
        ))
        .onAppear {
            if !isPreferredSettingMode {
                draft.challenge.challenger = ogs.user
                if draft.isRanked {
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
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.screenCustomGame
        )
    }
}

#if DEBUG
private func customGameFormPreview(
    initialChallenge: OGSChallengeTemplate? = nil,
    mode: CustomGameForm.Mode = .createChallenge,
    title: LocalizedStringKey
) -> some View {
    AppNavigationStack {
        CustomGameForm(
            initialChallenge: initialChallenge,
            mode: mode
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(
                username: "HongAnhKhoa",
                id: 314459,
                ranking: 27
            ),
            friends: [
                OGSUser(username: "kata-bot", id: 592684, ranking: 36),
            ]
        )
    )
    .environmentObject(NavigationService())
}

#Preview("Custom game — Create challenge") {
    customGameFormPreview(title: "Custom game")
}

#Preview("Custom game — Edit preferred setting") {
    let setting = OGSChallengeSampleData.sampleChallengeTemplate
    return customGameFormPreview(
        initialChallenge: setting,
        mode: .editPreferredSetting(original: setting),
        title: "Edit preferred setting"
    )
}
#endif
