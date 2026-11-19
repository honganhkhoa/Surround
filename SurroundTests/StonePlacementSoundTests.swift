import AVFAudio
import UIKit
import XCTest

final class StonePlacementSoundTests: XCTestCase {
    func testEveryAvailableThemeHasDistinctDecodableCaptureSounds() throws {
        let bundle = Bundle(for: Self.self)
        var sounds = Set<Data>()
        var assetNames = Set<String>()
        for theme in SurroundTheme.available {
            for color: StoneColor in [.black, .white] {
                for tier in StonePlacementSoundPlayer.CaptureTier.allCases {
                    for variation in StonePlacementSoundPlayer.variations {
                        let name = StonePlacementSoundPlayer.captureAssetName(theme: theme, color: color,
                                                                             tier: tier, variation: variation)
                        // Presentation variants deliberately share a bank;
                        // distinct named clips must still have distinct audio.
                        guard assetNames.insert(name).inserted else { continue }
                        let asset = try XCTUnwrap(NSDataAsset(name: name, bundle: bundle), name)
                        let player = try AVAudioPlayer(data: asset.data)
                        XCTAssertEqual(player.numberOfChannels, 1, name)
                        XCTAssertEqual(player.format.sampleRate, 44_100, name)
                        XCTAssertGreaterThan(player.duration, 0.1, name)
                        XCTAssertLessThan(player.duration, 1, name)
                        XCTAssertTrue(sounds.insert(asset.data).inserted, "Duplicate sound: \(name)")
                    }
                }
            }
        }
    }

    func testEveryAvailableThemeHasDistinctDecodablePlacementSounds() throws {
        let bundle = Bundle(for: Self.self)
        var sounds = Set<Data>()
        var assetNames = Set<String>()
        for theme in SurroundTheme.available {
            for color: StoneColor in [.black, .white] {
                for variation in StonePlacementSoundPlayer.variations {
                    let name = StonePlacementSoundPlayer.assetName(theme: theme, color: color, variation: variation)
                    guard assetNames.insert(name).inserted else { continue }
                    let asset = try XCTUnwrap(NSDataAsset(name: name, bundle: bundle), name)
                    let player = try AVAudioPlayer(data: asset.data)
                    XCTAssertEqual(player.numberOfChannels, 1, name)
                    XCTAssertEqual(player.format.sampleRate, 44_100, name)
                    XCTAssertGreaterThan(player.duration, 0.03, name)
                    XCTAssertLessThan(player.duration, 1, name)
                    XCTAssertTrue(sounds.insert(asset.data).inserted, "Duplicate sound: \(name)")
                }
            }
        }
        let fallback = try XCTUnwrap(NSDataAsset(name: "stonePlacing", bundle: bundle))
        XCTAssertGreaterThan(try AVAudioPlayer(data: fallback.data).duration, 0)
    }

    func testOnlyTheNextStonePlacementProducesAColor() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let black = try initial.makeMove(move: .placeStone(0, 0))
        let white = try black.makeMove(move: .placeStone(1, 1))
        let pass = try white.makeMove(move: .pass)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: black), .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: black, in: white), .white)
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: white, in: pass))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: initial))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: black, in: black))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: white), "Catch-up skips audio")
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: white, in: black), "Undo skips audio")

        let otherBranch = try initial.makeMove(move: .placeStone(2, 2))
        XCTAssertNil(StonePlacementSoundPlayer.placedStoneColor(after: otherBranch, in: white))
    }

    func testHandicapStonesUseTheirPlacedColorEvenWhenTheNextPlayerDoesNotChange() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let first = try initial.makeHandicapPlacement(move: .placeStone(2, 2))
        let second = try first.makeHandicapPlacement(move: .placeStone(6, 6))
        XCTAssertEqual(first.nextToMove, .black)
        XCTAssertEqual(second.nextToMove, .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: initial, in: first), .black)
        XCTAssertEqual(StonePlacementSoundPlayer.placedStoneColor(after: first, in: second), .black)
    }

    func testCaptureTiersCoverTheirExactBoundaries() {
        typealias Tier = StonePlacementSoundPlayer.CaptureTier
        XCTAssertNil(Tier(count: -1))
        XCTAssertNil(Tier(count: 0))
        XCTAssertEqual(Tier(count: 1), .single)
        for count in [2, 3] { XCTAssertEqual(Tier(count: count), .few) }
        for count in [4, 7] { XCTAssertEqual(Tier(count: count), .group) }
        for count in [8, 50, 361] { XCTAssertEqual(Tier(count: count), .many) }
    }

    func testCapturesUseNewPrisonerDeltasAndTheRemovedStonesColor() throws {
        let before = position(["-bbbw", "bww--", "-bb--"])
        before.captures = [.black: 12, .white: 9]
        let single = try before.makeMove(move: .placeStone(1, 4))
        let group = try before.makeMove(move: .placeStone(1, 3))
        XCTAssertEqual(StonePlacementSoundPlayer.captures(after: before, in: single), [
            .init(color: .white, count: 1, tier: .single)
        ])
        XCTAssertEqual(StonePlacementSoundPlayer.captures(after: before, in: group), [
            .init(color: .white, count: 2, tier: .few)
        ])
        let noCapture = try before.makeMove(move: .placeStone(0, 0))
        XCTAssertTrue(StonePlacementSoundPlayer.captures(after: before, in: noCapture).isEmpty)
        let pass = try before.makeMove(move: .pass)
        XCTAssertTrue(StonePlacementSoundPlayer.captures(after: before, in: pass).isEmpty)
        XCTAssertTrue(StonePlacementSoundPlayer.captures(after: group, in: before).isEmpty)
    }

    func testLegalSelfCaptureIncludesTheJustPlacedStone() throws {
        let before = position(["----w", "---wb", "--wb-"])
        before.captures = [.black: 8, .white: 6]
        let after = try before.makeMove(move: .placeStone(2, 4), allowsSelfCapture: true)
        XCTAssertEqual(after[2, 4], .empty)
        XCTAssertEqual(StonePlacementSoundPlayer.captures(after: before, in: after), [
            .init(color: .black, count: 3, tier: .few)
        ])
        let singleBefore = position(["-w-", "w-w", "-w-"])
        let singleAfter = try singleBefore.makeMove(move: .placeStone(1, 1), allowsSelfCapture: true)
        XCTAssertEqual(StonePlacementSoundPlayer.captures(after: singleBefore, in: singleAfter), [
            .init(color: .black, count: 1, tier: .single)
        ])
    }

    func testPlacementStartsBeforeSeparateScheduledCaptureVoice() throws {
        let audio = AudioRecorder()
        let player = soundPlayer(audio)
        player.prepare(theme: .surroundStudio, enabled: true)
        XCTAssertEqual(audio.voices.count, 6, "Only placement clips are prepared initially")
        XCTAssertFalse(audio.voices.contains { $0.name.hasPrefix("StoneCapture-") })

        player.play(move: try captureMove(count: 2), theme: .surroundStudio, enabled: true)
        let placement = try XCTUnwrap(audio.voices.first { $0.plays == 1 })
        let capture = try XCTUnwrap(audio.voices.first { !$0.scheduledTimes.isEmpty })
        XCTAssertTrue(placement.name.hasPrefix("StoneSound-surroundStudio-black-"))
        XCTAssertTrue(capture.name.hasPrefix("StoneCapture-surroundStudio-white-few-"))
        XCTAssertEqual(capture.scheduledTimes, [42 + StonePlacementSoundPlayer.captureDelay])
        XCTAssertEqual(placement.stops, 0, "Scheduling capture must not truncate placement")
        XCTAssertEqual(placement.currentTime, 0)
        XCTAssertEqual(capture.currentTime, 0)
        XCTAssertEqual(audio.actions, ["play:\(placement.name)", "schedule:\(capture.name)"])
    }

    func testMuteThemeChangeAndDisappearanceCancelScheduledCapture() throws {
        for action in ["mute", "theme", "disappear"] {
            let audio = AudioRecorder()
            let player = soundPlayer(audio)
            player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
            let placement = try XCTUnwrap(audio.voices.first { $0.plays == 1 })
            let capture = try XCTUnwrap(audio.voices.first { !$0.scheduledTimes.isEmpty })
            switch action {
            case "mute": player.prepare(theme: .standard, enabled: false)
            case "theme": player.prepare(theme: .nebulaPearl, enabled: true)
            default: player.reset()
            }
            XCTAssertEqual(placement.stops, 1, action)
            XCTAssertEqual(capture.stops, 1, "Cancel the device-scheduled voice: \(action)")
            XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.plays }, 1, action)
            XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.scheduledTimes.count }, 1, action)
        }
        let mutedAudio = AudioRecorder()
        let muted = StonePlacementSoundPlayer(makePlayer: mutedAudio.makePlayer)
        muted.play(move: try captureMove(count: 1), theme: .standard, enabled: false)
        XCTAssertTrue(mutedAudio.voices.isEmpty, "Muted moves must not decode or play audio")
    }

    func testNextPlacementOrPassLetsThePreviousSoundsFinish() throws {
        for isPass in [false, true] {
            let audio = AudioRecorder()
            let player = soundPlayer(audio)
            let first = try captureMove(count: 1)
            player.play(move: first, theme: .standard, enabled: true)
            let capture = try XCTUnwrap(audio.voices.first { !$0.scheduledTimes.isEmpty })
            let next = try first.after.makeMove(move: isPass ? .pass : .placeStone(2, 2))
            player.play(move: .init(before: first.after, after: next), theme: .standard, enabled: true)
            XCTAssertEqual(capture.stops, 0, "A quick reply or a pass must not cut the capture it follows")
            XCTAssertFalse(audio.actions.contains { $0.hasPrefix("stop:") }, "\(audio.actions)")
            XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.scheduledTimes.count }, 1)
            XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.plays }, isPass ? 1 : 2)
            XCTAssertEqual(player.liveVoiceCount, isPass ? 2 : 3)
        }
    }

    func testSoundingCaptureOutlivesItsEvictedBankUntilItEnds() throws {
        let audio = AudioRecorder(retainsVoices: false)
        let player = soundPlayer(audio)
        player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        let single = try XCTUnwrap(audio.voices.first { !$0.scheduledTimes.isEmpty }).name
        // Two more capture sizes evict the single-stone bank while its clip is due.
        player.play(move: try captureMove(count: 2), theme: .standard, enabled: true)
        player.play(move: try captureMove(count: 4), theme: .standard, enabled: true)
        XCTAssertEqual(audio.actions.filter { $0.hasPrefix("release:StoneCapture-standard-white-single-") }.count, 2,
                       "The evicted bank's unused clips go")
        XCTAssertTrue(audio.voices.contains { $0.name == single }, "Releasing a voice would stop it")
        XCTAssertFalse(audio.actions.contains("stop:\(single)"))

        audio.now += 1
        player.play(move: try captureMove(count: 0), theme: .standard, enabled: true)
        XCTAssertTrue(audio.actions.contains("release:\(single)"), "An ended voice is let go")
        XCTAssertFalse(audio.actions.contains("stop:\(single)"), "It ended by itself")
        XCTAssertEqual(player.liveVoiceCount, 1, "Only the newest placement is still sounding")
    }

    func testClipComingRoundWhileSoundingIsStoppedBeforeItRestarts() throws {
        let audio = AudioRecorder()
        let player = soundPlayer(audio)
        // Three quick single captures, with no time passing, use each of the
        // bank's three clips before any comes round again.
        for _ in 0..<3 {
            player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        }
        XCTAssertEqual(Set(audio.actions.filter { $0.hasPrefix("schedule:") }).count, 3,
                       "A quiet clip is chosen over one still sounding")
        XCTAssertEqual(Set(audio.actions.filter { $0.hasPrefix("play:") }).count, 3)
        XCTAssertFalse(audio.actions.contains { $0.hasPrefix("stop:") })

        // Every clip is still sounding now: the one reused stops first, so its
        // scheduled start waits for the delay instead of playing at once.
        player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        let last = Array(audio.actions.suffix(4))
        XCTAssertEqual(last.count, 4)
        let placement = last[1].replacingOccurrences(of: "play:", with: "")
        let capture = last[3].replacingOccurrences(of: "schedule:", with: "")
        XCTAssertEqual(last, ["stop:\(placement)", "play:\(placement)", "stop:\(capture)", "schedule:\(capture)"])
        XCTAssertEqual(player.liveVoiceCount, 6, "A restarted voice is listed once")
    }

    func testEndedVoicesStayEndedWhenTheAudioClockRestarts() throws {
        let audio = AudioRecorder()
        let player = soundPlayer(audio)
        for _ in 0..<3 {
            player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        }
        // Every player falls idle, so the audio device's clock restarts from
        // zero while the process clock moves on.
        audio.now += 5
        audio.deviceTime = 0.1
        for _ in 0..<2 {
            player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        }
        XCTAssertFalse(audio.actions.contains { $0.hasPrefix("stop:") },
                       "Finished clips are free, so no capture still playing is restarted")
        XCTAssertEqual(player.liveVoiceCount, 4, "Only the two new placements and captures")
        let delay = StonePlacementSoundPlayer.captureDelay
        XCTAssertEqual(audio.voices.flatMap(\.scheduledTimes).filter { $0 < 1 }, [0.1 + delay, 0.1 + delay],
                       "Starts are still scheduled on the device's clock")
    }

    func testLiveVoicesStayBoundedWhenMovesOutpaceTheirSounds() throws {
        let audio = AudioRecorder(retainsVoices: false)
        let player = soundPlayer(audio)
        let limit = StonePlacementSoundPlayer.maximumLiveVoices
        // Every move captures, each in a newly loaded bank, and no time passes,
        // so no voice ends by itself.
        for _ in 0..<10 {
            for count in [1, 2, 4, 8] {
                player.play(move: try captureMove(count: count), theme: .standard, enabled: true)
                XCTAssertLessThanOrEqual(player.liveVoiceCount, limit)
            }
        }
        XCTAssertEqual(player.liveVoiceCount, limit)
        XCTAssertTrue(audio.actions.contains { $0.hasPrefix("stop:StoneCapture-") }, "The oldest voices stop")
        // Six placement and six cached capture clips, plus at most the live voices.
        XCTAssertLessThanOrEqual(audio.voices.count, 6 + 6 + limit)
    }

    func testResetStopsEveryLiveVoiceIncludingOnesOutlivingTheirBank() throws {
        let audio = AudioRecorder(retainsVoices: false)
        let player = soundPlayer(audio)
        for count in [1, 2, 4] {
            player.play(move: try captureMove(count: count), theme: .standard, enabled: true)
        }
        let started = audio.voices.filter { $0.plays + $0.scheduledTimes.count > 0 }
        XCTAssertTrue(started.contains { $0.name.contains("-single-") }, "Its bank has been evicted")
        XCTAssertEqual(started.count, player.liveVoiceCount)
        player.reset()
        XCTAssertTrue(started.allSatisfy { $0.stops == 1 }, "\(audio.actions)")
        XCTAssertEqual(player.liveVoiceCount, 0)
    }

    func testCaptureCacheLoadsLazilyAndRetainsOnlyTwoRecentBanks() throws {
        let audio = AudioRecorder()
        let player = soundPlayer(audio)
        for count in [1, 2, 4] {
            player.play(move: try captureMove(count: count), theme: .standard, enabled: true)
        }
        XCTAssertEqual(audio.voices.count, 6 + 3 * 3)
        player.play(move: try captureMove(count: 4), theme: .standard, enabled: true)
        XCTAssertEqual(audio.voices.count, 15, "The most recent bank should be reused")
        player.play(move: try captureMove(count: 1), theme: .standard, enabled: true)
        XCTAssertEqual(audio.voices.count, 18, "The evicted bank must be loaded again")
        let placements = audio.actions.filter { $0.hasPrefix("play:") }
        for pair in zip(placements, placements.dropFirst()) {
            XCTAssertNotEqual(pair.0, pair.1, "Do not repeat the same placement clip immediately")
        }
    }

    func testBothPrisonerDeltasAreConsideredAndCaptureOverlapIsBounded() throws {
        let audio = AudioRecorder()
        let player = soundPlayer(audio)
        let move = try captureMove(count: 1)
        move.after.captures[.white] = 8
        XCTAssertEqual(StonePlacementSoundPlayer.captures(after: move.before, in: move.after), [
            .init(color: .white, count: 1, tier: .single),
            .init(color: .black, count: 8, tier: .many)
        ])
        player.play(move: move, theme: .nightGarden, enabled: true)
        XCTAssertEqual(audio.voices.filter { !$0.scheduledTimes.isEmpty }.count, 2)
        player.reset()
        XCTAssertTrue(audio.voices.filter { !$0.scheduledTimes.isEmpty }.allSatisfy { $0.stops == 1 })
    }

    func testMissingCaptureAssetsKeepThePlacementSound() throws {
        let audio = AudioRecorder()
        let player = StonePlacementSoundPlayer { name in
            name.hasPrefix("StoneCapture-") ? nil : audio.makePlayer(name)
        }
        player.play(move: try captureMove(count: 8), theme: .standard, enabled: true)
        XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.plays }, 1)
        XCTAssertEqual(audio.voices.reduce(0) { $0 + $1.stops }, 0)
    }

    private func position(_ rows: [String]) -> BoardPosition {
        let result = BoardPosition(width: rows[0].count, height: rows.count)
        for (row, text) in rows.enumerated() {
            for (column, character) in text.enumerated() {
                if character == "b" { result.putStone(row: row, column: column, color: .black) }
                if character == "w" { result.putStone(row: row, column: column, color: .white) }
            }
        }
        result.nextToMove = .black
        return result
    }

    /// A player whose clock is the recorder's.
    private func soundPlayer(_ audio: AudioRecorder) -> StonePlacementSoundPlayer {
        StonePlacementSoundPlayer(makePlayer: audio.makePlayer, uptime: { audio.now })
    }

    /// Audio-driver fixtures isolate sequencing from the rules tests above.
    private func captureMove(count: Int) throws -> Game.AppliedMove {
        let before = BoardPosition(width: 9, height: 9)
        let after = try before.makeMove(move: .placeStone(0, 0))
        after.captures[.black] = count
        return .init(before: before, after: after)
    }

    private final class AudioRecorder {
        private struct WeakVoice {
            weak var voice: Voice?
        }

        /// The process clock, which the player times voices by.
        var now: TimeInterval = 42
        /// The audio device's clock, which schedules starts. It follows the
        /// process clock unless set, as when it restarts from zero.
        var deviceTime: TimeInterval?
        var actions: [String] = []
        private let retainsVoices: Bool
        private var retained: [Voice] = []
        private var created: [WeakVoice] = []

        /// Without retaining voices, only the player under test keeps them,
        /// and each records when it is released.
        init(retainsVoices: Bool = true) {
            self.retainsVoices = retainsVoices
        }

        /// Every voice still allocated, in the order it was made.
        var voices: [Voice] { created.compactMap(\.voice) }

        func makePlayer(_ name: String) -> StoneSoundPlaying? {
            let voice = Voice(name: name, recorder: self)
            created.append(WeakVoice(voice: voice))
            if retainsVoices { retained.append(voice) }
            return voice
        }
    }

    private final class Voice: StoneSoundPlaying {
        let name: String
        private weak var recorder: AudioRecorder?
        var currentTime: TimeInterval = 7
        var deviceCurrentTime: TimeInterval { recorder?.deviceTime ?? recorder?.now ?? 0 }
        let duration: TimeInterval
        var plays = 0
        var scheduledTimes: [TimeInterval] = []
        var stops = 0

        init(name: String, recorder: AudioRecorder) {
            self.name = name
            self.recorder = recorder
            duration = name.hasPrefix("StoneCapture-") ? 0.5 : 0.2
        }

        deinit { record("release:\(name)") }

        private func record(_ action: String) {
            recorder?.actions.append(action)
        }

        func prepareToPlay() -> Bool { true }
        func play() -> Bool {
            plays += 1
            record("play:\(name)")
            return true
        }
        func play(atTime time: TimeInterval) -> Bool {
            scheduledTimes.append(time)
            record("schedule:\(name)")
            return true
        }
        func stop() {
            stops += 1
            record("stop:\(name)")
        }
    }
}
