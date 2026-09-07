//
//  OGSAutomatchEntry.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/02/2021.
//

import Foundation
import CoreFoundation

enum OGSAutomatchClockSystem: String, Codable, CaseIterable, Hashable {
    case fischer
    case byoyomi

    var alternate: OGSAutomatchClockSystem {
        self == .fischer ? .byoyomi : .fischer
    }
}

enum OGSAutomatchCondition: String, Codable, Hashable {
    case required
    case preferred
    case noPreference = "no-preference"
}

enum OGSAutomatchRuleSet: String, Codable, Hashable {
    case japanese
    case chinese
    case aga
    case korean
    case newZealand = "nz"
    case ing
}

enum OGSAutomatchHandicapValue: String, Codable, Hashable {
    case enabled
    case disabled
}

struct OGSAutomatchRulesPreference: Codable, Equatable {
    var condition: OGSAutomatchCondition
    var value: OGSAutomatchRuleSet

    static let quickMatchDefault = OGSAutomatchRulesPreference(
        condition: .required,
        value: .japanese
    )

    var jsonObject: [String: Any] {
        [
            "condition": condition.rawValue,
            "value": value.rawValue,
        ]
    }
}

struct OGSAutomatchHandicapPreference: Codable, Equatable {
    var condition: OGSAutomatchCondition
    var value: OGSAutomatchHandicapValue

    static let quickMatchDefault = OGSAutomatchHandicapPreference(
        condition: .preferred,
        value: .enabled
    )

    var jsonObject: [String: Any] {
        [
            "condition": condition.rawValue,
            "value": value.rawValue,
        ]
    }
}

struct OGSAutomatchSizeSpeedOption: Codable, Hashable {
    var size: Int
    var speed: TimeControlSpeed
    var system: OGSAutomatchClockSystem

    private enum CodingKeys: String, CodingKey {
        case size
        case speed
        case system
    }

    init(
        size: Int,
        speed: TimeControlSpeed,
        system: OGSAutomatchClockSystem
    ) {
        self.size = size
        self.speed = speed
        self.system = system
    }

    init?(
        jsonObject: [String: Any],
        fallbackSystem: OGSAutomatchClockSystem? = nil
    ) {
        guard
            let sizeString = jsonObject["size"] as? String,
            let size = Self.boardSize(from: sizeString),
            let speedString = jsonObject["speed"] as? String,
            let speed = TimeControlSpeed(rawValue: speedString)
        else {
            return nil
        }

        let system: OGSAutomatchClockSystem
        if let rawSystem = jsonObject["system"] {
            guard
                let systemString = rawSystem as? String,
                let decodedSystem = OGSAutomatchClockSystem(
                    rawValue: systemString
                )
            else {
                return nil
            }
            system = decodedSystem
        } else {
            guard let fallbackSystem else {
                return nil
            }
            system = fallbackSystem
        }

        self.init(size: size, speed: speed, system: system)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sizeString = try container.decode(String.self, forKey: .size)
        guard let size = Self.boardSize(from: sizeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .size,
                in: container,
                debugDescription: "Automatch size must be a square board such as 9x9."
            )
        }
        self.size = size
        speed = try container.decode(TimeControlSpeed.self, forKey: .speed)
        system = try container.decode(OGSAutomatchClockSystem.self, forKey: .system)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("\(size)x\(size)", forKey: .size)
        try container.encode(speed, forKey: .speed)
        try container.encode(system, forKey: .system)
    }

    var jsonObject: [String: Any] {
        [
            "size": "\(size)x\(size)",
            "speed": speed.rawValue,
            "system": system.rawValue,
        ]
    }

    private static func boardSize(from string: String) -> Int? {
        let components = string.split(separator: "x")
        guard
            components.count == 2,
            components[0] == components[1],
            let size = Int(components[0])
        else {
            return nil
        }
        return size
    }
}

/// The wire representation used by `automatch/find_match`.
///
/// The saved Quick Match form state lives in `OGSQuickMatchDraft` because a
/// server entry cannot distinguish Exact, Flexible, and Multiple selections.
struct OGSAutomatchEntry: Codable, Equatable {
    var sizeSpeedOptions: [OGSAutomatchSizeSpeedOption]
    var lowerRankDifference: Int
    var upperRankDifference: Int
    var rules: OGSAutomatchRulesPreference
    var handicap: OGSAutomatchHandicapPreference
    var uuid: String

    /// When OGS created this search, normalized from the wire timestamp to Unix
    /// epoch seconds. It is retained locally for lifecycle correlation, but is
    /// never sent in `automatch/find_match`.
    var creationTimestamp: TimeInterval?

    /// Classification metadata retained from an inbound wire entry.
    ///
    /// OGS can add a clock system before this client knows how to display it.
    /// In that case the individual option is deliberately skipped, but its
    /// recognized speed still tells us whether the request belongs under Live
    /// or Correspondence in Waiting Games.
    private var inboundSpeedClassificationHint: TimeControlSpeed?

    /// Whether inbound criteria were only partially understood. The entry is
    /// still retained so it remains cancellable, but a locked editor must not
    /// present the surviving subset as the complete server request.
    fileprivate var inboundQuickMatchDisplayWasDegraded: Bool

    private enum CodingKeys: String, CodingKey {
        case sizeSpeedOptions
        case lowerRankDifference
        case upperRankDifference
        case rules
        case handicap
        case uuid

        // Legacy UserDefaults representation.
        case sizeOptions
        case timeControlSpeed

        // Local persistence only; this is never included in `jsonObject`.
        case creationTimestamp
        case inboundSpeedClassificationHint
        case inboundQuickMatchDisplayWasDegraded
    }

    init(
        sizeSpeedOptions: [OGSAutomatchSizeSpeedOption],
        lowerRankDifference: Int = 3,
        upperRankDifference: Int = 3,
        rules: OGSAutomatchRulesPreference = .quickMatchDefault,
        handicap: OGSAutomatchHandicapPreference = .quickMatchDefault,
        uuid: String = UUID().uuidString.lowercased(),
        creationTimestamp: TimeInterval? = nil
    ) {
        self.sizeSpeedOptions = sizeSpeedOptions
        self.lowerRankDifference = lowerRankDifference
        self.upperRankDifference = upperRankDifference
        self.rules = rules
        self.handicap = handicap
        self.uuid = uuid
        self.creationTimestamp = creationTimestamp
        inboundSpeedClassificationHint = nil
        inboundQuickMatchDisplayWasDegraded = false
    }

    /// Compatibility adapter for the pre-redesign Quick Match screen.
    ///
    /// The old UI has no clock-system picker, so real-time searches include
    /// both official systems. This preserves its previous no-preference intent.
    init(
        sizeOptions: Set<Int>,
        timeControlSpeed: TimeControlSpeed,
        optionsShuffler: (inout [OGSAutomatchSizeSpeedOption]) -> Void = {
            $0.shuffle()
        }
    ) {
        let systems: [OGSAutomatchClockSystem] = timeControlSpeed == .correspondence
            ? [.fischer]
            : [.fischer, .byoyomi]
        var options = sizeOptions.sorted().flatMap { size in
            systems.map {
                OGSAutomatchSizeSpeedOption(
                    size: size,
                    speed: timeControlSpeed,
                    system: $0
                )
            }
        }
        optionsShuffler(&options)
        sizeSpeedOptions = options
        lowerRankDifference = 3
        upperRankDifference = 3
        rules = OGSAutomatchRulesPreference(
            condition: .noPreference,
            value: .japanese
        )
        handicap = timeControlSpeed == .blitz
            ? OGSAutomatchHandicapPreference(
                condition: .noPreference,
                value: .disabled
            )
            : OGSAutomatchHandicapPreference(
                condition: .noPreference,
                value: .enabled
            )
        uuid = UUID().uuidString.lowercased()
        creationTimestamp = nil
        inboundSpeedClassificationHint = nil
        inboundQuickMatchDisplayWasDegraded = false
    }

    init?(_ jsonObject: [String: Any]) {
        // The UUID is sufficient to let the user cancel a server-side search.
        // Treat the remaining, display-only metadata as independently optional
        // so new OGS enum values cannot make an active search unreachable.
        guard
            let uuid = jsonObject["uuid"] as? String,
            !uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let legacyTimeControl = jsonObject["time_control"] as? [String: Any]
        let legacyTimeControlValue = legacyTimeControl?["value"] as? [String: Any]
        let fallbackSystem = (legacyTimeControlValue?["system"] as? String)
            .flatMap(OGSAutomatchClockSystem.init(rawValue:))

        let rawOptions = jsonObject["size_speed_options"] as? [Any] ?? []
        let options = rawOptions.compactMap { rawValue -> OGSAutomatchSizeSpeedOption? in
            guard let rawOption = rawValue as? [String: Any] else {
                return nil
            }
            let optionFallback = fallbackSystem ?? {
                if rawOption["speed"] as? String == TimeControlSpeed.correspondence.rawValue {
                    return OGSAutomatchClockSystem.fischer
                }
                return OGSAutomatchClockSystem.byoyomi
            }()
            return OGSAutomatchSizeSpeedOption(
                jsonObject: rawOption,
                fallbackSystem: optionFallback
            )
        }
        // The parsed options already carry their own speed. Retain a separate
        // hint only for a fully degraded entry, where every option used a
        // future clock system and was skipped.
        let inboundSpeedClassificationHint = options.isEmpty
            ? Self.speedClassification(
                rawOptions: rawOptions,
                legacyTimeControlValue: legacyTimeControlValue
            )
            : nil

        let rawRules = jsonObject["rules"]
        let rulesObject = rawRules as? [String: Any]
        let rulesCondition = Self.enumValue(
            OGSAutomatchCondition.self,
            in: rulesObject,
            forKey: "condition",
            defaultValue: .noPreference
        )
        let ruleSet = Self.enumValue(
            OGSAutomatchRuleSet.self,
            in: rulesObject,
            forKey: "value",
            defaultValue: .japanese
        )

        let rawHandicap = jsonObject["handicap"]
        let handicapObject = rawHandicap as? [String: Any]
        let handicapCondition = Self.enumValue(
            OGSAutomatchCondition.self,
            in: handicapObject,
            forKey: "condition",
            defaultValue: .noPreference
        )
        let handicapValue = Self.enumValue(
            OGSAutomatchHandicapValue.self,
            in: handicapObject,
            forKey: "value",
            defaultValue: .enabled
        )

        self.init(
            sizeSpeedOptions: options,
            lowerRankDifference: Self.integer(
                jsonObject["lower_rank_diff"],
                defaultValue: 3
            ),
            upperRankDifference: Self.integer(
                jsonObject["upper_rank_diff"],
                defaultValue: 3
            ),
            rules: OGSAutomatchRulesPreference(
                condition: rulesCondition,
                value: ruleSet
            ),
            handicap: OGSAutomatchHandicapPreference(
                condition: handicapCondition,
                value: handicapValue
            ),
            uuid: uuid,
            creationTimestamp: Self.creationTimestamp(
                fromWireValue: jsonObject["timestamp"]
            )
        )
        self.inboundSpeedClassificationHint = inboundSpeedClassificationHint
        self.inboundQuickMatchDisplayWasDegraded =
            options.count != rawOptions.count
            || Self.inboundContainerWasDegraded(rawRules)
            || Self.inboundContainerWasDegraded(rawHandicap)
            || Self.inboundEnumWasDegraded(
                OGSAutomatchCondition.self,
                in: handicapObject,
                forKey: "condition"
            )
            || Self.inboundEnumWasDegraded(
                OGSAutomatchHandicapValue.self,
                in: handicapObject,
                forKey: "value"
            )
            || Self.inboundEnumWasDegraded(
                OGSAutomatchCondition.self,
                in: rulesObject,
                forKey: "condition"
            )
            || Self.inboundEnumWasDegraded(
                OGSAutomatchRuleSet.self,
                in: rulesObject,
                forKey: "value"
            )
            || Self.inboundIntegerWasDegraded(
                jsonObject["lower_rank_diff"]
            )
            || Self.inboundIntegerWasDegraded(
                jsonObject["upper_rank_diff"]
            )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let options = try container.decodeIfPresent(
            [OGSAutomatchSizeSpeedOption].self,
            forKey: .sizeSpeedOptions
        ) {
            sizeSpeedOptions = options
            lowerRankDifference = try container.decodeIfPresent(
                Int.self,
                forKey: .lowerRankDifference
            ) ?? 3
            upperRankDifference = try container.decodeIfPresent(
                Int.self,
                forKey: .upperRankDifference
            ) ?? 3
            rules = try container.decodeIfPresent(
                OGSAutomatchRulesPreference.self,
                forKey: .rules
            ) ?? .quickMatchDefault
            handicap = try container.decodeIfPresent(
                OGSAutomatchHandicapPreference.self,
                forKey: .handicap
            ) ?? .quickMatchDefault
            uuid = try container.decode(String.self, forKey: .uuid)
            creationTimestamp = try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .creationTimestamp
            )
            inboundSpeedClassificationHint = try container.decodeIfPresent(
                TimeControlSpeed.self,
                forKey: .inboundSpeedClassificationHint
            )
            inboundQuickMatchDisplayWasDegraded = try container
                .decodeIfPresent(
                    Bool.self,
                    forKey: .inboundQuickMatchDisplayWasDegraded
                ) ?? false
            return
        }

        let legacySizes = try container.decode(Set<Int>.self, forKey: .sizeOptions)
        let legacySpeed = try container.decode(
            TimeControlSpeed.self,
            forKey: .timeControlSpeed
        )
        let legacySystem: OGSAutomatchClockSystem = legacySpeed == .correspondence
            ? .fischer
            : .byoyomi
        sizeSpeedOptions = legacySizes.sorted().map {
            OGSAutomatchSizeSpeedOption(
                size: $0,
                speed: legacySpeed,
                system: legacySystem
            )
        }
        lowerRankDifference = 3
        upperRankDifference = 3
        rules = OGSAutomatchRulesPreference(
            condition: .noPreference,
            value: .japanese
        )
        handicap = OGSAutomatchHandicapPreference(
            condition: .noPreference,
            value: legacySpeed == .blitz ? .disabled : .enabled
        )
        uuid = try container.decode(String.self, forKey: .uuid)
        creationTimestamp = nil
        inboundSpeedClassificationHint = nil
        inboundQuickMatchDisplayWasDegraded = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sizeSpeedOptions, forKey: .sizeSpeedOptions)
        try container.encode(lowerRankDifference, forKey: .lowerRankDifference)
        try container.encode(upperRankDifference, forKey: .upperRankDifference)
        try container.encode(rules, forKey: .rules)
        try container.encode(handicap, forKey: .handicap)
        try container.encode(uuid, forKey: .uuid)
        try container.encodeIfPresent(
            creationTimestamp,
            forKey: .creationTimestamp
        )
        try container.encodeIfPresent(
            inboundSpeedClassificationHint,
            forKey: .inboundSpeedClassificationHint
        )
        if inboundQuickMatchDisplayWasDegraded {
            try container.encode(
                true,
                forKey: .inboundQuickMatchDisplayWasDegraded
            )
        }

        // Keep the active legacy key readable by older app versions. Their
        // synthesized decoder ignores the richer keys above.
        try container.encode(sizeOptions, forKey: .sizeOptions)
        try container.encode(timeControlSpeed, forKey: .timeControlSpeed)
    }

    var sizeOptions: Set<Int> {
        Set(sizeSpeedOptions.map(\.size))
    }

    var timeControlSpeed: TimeControlSpeed {
        if let inboundSpeedClassificationHint {
            return inboundSpeedClassificationHint
        }
        let speeds = Set(sizeSpeedOptions.map(\.speed))
        return speeds.count == 1 ? speeds.first! : .live
    }

    var isCorrespondence: Bool {
        timeControlSpeed == .correspondence
    }

    /// Whether every inbound setting was decoded and is safe to summarize.
    var quickMatchDisplayIsComplete: Bool {
        !inboundQuickMatchDisplayWasDegraded
    }

    var jsonObject: [String: Any] {
        [
            "uuid": uuid,
            "size_speed_options": sizeSpeedOptions.map(\.jsonObject),
            "lower_rank_diff": lowerRankDifference,
            "upper_rank_diff": upperRankDifference,
            "rules": rules.jsonObject,
            "handicap": handicap.jsonObject,
        ]
    }

    private static func integer(_ value: Any?, defaultValue: Int) -> Int {
        guard let number = numericValue(value) else { return defaultValue }
        let double = number.doubleValue
        let integer = number.int64Value
        guard
            double.isFinite,
            double.rounded(.towardZero) == double,
            Double(integer) == double,
            integer >= Int64(Int.min),
            integer <= Int64(Int.max)
        else {
            return defaultValue
        }
        return Int(integer)
    }

    private static func creationTimestamp(
        fromWireValue value: Any?
    ) -> TimeInterval? {
        guard var timestamp = numericValue(value)?.doubleValue,
              timestamp.isFinite,
              timestamp > 0 else {
            return nil
        }
        while timestamp > 10_000_000_000 {
            timestamp /= 1_000
        }
        return timestamp
    }

    private static func numericValue(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }

    private static func speedClassification(
        rawOptions: [Any],
        legacyTimeControlValue: [String: Any]?
    ) -> TimeControlSpeed? {
        var speeds = Set(
            rawOptions.compactMap { rawValue -> TimeControlSpeed? in
                guard
                    let rawOption = rawValue as? [String: Any],
                    let rawSpeed = rawOption["speed"] as? String
                else {
                    return nil
                }
                return TimeControlSpeed(rawValue: rawSpeed)
            }
        )
        if speeds.isEmpty,
           let rawSpeed = legacyTimeControlValue?["speed"] as? String,
           let speed = TimeControlSpeed(rawValue: rawSpeed) {
            speeds.insert(speed)
        }
        guard !speeds.isEmpty else { return nil }
        return speeds.count == 1 ? speeds.first : .live
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        in object: [String: Any]?,
        forKey key: String,
        defaultValue: Value
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard
            let stringValue = object?[key] as? String,
            let value = Value(rawValue: stringValue)
        else {
            return defaultValue
        }
        return value
    }

    private static func inboundEnumWasDegraded<Value>(
        _ type: Value.Type,
        in object: [String: Any]?,
        forKey key: String
    ) -> Bool where Value: RawRepresentable, Value.RawValue == String {
        // A missing whole container is valid legacy data. Once the container
        // is present, however, both nested fields are required for a complete
        // display of the server-side request.
        guard let object else { return false }
        guard let rawValue = object[key] else { return true }
        guard let stringValue = rawValue as? String else { return true }
        return Value(rawValue: stringValue) == nil
    }

    private static func inboundContainerWasDegraded(_ value: Any?) -> Bool {
        guard let value else { return false }
        return !(value is [String: Any])
    }

    private static func inboundIntegerWasDegraded(_ value: Any?) -> Bool {
        guard let value else { return false }
        guard let number = numericValue(value) else { return true }
        let double = number.doubleValue
        let integer = number.int64Value
        return !double.isFinite
            || double.rounded(.towardZero) != double
            || Double(integer) != double
            || integer < Int64(Int.min)
            || integer > Int64(Int.max)
    }
}

struct OGSQuickMatchClockPreset: Equatable {
    let boardSize: Int
    let speed: TimeControlSpeed
    let system: OGSAutomatchClockSystem
    let timeControl: TimeControlSystem
    let estimatedGameDuration: Int?

    static let supportedBoardSizes = [9, 13, 19]

    static func presets(for boardSize: Int) -> [OGSQuickMatchClockPreset] {
        var result = [OGSQuickMatchClockPreset]()
        for speed in [TimeControlSpeed.blitz, .rapid, .live] {
            for system in OGSAutomatchClockSystem.allCases {
                if let preset = preset(
                    boardSize: boardSize,
                    speed: speed,
                    system: system
                ) {
                    result.append(preset)
                }
            }
        }
        if let correspondence = preset(
            boardSize: boardSize,
            speed: .correspondence,
            system: .fischer
        ) {
            result.append(correspondence)
        }
        return result
    }

    static func preset(
        boardSize: Int,
        speed: TimeControlSpeed,
        system: OGSAutomatchClockSystem
    ) -> OGSQuickMatchClockPreset? {
        guard supportedBoardSizes.contains(boardSize) else {
            return nil
        }

        let duration: Int?
        switch (boardSize, speed) {
        case (9, .blitz): duration = 5 * 60
        case (9, .rapid): duration = 10 * 60
        case (9, .live): duration = 15 * 60
        case (13, .blitz): duration = 10 * 60
        case (13, .rapid): duration = 20 * 60
        case (13, .live): duration = 30 * 60
        case (19, .blitz): duration = 15 * 60
        case (19, .rapid): duration = 25 * 60
        case (19, .live): duration = 40 * 60
        case (_, .correspondence): duration = nil
        default: return nil
        }

        let timeControl: TimeControlSystem
        switch (speed, system) {
        case (.blitz, .fischer):
            timeControl = .Fischer(
                initialTime: 30,
                timeIncrement: 5,
                maxTime: 300
            )
        case (.blitz, .byoyomi):
            timeControl = .ByoYomi(
                mainTime: 30,
                periods: 5,
                periodTime: 10
            )
        case (.rapid, .fischer):
            let initialTime = [9: 120, 13: 180, 19: 300][boardSize]!
            let maxTime = [9: 1200, 13: 1800, 19: 3000][boardSize]!
            timeControl = .Fischer(
                initialTime: initialTime,
                timeIncrement: 7,
                maxTime: maxTime
            )
        case (.rapid, .byoyomi):
            let mainTime = [9: 120, 13: 180, 19: 300][boardSize]!
            timeControl = .ByoYomi(
                mainTime: mainTime,
                periods: 5,
                periodTime: 30
            )
        case (.live, .fischer):
            let initialTime = [9: 180, 13: 300, 19: 600][boardSize]!
            let maxTime = [9: 1800, 13: 1800, 19: 3600][boardSize]!
            timeControl = .Fischer(
                initialTime: initialTime,
                timeIncrement: 10,
                maxTime: maxTime
            )
        case (.live, .byoyomi):
            let mainTime = [9: 300, 13: 600, 19: 1200][boardSize]!
            timeControl = .ByoYomi(
                mainTime: mainTime,
                periods: 5,
                periodTime: 30
            )
        case (.correspondence, .fischer):
            timeControl = .Fischer(
                initialTime: 3 * 86400,
                timeIncrement: 86400,
                maxTime: 7 * 86400
            )
        case (.correspondence, .byoyomi):
            return nil
        }

        return OGSQuickMatchClockPreset(
            boardSize: boardSize,
            speed: speed,
            system: system,
            timeControl: timeControl,
            estimatedGameDuration: duration
        )
    }
}

enum OGSQuickMatchMode: String, Codable, CaseIterable, Hashable {
    case exact
    case flexible
    case multiple
}

enum OGSQuickMatchHandicapPreference: String, Codable, CaseIterable, Hashable {
    case required
    case standard
    case disabled

    var automatchPreference: OGSAutomatchHandicapPreference {
        switch self {
        case .required:
            return OGSAutomatchHandicapPreference(
                condition: .required,
                value: .enabled
            )
        case .standard:
            return .quickMatchDefault
        case .disabled:
            return OGSAutomatchHandicapPreference(
                condition: .required,
                value: .disabled
            )
        }
    }
}

struct OGSQuickMatchClockSelection: Codable, Hashable {
    var speed: TimeControlSpeed
    var system: OGSAutomatchClockSystem

    static let allRealtime: [OGSQuickMatchClockSelection] = [
        OGSQuickMatchClockSelection(speed: .blitz, system: .fischer),
        OGSQuickMatchClockSelection(speed: .blitz, system: .byoyomi),
        OGSQuickMatchClockSelection(speed: .rapid, system: .fischer),
        OGSQuickMatchClockSelection(speed: .rapid, system: .byoyomi),
        OGSQuickMatchClockSelection(speed: .live, system: .fischer),
        OGSQuickMatchClockSelection(speed: .live, system: .byoyomi),
    ]

    static let allSupported = allRealtime + [
        OGSQuickMatchClockSelection(speed: .correspondence, system: .fischer),
    ]

    fileprivate var sortIndex: Int {
        Self.allSupported.firstIndex(of: self) ?? Int.max
    }
}

extension OGSQuickMatchHandicapPreference {
    func quickMatchSummary(locale: Locale = .current) -> String {
        switch self {
        case .required:
            return String(localized: "Handicap required", locale: locale)
        case .standard:
            return String(localized: "Handicap allowed", locale: locale)
        case .disabled:
            return String(
                localized: "quickMatch.noHandicap",
                defaultValue: "No handicap",
                locale: locale,
                comment: "Quick Match recap: handicap games are not allowed"
            )
        }
    }
}

extension OGSAutomatchClockSystem {
    var quickMatchTitle: String {
        switch self {
        case .fischer:
            return String(localized: "Fischer")
        case .byoyomi:
            return String(localized: "Byo-Yomi")
        }
    }
}

extension TimeControlSpeed {
    /// Quick Match distinguishes Rapid from Live even though the rest of the
    /// app intentionally groups both values under `localizedString()`.
    var quickMatchTitle: String {
        switch self {
        case .blitz:
            return String(localized: "Blitz")
        case .rapid:
            return String(localized: "Rapid")
        case .live:
            return String(
                localized: "quickMatch.speed.live",
                defaultValue: "Live",
                comment: "Individual Quick Match speed, slower than Blitz and Rapid. Distinguish it from the Real-time category; Live remains the English name."
            )
        case .correspondence:
            return String(localized: "Correspondence")
        }
    }

    var quickMatchSystemImage: String {
        switch self {
        case .blitz:
            return "bolt"
        case .rapid:
            return "hare"
        case .live:
            return "clock"
        case .correspondence:
            return "calendar"
        }
    }
}

extension OGSQuickMatchClockPreset {
    var quickMatchShortDescription: String {
        switch timeControl {
        case .Fischer(let initialTime, let timeIncrement, _):
            return "\(durationString(seconds: initialTime)) + \(durationString(seconds: timeIncrement))"
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return "\(durationString(seconds: mainTime)) + \(periods)×\(durationString(seconds: periodTime))"
        default:
            return timeControl.shortDescription
        }
    }


}


/// Persisted Quick Match form state. It intentionally excludes submission UUIDs.
struct OGSQuickMatchDraft: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: OGSQuickMatchMode
    var boardSize: Int
    var speed: TimeControlSpeed
    var system: OGSAutomatchClockSystem
    var multipleBoardSizes: Set<Int>
    var multipleClocks: Set<OGSQuickMatchClockSelection>
    var handicap: OGSQuickMatchHandicapPreference
    var lowerRankDifference: Int
    var upperRankDifference: Int

    static var ogsDefault: OGSQuickMatchDraft {
        OGSQuickMatchDraft()
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        mode: OGSQuickMatchMode = .flexible,
        boardSize: Int = 9,
        speed: TimeControlSpeed = .rapid,
        system: OGSAutomatchClockSystem = .fischer,
        multipleBoardSizes: Set<Int> = [],
        multipleClocks: Set<OGSQuickMatchClockSelection> = [],
        handicap: OGSQuickMatchHandicapPreference = .standard,
        lowerRankDifference: Int = 3,
        upperRankDifference: Int = 3
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.boardSize = boardSize
        self.speed = speed
        self.system = system
        self.multipleBoardSizes = multipleBoardSizes
        self.multipleClocks = multipleClocks
        self.handicap = handicap
        self.lowerRankDifference = lowerRankDifference
        self.upperRankDifference = upperRankDifference
    }

    init(migrating legacyEntry: OGSAutomatchEntry) {
        let validSizes = legacyEntry.sizeOptions.intersection(
            Set(OGSQuickMatchClockPreset.supportedBoardSizes)
        )
        let migratedBoardSize = validSizes.max() ?? 9
        let migratedSpeed = legacyEntry.sizeSpeedOptions.first?.speed ?? .rapid
        let migratedSystem: OGSAutomatchClockSystem
        if migratedSpeed == .correspondence {
            migratedSystem = .fischer
        } else if legacyEntry.sizeSpeedOptions.contains(where: {
            $0.size == migratedBoardSize
                && $0.speed == migratedSpeed
                && $0.system == .byoyomi
        }) {
            migratedSystem = .byoyomi
        } else {
            migratedSystem = legacyEntry.sizeSpeedOptions.first?.system ?? .fischer
        }

        var migratedClocks = Set(
            legacyEntry.sizeSpeedOptions.compactMap { option in
                let clock = OGSQuickMatchClockSelection(
                    speed: option.speed,
                    system: option.system
                )
                return OGSQuickMatchClockSelection.allSupported.contains(clock)
                    ? clock : nil
            }
        )
        if migratedSpeed.isRealtime {
            migratedClocks.insert(
                OGSQuickMatchClockSelection(
                    speed: migratedSpeed,
                    system: migratedSystem
                )
            )
            migratedClocks.insert(
                OGSQuickMatchClockSelection(
                    speed: migratedSpeed,
                    system: migratedSystem.alternate
                )
            )
        }
        if migratedClocks.isEmpty {
            migratedClocks.insert(
                OGSQuickMatchClockSelection(
                    speed: migratedSpeed,
                    system: migratedSystem
                )
            )
        }

        let migratedHandicap: OGSQuickMatchHandicapPreference
        switch (
            legacyEntry.handicap.condition,
            legacyEntry.handicap.value
        ) {
        case (_, .disabled): migratedHandicap = .disabled
        case (.required, .enabled): migratedHandicap = .required
        default: migratedHandicap = .standard
        }

        self.init(
            mode: validSizes.count > 1 ? .multiple : .flexible,
            boardSize: migratedBoardSize,
            speed: migratedSpeed,
            system: migratedSystem,
            multipleBoardSizes: validSizes,
            multipleClocks: migratedClocks,
            handicap: migratedHandicap,
            lowerRankDifference: Self.clampedRankDifference(
                legacyEntry.lowerRankDifference
            ),
            upperRankDifference: Self.clampedRankDifference(
                legacyEntry.upperRankDifference
            )
        )
    }

    /// Shuffle every set of accepted alternatives so neither clock is preferred.
    func makeAutomatchEntry(
        uuid: String = UUID().uuidString.lowercased(),
        multipleOptionsShuffler: (inout [OGSAutomatchSizeSpeedOption]) -> Void = {
            $0.shuffle()
        }
    ) -> OGSAutomatchEntry {
        var options: [OGSAutomatchSizeSpeedOption]
        let primarySize = normalizedBoardSize
        let primarySystem: OGSAutomatchClockSystem = speed == .correspondence
            ? .fischer
            : system

        switch mode {
        case .exact:
            options = [
                OGSAutomatchSizeSpeedOption(
                    size: primarySize,
                    speed: speed,
                    system: primarySystem
                ),
            ]
        case .flexible:
            options = [
                OGSAutomatchSizeSpeedOption(
                    size: primarySize,
                    speed: speed,
                    system: primarySystem
                ),
            ]
            if speed.isRealtime {
                options.append(
                    OGSAutomatchSizeSpeedOption(
                        size: primarySize,
                        speed: speed,
                        system: primarySystem.alternate
                    )
                )
            }
            multipleOptionsShuffler(&options)
        case .multiple:
            let sizes = normalizedMultipleBoardSizes
            let clocks = normalizedMultipleClocks
            options = sizes.flatMap { size in
                clocks.map { clock in
                    OGSAutomatchSizeSpeedOption(
                        size: size,
                        speed: clock.speed,
                        system: clock.system
                    )
                }
            }
            multipleOptionsShuffler(&options)
        }

        return OGSAutomatchEntry(
            sizeSpeedOptions: options,
            lowerRankDifference: Self.clampedRankDifference(lowerRankDifference),
            upperRankDifference: Self.clampedRankDifference(upperRankDifference),
            rules: .quickMatchDefault,
            handicap: handicap.automatchPreference,
            uuid: uuid.lowercased()
        )
    }

    private var normalizedBoardSize: Int {
        OGSQuickMatchClockPreset.supportedBoardSizes.contains(boardSize)
            ? boardSize
            : 9
    }

    private var normalizedMultipleBoardSizes: [Int] {
        let validSizes = multipleBoardSizes.intersection(
            Set(OGSQuickMatchClockPreset.supportedBoardSizes)
        )
        return (validSizes.isEmpty ? [normalizedBoardSize] : Array(validSizes))
            .sorted()
    }

    private var normalizedMultipleClocks: [OGSQuickMatchClockSelection] {
        let validClocks = multipleClocks.intersection(
            Set(OGSQuickMatchClockSelection.allSupported)
        )
        if validClocks.isEmpty {
            return [
                OGSQuickMatchClockSelection(
                    speed: speed,
                    system: speed == .correspondence ? .fischer : system
                ),
            ]
        }
        return validClocks.sorted { $0.sortIndex < $1.sortIndex }
    }

    private static func clampedRankDifference(_ value: Int) -> Int {
        min(max(value, 0), 9)
    }
}

extension OGSQuickMatchDraft {
    /// Whether this draft can create another request while a correspondence
    /// search is already active. Multiple board sizes may share the single
    /// correspondence clock, independently of the last primary speed.
    var quickMatchIsCorrespondenceOnly: Bool {
        switch mode {
        case .exact, .flexible:
            return speed == .correspondence
        case .multiple:
            let clocks = multipleClocks.intersection(
                Set(OGSQuickMatchClockSelection.allSupported)
            )
            return !clocks.isEmpty && clocks.allSatisfy {
                $0.speed == .correspondence
            }
        }
    }
}

/// A Waiting Games summary of the exact criteria OGS is matching.
///
/// Unlike the locked Quick Match editor projection below, this projection can
/// represent older known preferences and arbitrary size/clock tuple pairings.
/// It only rejects entries whose wire data was degraded or whose surviving
/// values cannot be displayed truthfully.
struct AutomatchEntryPresentation: Equatable {
    /// This is a numeric-safety limit, not OGS's current product limit. The
    /// editor currently offers 0...9, while restored server entries may use a
    /// wider future range and should remain truthfully displayable.
    private static let maximumSafelyDisplayableRankDifference = Int.max / 2

    let boardAndSpeed: String
    let clockLines: [String]
    let rankRange: String
    let handicap: String
    let rules: String?

    init?(
        entry: OGSAutomatchEntry,
        userRank: Double?,
        locale: Locale = .current
    ) {
        let options = entry.sizeSpeedOptions
        let supportedSizes = Set(OGSQuickMatchClockPreset.supportedBoardSizes)
        guard entry.quickMatchDisplayIsComplete,
              (0...Self.maximumSafelyDisplayableRankDifference)
                .contains(entry.lowerRankDifference),
              (0...Self.maximumSafelyDisplayableRankDifference)
                .contains(entry.upperRankDifference),
              !options.isEmpty,
              options.allSatisfy({ option in
                  supportedSizes.contains(option.size)
                      && OGSQuickMatchClockPreset.preset(
                          boardSize: option.size,
                          speed: option.speed,
                          system: option.system
                      ) != nil
              }) else {
            return nil
        }

        let allSizes = Set(options.map(\.size))
        let sizes = allSizes.sorted()
        let speeds = Self.sortedSpeeds(Set(options.map(\.speed)))
        let sizeText = Self.localizedList(
            sizes.map { "\($0)×\($0)" },
            locale: locale
        )
        let speedText = Self.localizedList(
            speeds.map(\.quickMatchTitle),
            locale: locale
        )
        boardAndSpeed = sizes.count == 1 && speeds.count == 1
            ? String(
                localized: "\(sizeText) \(speedText)",
                locale: locale,
                comment: "Board size followed by game speed in a waiting Quick Match request."
            )
            : String(
                localized: "\(sizeText) · \(speedText)",
                locale: locale,
                comment: "Board sizes followed by game speeds in a waiting Quick Match request."
            )

        let groups = speeds.flatMap { speed -> [ClockSummaryGroup] in
            let optionsBySize = Dictionary(
                grouping: options.filter { $0.speed == speed },
                by: \.size
            )
            var sizesBySystems = [Set<OGSAutomatchClockSystem>: [Int]]()
            for (size, sizeOptions) in optionsBySize {
                sizesBySystems[Set(sizeOptions.map(\.system)), default: []].append(size)
            }
            return sizesBySystems.map { systems, matchingSizes in
                ClockSummaryGroup(
                    sizes: matchingSizes.sorted(),
                    speed: speed,
                    systems: systems
                )
            }
            .sorted { $0.sizes[0] < $1.sizes[0] }
        }
        if let first = groups.first,
           groups.allSatisfy({ $0.sizes == sizes && $0.systems == first.systems }) {
            clockLines = [Self.clockSystemSummary(first.systems, locale: locale)]
        } else {
            clockLines = groups.map { group in
                [
                    group.sizes == sizes ? nil : Self.localizedList(
                        group.sizes.map { "\($0)×\($0)" },
                        locale: locale
                    ),
                    speeds.count > 1 ? group.speed.quickMatchTitle : nil,
                    Self.clockSystemSummary(group.systems, locale: locale),
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            }
        }

        if let userRank {
            let lower = RankUtils.formattedRank(
                userRank - Double(entry.lowerRankDifference),
                longFormat: true
            )
            let upper = RankUtils.formattedRank(
                userRank + Double(entry.upperRankDifference),
                longFormat: true
            )
            rankRange = String(
                localized: "\(lower) - \(upper)",
                locale: locale,
                comment: "Lowest and highest opponent ranks accepted by a Quick Match request."
            )
        } else {
            rankRange = String(
                localized: "\(entry.lowerRankDifference) ranks below to \(entry.upperRankDifference) ranks above",
                locale: locale
            )
        }

        switch (entry.handicap.condition, entry.handicap.value) {
        case (.required, .enabled):
            handicap = OGSQuickMatchHandicapPreference.required.quickMatchSummary(locale: locale)
        case (.preferred, .enabled):
            handicap = OGSQuickMatchHandicapPreference.standard.quickMatchSummary(locale: locale)
        case (.required, .disabled):
            handicap = OGSQuickMatchHandicapPreference.disabled.quickMatchSummary(locale: locale)
        case (.preferred, .disabled):
            handicap = String(
                localized: "No handicap preferred: Accept games with or without handicap stones.",
                locale: locale,
                comment: "A waiting Quick Match request prefers an even game but accepts either handicap setting."
            )
        case (.noPreference, .enabled), (.noPreference, .disabled):
            handicap = String(
                localized: "No preference: Accept any handicap setting.",
                locale: locale,
                comment: "Fallback handicap description for an active Quick Match request without a recognized preference."
            )
        }

        if entry.rules == .quickMatchDefault {
            rules = nil
        } else {
            let ruleSet = Self.ruleSetTitle(entry.rules.value, locale: locale)
            switch entry.rules.condition {
            case .required:
                rules = String(
                    localized: "Rules: \(ruleSet)",
                    locale: locale,
                    comment: "Ruleset required by a waiting Quick Match request."
                )
            case .preferred:
                rules = String(
                    localized: "Preferred rules: \(ruleSet)",
                    locale: locale,
                    comment: "Ruleset preferred, but not required, by a waiting Quick Match request."
                )
            case .noPreference:
                rules = String(
                    localized: "No rules preference",
                    locale: locale,
                    comment: "A waiting Quick Match request accepts any supported ruleset."
                )
            }
        }
    }

    private struct ClockSummaryGroup {
        let sizes: [Int]
        let speed: TimeControlSpeed
        let systems: Set<OGSAutomatchClockSystem>
    }

    private static func clockSystemSummary(
        _ systems: Set<OGSAutomatchClockSystem>,
        locale: Locale
    ) -> String {
        if systems.count == 2 {
            return String(localized: "Fischer or Byo-Yomi", locale: locale)
        }
        return systems.contains(.fischer)
            ? String(localized: "Fischer", locale: locale)
            : String(localized: "Byo-Yomi", locale: locale)
    }

    private static func ruleSetTitle(
        _ ruleSet: OGSAutomatchRuleSet,
        locale: Locale
    ) -> String {
        switch ruleSet {
        case .japanese:
            return String(localized: "Japanese", locale: locale, comment: "rules name")
        case .chinese:
            return String(localized: "Chinese", locale: locale, comment: "rules name")
        case .aga:
            return String(localized: "AGA", locale: locale, comment: "rules name")
        case .korean:
            return String(localized: "Korean", locale: locale, comment: "rules name")
        case .newZealand:
            return String(localized: "New Zealand", locale: locale, comment: "rules name")
        case .ing:
            return String(localized: "Ing SST", locale: locale, comment: "rules name")
        }
    }

    private static func localizedList(
        _ values: [String],
        locale: Locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    private static func sortedSpeeds(
        _ speeds: Set<TimeControlSpeed>
    ) -> [TimeControlSpeed] {
        let order: [TimeControlSpeed] = [
            .blitz, .rapid, .live, .correspondence,
        ]
        return speeds.sorted {
            (order.firstIndex(of: $0) ?? .max)
                < (order.firstIndex(of: $1) ?? .max)
        }
    }


}

/// A read-only projection of the criteria OGS is actively matching.
///
/// This is intentionally separate from the persisted editor draft: an entry
/// restored after reconnect, or created by another client, may not match the
/// user's last local selections. It also must not use the legacy migration
/// initializer, which deliberately broadens a one-clock entry for editing.
struct OGSActiveQuickMatchPresentation: Equatable {
    let draft: OGSQuickMatchDraft

    init?(entry: OGSAutomatchEntry) {
        let options = entry.sizeSpeedOptions
        let supportedSizes = Set(OGSQuickMatchClockPreset.supportedBoardSizes)
        guard entry.quickMatchDisplayIsComplete,
              entry.rules == .quickMatchDefault,
              (0...9).contains(entry.lowerRankDifference),
              (0...9).contains(entry.upperRankDifference),
              let preferred = options.first,
              options.allSatisfy({ option in
                  supportedSizes.contains(option.size)
                      && OGSQuickMatchClockPreset.preset(
                          boardSize: option.size,
                          speed: option.speed,
                          system: option.system
                      ) != nil
              }) else {
            return nil
        }

        let distinctOptions = Set(options)
        let boardSizes = Set(options.map(\.size))
        let clocks = Set(options.map {
            OGSQuickMatchClockSelection(speed: $0.speed, system: $0.system)
        })
        let speeds = Set(clocks.map(\.speed))
        let systems = Set(clocks.map(\.system))

        let mode: OGSQuickMatchMode
        if distinctOptions.count == 1 {
            mode = .exact
        } else if boardSizes.count == 1,
                  clocks.count == 2,
                  speeds.count == 1,
                  preferred.speed.isRealtime,
                  systems == Set(OGSAutomatchClockSystem.allCases) {
            mode = .flexible
        } else {
            // Multiple exposes the board-size/clock Cartesian product. Reject
            // arbitrary pairings instead of displaying broader criteria than
            // the server is actually matching.
            let representedOptions = Set(boardSizes.flatMap { size in
                clocks.map { clock in
                    OGSAutomatchSizeSpeedOption(
                        size: size,
                        speed: clock.speed,
                        system: clock.system
                    )
                }
            })
            let hasCompatibleSpeeds = clocks.allSatisfy { $0.speed.isRealtime }
                || clocks.allSatisfy { $0.speed == .correspondence }
            guard hasCompatibleSpeeds,
                  distinctOptions == representedOptions else {
                return nil
            }
            mode = .multiple
        }

        let handicap: OGSQuickMatchHandicapPreference
        switch (entry.handicap.condition, entry.handicap.value) {
        case (.required, .enabled):
            handicap = .required
        case (.preferred, .enabled):
            handicap = .standard
        case (.required, .disabled):
            handicap = .disabled
        default:
            return nil
        }

        draft = OGSQuickMatchDraft(
            mode: mode,
            boardSize: preferred.size,
            speed: preferred.speed,
            system: preferred.system,
            multipleBoardSizes: boardSizes,
            multipleClocks: clocks,
            handicap: handicap,
            lowerRankDifference: entry.lowerRankDifference,
            upperRankDifference: entry.upperRankDifference
        )
    }
}

/// A send is only queued when `findAutomatch` returns. Keep each batch member
/// pending until OGS echoes it or reports a terminal result, including the
/// service's bounded reconciliation result for an unanswered request.
struct QuickMatchSubmissionState: Equatable {
    private(set) var pendingEntryIDs = Set<String>()

    var isSubmitting: Bool { !pendingEntryIDs.isEmpty }

    mutating func begin(
        entryIDs: [String],
        retryingFailedEntries: Bool = false
    ) -> Bool {
        let ids = Set(entryIDs)
        guard !ids.isEmpty,
              retryingFailedEntries || !isSubmitting,
              pendingEntryIDs.isDisjoint(with: ids) else { return false }
        pendingEntryIDs.formUnion(ids)
        return true
    }

    mutating func finish(uuid: String) {
        pendingEntryIDs.remove(uuid)
    }

    mutating func handle(_ event: OGSAutomatchLifecycleEvent.Kind) {
        switch event {
        case .entry(let uuid), .started(let uuid, _, _),
             .notFoundAfterReconciliation(let uuid):
            finish(uuid: uuid)
        case .cancelled(let uuid, _):
            if let uuid {
                finish(uuid: uuid)
            } else {
                pendingEntryIDs.removeAll()
            }
        }
    }
}

struct QuickMatchRequestFailure: Identifiable, Equatable {
    enum Operation: Equatable {
        case start
        case cancel
        case cancelTimedOut
    }

    let operation: Operation
    let entry: OGSAutomatchEntry

    var id: String {
        "\(entry.uuid)-\(String(describing: operation))"
    }

    var isCancellationFailure: Bool {
        switch operation {
        case .cancel, .cancelTimedOut:
            return true
        case .start:
            return false
        }
    }

    /// Applies a server terminal event to an alert without clearing an
    /// unrelated request failure.
    func retainedAfterCancellationTerminal(uuid: String?) -> Self? {
        guard isCancellationFailure,
              uuid == nil || entry.uuid == uuid else {
            return self
        }
        return nil
    }

    func canRetryCancellation(activeEntryIDs: Set<String>) -> Bool {
        isCancellationFailure && activeEntryIDs.contains(entry.uuid)
    }
}

extension UserDefaults {
    /// Loads the new draft first, then performs a one-time copy migration from
    /// the legacy entry. The legacy key is retained for downgrade safety.
    func loadQuickMatchDraft() -> OGSQuickMatchDraft {
        let draftKey = SettingKey<OGSQuickMatchDraft>.lastQuickMatchDraft
        if object(forKey: draftKey.name) != nil {
            guard
                let draft = self[draftKey],
                draft.schemaVersion == OGSQuickMatchDraft.currentSchemaVersion
            else {
                // Preserve corrupt or newer bytes rather than replacing data
                // that a future app version may still understand.
                return .ogsDefault
            }
            return draft
        }
        if let legacyEntry = self[.lastAutomatchEntry] {
            let draft = OGSQuickMatchDraft(migrating: legacyEntry)
            self[.lastQuickMatchDraft] = draft
            return draft
        }
        return .ogsDefault
    }
}

extension OGSAutomatchEntry {
    static var sampleEntry: OGSAutomatchEntry {
        let data = #"""
            {
              "uuid": "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d0",
              "size_speed_options": [
                {
                  "size": "9x9",
                  "speed": "live",
                  "system": "fischer"
                },
                {
                  "size": "13x13",
                  "speed": "live",
                  "system": "byoyomi"
                }
              ],
              "lower_rank_diff": 3,
              "upper_rank_diff": 3,
              "rules": {
                "condition": "required",
                "value": "japanese"
              },
              "handicap": {
                "condition": "preferred",
                "value": "enabled"
              }
            }
        """#
        let jsonObject = try! JSONSerialization.jsonObject(
            with: data.data(using: .utf8)!
        ) as! [String: Any]
        return OGSAutomatchEntry(jsonObject)!
    }
}

struct OGSQuickMatchRecap: Equatable {
    let firstLine: String
    let secondLine: String
}

enum OGSQuickMatchClockPreference: String, CaseIterable {
    case flexible, fischer, byoyomi, mixed

    var quickMatchTitle: String {
        switch self {
        case .flexible:
            return String(
                localized: "Either clock",
                comment: "Short option in a three-option segmented control. Accepts either Fischer or Byo-Yomi without preferring one."
            )
        case .fischer: return String(localized: "Fischer")
        case .byoyomi: return String(localized: "Byo-Yomi")
        case .mixed: return String(localized: "Mixed clocks")
        }
    }

    var systems: [OGSAutomatchClockSystem] {
        switch self {
        case .fischer: return [.fischer]
        case .byoyomi: return [.byoyomi]
        case .flexible, .mixed: return [.fischer, .byoyomi]
        }
    }
}

extension OGSQuickMatchDraft {
    var quickMatchSelectedBoardSizes: [Int] {
        if mode == .multiple {
            return multipleBoardSizes
                .intersection(Set(OGSQuickMatchClockPreset.supportedBoardSizes))
                .sorted()
        }
        return OGSQuickMatchClockPreset.supportedBoardSizes.contains(boardSize)
            ? [boardSize]
            : []
    }

    var quickMatchSelectedClocks: [OGSQuickMatchClockSelection] {
        if mode == .multiple {
            return multipleClocks
                .intersection(Set(OGSQuickMatchClockSelection.allSupported))
                .sorted { lhs, rhs in
                    let all = OGSQuickMatchClockSelection.allSupported
                    return (all.firstIndex(of: lhs) ?? .max)
                        < (all.firstIndex(of: rhs) ?? .max)
                }
        }

        let preferred = OGSQuickMatchClockSelection(
            speed: speed,
            system: speed == .correspondence ? .fischer : system
        )
        guard mode == .flexible, speed.isRealtime else {
            return [preferred]
        }
        return [
            preferred,
            OGSQuickMatchClockSelection(
                speed: speed,
                system: preferred.system.alternate
            ),
        ]
    }

    var quickMatchIsValid: Bool {
        !quickMatchSelectedBoardSizes.isEmpty && !quickMatchSelectedClocks.isEmpty
    }

    static let quickMatchSpeeds: [TimeControlSpeed] = [.blitz, .rapid, .live, .correspondence]

    var quickMatchSelectedSpeeds: [TimeControlSpeed] {
        let selected = Set(quickMatchSelectedClocks.map(\.speed))
        return Self.quickMatchSpeeds.filter { selected.contains($0) }
    }

    var quickMatchClockPreference: OGSQuickMatchClockPreference {
        let clocks = quickMatchSelectedClocks
        let systems = Set(clocks.map(\.system))
        if systems == [.fischer] { return .fischer }
        if systems == [.byoyomi] { return .byoyomi }
        let speeds = Set(clocks.map(\.speed))
        if clocks.isEmpty || clocks.count == speeds.count * 2 { return .flexible }
        return .mixed
    }

    var quickMatchClockSummary: String {
        quickMatchClockPreference == .flexible
            ? String(localized: "Fischer or Byo-Yomi")
            : quickMatchClockPreference.quickMatchTitle
    }

    var quickMatchHandicapSummary: String {
        handicap.quickMatchSummary()
    }

    func quickMatchClockDetailLines(
        for selectedSpeed: TimeControlSpeed,
        fallbackPreference: OGSQuickMatchClockPreference
    ) -> [String] {
        let selectedSizes = quickMatchSelectedBoardSizes
        let sizes = selectedSizes.isEmpty ? [boardSize] : selectedSizes
        let selectedSystems = Set(
            quickMatchSelectedClocks
                .filter { $0.speed == selectedSpeed }
                .map(\.system)
        )
        let systems: [OGSAutomatchClockSystem]
        if selectedSpeed == .correspondence {
            systems = [.fischer]
        } else if selectedSystems.isEmpty {
            systems = fallbackPreference.systems
        } else {
            systems = OGSAutomatchClockSystem.allCases.filter {
                selectedSystems.contains($0)
            }
        }

        return systems.flatMap { system in
            var groups = [(sizes: [Int], preset: OGSQuickMatchClockPreset)]()
            for size in sizes {
                guard let preset = OGSQuickMatchClockPreset.preset(
                    boardSize: size,
                    speed: selectedSpeed,
                    system: system
                ) else { continue }
                if let index = groups.firstIndex(where: {
                    $0.preset.timeControl == preset.timeControl
                }) {
                    groups[index].sizes.append(size)
                } else {
                    groups.append((sizes: [size], preset: preset))
                }
            }

            return groups.map { group in
                let clockName: String
                if sizes.count > 1 && groups.count > 1 {
                    let sizeNames = group.sizes.map { "\($0)×\($0)" }
                    clockName = "\(ListFormatter.localizedString(byJoining: sizeNames)) · \(system.quickMatchTitle)"
                } else {
                    clockName = system.quickMatchTitle
                }
                return String(
                    localized: "\(clockName): \(group.preset.quickMatchShortDescription)",
                    comment: "Clock system and optional board sizes followed by the Quick Match clock values."
                )
            }
        }
    }

    mutating func toggleQuickMatchBoardSize(_ size: Int) {
        guard OGSQuickMatchClockPreset.supportedBoardSizes.contains(size) else { return }
        var sizes = Set(quickMatchSelectedBoardSizes)
        if sizes.contains(size) { sizes.remove(size) } else { sizes.insert(size) }
        updateQuickMatchSelection(sizes: sizes, clocks: Set(quickMatchSelectedClocks))
    }

    mutating func toggleQuickMatchSpeed(
        _ selectedSpeed: TimeControlSpeed,
        clockPreference: OGSQuickMatchClockPreference? = nil
    ) {
        var clocks = Set(quickMatchSelectedClocks)
        if clocks.contains(where: { $0.speed == selectedSpeed }) {
            clocks = clocks.filter { $0.speed != selectedSpeed }
        } else if selectedSpeed == .correspondence {
            clocks = [OGSQuickMatchClockSelection(speed: .correspondence, system: .fischer)]
        } else {
            clocks = clocks.filter { $0.speed != .correspondence }
            for system in (clockPreference ?? quickMatchClockPreference).systems {
                clocks.insert(OGSQuickMatchClockSelection(speed: selectedSpeed, system: system))
            }
        }
        updateQuickMatchSelection(sizes: Set(quickMatchSelectedBoardSizes), clocks: clocks)
    }

    mutating func setQuickMatchClockPreference(_ preference: OGSQuickMatchClockPreference) {
        guard !quickMatchIsCorrespondenceOnly, preference != .mixed else { return }
        let clocks = Set(quickMatchSelectedSpeeds.flatMap { speed in
            preference.systems.map { OGSQuickMatchClockSelection(speed: speed, system: $0) }
        })
        updateQuickMatchSelection(sizes: Set(quickMatchSelectedBoardSizes), clocks: clocks)
    }

    mutating func setQuickMatchClocks(_ clocks: Set<OGSQuickMatchClockSelection>) {
        updateQuickMatchSelection(
            sizes: Set(quickMatchSelectedBoardSizes),
            clocks: clocks.intersection(Set(OGSQuickMatchClockSelection.allSupported))
        )
    }

    private mutating func updateQuickMatchSelection(
        sizes: Set<Int>, clocks: Set<OGSQuickMatchClockSelection>
    ) {
        multipleBoardSizes = sizes
        multipleClocks = clocks
        if let size = sizes.sorted().last { boardSize = size }
        let speeds = Set(clocks.map(\.speed))
        if let selectedSpeed = Self.quickMatchSpeeds.first(where: { speeds.contains($0) }) {
            speed = selectedSpeed
        }
        if clocks.count == 1, let clock = clocks.first { system = clock.system }
        if sizes.count == 1 && speeds.count == 1 {
            mode = clocks.count == 1 ? .exact : .flexible
        } else {
            mode = .multiple
        }
    }

    func quickMatchRecap(userRank: Double?) -> OGSQuickMatchRecap {
        guard quickMatchIsValid else {
            return OGSQuickMatchRecap(firstLine: String(localized: "Nothing selected"), secondLine: "")
        }
        let sizes = quickMatchSelectedBoardSizes.map { "\($0)×\($0)" }.joined(separator: ", ")
        let speeds = quickMatchSelectedSpeeds.map(\.quickMatchTitle).joined(separator: ", ")
        let clock = quickMatchClockSummary
        return OGSQuickMatchRecap(
            firstLine: "\(sizes) · \(speeds)",
            secondLine: [quickMatchHandicapSummary, clock, quickMatchRankRange(userRank: userRank)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        )
    }

    func quickMatchAccessibleRecap(userRank: Double?) -> String {
        guard quickMatchIsValid else { return String(localized: "Nothing selected") }
        let sizes = quickMatchSelectedBoardSizes.map { String(localized: "\($0) by \($0)") }
        return [
            ListFormatter.localizedString(byJoining: sizes),
            ListFormatter.localizedString(byJoining: quickMatchSelectedSpeeds.map(\.quickMatchTitle)),
            quickMatchHandicapSummary,
            quickMatchClockSummary,
            quickMatchAccessibleRankRange(userRank: userRank),
        ].joined(separator: ", ")
    }

    func quickMatchRankRange(userRank: Double?) -> String {
        guard let userRank else {
            return String(
                localized: "\(lowerRankDifference) ranks below to \(upperRankDifference) ranks above"
            )
        }
        return "\(Self.quickMatchRankLabel(userRank - Double(lowerRankDifference)))–\(Self.quickMatchRankLabel(userRank + Double(upperRankDifference)))"
    }

    func quickMatchAccessibleRankRange(userRank: Double?) -> String {
        guard let userRank else {
            return String(
                localized: "\(lowerRankDifference) ranks below to \(upperRankDifference) ranks above"
            )
        }
        let lower = Self.quickMatchAccessibleRankLabel(
            userRank - Double(lowerRankDifference)
        )
        let upper = Self.quickMatchAccessibleRankLabel(
            userRank + Double(upperRankDifference)
        )
        return String(localized: "Opponent rank from \(lower) to \(upper)")
    }

    static func quickMatchRankLabel(_ rank: Double) -> String {
        let boundedRank = min(max(rank, 5), 38)
        if boundedRank < 30 {
            return "\(Int(ceil(30 - boundedRank)))k"
        }
        return "\(Int(floor(boundedRank - 29)))d"
    }

    static func quickMatchAccessibleRankLabel(_ rank: Double) -> String {
        RankUtils.formattedRank(rank, longFormat: true)
    }
}
