//
//  MainThreadWatchdog.swift
//  Surround
//
//  Debug only: `--surround-main-thread-watchdog` reports each gap of 250 ms
//  or more in the main queue's work, so a run that freezes leaves a record
//  even when the app never comes back. A timer on the main queue beats every
//  100 ms; a timer on a queue of its own checks the last beat every 100 ms.
//  The lines are under subsystem com.honganhkhoa.Surround, category
//  MainThreadWatchdog:
//  - `MAIN-HANG <ms> ms at <s> s`: the main queue beat again after that
//    gap, which began that long after the watchdog started;
//  - `MAIN-HANG <ms> ms at <s> s, ongoing`: once a second while a gap lasts.
//

#if DEBUG && MAIN_APP
import Foundation
import os

enum MainThreadWatchdog {
    private static let beatMilliseconds = 100
    private static let reportedGapMilliseconds = 250
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "MainThreadWatchdog")
    /// The main queue's last beat, in uptime nanoseconds.
    private static let lastBeat = OSAllocatedUnfairLock(initialState: DispatchTime.now().uptimeNanoseconds)
    private static var timers: [DispatchSourceTimer] = []

    /// Starts once, at launch, when the launch asks for it.
    static func startIfRequested() {
        guard SurroundUITestContract.gameControlDrivers.runsMainThreadWatchdog, timers.isEmpty else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        lastBeat.withLock { $0 = started }
        let interval = DispatchTimeInterval.milliseconds(beatMilliseconds)

        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(10))
        heartbeat.setEventHandler {
            Self.lastBeat.withLock { $0 = DispatchTime.now().uptimeNanoseconds }
        }

        let checker = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.honganhkhoa.Surround.MainThreadWatchdog", qos: .userInteractive)
        )
        // Only the checker's queue reads and writes it: the beat a gap
        // began after, and the whole seconds already reported as ongoing.
        var gap: (since: UInt64, reportedSeconds: Int)?
        checker.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(10))
        checker.setEventHandler {
            let now = DispatchTime.now().uptimeNanoseconds
            let beat = Self.lastBeat.withLock { $0 }
            let milliseconds = now > beat ? Int((now - beat) / 1_000_000) : 0
            if let current = gap {
                if beat > current.since {
                    let length = Int((beat - current.since) / 1_000_000)
                    if length >= Self.reportedGapMilliseconds {
                        Self.report(length, since: current.since, started: started, ongoing: false)
                    }
                    gap = nil
                } else if milliseconds / 1_000 > current.reportedSeconds {
                    gap?.reportedSeconds = milliseconds / 1_000
                    Self.report(milliseconds, since: current.since, started: started, ongoing: true)
                }
            } else if milliseconds >= Self.reportedGapMilliseconds {
                gap = (since: beat, reportedSeconds: 0)
            }
        }

        heartbeat.resume()
        checker.resume()
        timers = [heartbeat, checker]
        log.notice("MAIN-WATCHDOG on: a beat every \(beatMilliseconds, privacy: .public) ms, gaps from \(reportedGapMilliseconds, privacy: .public) ms")
    }

    private static func report(_ milliseconds: Int, since beat: UInt64, started: UInt64, ongoing: Bool) {
        let seconds = Double(beat > started ? beat - started : 0) / 1_000_000_000
        if ongoing {
            log.notice("MAIN-HANG \(milliseconds, privacy: .public) ms at \(seconds, format: .fixed(precision: 1), privacy: .public) s, ongoing")
        } else {
            log.notice("MAIN-HANG \(milliseconds, privacy: .public) ms at \(seconds, format: .fixed(precision: 1), privacy: .public) s")
        }
    }
}
#endif
