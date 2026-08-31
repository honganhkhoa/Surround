//
//  OGSAutomatchEntry.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/02/2021.
//

import Foundation

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
    }

    init(
        sizeSpeedOptions: [OGSAutomatchSizeSpeedOption],
        lowerRankDifference: Int = 3,
        upperRankDifference: Int = 3,
        rules: OGSAutomatchRulesPreference = .quickMatchDefault,
        handicap: OGSAutomatchHandicapPreference = .quickMatchDefault,
        uuid: String = UUID().uuidString.lowercased()
    ) {
        self.sizeSpeedOptions = sizeSpeedOptions
        self.lowerRankDifference = lowerRankDifference
        self.upperRankDifference = upperRankDifference
        self.rules = rules
        self.handicap = handicap
        self.uuid = uuid
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

        let rulesObject = jsonObject["rules"] as? [String: Any]
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

        let handicapObject = jsonObject["handicap"] as? [String: Any]
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
            uuid: uuid
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sizeSpeedOptions, forKey: .sizeSpeedOptions)
        try container.encode(lowerRankDifference, forKey: .lowerRankDifference)
        try container.encode(upperRankDifference, forKey: .upperRankDifference)
        try container.encode(rules, forKey: .rules)
        try container.encode(handicap, forKey: .handicap)
        try container.encode(uuid, forKey: .uuid)

        // Keep the active legacy key readable by older app versions. Their
        // synthesized decoder ignores the richer keys above.
        try container.encode(sizeOptions, forKey: .sizeOptions)
        try container.encode(timeControlSpeed, forKey: .timeControlSpeed)
    }

    var sizeOptions: Set<Int> {
        Set(sizeSpeedOptions.map(\.size))
    }

    var timeControlSpeed: TimeControlSpeed {
        let speeds = Set(sizeSpeedOptions.map(\.speed))
        return speeds.count == 1 ? speeds.first! : .live
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
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return defaultValue
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

    fileprivate var sortIndex: Int {
        Self.allRealtime.firstIndex(of: self) ?? Int.max
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
                option.speed.isRealtime
                    ? OGSQuickMatchClockSelection(
                        speed: option.speed,
                        system: option.system
                    )
                    : nil
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
                    speed: migratedSpeed == .correspondence ? .rapid : migratedSpeed,
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
            mode: validSizes.count > 1 && migratedSpeed.isRealtime
                ? .multiple
                : .flexible,
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
            Set(OGSQuickMatchClockSelection.allRealtime)
        )
        if validClocks.isEmpty {
            return [
                OGSQuickMatchClockSelection(
                    speed: speed == .correspondence ? .rapid : speed,
                    system: system
                ),
            ]
        }
        return validClocks.sorted { $0.sortIndex < $1.sortIndex }
    }

    private static func clampedRankDifference(_ value: Int) -> Int {
        min(max(value, 0), 9)
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
