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
    @State var challengeType: ChallengeType =
        SurroundUITestContract.compatibilityScene == .rengoOpenChallenges
            ? .rengo
            : .standard
    
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
        .accessibilityIdentifier(
            SurroundUITestContract.AccessibilityID.screenOpenChallenges
        )
    }
}

struct NewGameView: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @Environment(\.surroundAllowsLocalPersistence) private var allowsLocalPersistence
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @State var newGameOption: NewGameOption = .quickMatch
    @State var eligibleOpenChallenges = [OGSSeekgraphChallenge]()
    @State private var quickMatchDraft = OGSQuickMatchDraft.ogsDefault
    @State private var realtimeClockPreference = OGSQuickMatchClockPreference.flexible
    @State private var realtimeClocks = Set(
        OGSQuickMatchDraft.ogsDefault.quickMatchSelectedClocks
    )
    @State private var lastPersistedQuickMatchDraft: OGSQuickMatchDraft?
    @State private var hasLoadedQuickMatchDraft = false
    @State private var optimisticLiveEntry: OGSAutomatchEntry?
    @State private var optimisticCorrespondenceEntries =
        [String: OGSAutomatchEntry]()
    @State private var cancellingEntryID: String?
    @State private var quickMatchRequestFailure: QuickMatchRequestFailure?
    @State private var failedQuickMatchStartEntries = [OGSAutomatchEntry]()
    @State private var quickMatchServerNotice: String?
    @State private var correspondenceGameCount = 1
    @State private var quickMatchSubmission = QuickMatchSubmissionState()
    @State private var unconfirmedSearchIDs = Set<String>()
    @State private var reconciliationNoticeGeneration = UUID()

    enum NewGameOption {
        case quickMatch
        case custom
        case openChallenges
    }

    private var serverLiveEntry: OGSAutomatchEntry? {
        ogs.activeLiveAutomatchEntry
    }

    private var activeLiveEntry: OGSAutomatchEntry? {
        serverLiveEntry ?? optimisticLiveEntry
    }

    private var quickMatchIsConnected: Bool {
        !allowsRemoteActivity
            || (ogs.socketStatus == .connected && ogs.isWebsocketAuthenticated)
    }

    private var isSubmittingQuickMatch: Bool {
        quickMatchSubmission.isSubmitting
    }

    private var displayedWaitingGames: Int {
        var pendingIDs = Set<String>()
        if let optimisticLiveEntry,
           ogs.autoMatchEntryById[optimisticLiveEntry.uuid] == nil {
            pendingIDs.insert(optimisticLiveEntry.uuid)
        }
        for uuid in optimisticCorrespondenceEntries.keys
        where ogs.autoMatchEntryById[uuid] == nil {
            pendingIDs.insert(uuid)
        }
        return ogs.waitingGames + pendingIDs.count
    }

    private var activeCorrespondenceSearchCount: Int {
        Set(
            ogs.autoMatchEntryById.values
                .filter(\.isCorrespondence)
                .map(\.uuid)
        )
        .union(optimisticCorrespondenceEntries.keys)
        .count
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
            if displayedWaitingGames > 0 {
                Spacer().frame(height: 0.5)
                NavigationLink(destination: WaitingGamesView()) {
                    HStack(spacing: 4) {
                        Text(
                            displayedWaitingGames == 1
                                ? String(localized: "Searching for a game")
                                : String(localized: "Searching for \(displayedWaitingGames) games")
                        )
                        Image(systemName: "chevron.forward")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                }
                .background(Color(.systemIndigo))
                .padding(.horizontal, -18)
                .accessibilityHint("Show active searches")
                .accessibilityIdentifier(
                    SurroundUITestContract.AccessibilityID.quickMatchWaitingBanner
                )
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
                Text("Open (\(eligibleOpenChallengesCount))", comment: "NewGameView top Picker: open games offered by other players").tag(NewGameOption.openChallenges)
                Text("Custom", comment: "NewGameView top Picker").tag(NewGameOption.custom)
            }
            .pickerStyle(SegmentedPickerStyle())
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.newGameOptionPicker
            )
            switch newGameOption {
            case .quickMatch:
                Spacer().frame(height: 10)
            case .custom:
                Spacer().frame(height: 10)
                Text("Create a game precisely as you want.")
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
                Spacer().frame(height: 10)
            case .openChallenges:
                Spacer().frame(height: 10)
                Text(openChallengesSubheader)
                    .font(.subheadline)
                    .leadingAlignedInScrollView()
                Spacer().frame(height: 10)
            }
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            newGameOptionsPicker
                .background(Color(.systemGray6).shadow(radius: 2))

            if newGameOption == .quickMatch {
                QuickMatchForm(
                    draft: $quickMatchDraft,
                    realtimeClockPreference: $realtimeClockPreference,
                    realtimeClocks: $realtimeClocks,
                    correspondenceGameCount: $correspondenceGameCount,
                    activeCorrespondenceSearchCount: activeCorrespondenceSearchCount,
                    isSubmitting: isSubmittingQuickMatch,
                    eligibleOpenChallenges: eligibleOpenChallenges,
                    allowsRemoteActivity: allowsRemoteActivity,
                    activeLiveEntry: activeLiveEntry,
                    cancellingEntryID: cancellingEntryID,
                    isConnected: quickMatchIsConnected,
                    isRestoringSearches: allowsRemoteActivity
                        && ogs.isReconcilingAutomatches,
                    serverNotice: quickMatchServerNotice,
                    onFind: submitQuickMatch,
                    onCancel: cancelQuickMatch,
                    onShowOpenChallenges: {
                        newGameOption = .openChallenges
                    }
                )
            } else if newGameOption == .custom {
                CustomGameForm()
            } else if newGameOption == .openChallenges {
                OpenChallengesForm(
                    eligibleOpenChallenges: eligibleOpenChallenges
                )
            }

            #if DEBUG && MAIN_APP
            if SurroundUITestContract.isEnabled {
                Text(verbatim: "New game")
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.screenNewGame
                    )
            }
            #endif
        }
        .onAppear {
            loadQuickMatchDraftIfNecessary()
            if allowsRemoteActivity {
                ogs.subscribeToSeekGraph()
            }
        }
        .onDisappear {
            guard allowsRemoteActivity else { return }
            ogs.unsubscribeFromSeekGraphWhenDone()
        }
        .onReceive(ogs.$eligibleOpenChallengeById) { eligibleOpenChallengesById in
            self.eligibleOpenChallenges = Array(
                eligibleOpenChallengesById.values.sorted(
                    by: { ($0.challenger?.username ?? "") < ($1.challenger?.username ?? "") }
                )
            )
        }
        .onChange(of: quickMatchDraft) { _, draft in
            persistQuickMatchDraftIfNecessary(draft)
        }
        .onChange(of: ogs.user?.id) { _, _ in
            // An identity change clears the service's searches without
            // individual lifecycle events for the previous account.
            quickMatchSubmission = QuickMatchSubmissionState()
        }
        .onReceive(ogs.automatchLifecycleEvents) { event in
            handleAutomatchLifecycleEvent(event)
        }
        .alert(item: $quickMatchRequestFailure) { failure in
            switch failure.operation {
            case .start:
                return Alert(
                    title: Text("Couldn’t start the search"),
                    message: Text(quickMatchStartFailureMessage),
                    primaryButton: .default(
                        Text(failedQuickMatchStartEntries.count > 1
                            ? String(localized: "Retry failed searches")
                            : String(localized: "Retry"))
                    ) {
                        retryQuickMatchStart(failure.entry)
                    },
                    secondaryButton: .cancel(Text("Close")) {
                        failedQuickMatchStartEntries.removeAll()
                    }
                )
            case .cancel, .cancelTimedOut:
                return Alert(
                    title: Text("Couldn’t cancel the search"),
                    message: Text("OGS did not confirm the cancellation. The search is still shown so you can try again."),
                    primaryButton: .default(Text("Retry")) {
                        retryCancellation(failure)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func loadQuickMatchDraftIfNecessary() {
        guard !hasLoadedQuickMatchDraft else { return }
        let draft = allowsLocalPersistence
            ? ogs.preferences.loadQuickMatchDraft()
            : OGSQuickMatchDraft.ogsDefault
        quickMatchDraft = draft
        lastPersistedQuickMatchDraft = draft
        hasLoadedQuickMatchDraft = true
    }

    private func persistQuickMatchDraftIfNecessary(
        _ draft: OGSQuickMatchDraft
    ) {
        guard hasLoadedQuickMatchDraft,
              allowsLocalPersistence,
              lastPersistedQuickMatchDraft != draft else {
            return
        }
        ogs.preferences[.lastQuickMatchDraft] = draft
        lastPersistedQuickMatchDraft = draft
    }

    private func submitQuickMatch() {
        guard quickMatchDraft.quickMatchIsValid else { return }
        let count = quickMatchDraft.quickMatchIsCorrespondenceOnly
            ? min(max(correspondenceGameCount, 1), 10)
            : 1
        submitQuickMatches(
            entries: (0..<count).map { _ in quickMatchDraft.makeAutomatchEntry() }
        )
    }

    private func submitQuickMatches(
        entries: [OGSAutomatchEntry],
        retryingFailedEntries: Bool = false
    ) {
        guard !entries.isEmpty else { return }
        if entries.contains(where: { !$0.isCorrespondence }),
           ogs.isReconcilingAutomatches || activeLiveEntry != nil {
            return
        }

        // Register the whole batch before the first send: one fast echo must
        // not release Find while another member is still being submitted.
        guard quickMatchSubmission.begin(
            entryIDs: entries.map(\.uuid),
            retryingFailedEntries: retryingFailedEntries
        ) else { return }

        var submittedEntries = [OGSAutomatchEntry]()
        var failedEntries = [OGSAutomatchEntry]()
        for entry in entries {
            if allowsRemoteActivity && !ogs.findAutomatch(entry: entry) {
                quickMatchSubmission.finish(uuid: entry.uuid)
                failedEntries.append(entry)
                continue
            }

            if entry.isCorrespondence {
                optimisticCorrespondenceEntries[entry.uuid] = entry
            } else {
                optimisticLiveEntry = entry
            }
            submittedEntries.append(entry)
            if !allowsRemoteActivity && !SurroundUITestContract.holdsQuickMatchAcknowledgements {
                // Offline previews have no server acknowledgement to await.
                quickMatchSubmission.finish(uuid: entry.uuid)
            }
        }

        if allowsLocalPersistence, let lastEntry = submittedEntries.last {
            ogs.preferences[.lastQuickMatchDraft] = quickMatchDraft
            ogs.preferences[.lastAutomatchEntry] = lastEntry
            lastPersistedQuickMatchDraft = quickMatchDraft
        }

        failedQuickMatchStartEntries = failedEntries
        if let firstFailure = failedEntries.first {
            quickMatchRequestFailure = QuickMatchRequestFailure(
                operation: .start,
                entry: firstFailure
            )
        }

        guard !submittedEntries.isEmpty else { return }
        quickMatchServerNotice = nil
        unconfirmedSearchIDs.removeAll()
        reconciliationNoticeGeneration = UUID()
        let announcement: String
        if submittedEntries.allSatisfy(\.isCorrespondence) {
            announcement = submittedEntries.count == 1
                ? String(
                    localized: "Searching for a correspondence game",
                    comment: "Accessibility announcement after starting a correspondence Quick Match search"
                )
                : String(
                    localized: "Searching for \(submittedEntries.count) correspondence games",
                    comment: "Accessibility announcement after starting multiple correspondence Quick Match searches"
                )
        } else {
            announcement = String(localized: "Searching for a game")
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func retryQuickMatchStart(_ entry: OGSAutomatchEntry) {
        // Keep every failed UUID, but never retry batch members OGS already
        // accepted. A partial retry replaces this list with its remaining
        // failures, so repeated retries cannot duplicate successful searches.
        let entries = failedQuickMatchStartEntries.isEmpty
            ? [entry]
            : failedQuickMatchStartEntries
        failedQuickMatchStartEntries.removeAll()
        quickMatchRequestFailure = nil
        DispatchQueue.main.async {
            // These UUIDs were never sent. They may be retried while other
            // members of the original batch are awaiting acknowledgement.
            submitQuickMatches(entries: entries, retryingFailedEntries: true)
        }
    }

    private var quickMatchStartFailureMessage: String {
        let failedCount = failedQuickMatchStartEntries.count
        guard failedCount > 1 else {
            return String(localized: "The request could not be sent to OGS. Check your connection and try again.")
        }
        return String(
            localized: "\(failedCount) search requests could not be sent to OGS. Check your connection and try again. Searches that already started will continue."
        )
    }

    private func cancelQuickMatch(_ entry: OGSAutomatchEntry) {
        guard cancellingEntryID == nil else { return }
        if allowsRemoteActivity && !ogs.cancelAutomatch(entry: entry) {
            quickMatchRequestFailure = QuickMatchRequestFailure(
                operation: .cancel,
                entry: entry
            )
            return
        }

        cancellingEntryID = entry.uuid
        if !allowsRemoteActivity {
            finishCancellation(uuid: entry.uuid)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard cancellingEntryID == entry.uuid else { return }
            cancellingEntryID = nil
            quickMatchRequestFailure = QuickMatchRequestFailure(
                operation: .cancelTimedOut,
                entry: entry
            )
        }
    }

    private func finishCancellation(uuid: String) {
        if optimisticLiveEntry?.uuid == uuid {
            optimisticLiveEntry = nil
        }
        optimisticCorrespondenceEntries.removeValue(forKey: uuid)
        if cancellingEntryID == uuid {
            cancellingEntryID = nil
        }
        quickMatchRequestFailure = quickMatchRequestFailure?
            .retainedAfterCancellationTerminal(uuid: uuid)
    }

    private func retryCancellation(_ failure: QuickMatchRequestFailure) {
        var activeEntryIDs = Set(ogs.autoMatchEntryById.keys)
        if let optimisticLiveEntry {
            activeEntryIDs.insert(optimisticLiveEntry.uuid)
        }
        activeEntryIDs.formUnion(optimisticCorrespondenceEntries.keys)
        guard failure.canRetryCancellation(
            activeEntryIDs: activeEntryIDs
        ) else {
            quickMatchRequestFailure = nil
            return
        }
        cancelQuickMatch(failure.entry)
    }

    private func handleAutomatchLifecycleEvent(
        _ event: OGSAutomatchLifecycleEvent
    ) {
        quickMatchSubmission.handle(event.kind)
        switch event.kind {
        case .entry:
            // Keep the local copy until a terminal event so the searching UI
            // cannot briefly unlock while reconnecting and replaying the list.
            break
        case .started(let uuid, _, _):
            finishCancellation(uuid: uuid)
        case .cancelled(let uuid, let removedCount):
            if let uuid {
                finishCancellation(uuid: uuid)
                AccessibilityNotification.Announcement(
                    String(
                        localized: "Search cancelled",
                        comment: "Accessibility announcement after cancelling a Quick Match search"
                    )
                ).post()
            } else {
                optimisticLiveEntry = nil
                optimisticCorrespondenceEntries.removeAll()
                cancellingEntryID = nil
                quickMatchRequestFailure = quickMatchRequestFailure?
                    .retainedAfterCancellationTerminal(uuid: nil)
                let notice = removedCount == 1
                    ? String(localized: "Your search ended before a game was found. Your settings are unchanged, so you can search again.")
                    : String(localized: "Your active searches ended before games were found. Your settings are unchanged, so you can search again.")
                quickMatchServerNotice = notice
                AccessibilityNotification.Announcement(notice).post()
            }
        case .notFoundAfterReconciliation(let uuid):
            finishCancellation(uuid: uuid)
            unconfirmedSearchIDs.insert(uuid)
            let generation = UUID()
            reconciliationNoticeGeneration = generation
            // A list replay can retire several batch members together. Show
            // one total instead of overwriting a singular notice for each UUID.
            DispatchQueue.main.async {
                guard reconciliationNoticeGeneration == generation else { return }
                let count = unconfirmedSearchIDs.count
                let notice = count == 1
                    ? String(localized: "OGS did not confirm this search. Your settings are unchanged, so you can search again.")
                    : String(localized: "OGS did not confirm \(count) searches. Your settings are unchanged, so you can search again.")
                quickMatchServerNotice = notice
                AccessibilityNotification.Announcement(notice).post()
            }
        }
    }
}

#if DEBUG
private func newGamePreview(
    option: NewGameView.NewGameOption
) -> some View {
    let openChallenge = OGSChallengeSampleData.sampleOpenChallenge
    let rengoChallenge = OGSChallengeSampleData.sampleRengoChallenge
    return NavigationStack {
        NewGameView(newGameOption: option)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(
        OGSService.previewInstance(
            user: OGSUser(
                username: "HongAnhKhoa",
                id: 314459,
                ranking: 27
            ),
            eligibleOpenChallenges: [
                openChallenge,
                rengoChallenge,
            ],
            openChallengesSent: [
                openChallenge,
            ],
            cachedUsers: [
                OGSUser(
                    username: "hakhoa4",
                    id: 1769
                ),
                OGSUser(
                    username: "honganhkhoa",
                    id: 1526
                ),
            ]
        )
    )
    .environmentObject(NavigationService())
    .environment(\.surroundAllowsRemoteActivity, false)
    .environment(\.surroundAllowsLocalPersistence, false)
}

#Preview("New game — Quick match") {
    newGamePreview(option: .quickMatch)
}

#Preview("New game — Custom game") {
    newGamePreview(option: .custom)
}

#Preview("New game — Open challenges") {
    newGamePreview(option: .openChallenges)
}
#endif
