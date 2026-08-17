//
//  OGSConditionalMoves.swift
//  Surround
//

import Foundation

/// The recursive tuple used by OGS for conditional moves.
///
/// Each child key is an opponent move. The child node's `response` is the
/// user's planned reply, and its children contain the opponent's subsequent
/// alternatives. The root response must be `nil`. OGS also uses a descendant
/// `[null, {}]` as a terminal opponent move for which the user has not planned
/// a reply yet; this is valid protocol state and is preserved for display.
struct OGSConditionalMoveWireNode: Codable, Equatable {
    var response: String?
    var children: [String: OGSConditionalMoveWireNode]

    init(
        response: String?,
        children: [String: OGSConditionalMoveWireNode] = [:]
    ) {
        self.response = response
        self.children = children
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if try container.decodeNil() {
            response = nil
        } else {
            response = try container.decode(String.self)
        }
        children = try container.decode([String: OGSConditionalMoveWireNode].self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A conditional-move node must contain exactly two elements."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        if let response {
            try container.encode(response)
        } else {
            try container.encodeNil()
        }
        try container.encode(children)
    }
}

/// A server update received on `game/<id>/conditional_moves`.
///
/// The official Goban runtime currently consumes the `moves` field, while its
/// protocol declaration calls the same field `conditional_moves`. Surround
/// accepts either spelling and rejects conflicting values when both are sent.
struct OGSConditionalMovesUpdate: Decodable, Equatable {
    var gameID: Int?
    var playerID: Int?
    var rootMoveNumber: Int
    var root: OGSConditionalMoveWireNode?

    private enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case playerID = "player_id"
        case moveNumber = "move_number"
        case moves
        case conditionalMoves = "conditional_moves"
    }

    init(
        gameID: Int? = nil,
        playerID: Int? = nil,
        rootMoveNumber: Int,
        root: OGSConditionalMoveWireNode?
    ) {
        self.gameID = gameID
        self.playerID = playerID
        self.rootMoveNumber = rootMoveNumber
        self.root = root
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try container.decodeIfPresent(Int.self, forKey: .gameID)
        playerID = try container.decodeIfPresent(Int.self, forKey: .playerID)
        rootMoveNumber = try container.decode(Int.self, forKey: .moveNumber)
        guard rootMoveNumber >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .moveNumber,
                in: container,
                debugDescription: "The conditional-move root cannot be negative."
            )
        }

        let hasMoves = container.contains(.moves)
        let hasConditionalMoves = container.contains(.conditionalMoves)
        guard hasMoves || hasConditionalMoves else {
            throw DecodingError.keyNotFound(
                CodingKeys.moves,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected moves or conditional_moves."
                )
            )
        }

        let movesValue = hasMoves
            ? try container.decode(ConditionalMoveJSONValue.self, forKey: .moves)
            : nil
        let conditionalMovesValue = hasConditionalMoves
            ? try container.decode(ConditionalMoveJSONValue.self, forKey: .conditionalMoves)
            : nil

        if let movesValue, let conditionalMovesValue,
           movesValue != conditionalMovesValue {
            throw DecodingError.dataCorruptedError(
                forKey: .conditionalMoves,
                in: container,
                debugDescription: "moves and conditional_moves disagree."
            )
        }

        let value = movesValue ?? conditionalMovesValue!
        if value == .null {
            root = nil
        } else {
            root = try OGSConditionalMovesUpdate.parseRoot(value)
        }
    }

    init(payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        self = try JSONDecoder().decode(OGSConditionalMovesUpdate.self, from: data)
    }

    /// Parses the root strictly, while dropping malformed descendants one at a
    /// time so a bad sibling cannot hide otherwise valid conditional branches.
    private static func parseRoot(
        _ value: ConditionalMoveJSONValue
    ) throws -> OGSConditionalMoveWireNode {
        let root = try parseNode(value, isRoot: true)
        guard case .array(let elements) = value,
              case .object(let rawChildren) = elements[1] else {
            throw ConditionalMoveWireError.invalidNode
        }
        // Preserve the distinction between an explicit empty authoritative
        // tree and a nonempty tree whose every child was malformed.
        guard rawChildren.isEmpty || !root.children.isEmpty else {
            throw ConditionalMoveWireError.invalidChildren
        }
        return root
    }

    private static func parseNode(
        _ value: ConditionalMoveJSONValue,
        isRoot: Bool
    ) throws -> OGSConditionalMoveWireNode {
        guard case .array(let elements) = value, elements.count == 2 else {
            throw ConditionalMoveWireError.invalidNode
        }

        let response: String?
        switch elements[0] {
        case .null:
            response = nil
        case .string(let move):
            response = move
        default:
            throw ConditionalMoveWireError.invalidResponse
        }

        guard case .object(let rawChildren) = elements[1] else {
            throw ConditionalMoveWireError.invalidChildren
        }
        // Only the root may pair a nil response with alternatives. For a
        // descendant, accepting this shape after malformed children were
        // filtered would incorrectly manufacture a terminal branch.
        guard isRoot || response != nil || rawChildren.isEmpty else {
            throw ConditionalMoveWireError.invalidResponse
        }

        var children = [String: OGSConditionalMoveWireNode]()
        for key in rawChildren.keys.sorted() {
            guard let rawChild = rawChildren[key] else {
                continue
            }
            if let child = try? parseNode(rawChild, isRoot: false) {
                children[key] = child
            }
        }
        return OGSConditionalMoveWireNode(response: response, children: children)
    }
}

private enum ConditionalMoveWireError: Error {
    case invalidNode
    case invalidResponse
    case invalidChildren
}

private indirect enum ConditionalMoveJSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([ConditionalMoveJSONValue])
    case object([String: ConditionalMoveJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ConditionalMoveJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ConditionalMoveJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported conditional-move JSON value."
            )
        }
    }
}

struct ConditionalMoveNode: Equatable {
    var response: Move?
    var children: [Move: ConditionalMoveNode]

    init(response: Move?, children: [Move: ConditionalMoveNode] = [:]) {
        self.response = response
        self.children = children
    }

    fileprivate mutating func insert(path: ArraySlice<Move>) throws {
        guard let opponentMove = path.first else {
            throw ConditionalMovePlanError.emptyPath
        }

        let afterOpponent = path.dropFirst()
        let proposedResponse = afterOpponent.first
        var child = children[opponentMove]
            ?? ConditionalMoveNode(response: proposedResponse)

        if let existingResponse = child.response,
           let proposedResponse,
           existingResponse != proposedResponse {
            throw ConditionalMovePlanError.conflictingResponse(opponentMove)
        }
        if child.response == nil {
            child.response = proposedResponse
        }

        let remainingPath = afterOpponent.dropFirst()
        if !remainingPath.isEmpty {
            guard child.response != nil else {
                throw ConditionalMovePlanError.missingResponse(opponentMove)
            }
            try child.insert(path: remainingPath)
        }
        children[opponentMove] = child
    }

    fileprivate var wireNode: OGSConditionalMoveWireNode {
        OGSConditionalMoveWireNode(
            response: response?.toOGSString(),
            children: Dictionary(
                uniqueKeysWithValues: children.map { move, node in
                    (move.toOGSString(), node.wireNode)
                }
            )
        )
    }
}

enum ConditionalMovePlanError: Error, Equatable {
    case emptyPath
    case conflictingResponse(Move)
    case missingResponse(Move)
}

struct ConditionalMovePlan: Equatable {
    var gameID: Int
    var ownerID: Int?
    var rootMoveNumber: Int
    var root: ConditionalMoveNode

    init(
        gameID: Int,
        ownerID: Int?,
        rootMoveNumber: Int,
        root: ConditionalMoveNode
    ) {
        self.gameID = gameID
        self.ownerID = ownerID
        self.rootMoveNumber = rootMoveNumber
        self.root = root
    }

    /// Fixture- and editor-friendly construction from alternating paths.
    /// Every path begins with an opponent move and then alternates the user's
    /// response and the opponent's next move. A path may end after an opponent
    /// move when OGS has recorded that alternative without a planned reply.
    init(
        gameID: Int,
        ownerID: Int?,
        rootMoveNumber: Int,
        paths: [[Move]]
    ) throws {
        var root = ConditionalMoveNode(response: nil)
        for path in paths {
            try root.insert(path: path[...])
        }
        self.init(
            gameID: gameID,
            ownerID: ownerID,
            rootMoveNumber: rootMoveNumber,
            root: root
        )
    }

    var encodedRoot: OGSConditionalMoveWireNode {
        root.wireNode
    }
}

/// Stable, value-based identity for one root-to-leaf conditional variation.
///
/// Move-tree nodes deliberately use object identity, but a server refresh must
/// be able to recognize the same conditional path without depending on the
/// lifetime of any particular `BoardPosition` instance. Keeping the moves in
/// the identity also preserves pass moves, whose board contents do not change.
struct ConditionalVariationID: Hashable {
    let rootMoveNumber: Int
    let moves: [Move]

    var rawValue: String {
        "\(rootMoveNumber):\(moves.map { $0.toOGSString() }.joined())"
    }
}

/// A pure, ordered root-to-leaf conditional path.
///
/// Unlike `ConditionalMoveBranch`, this descriptor is independent of any
/// move-tree node. `MoveTree` is the sole place that replays these moves and
/// turns a legal path into canonical registered positions.
struct ConditionalMovePath: Identifiable, Hashable {
    let rootMoveNumber: Int
    let moves: [Move]

    var variationID: ConditionalVariationID {
        ConditionalVariationID(
            rootMoveNumber: rootMoveNumber,
            moves: moves
        )
    }

    var id: String { variationID.rawValue }
}

/// A root-to-leaf conditional variation materialized in the game's move tree.
struct ConditionalMoveBranch: Identifiable, Hashable {
    let variationID: ConditionalVariationID
    let position: BoardPosition
    let variation: Variation
    let moves: [Move]

    var id: String { variationID.rawValue }

    static func == (lhs: ConditionalMoveBranch, rhs: ConditionalMoveBranch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ConditionalMovePlan {
    func validated(width: Int, height: Int) -> ConditionalMovePlan? {
        guard let validatedRoot = root.validated(
            width: width,
            height: height,
            isRoot: true
        ) else {
            return nil
        }
        return ConditionalMovePlan(
            gameID: gameID,
            ownerID: ownerID,
            rootMoveNumber: rootMoveNumber,
            root: validatedRoot
        )
    }

    func orderedPaths() -> [ConditionalMovePath] {
        var paths = [[Move]]()
        root.collectLeafPaths(moves: [], into: &paths)
        return paths.map { moves in
            ConditionalMovePath(
                rootMoveNumber: rootMoveNumber,
                moves: moves
            )
        }
    }
}

extension ConditionalMoveNode {
    /// Converts wire move strings into domain moves. Malformed strings drop
    /// only their containing branch; structural domain validation remains the
    /// single responsibility of `validated(width:height:isRoot:)` below.
    static func decodedRoot(
        wireNode: OGSConditionalMoveWireNode
    ) -> ConditionalMoveNode? {
        decoded(wireNode: wireNode)
    }

    private static func decoded(
        wireNode: OGSConditionalMoveWireNode
    ) -> ConditionalMoveNode? {
        let response: Move?
        if let rawResponse = wireNode.response {
            guard let decodedResponse = Move.decodedConditionalMove(
                from: rawResponse
            ) else {
                return nil
            }
            response = decodedResponse
        } else {
            response = nil
        }

        var children = [Move: ConditionalMoveNode]()
        for rawMove in wireNode.children.keys.sorted() {
            guard let wireChild = wireNode.children[rawMove],
                  let opponentMove = Move.decodedConditionalMove(
                    from: rawMove
                  ),
                  let child = decoded(wireNode: wireChild) else {
                continue
            }
            children[opponentMove] = child
        }
        return ConditionalMoveNode(response: response, children: children)
    }

    fileprivate func validated(
        width: Int,
        height: Int,
        isRoot: Bool
    ) -> ConditionalMoveNode? {
        if isRoot {
            guard response == nil else {
                return nil
            }
        } else if let response {
            guard response.isValidConditionalMove(
                width: width,
                height: height
            ) else {
                return nil
            }
        } else if !children.isEmpty {
            return nil
        }

        var validatedChildren = [Move: ConditionalMoveNode]()
        let validMoves = children.keys.filter {
            $0.isValidConditionalMove(width: width, height: height)
        }
        for move in validMoves.sorted(by: Move.conditionalSort) {
            guard let child = children[move]?.validated(
                width: width,
                height: height,
                isRoot: false
            ) else {
                continue
            }
            validatedChildren[move] = child
        }
        return ConditionalMoveNode(response: response, children: validatedChildren)
    }

    fileprivate func collectLeafPaths(
        moves: [Move],
        into paths: inout [[Move]]
    ) {
        for opponentMove in children.keys.sorted(by: Move.conditionalSort) {
            guard let child = children[opponentMove] else {
                continue
            }
            var childMoves = moves + [opponentMove]
            if let response = child.response {
                childMoves.append(response)
            }

            if child.children.isEmpty {
                paths.append(childMoves)
            } else {
                child.collectLeafPaths(moves: childMoves, into: &paths)
            }
        }
    }
}

extension Move {
    fileprivate static func decodedConditionalMove(from string: String) -> Move? {
        guard string.utf8.count == 2 else {
            return nil
        }
        if string == ".." {
            return .pass
        }

        let bytes = Array(string.utf8)
        guard bytes.count == 2,
              bytes[0] >= Character("a").asciiValue!,
              bytes[0] <= Character("z").asciiValue!,
              bytes[1] >= Character("a").asciiValue!,
              bytes[1] <= Character("z").asciiValue! else {
            return nil
        }

        let column = Int(bytes[0] - Character("a").asciiValue!)
        let row = Int(bytes[1] - Character("a").asciiValue!)
        return .placeStone(row, column)
    }

    fileprivate func isValidConditionalMove(width: Int, height: Int) -> Bool {
        switch self {
        case .pass:
            return true
        case .placeStone(let row, let column):
            return row >= 0 && row < height && column >= 0 && column < width
        }
    }

    fileprivate static func conditionalSort(_ lhs: Move, _ rhs: Move) -> Bool {
        lhs.toOGSString() < rhs.toOGSString()
    }
}
