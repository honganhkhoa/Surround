//
//  SuperchatDebugCommands.swift
//  Surround
//
//  Debug-only stand-ins for OGS's moderator superchats in offline UI-test
//  runs: Darwin notifications, a launch-time script and the Superchat
//  (Debug) menu, which every window's service hears (TESTING.md). Every
//  string is verbatim: no localization keys.
//

#if DEBUG && MAIN_APP
import Foundation
import OSLog
import SwiftUI

/// Sends `SurroundUITestContract.SuperchatCommand`s to every offline window's
/// service, as OGS sends a superchat to every open connection. Main thread
/// only, like the services.
enum SuperchatDebugCommands {
    private typealias Command = SurroundUITestContract.SuperchatCommand

    /// Held weakly: services a window's root re-made, and closed windows' services, go away.
    private struct Registration {
        weak var service: OGSService?
    }

    private static var registrations = [Registration]()
    private static var isListening = false
    private final class DarwinToken {}
    private static let darwinToken = DarwinToken()
    private static let log = Logger(subsystem: "com.honganhkhoa.Surround", category: "SuperchatDebug")

    /// Offline UI-test runs whose windows get the fixture factory's services,
    /// which register: not captures, nor the App Review presentation's root.
    static var isAvailable: Bool {
        SurroundUITestContract.isEnabled
            && !SurroundUITestContract.isCapturingAppStoreScreenshots
            && !SurroundUITestContract.isCapturingCompatibilityScreenshots
            && !SurroundUITestContract.testsAppReviewPresentation
    }

    /// Called for each offline service the fixture factory makes. The first
    /// call starts the Darwin observers and the launch-time script.
    static func register(_ service: OGSService) {
        registrations.removeAll { $0.service == nil }
        if !registrations.contains(where: { $0.service === service }) {
            registrations.append(Registration(service: service))
        }
        guard !isListening else { return }
        isListening = true
        startDarwinObservers()
        scheduleLaunchScript()
    }

    /// Runs one command in every live registered service.
    static func perform(_ command: SurroundUITestContract.SuperchatCommand) {
        registrations.removeAll { $0.service == nil }
        let services = registrations.compactMap(\.service)
        for service in services {
            switch command {
            case .start, .end, .startSecond, .endSecond:
                guard let user = service.user else { continue }
                let moderator = command == .startSecond || command == .endSecond
                    ? ActivityFixtures.Cast.secondModerator : ActivityFixtures.Cast.moderator
                service.handleSuperchat(config: ActivityFixtures.superchatPayload(
                    for: user, enable: command == .start || command == .startSecond, moderator: moderator))
            case .echo:
                guard let user = service.user else { continue }
                service.handleSuperchat(config: ActivityFixtures.superchatEchoPayload(for: user, enable: true))
            case .reconnect:
                service.simulateSuperchatReconnectForUITests()
            }
        }
        log.notice("SUPERCHAT-DEBUG \(command.scriptName, privacy: .public) services=\(services.count, privacy: .public)")
    }

    /// One observer per command. Each callback hops to the main queue.
    private static func startDarwinObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(darwinToken).toOpaque())
        for command in Command.allCases {
            CFNotificationCenterAddObserver(
                center, observer,
                { _, _, name, _, _ in
                    guard let name,
                          let command = SurroundUITestContract.SuperchatCommand(rawValue: name.rawValue as String)
                    else { return }
                    DispatchQueue.main.async {
                        SuperchatDebugCommands.perform(command)
                    }
                },
                command.rawValue as CFString, nil, .deliverImmediately
            )
        }
    }

    // MARK: The launch-time script

    private struct ScriptStep {
        let seconds: TimeInterval
        let command: SurroundUITestContract.SuperchatCommand
    }

    private struct ScriptError: Error, CustomStringConvertible {
        let description: String
    }

    /// `--surround-superchat-debug-script start@0,end@30`: each command at
    /// its second after the first registration, at launch. A malformed
    /// script stops the launch.
    private static func scheduleLaunchScript() {
        let flag = SurroundUITestContract.superchatDebugScriptLaunchArgument
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return }
        guard arguments.indices.contains(index + 1) else {
            preconditionFailure("\(flag) needs a value, such as start@0,end@30.")
        }
        let steps: [ScriptStep]
        do {
            steps = try scriptSteps(arguments[index + 1])
        } catch {
            preconditionFailure("Invalid \(flag): \(error)")
        }
        // Steps due at the same second run in the script's order.
        for (seconds, due) in Dictionary(grouping: steps, by: \.seconds) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                due.forEach { SuperchatDebugCommands.perform($0.command) }
            }
        }
        log.notice("SUPERCHAT-DEBUG script \(arguments[index + 1], privacy: .public)")
    }

    private static func scriptSteps(_ script: String) throws -> [ScriptStep] {
        let names = Command.allCases.map(\.scriptName).joined(separator: ", ")
        return try script.split(separator: ",", omittingEmptySubsequences: false).map { entry -> ScriptStep in
            let step = entry.trimmingCharacters(in: .whitespaces)
            let parts = step.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                throw ScriptError(description: "'\(step)' isn't command@seconds.")
            }
            guard let command = Command.allCases.first(where: { $0.scriptName == parts[0] }) else {
                throw ScriptError(description: "Unknown command '\(parts[0])'. Use one of: \(names).")
            }
            guard let seconds = TimeInterval(parts[1]), seconds.isFinite, seconds >= 0 else {
                throw ScriptError(description: "'\(parts[1])' in '\(step)' isn't a number of seconds from 0.")
            }
            return ScriptStep(seconds: seconds, command: command)
        }
    }
}

private extension SurroundUITestContract.SuperchatCommand {
    /// The Darwin name's last part: `start-second` in scripts and logs.
    var scriptName: String {
        rawValue.components(separatedBy: ".").last ?? rawValue
    }

    var menuTitle: String {
        switch self {
        case .start: "Start"
        case .end: "End"
        case .startSecond: "Start Second"
        case .endSecond: "End Second"
        case .echo: "Echo"
        case .reconnect: "Reconnect"
        }
    }
}

/// The Superchat (Debug) menu, on the Mac and in the iPadOS menu bar; empty
/// outside offline UI-test runs.
struct SuperchatDebugMenu: Commands {
    var body: some Commands {
        if SuperchatDebugCommands.isAvailable {
            SuperchatDebugCommandMenu(store: .shared)
        }
    }
}

private struct SuperchatDebugCommandMenu: Commands {
    /// Observed, so the Covered line also shows whether a menu that reads
    /// the store refreshes.
    @ObservedObject var store: SuperchatStore

    var body: some Commands {
        CommandMenu(Text(verbatim: "Superchat (Debug)")) {
            ForEach(SurroundUITestContract.SuperchatCommand.allCases, id: \.self) { command in
                Button { SuperchatDebugCommands.perform(command) } label: {
                    Text(verbatim: command.menuTitle)
                }
            }
            Divider()
            Button {} label: { Text(verbatim: store.covers.isEmpty ? "Not covered" : "Covered") }
                .disabled(true)
        }
    }
}
#endif
