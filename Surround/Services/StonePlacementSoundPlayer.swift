import AVFAudio
import Combine
import UIKit

/// The small audio boundary lets tests verify sequencing and cancellation
/// without opening the audio device or waiting for a scheduled sound.
protocol StoneSoundPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var deviceCurrentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    @discardableResult func play(atTime time: TimeInterval) -> Bool
    func stop()
}

extension AVAudioPlayer: StoneSoundPlaying {}

/// Each board owns its voices. A move's placement and capture overlap, and
/// the next move or a pass lets both finish, as OGS, Sabaki and KaTrain let
/// a capture finish. Only muting, changing theme or game, and leaving the
/// board stop them. A released AVAudioPlayer stops, so the player keeps every
/// voice it starts until that voice ends, apart from the banks that hold them.
final class StonePlacementSoundPlayer: ObservableObject {
    static let variations = 1...3
    static let captureDelay: TimeInterval = 0.25
    /// A bot's fastest replies leave a few moves' sounds overlapping. Past
    /// this many, the oldest voice stops instead of more piling up.
    static let maximumLiveVoices = 12

    enum CaptureTier: String, CaseIterable {
        case single, few, group, many

        init?(count: Int) {
            switch count {
            case 1: self = .single
            case 2...3: self = .few
            case 4...7: self = .group
            case 8...: self = .many
            default: return nil
            }
        }
    }

    struct Capture: Equatable {
        let color: StoneColor
        let count: Int
        let tier: CaptureTier
    }

    private struct CaptureKey: Hashable {
        let color: StoneColor
        let tier: CaptureTier
    }

    private final class Bank {
        let players: [StoneSoundPlaying]
        private var previousIndex: Int?

        init(players: [StoneSoundPlaying]) { self.players = players }

        /// Avoids repeating the last clip and, where it can, a clip still
        /// sounding, which restarting would cut short.
        func next(isSounding: (StoneSoundPlaying) -> Bool) -> StoneSoundPlaying? {
            let choices = players.indices.filter { players.count == 1 || $0 != previousIndex }
            let quiet = choices.filter { !isSounding(players[$0]) }
            guard let index = (quiet.isEmpty ? choices : quiet).randomElement() else { return nil }
            previousIndex = index
            return players[index]
        }
    }

    /// A started voice, with the process clock's time by which it has
    /// ended. The audio device's clock only schedules starts: it restarts
    /// from zero once every player is idle.
    private struct LiveVoice {
        let player: StoneSoundPlaying
        let endTime: TimeInterval
    }

    /// A stone the user committed, kept until the board settles it. The echo
    /// is a new position object, so it is matched by value.
    private struct CommittedStone: Equatable {
        let moveNumber: Int
        let move: Move?
        let color: StoneColor?

        init(_ position: BoardPosition) {
            moveNumber = position.lastMoveNumber
            move = position.lastMove
            color = position.lastMoveColor
        }

        /// Whether `position` has this stone as its move with this number.
        func isOnBoard(in position: BoardPosition) -> Bool {
            var current: BoardPosition? = position
            while let earlier = current, earlier.lastMoveNumber > moveNumber {
                current = earlier.previousPosition
            }
            return current.map { CommittedStone($0) == self } ?? false
        }
    }

    /// A request waiting for OGS. Windows can each send a move for one
    /// turn, even the same stone, so several can wait at once, and each is
    /// settled on its own.
    private struct PendingStone {
        let id: UUID
        let stone: CommittedStone
        /// Its capture, which must not follow a refusal. None when another
        /// window played the stone.
        let captureVoices: [StoneSoundPlaying]
        /// The board has shown the stone, as a snapshot can before its echo.
        var isConfirmed = false
    }

    private let makePlayer: (String) -> StoneSoundPlaying?
    private let uptime: () -> TimeInterval
    private var theme: SurroundTheme?
    private var placementBanks: [StoneColor: Bank] = [:]
    // At most two color/tier banks (six capture clips) are retained. Capture
    // sounds load on first use, never all themes or all counts at startup.
    private var captureBanks: [CaptureKey: Bank] = [:]
    private var captureBankOrder: [CaptureKey] = []
    private var fallbackPlayer: StoneSoundPlaying?
    // Separate from the banks: a capture still sounding when the cache
    // evicts its bank keeps playing to its end.
    private var liveVoices: [LiveVoice] = []
    private var pendingStones: [PendingStone] = []

    /// Voices started and not yet ended or stopped.
    var liveVoiceCount: Int { liveVoices.count }

    init(makePlayer: ((String) -> StoneSoundPlaying?)? = nil,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.makePlayer = makePlayer ?? Self.bundledPlayer
        self.uptime = uptime
    }

    /// Folded paper shares the soft felt bank; visual presentations need not
    /// duplicate audio assets merely to preserve their material character.
    private static func soundTheme(for theme: SurroundTheme) -> SurroundTheme {
        if theme.isFlowingInk || theme == .sakuraStream { return .standard }
        return theme == .paperBlossoms ? .feltMeadow : theme
    }

    static func assetName(theme: SurroundTheme, color: StoneColor, variation: Int) -> String {
        "StoneSound-\(soundTheme(for: theme).rawValue)-\(color.rawValue)-\(variation)"
    }

    static func captureAssetName(theme: SurroundTheme, color: StoneColor,
                                 tier: CaptureTier, variation: Int) -> String {
        "StoneCapture-\(soundTheme(for: theme).rawValue)-\(color.rawValue)-\(tier.rawValue)-\(variation)"
    }

    /// A structural guard for one placement, not proof of a live update. The
    /// views feed this player Game.moveApplied and the user's own commits on
    /// Game.moveCommits, which exclude snapshots, analysis and undo even when
    /// their reconstructed boards look adjacent.
    static func placedStoneColor(after previous: BoardPosition, in position: BoardPosition) -> StoneColor? {
        guard case .placeStone = position.lastMove,
              position.lastMoveNumber == previous.lastMoveNumber + 1,
              let parent = position.previousPosition,
              parent.lastMoveNumber == previous.lastMoveNumber,
              parent.nextToMove == previous.nextToMove,
              parent.hasTheSamePosition(with: previous) else { return nil }
        return position.lastMoveColor
    }

    static func captures(after previous: BoardPosition, in position: BoardPosition) -> [Capture] {
        guard placedStoneColor(after: previous, in: position) != nil else { return [] }
        return [StoneColor.black, .white].compactMap { creditedColor in
            let count = position.captures[creditedColor, default: 0] - previous.captures[creditedColor, default: 0]
            guard let tier = CaptureTier(count: count) else { return nil }
            // Prisoners are credited to the captor. Checking both counters
            // includes legal self-capture, including the just-placed stone.
            return Capture(color: creditedColor.opponentColor(), count: count, tier: tier)
        }
    }

    func prepare(theme: SurroundTheme, enabled: Bool) {
        guard enabled else {
            reset()
            return
        }
        guard self.theme != theme else { return }
        // A first theme has nothing to stop. A commit another window sent
        // while this board was off screen still waits for its echo.
        if self.theme != nil { reset() }
        self.theme = theme
        for color: StoneColor in [.black, .white] {
            placementBanks[color] = Bank(players: Self.variations.compactMap { variation in
                preparedPlayer(named: Self.assetName(theme: theme, color: color, variation: variation))
            })
        }
        if placementBanks.values.contains(where: { $0.players.isEmpty }) {
            fallbackPlayer = preparedPlayer(named: "stonePlacing")
        }
    }

    /// Plays the user's own stone as it is committed, a round trip before
    /// OGS echoes it, and its capture locally. The matching echo then plays
    /// nothing; any other move plays as usual.
    func playCommitted(move: Game.AppliedMove, id: UUID, theme: SurroundTheme, enabled: Bool) {
        let captureVoices = startSounds(for: move, theme: theme, enabled: enabled)
        addPendingStone(for: move, id: id, captureVoices: captureVoices)
    }

    /// OGS refused request `id`, so a later move with its number plays. Its
    /// click has sounded, but a capture still due is stopped. Other
    /// requests, the same stone sent from another window among them, wait on.
    func forgetCommittedMove(id: UUID) {
        settle(pendingStones.filter { $0.id == id }, accepted: false)
    }

    /// Expects the echo of a stone that another window has played.
    func expectEcho(of move: Game.AppliedMove, id: UUID) {
        addPendingStone(for: move, id: id, captureVoices: [])
    }

    /// Follows `Game.moveCommits`.
    func play(commit: Game.MoveCommit, theme: SurroundTheme, enabled: Bool) {
        switch commit {
        case .committed(let move, let id):
            playCommitted(move: move, id: id, theme: theme, enabled: enabled)
        case .committedElsewhere(let move, let id):
            expectEcho(of: move, id: id)
        case .withdrawn(let id):
            forgetCommittedMove(id: id)
        }
    }

    /// Follows the board through changes that are not moves, such as a
    /// snapshot or an undo. A stone the board shows is confirmed: its echo
    /// stays silent and its capture plays on. One that the board shows no
    /// longer was undone, so a later stone there plays.
    func boardChanged(to position: BoardPosition) {
        for pending in pendingStones {
            if pending.stone.moveNumber <= position.lastMoveNumber {
                if pending.stone.isOnBoard(in: position) {
                    if let index = pendingStones.firstIndex(where: { $0.id == pending.id }) {
                        pendingStones[index].isConfirmed = true
                    }
                } else {
                    settle([pending], accepted: false)
                }
            } else if pending.isConfirmed {
                pendingStones.removeAll { $0.id == pending.id }
            }
        }
    }

    func play(move: Game.AppliedMove, theme: SurroundTheme, enabled: Bool) {
        guard enabled else {
            reset()
            return
        }
        // A request this move answers is settled; one with a later number is
        // left for its own echo, which a window one move behind sees later.
        let answered = pendingStones.filter { $0.stone.moveNumber <= move.after.lastMoveNumber }
        let echo = answered.contains { $0.stone == CommittedStone(move.after) }
        for pending in answered {
            // A snapshot may already have shown the stone, so a later move
            // confirms it; otherwise another move took its place.
            settle([pending], accepted: pending.stone.isOnBoard(in: move.after))
        }
        // The echo of a stone already played: neither its placement nor its
        // capture plays again.
        guard !echo else { return }
        startSounds(for: move, theme: theme, enabled: true)
    }

    func reset() {
        pendingStones = []
        liveVoices.forEach { $0.player.stop() }
        liveVoices.removeAll()
        placementBanks.removeAll()
        captureBanks.removeAll()
        captureBankOrder.removeAll()
        fallbackPlayer = nil
        theme = nil
    }

    /// Starts a move's placement and capture, returning the capture voices.
    @discardableResult
    private func startSounds(for move: Game.AppliedMove, theme: SurroundTheme,
                             enabled: Bool) -> [StoneSoundPlaying] {
        prepare(theme: theme, enabled: enabled)
        // Earlier voices keep playing: a pass or a quick reply must not cut
        // the capture it follows, or the capturing stone's own click.
        guard enabled, let color = Self.placedStoneColor(after: move.before, in: move.after) else { return [] }

        // Prepare any newly needed capture bank before starting the sequence,
        // so decoding does not stretch the gap after the placement transient.
        let captures = Self.captures(after: move.before, in: move.after)
        let capturePlayers = captures.compactMap { capture in
            captureBank(theme: theme, key: CaptureKey(color: capture.color, tier: capture.tier))
                .next(isSounding: isSounding)
        }
        if let placement = placementBanks[color]?.next(isSounding: isSounding) ?? fallbackPlayer {
            start(placement, after: 0)
        }
        // A legal move removes stones of one color. Even a supplied transition
        // with both positive counters is bounded to one voice per color.
        for player in capturePlayers {
            start(player, after: Self.captureDelay)
        }
        return capturePlayers
    }

    private func addPendingStone(for move: Game.AppliedMove, id: UUID, captureVoices: [StoneSoundPlaying]) {
        guard Self.placedStoneColor(after: move.before, in: move.after) != nil else { return }
        let stone = CommittedStone(move.after)
        // A request for a later turn means the board moved on from earlier
        // ones without their echoes; it shows whether each was taken. So
        // only one turn's requests ever wait.
        for pending in pendingStones where pending.stone.moveNumber < stone.moveNumber {
            settle([pending], accepted: pending.stone.isOnBoard(in: move.before))
        }
        pendingStones.append(PendingStone(id: id, stone: stone, captureVoices: captureVoices))
    }

    /// Settles requests: an accepted one keeps its capture playing, a
    /// refused or replaced one stops it if it is still due.
    private func settle(_ stones: [PendingStone], accepted: Bool) {
        for pending in stones {
            pendingStones.removeAll { $0.id == pending.id }
            guard !accepted else { continue }
            for voice in pending.captureVoices where isSounding(voice) {
                voice.stop()
                liveVoices.removeAll { $0.player === voice }
            }
        }
    }

    /// Whether a voice that was started, or is scheduled, has yet to end.
    private func isSounding(_ player: StoneSoundPlaying) -> Bool {
        let now = uptime()
        return liveVoices.contains { $0.player === player && $0.endTime > now }
    }

    private func start(_ player: StoneSoundPlaying, after delay: TimeInterval) {
        let now = uptime()
        // A clip coming round again while it still sounds is stopped first.
        // Seeking a playing player plays on at once, and a scheduled start
        // would not wait for its delay.
        if isSounding(player) {
            player.stop()
            player.prepareToPlay()
        }
        // Ended voices go, and a restarted one is listed once.
        liveVoices.removeAll { $0.endTime <= now || $0.player === player }
        player.currentTime = 0
        if delay > 0 {
            player.play(atTime: player.deviceCurrentTime + delay)
        } else {
            player.play()
        }
        liveVoices.append(LiveVoice(player: player, endTime: now + delay + player.duration))
        while liveVoices.count > Self.maximumLiveVoices {
            liveVoices.removeFirst().player.stop()
        }
    }

    private func captureBank(theme: SurroundTheme, key: CaptureKey) -> Bank {
        captureBankOrder.removeAll { $0 == key }
        captureBankOrder.append(key)
        if let bank = captureBanks[key] { return bank }
        let bank = Bank(players: Self.variations.compactMap { variation in
            preparedPlayer(named: Self.captureAssetName(theme: theme, color: key.color,
                                                        tier: key.tier, variation: variation))
        })
        captureBanks[key] = bank
        if captureBankOrder.count > 2 {
            captureBanks.removeValue(forKey: captureBankOrder.removeFirst())
        }
        return bank
    }

    private func preparedPlayer(named name: String) -> StoneSoundPlaying? {
        let player = makePlayer(name)
        player?.prepareToPlay()
        return player
    }

    private static func bundledPlayer(named name: String) -> StoneSoundPlaying? {
        guard let data = NSDataAsset(name: name)?.data else { return nil }
        return try? AVAudioPlayer(data: data)
    }
}
