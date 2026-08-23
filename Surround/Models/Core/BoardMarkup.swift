//
//  BoardMarkup.swift
//  Surround
//

import Foundation

struct BoardPoint: Hashable, Comparable {
    let row: Int
    let column: Int

    static func < (lhs: BoardPoint, rhs: BoardPoint) -> Bool {
        lhs.row == rhs.row
            ? lhs.column < rhs.column
            : lhs.row < rhs.row
    }
}

enum BoardMarkShape: String, CaseIterable, Hashable {
    case triangle
    case square
    case circle
    case cross
}

struct BoardMarkup: Equatable {
    var label: String?
    var shapes = Set<BoardMarkShape>()

    init(label: String? = nil, shapes: Set<BoardMarkShape> = []) {
        self.label = label
        self.shapes = shapes
    }

    var isEmpty: Bool {
        label == nil && shapes.isEmpty
    }
}

typealias BoardMarkups = [BoardPoint: BoardMarkup]

enum AnalyzeBoardTool: String, CaseIterable, Hashable {
    case moves
    case letters
    case numbers
    case triangle
    case square
    case circle
    case cross
    case eraser

    var shape: BoardMarkShape? {
        BoardMarkShape(rawValue: rawValue)
    }

    func matches(_ markup: BoardMarkup?) -> Bool {
        guard let markup else {
            return false
        }
        if let shape {
            return markup.shapes.contains(shape)
        }
        switch self {
        case .letters:
            return markup.label?.isBoardLetter == true
        case .numbers:
            return markup.label?.isBoardNumber == true
        default:
            return false
        }
    }
}

extension Dictionary where Key == BoardPoint, Value == BoardMarkup {
    mutating func paint(_ tool: AnalyzeBoardTool, at point: BoardPoint) {
        if let shape = tool.shape {
            self[point] = BoardMarkup(shapes: [shape])
        } else if tool == .letters {
            self[point] = BoardMarkup(label: nextBoardLetter)
        } else if tool == .numbers {
            self[point] = BoardMarkup(label: nextBoardNumber)
        } else if tool == .eraser {
            self[point] = nil
        }
    }

    var nextBoardLetter: String {
        let sequence = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let highestIndex = values.compactMap { markup -> Int? in
            guard let label = markup.label,
                  label.count == 1,
                  let character = label.first else {
                return nil
            }
            return sequence.firstIndex(of: character)
        }.max() ?? -1
        return String(sequence[(highestIndex + 1) % sequence.count])
    }

    var nextBoardNumber: String {
        let highestNumber = values.compactMap { markup -> Int? in
            guard let label = markup.label, label.isBoardNumber else {
                return nil
            }
            return Int(label)
        }.max() ?? 0
        return String(highestNumber == Int.max ? 1 : highestNumber + 1)
    }

    func ogsMarks(boardWidth: Int, boardHeight: Int) -> [String: String] {
        var pointsByKey = [String: [BoardPoint]]()
        for (point, markup) in self where point.row >= 0
            && point.column >= 0
            && point.row < boardHeight
            && point.column < boardWidth {
            if let label = markup.label, !label.isEmpty, label.count <= 3 {
                pointsByKey[label, default: []].append(point)
            }
            for shape in markup.shapes {
                pointsByKey[shape.rawValue, default: []].append(point)
            }
        }

        return pointsByKey.reduce(into: [:]) { result, entry in
            let coordinates = entry.value.sorted().compactMap { point in
                BoardMarkupCodec.ogsCoordinate(for: point)
            }.joined()
            if !coordinates.isEmpty {
                result[entry.key] = coordinates
            }
        }
    }
}

enum BoardMarkupCodec {
    static func decode(
        _ marks: [String: String]?,
        boardWidth: Int,
        boardHeight: Int
    ) -> BoardMarkups {
        guard let marks else {
            return [:]
        }

        var result = BoardMarkups()
        for (key, coordinates) in marks {
            let shape = BoardMarkShape(rawValue: key)
            let label = shape == nil && !key.isEmpty && key.count <= 3
                ? key
                : nil
            guard shape != nil || label != nil else {
                continue
            }

            let bytes = Array(coordinates.utf8)
            for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                guard let column = coordinateIndex(bytes[index]),
                      let row = coordinateIndex(bytes[index + 1]),
                      row < boardHeight,
                      column < boardWidth else {
                    continue
                }
                let point = BoardPoint(row: row, column: column)
                var markup = result[point] ?? BoardMarkup()
                if let shape {
                    markup.shapes.insert(shape)
                }
                if let label {
                    markup.label = label
                }
                result[point] = markup
            }
        }
        return result
    }

    fileprivate static func ogsCoordinate(for point: BoardPoint) -> String? {
        let labels = Array("abcdefghijklmnopqrstuvwxyz")
        guard point.row >= 0,
              point.column >= 0,
              point.row < labels.count,
              point.column < labels.count else {
            return nil
        }
        return String(labels[point.column]) + String(labels[point.row])
    }

    private static func coordinateIndex(_ byte: UInt8) -> Int? {
        let a = Character("a").asciiValue!
        let z = Character("z").asciiValue!
        guard byte >= a, byte <= z else {
            return nil
        }
        return Int(byte - a)
    }
}

private extension String {
    var isBoardLetter: Bool {
        count == 1 && first?.isASCII == true && first?.isLetter == true
    }

    var isBoardNumber: Bool {
        !isEmpty && allSatisfy(\.isNumber) && Int(self) != nil
    }
}
