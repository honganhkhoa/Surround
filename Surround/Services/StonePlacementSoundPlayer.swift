import AVFAudio
import Combine
import UIKit

/// The small audio boundary lets tests verify sequencing and cancellation
/// without opening the audio device or waiting for a scheduled sound.
protocol StoneSoundPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var deviceCurrentTime: TimeInterval { get }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    @discardableResult func play(atTime time: TimeInterval) -> Bool
    func stop()
}

extension AVAudioPlayer: StoneSoundPlaying {}

/// Each board owns its voices. Placement and capture overlap briefly, while a
/// new move, muting, changing theme or leaving the board stops the old gesture.
final class StonePlacementSoundPlayer: ObservableObject {
    static let variations = 1...3
    static let captureDelay: TimeInterval = 0.25

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

        func next() -> StoneSoundPlaying? {
            let choices = players.indices.filter { players.count == 1 || $0 != previousIndex }
            guard let index = choices.randomElement() else { return nil }
            previousIndex = index
            return players[index]
        }
    }

    private let makePlayer: (String) -> StoneSoundPlaying?
    private var theme: SurroundTheme?
    private var placementBanks: [StoneColor: Bank] = [:]
    // At most two color/tier banks (six capture clips) are retained. Capture
    // sounds load on first use, never all themes or all counts at startup.
    private var captureBanks: [CaptureKey: Bank] = [:]
    private var captureBankOrder: [CaptureKey] = []
    private var fallbackPlayer: StoneSoundPlaying?
    private var activePlacement: StoneSoundPlaying?
    private var activeCaptures: [StoneSoundPlaying] = []

    init(makePlayer: ((String) -> StoneSoundPlaying?)? = nil) {
        self.makePlayer = makePlayer ?? Self.bundledPlayer
    }

    static func assetName(theme: SurroundTheme, color: StoneColor, variation: Int) -> String {
        "StoneSound-\(theme.rawValue)-\(color.rawValue)-\(variation)"
    }

    static func captureAssetName(theme: SurroundTheme, color: StoneColor,
                                 tier: CaptureTier, variation: Int) -> String {
        "StoneCapture-\(theme.rawValue)-\(color.rawValue)-\(tier.rawValue)-\(variation)"
    }

    /// A structural guard for one placement, not proof of a live update. The
    /// views feed this player Game.moveApplied, which excludes snapshots,
    /// analysis and undo even when their reconstructed boards look adjacent.
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
        reset()
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

    func play(move: Game.AppliedMove, theme: SurroundTheme, enabled: Bool) {
        prepare(theme: theme, enabled: enabled)
        stopActiveSounds()
        guard enabled, let color = Self.placedStoneColor(after: move.before, in: move.after) else { return }

        // Prepare any newly needed capture bank before starting the sequence,
        // so decoding does not stretch the gap after the placement transient.
        let captures = Self.captures(after: move.before, in: move.after)
        let capturePlayers = captures.compactMap { capture in
            captureBank(theme: theme, key: CaptureKey(color: capture.color, tier: capture.tier)).next()
        }
        let placement = placementBanks[color]?.next() ?? fallbackPlayer
        placement?.currentTime = 0
        placement?.play()
        activePlacement = placement
        for player in capturePlayers {
            player.currentTime = 0
            player.play(atTime: player.deviceCurrentTime + Self.captureDelay)
        }
        // A legal move removes stones of one color. Even a supplied transition
        // with both positive counters is bounded to one voice per color.
        activeCaptures = capturePlayers
    }

    func reset() {
        stopActiveSounds()
        placementBanks.removeAll()
        captureBanks.removeAll()
        captureBankOrder.removeAll()
        fallbackPlayer = nil
        theme = nil
    }

    private func stopActiveSounds() {
        activePlacement?.stop()
        activePlacement = nil
        activeCaptures.forEach { $0.stop() }
        activeCaptures.removeAll()
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
