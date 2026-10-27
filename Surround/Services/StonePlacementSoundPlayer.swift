import AVFAudio
import Combine
import UIKit

/// Keeps a small, prepared bank for the visible board's material. Each view
/// owns its player, so changing one window's theme cannot affect another.
final class StonePlacementSoundPlayer: ObservableObject {
    static let variations = 1...3

    private var theme: SurroundTheme?
    private var players: [StoneColor: [AVAudioPlayer]] = [:]
    private var previousVariation: [StoneColor: Int] = [:]
    private var fallbackPlayer: AVAudioPlayer?
    private var activePlayer: AVAudioPlayer?

    static func assetName(theme: SurroundTheme, color: StoneColor, variation: Int) -> String {
        "StoneSound-\(theme.rawValue)-\(color.rawValue)-\(variation)"
    }

    /// Published positions arrive before Game.currentPosition changes. Only a
    /// single new placement following that position should make a sound.
    static func placedStoneColor(after previous: BoardPosition, in position: BoardPosition) -> StoneColor? {
        guard case .placeStone = position.lastMove,
              position.lastMoveNumber == previous.lastMoveNumber + 1,
              let parent = position.previousPosition,
              parent.lastMoveNumber == previous.lastMoveNumber,
              parent.nextToMove == previous.nextToMove,
              parent.hasTheSamePosition(with: previous) else { return nil }
        return position.lastMoveColor
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
            players[color] = Self.variations.compactMap { variation in
                makePlayer(named: Self.assetName(theme: theme, color: color, variation: variation))
            }
        }
        if players.values.contains(where: { $0.isEmpty }) {
            fallbackPlayer = makePlayer(named: "stonePlacing")
        }
    }

    func play(theme: SurroundTheme, color: StoneColor, enabled: Bool) {
        prepare(theme: theme, enabled: enabled)
        guard enabled else { return }
        let bank = players[color] ?? []
        let choices = bank.indices.filter { bank.count == 1 || $0 != previousVariation[color] }
        let player: AVAudioPlayer?
        if let index = choices.randomElement() {
            previousVariation[color] = index
            player = bank[index]
        } else {
            player = fallbackPlayer
        }
        // A quick next placement starts cleanly, including when a sample is
        // reused before its short tail has finished.
        activePlayer?.stop()
        player?.currentTime = 0
        player?.play()
        activePlayer = player
    }

    func reset() {
        activePlayer?.stop()
        activePlayer = nil
        players.removeAll()
        previousVariation.removeAll()
        fallbackPlayer = nil
        theme = nil
    }

    private func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let data = NSDataAsset(name: name)?.data,
              let player = try? AVAudioPlayer(data: data) else { return nil }
        player.prepareToPlay()
        return player
    }
}
