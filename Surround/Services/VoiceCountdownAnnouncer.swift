//
//  VoiceCountdownAnnouncer.swift
//  Surround
//

import AVFAudio
import Foundation

/// The voice countdown's speech. Tests record what would be said.
protocol CountdownSpeaking: AnyObject {
    /// Ready the voice, so the first number does not start late.
    func prepare()
    func speak(_ text: String)
    func stop()
}

/// A synthesizer that exists only while the countdown may speak.
final class SystemCountdownSpeaker: CountdownSpeaking {
    private var synthesizer: AVSpeechSynthesizer?

    func prepare() {
        if synthesizer == nil { synthesizer = AVSpeechSynthesizer() }
    }

    func speak(_ text: String) {
        prepare()
        synthesizer?.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
    }
}

/// Says the user's last ten seconds on their own turn, one number a second.
///
/// It judges the clock it is given. `Game.clock` publishes before it is
/// stored, so while the clock that ends the user's turn is delivered,
/// `Game.isUserTurn` still reads the previous one; a turn checked there
/// spoke the user's time left after the move, a stray number after most
/// overtime moves. After a move is sent the clock still ticks until that
/// turn-ending clock arrives, so speech holds briefly after a commit, as
/// OGS's board pauses its clock sounds from sending a move until the next
/// clock. The hold ends once the board moves on, so an instant reply
/// starts the next turn's count at once.
final class VoiceCountdownAnnouncer: ObservableObject {
    /// How long a sent move holds speech while its turn-ending clock is due.
    static let commitHold: TimeInterval = 1
    static let highestNumber = 10

    private let speaker: CountdownSpeaking
    private let now: () -> Date
    private var lastValue: Int?
    private var lastSpokenAt = Date.distantPast
    /// The turn being counted, by its clock's last move time.
    private var turn: Double?
    private var hasSpokenThisTurn = false
    /// Byo-yomi periods left at this turn's last tick. Losing one is said
    /// even when the number stays the same, as it does with 1 s periods.
    private var periodsLeft: Int?

    init(speaker: CountdownSpeaking = SystemCountdownSpeaker(), now: @escaping () -> Date = Date.init) {
        self.speaker = speaker
        self.now = now
    }

    func prepare() {
        speaker.prepare()
    }

    /// Considers `clock` for `game`, as delivered by `Game.$clock` and
    /// before the game has stored it. The caller checks the setting and the
    /// connection.
    func clockChanged(to clock: OGSClock?, in game: Game, userID: Int?) {
        guard let clock, let userID,
              game.isUserPlaying, game.gamePhase == .play,
              // A finishing snapshot stores its clock before its phase.
              game.gameData?.outcome == nil,
              // Waiting for the first move, the time left does not run.
              clock.started,
              clock.currentPlayerId == userID,
              game.pauseControl?.isPaused() != true,
              let color = game.userStoneColor,
              // Once the user's move is applied, the clock is out of date.
              game.currentPosition.nextToMove == color else { return }
        let date = now()
        // Any request still in flight from this position holds, whichever
        // window sent it.
        if game.sentMoves.contains(where: {
            $0.fromMoveNumber == game.currentPosition.lastMoveNumber
                && date.timeIntervalSince($0.date) < Self.commitHold
        }) { return }
        let time = color == .black ? clock.blackTime : clock.whiteTime
        guard let remaining = time.timeLeft, remaining.isFinite,
              remaining >= 0, remaining <= Double(Self.highestNumber) else { return }
        let value = Int(remaining)
        if turn != clock.lastMoveTime {
            turn = clock.lastMoveTime
            hasSpokenThisTurn = false
            lastValue = nil
            periodsLeft = nil
        }
        let system = game.gameData?.timeControl.system
        let lostPeriod = Self.isOvertime(time, system: system)
            && (periodsLeft.map { (time.periodsLeft ?? $0) < $0 } ?? false)
        periodsLeft = time.periodsLeft
        if !lostPeriod {
            if !hasSpokenThisTurn, Self.isPeriodTop(value, of: time, system: system) { return }
            guard value != lastValue || date.timeIntervalSince(lastSpokenAt) >= 3 else { return }
        }
        lastValue = value
        lastSpokenAt = date
        hasSpokenThisTurn = true
        speaker.speak(String(value))
    }

    func stop() {
        speaker.stop()
        lastValue = nil
        turn = nil
        hasSpokenThisTurn = false
        periodsLeft = nil
    }

    private static func isOvertime(_ time: ThinkingTime, system: TimeControlSystem?) -> Bool {
        guard case .ByoYomi? = system else { return false }
        return time.thinkingTimeLeft == 0
    }

    /// A byo-yomi turn in overtime starts at the full period. OGS does not
    /// count that number aloud: it would land on the opponent's stone and
    /// capture, and rush into the next number. Only periods of ten seconds
    /// or less reach the countdown. A period running out mid-turn is said,
    /// from its top, which tells the user a period has gone.
    private static func isPeriodTop(_ value: Int, of time: ThinkingTime, system: TimeControlSystem?) -> Bool {
        guard case .ByoYomi(_, _, let periodTime)? = system,
              periodTime <= highestNumber,
              time.thinkingTimeLeft == 0 else { return false }
        return value == periodTime
    }
}
