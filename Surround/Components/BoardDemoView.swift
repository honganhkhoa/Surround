//
//  BoardDemoView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 11/03/2021.
//

import SwiftUI
import Combine
import AVFoundation

struct BoardDemoView: View {
    @StateObject var game = Game(
        width: 19, height: 19, blackName: "Black", whiteName: "White", gameId: .OGS(-1)
    )
    var timeControl = TimeControlSystem.ByoYomi(mainTime: 20, periods: 5, periodTime: 15).timeControlObject
    @State var pendingMove: Move?
    @State var pendingPosition: BoardPosition?
    @State var simulatingRequest = false
    @State var timerCancellable: AnyCancellable?
    @Setting(.showsBoardCoordinates) var showsBoardCoordinates: Bool
    @Setting(.autoSubmitForLiveGames) var autoSubmitForLiveGames: Bool
    @Setting(.voiceCountdown) var voiceCountdown: Bool
    @Setting(.soundOnStonePlacement) var soundOnStonePlacement: Bool
    @State var speechSynthesizer: AVSpeechSynthesizer?
    @State var lastUtterance: String?
    @State var clearLastUtteranceCancellable: AnyCancellable?
    @State var stonePlacingPlayer: AVAudioPlayer?

    func initializePlayersIfNecessary() {
        if voiceCountdown && self.speechSynthesizer == nil {
            self.speechSynthesizer = AVSpeechSynthesizer()
        }
        if soundOnStonePlacement && self.stonePlacingPlayer == nil {
            if let audioData = NSDataAsset(name: "stonePlacing")?.data {
                self.stonePlacingPlayer = try? AVAudioPlayer(data: audioData)
            }
        }
    }
    
    func updateTimeAfterMove(time: inout ThinkingTime) {
        if time.thinkingTimeLeft == 0 {
            time.thinkingTime = 0
            time.periodTimeLeft = Double(timeControl.periodTime ?? 0)
            time.periods = time.periodsLeft
        } else {
            time.thinkingTime = time.thinkingTimeLeft
        }
    }
    
    func submitMove(move: Move) {
        simulatingRequest = true
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(300))) {
            do {
                try game.makeMove(move: move)
                if var clock = game.clock {
                    if clock.currentPlayerColor == .black {
                        updateTimeAfterMove(time: &clock.blackTime)
                    } else {
                        updateTimeAfterMove(time: &clock.whiteTime)
                    }
                    clock.lastMoveTime = Date().timeIntervalSince1970 * 1000
                    clock.currentPlayerColor = game.currentPosition.nextToMove
                    game.clock = clock
                }
                if let stonePlacingPlayer = stonePlacingPlayer, soundOnStonePlacement {
                    stonePlacingPlayer.play()
                }
            } catch {}
            pendingMove = nil
            pendingPosition = nil
            simulatingRequest = false
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Stone(color: .black, shadowRadius: 2)
                        .frame(width: 20, height: 20)
                    TimerView(timeControl: timeControl, clock: game.clock, player: .black)
                    if game.currentPosition.nextToMove == .black {
                        Image(systemName: "hourglass")
                    }
                }
                Spacer()
                HStack {
                    if game.currentPosition.nextToMove == .white {
                        Image(systemName: "hourglass")
                    }
                    TimerView(timeControl: timeControl, clock: game.clock, player: .white)
                    Stone(color: .white, shadowRadius: 2)
                        .frame(width: 20, height: 20)
                }
            }
            HStack {
                (Text(game.currentPosition.nextToMove == .black ? "Black to move" : "White to move"))
                    .font(.title2).bold()
                Spacer()
                if simulatingRequest {
                    ProgressView()
                } else {
                    if let move = pendingMove {
                        Button(action: { submitMove(move: move) }) {
                            Text("Submit")
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            BoardView(
                boardPosition: game.currentPosition,
                showsCoordinate: showsBoardCoordinates,
                playable: true,
                newMove: $pendingMove,
                newPosition: $pendingPosition
            )
            .aspectRatio(1, contentMode: .fit)
            .layoutPriority(1)
            Spacer().frame(height: 10)
            Text("Tap and drag to place a stone. Drag outside of the board to cancel.")
                .font(.caption)
                .leadingAlignedInScrollView()
        }
        .onAppear {
            self.initializePlayersIfNecessary()
            self.game.clock = OGSClock(
                blackTime: ThinkingTime(thinkingTime: Double(timeControl.mainTime!), thinkingTimeLeft: Double(timeControl.mainTime!), periods: timeControl.periods, periodTime: Double(timeControl.periodTime!)),
                whiteTime: ThinkingTime(thinkingTime: Double(timeControl.mainTime!), thinkingTimeLeft: Double(timeControl.mainTime!), periods: timeControl.periods, periodTime: Double(timeControl.periodTime!)),
                currentPlayerColor: .black,
                lastMoveTime: Date().timeIntervalSince1970 * 1000,
                currentPlayerId: 1, blackPlayerId: 1, whitePlayerId: 2
            )
            self.game.clock?.calculateTimeLeft(with: timeControl.system, pauseControl: nil)
            timerCancellable = TimeUtilities.shared.timer.receive(on: RunLoop.main).sink { _ in
                self.game.clock?.calculateTimeLeft(with: timeControl.system, pauseControl: nil)
                if voiceCountdown, let time = game.clock?.currentPlayerColor == .black ? game.clock?.blackTime : game.clock?.whiteTime {
                    if let timeLeft = time.timeLeft {
                        if timeLeft <= 10 {
                            let utteranceString = "\(Int(timeLeft))"
                            if utteranceString != lastUtterance {
                                lastUtterance = utteranceString
                                let utterance = AVSpeechUtterance(string: utteranceString)
                                self.speechSynthesizer?.speak(utterance)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: lastUtterance) { _ in
            if clearLastUtteranceCancellable != nil {
                clearLastUtteranceCancellable?.cancel()
            }
            clearLastUtteranceCancellable = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink(receiveValue: { _ in
                self.lastUtterance = nil
                self.clearLastUtteranceCancellable?.cancel()
                self.clearLastUtteranceCancellable = nil
            })
        }
        .onDisappear {
            self.speechSynthesizer = nil
        }
        .onChange(of: pendingMove) { move in
            if let move = move, autoSubmitForLiveGames {
                self.submitMove(move: move)
            }
        }
        .onChange(of: voiceCountdown) { _ in
            self.initializePlayersIfNecessary()
        }
    }
}

struct BoardDemoView_Previews: PreviewProvider {
    static var previews: some View {
        BoardDemoView()
            .previewLayout(.fixed(width: 300, height: 500))
    }
}
