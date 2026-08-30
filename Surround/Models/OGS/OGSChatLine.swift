//
//  OGSChatLine.swift
//  Surround
//
//  Created by Anh Khoa Hong on 16/11/2020.
//

import Foundation

enum OGSChatChannel: String, Decodable {
    case main
    case hidden
    case malkovich
    case personal
    case shadowban
    case spectator
}

extension CodingUserInfoKey {
    static let ogsChatPreferredLanguageIdentifiers = CodingUserInfoKey(
        rawValue: "ogsChatPreferredLanguageIdentifiers"
    )!
}

enum OGSChatSendChannel: String, Codable {
    case main
    case malkovich
    case personal

    func resolved(isUserPlaying: Bool) -> OGSChatSendChannel {
        isUserPlaying ? self : .main
    }
}

struct OGSChatAnalysisBody: Codable, Equatable {
    var fromMoveNumber: Int
    var moves: String
    var name: String
    var marks: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case branchMove
        case from
        case moves
        case name
        case marks
    }

    init(
        fromMoveNumber: Int,
        moves: String,
        name: String,
        marks: [String: String]? = nil
    ) {
        self.fromMoveNumber = fromMoveNumber
        self.moves = moves
        self.name = name
        self.marks = marks
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        guard type == nil || type == "analysis" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported structured chat body type"
            )
        }
        if let legacyBranchMove = try? container.decode(
            Int.self,
            forKey: .branchMove
        ), legacyBranchMove > Int.min {
            // Legacy OGS chat bodies counted the branch point one move ahead.
            fromMoveNumber = legacyBranchMove - 1
        } else {
            fromMoveNumber = try container.decode(Int.self, forKey: .from)
        }
        moves = try container.decode(String.self, forKey: .moves)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        marks = try? container.decode(
            [String: String].self,
            forKey: .marks
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("analysis", forKey: .type)
        try container.encode(fromMoveNumber, forKey: .from)
        try container.encode(moves, forKey: .moves)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(marks, forKey: .marks)
    }

    func decodedMoves(boardWidth: Int, boardHeight: Int) throws -> [Move] {
        try Move.fromMoveString(
            moveString: moves,
            boardWidth: boardWidth,
            boardHeight: boardHeight
        )
    }

    func decodedMarkups(boardWidth: Int, boardHeight: Int) -> BoardMarkups {
        BoardMarkupCodec.decode(
            marks,
            boardWidth: boardWidth,
            boardHeight: boardHeight
        )
    }
}

typealias OGSChatLineVariation = OGSChatAnalysisBody

struct OGSChatLine: Decodable, Identifiable, Hashable {
    var id: String
    var channel: OGSChatChannel
    var timestamp: Date
    var moveNumber: Int?
    var body: String
    var user: OGSUser
    var isPlainTextBody: Bool
    var isAnalysis: Bool
    var variationData: OGSChatLineVariation?
    var variation: Variation?
    var reviewID: Int?
    
    struct OGSChatLineCodingData: Decodable, Hashable {
        private struct DynamicCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int?

            init(stringValue: String) {
                self.stringValue = stringValue
                intValue = nil
            }

            init(intValue: Int) {
                stringValue = String(intValue)
                self.intValue = intValue
            }
        }

        private struct StructuredBody: Decodable {
            var type: String?
            var name: String?
            var reviewID: Int?
            var translations: [(key: String, value: String)] = []

            init(from decoder: Decoder) throws {
                let container = try decoder.container(
                    keyedBy: DynamicCodingKey.self
                )
                func key(_ value: String) -> DynamicCodingKey {
                    DynamicCodingKey(stringValue: value)
                }

                type = try? container.decode(String.self, forKey: key("type"))
                name = try? container.decode(String.self, forKey: key("name"))
                reviewID = try? container.decode(
                    Int.self,
                    forKey: key("reviewId")
                )

                // JSONDecoder does not promise source-key order, so sort the
                // last-resort translations to keep fallback behavior stable.
                translations = container.allKeys.compactMap { key in
                    guard key.stringValue != "type",
                          let value = try? container.decode(
                            String.self,
                            forKey: key
                          ) else {
                        return nil
                    }
                    return (key.stringValue, value)
                }
                .sorted { $0.key < $1.key }
            }
        }

        private struct DecodedBody: Decodable {
            var text: String
            var isPlainTextBody = false
            var isAnalysis = false
            var variation: OGSChatLineVariation?
            var reviewID: Int?

            init(from decoder: Decoder) throws {
                let singleValue = try decoder.singleValueContainer()
                if let text = try? singleValue.decode(String.self) {
                    self.text = text
                    isPlainTextBody = true
                    return
                }

                guard let structuredBody = try? StructuredBody(from: decoder)
                else {
                    text = String(
                        localized: "[Unknown chat message]",
                        comment: "Fallback for an unsupported structured game-chat body"
                    )
                    return
                }

                switch structuredBody.type {
                case "translated":
                    let preferredLanguages = decoder.userInfo[
                        .ogsChatPreferredLanguageIdentifiers
                    ] as? [String] ?? Locale.preferredLanguages
                    text = Self.translatedText(
                        structuredBody.translations,
                        preferredLanguages: preferredLanguages
                    )

                case "analysis":
                    isAnalysis = true
                    text = structuredBody.name ?? ""
                    variation = try? OGSChatAnalysisBody(from: decoder)

                case "review":
                    guard let reviewID = structuredBody.reviewID else {
                        text = String(
                            localized: "[Unknown chat message]",
                            comment: "Fallback for an unsupported structured game-chat body"
                        )
                        return
                    }
                    self.reviewID = reviewID
                    text = ""

                default:
                    text = String(
                        localized: "[Unknown chat message]",
                        comment: "Fallback for an unsupported structured game-chat body"
                    )
                }
            }

            private static func translatedText(
                _ translations: [(key: String, value: String)],
                preferredLanguages: [String]
            ) -> String {
                let normalizedTranslations = translations.map {
                    (
                        key: normalizeLanguageIdentifier($0.key),
                        value: $0.value
                    )
                }

                func value(for language: String) -> String? {
                    normalizedTranslations.first {
                        $0.key == language && !$0.value.isEmpty
                    }?.value
                }

                if let preferredLanguage = preferredLanguages.first {
                    let normalized = normalizeLanguageIdentifier(
                        preferredLanguage
                    )
                    if let exact = value(for: normalized) {
                        return exact
                    }
                    if let alias = chineseAlias(for: normalized),
                       let aliased = value(for: alias) {
                        return aliased
                    }
                    if let base = normalized.split(separator: "-").first,
                       let baseTranslation = value(for: String(base)) {
                        return baseTranslation
                    }
                }

                if let english = value(for: "en") {
                    return english
                }
                if let firstAvailable = normalizedTranslations.first(
                    where: { !$0.value.isEmpty }
                ) {
                    return firstAvailable.value
                }
                return String(
                    localized: "[Message unavailable in this language]",
                    comment: "Fallback for a translated game-chat body with no usable text"
                )
            }

            private static func normalizeLanguageIdentifier(
                _ identifier: String
            ) -> String {
                identifier.replacingOccurrences(of: "_", with: "-")
                    .lowercased()
            }

            private static func chineseAlias(for language: String) -> String? {
                let components = language.split(separator: "-").map(String.init)
                guard components.first == "zh" else { return nil }

                if components.contains("hans") {
                    return "zh-cn"
                }
                if components.contains("hant") {
                    return "zh-tw"
                }
                if components.contains("cn") || components.contains("sg") {
                    return "zh-cn"
                }
                if components.contains("tw")
                    || components.contains("hk")
                    || components.contains("mo") {
                    return "zh-tw"
                }
                return nil
            }
        }

        var body: String
        var chatId: String
        var date: Double
        var moveNumber: Int?
        var playerId: Int
        var professional: Bool?
        var ranking: Double?
        var ratings: OGSRating?
        var uiClass: String?
        var username: String
        var isPlainTextBody: Bool
        var isAnalysis: Bool
        var variation: OGSChatLineVariation?
        var reviewID: Int?
        
        enum CodingKeys: String, CodingKey {
            case body, chatId, date, moveNumber, playerId, professional, ranking, ratings, uiClass, username
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: OGSChatLineCodingData.CodingKeys.self)
            let decodedBody = try container.decode(DecodedBody.self, forKey: .body)
            body = decodedBody.text
            isPlainTextBody = decodedBody.isPlainTextBody
            isAnalysis = decodedBody.isAnalysis
            variation = decodedBody.variation
            reviewID = decodedBody.reviewID
            chatId = try container.decode(String.self, forKey: .chatId)
            date = try container.decode(Double.self, forKey: .date)
            moveNumber = try container.decodeIfPresent(Int.self, forKey: .moveNumber)
            if let playerIdString = try? container.decode(String.self, forKey: .playerId) {
                playerId = Int(playerIdString) ?? -1
            } else {
                playerId = try container.decode(Int.self, forKey: .playerId)
            }
            professional = try container.decodeIfPresent(Bool.self, forKey: .professional)
            ranking = try container.decodeIfPresent(Double.self, forKey: .ranking)
            ratings = try container.decodeIfPresent(OGSRating.self, forKey: .ratings)
            uiClass = try container.decodeIfPresent(String.self, forKey: .uiClass)
            username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        }

        static func == (lhs: OGSChatLine.OGSChatLineCodingData, rhs: OGSChatLine.OGSChatLineCodingData) -> Bool {
            return lhs.chatId == rhs.chatId
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(chatId)
        }
    }
    
    struct OGSChatCodingData: Decodable {
        var channel: OGSChatChannel
        var line: OGSChatLineCodingData
    }
    
    var codingData: OGSChatCodingData
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        codingData = try container.decode(OGSChatCodingData.self)
        
        channel = codingData.channel
        id = codingData.line.chatId
        timestamp = Date(timeIntervalSince1970: codingData.line.date)
        moveNumber = codingData.line.moveNumber
        body = codingData.line.body
        user = OGSUser(
            username: codingData.line.username,
            id: codingData.line.playerId,
            ranking: codingData.line.ranking,
            uiClass: codingData.line.uiClass,
            professional: codingData.line.professional,
            ratings: codingData.line.ratings
        )
        isPlainTextBody = codingData.line.isPlainTextBody
        isAnalysis = codingData.line.isAnalysis
        variationData = codingData.line.variation
        reviewID = codingData.line.reviewID
    }

    static func == (lhs: OGSChatLine, rhs: OGSChatLine) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let coordinatesRegex = try! NSRegularExpression(
        pattern: #"\b[abcdefghjklmnopqrstuvwxyz]([1-9]|1[0-9]|2[0-5])\b"#,
        options: [.caseInsensitive]
    )
    
    lazy var coordinatesInBody: [NSTextCheckingResult] = {
        OGSChatLine.coordinatesRegex.matches(
            in: self.body,
            options: [],
            range: NSRange(location: 0, length: self.body.utf16.count)
        )
    }()
    
    lazy var coordinatesRanges: [NSRange] = {
        self.coordinatesInBody.map { $0.range }
    }()
    
    lazy var coordinates: [[Int]] = {
        self.coordinatesRanges.compactMap { nsRange in
            guard let range = Range(nsRange, in: self.body) else {
                return nil
            }
            let coordinate = self.body[range]
            guard let letterASCII = coordinate.first?.lowercased().utf8.first,
                  (97...122).contains(letterASCII),
                  let number = Int(coordinate.dropFirst()) else {
                return nil
            }
            let column = Int(letterASCII - 97)
            return [number - 1, column > 8 ? column - 1 : column]
        }
    }()
}
