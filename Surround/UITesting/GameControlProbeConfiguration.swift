//
//  GameControlProbeConfiguration.swift
//  Surround
//
//  Launch flags of the Debug-only toolbar-item probe, which puts a
//  placeholder in Game Detail's Active games slot (TESTING.md). Nothing
//  changes without --surround-notices-placeholder-game-control.
//

#if DEBUG
import CoreGraphics
import Foundation

/// Launch flags of the Debug-only toolbar-item probe.
struct GameControlProbeConfiguration: Equatable {
    enum Variant: String, CaseIterable {
        case chip, gestureView = "gesture-view", nativeBadge = "native-badge"
        case railTile = "rail-tile", everyGame = "every-game"
    }
    enum ParseError: Error, Equatable { case missingValue(String), unknownVariant(String), invalidSize(String) }

    var variants = Set<Variant>()
    /// Replaces every form's drawn size.
    var size: CGSize?

    func size(for form: GameActiveGamesPlacement.Form) -> CGSize {
        if let size { return size }
        switch form {
        case .bottomBar: return CGSize(width: 200, height: 48)
        case .topBar: return CGSize(width: 96, height: 44)
        case .rail: return CGSize(width: 62, height: 60)
        }
    }

    /// Nil without the probe's own flag: its other flags alone do nothing.
    static func parse(_ arguments: [String]) throws -> GameControlProbeConfiguration? {
        typealias Contract = SurroundUITestContract
        guard arguments.contains(Contract.gameControlProbeLaunchArgument) else { return nil }
        var configuration = GameControlProbeConfiguration()
        if let list = try value(after: Contract.gameControlProbeVariantLaunchArgument, in: arguments) {
            for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
            where !name.isEmpty {
                guard let variant = Variant(rawValue: name) else { throw ParseError.unknownVariant(name) }
                configuration.variants.insert(variant)
            }
        }
        if let text = try value(after: Contract.gameControlProbeSizeLaunchArgument, in: arguments) {
            configuration.size = try drawnSize(text)
        }
        return configuration
    }

    /// This launch's probe. A malformed flag stops the app, so a probe never runs half-configured.
    static let current: GameControlProbeConfiguration? = {
        do { return try parse(ProcessInfo.processInfo.arguments) }
        catch { preconditionFailure("Invalid game control probe flags: \(error)") }
    }()

    /// A flag's value is the next argument; none, or another flag, is missing.
    private static func value(after flag: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw ParseError.missingValue(flag)
        }
        return arguments[index + 1]
    }

    /// `WxH` in points, each side from 20 to 400.
    private static func drawnSize(_ text: String) throws -> CGSize {
        let sides = text.split(separator: "x", omittingEmptySubsequences: false)
        guard sides.count == 2, let width = Double(sides[0]), let height = Double(sides[1]),
              (20...400).contains(width), (20...400).contains(height) else {
            throw ParseError.invalidSize(text)
        }
        return CGSize(width: width, height: height)
    }
}

/// What the placeholder received; its popover shows the summary for UI tests.
struct GameControlProbeEvents: Equatable {
    enum Kind: String, CaseIterable {
        case tap, hold, secondaryClick = "secondary-click", accessibilityAction = "accessibility-action"
    }
    private(set) var counts: [Kind: Int] = [:]
    private(set) var last: Kind?

    mutating func record(_ kind: Kind) { counts[kind, default: 0] += 1; last = kind }

    /// "tap 1 · hold 2 · secondary-click 0 · accessibility-action 0 · last hold"
    var summary: String {
        let parts = Kind.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }
        return (parts + (last.map { ["last \($0.rawValue)"] } ?? [])).joined(separator: " · ")
    }
}
#endif
