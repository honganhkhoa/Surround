import CryptoKit
import CoreFoundation
import Foundation

public enum ReleaseToolError: Error, CustomStringConvertible, LocalizedError {
    case usage(String)
    case validation(String)
    case file(String)
    case api(String)
    case remoteDrift(String)

    public var description: String {
        switch self {
        case let .usage(message): return "Usage error: \(message)"
        case let .validation(message): return "Validation error: \(message)"
        case let .file(message): return "File error: \(message)"
        case let .api(message): return "App Store Connect error: \(message)"
        case let .remoteDrift(message): return "Remote state changed: \(message)"
        }
    }

    public var errorDescription: String? { description }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case let .number(value) = self, value.rounded() == value else { return nil }
        return Int(value)
    }

    public subscript(_ key: String) -> JSONValue? { objectValue?[key] }

    public init(any: Any) throws {
        switch any {
        case is NSNull: self = .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool: self = .bool(value)
        case let value as String: self = .string(value)
        case let value as [Any]: self = .array(try value.map(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(try value.mapValues(JSONValue.init(any:)))
        default: throw ReleaseToolError.validation("Unsupported JSON value \(type(of: any))")
        }
    }

    public var any: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .number(value): return value
        case let .string(value): return value
        case let .array(value): return value.map(\.any)
        case let .object(value): return value.mapValues(\.any)
        }
    }
}

public enum FileIO {
    public static func readJSON(at url: URL) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        } catch {
            throw ReleaseToolError.file("Could not read JSON at \(url.path): \(error.localizedDescription)")
        }
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try write(data: data + Data([0x0A]), to: url)
    }

    public static func writeJSONValue(_ value: JSONValue, to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: value.any,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try write(data: data + Data([0x0A]), to: url)
    }

    public static func write(data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            throw ReleaseToolError.file("Could not write \(url.path): \(error.localizedDescription)")
        }
    }

    public static func canonicalData(_ value: JSONValue) throws -> Data {
        try JSONSerialization.data(withJSONObject: value.any, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func relativeOrAbsoluteURL(_ path: String, relativeTo base: URL) -> URL {
        NSString(string: path).isAbsolutePath
            ? URL(fileURLWithPath: path)
            : base.appendingPathComponent(path)
    }
}

public extension ISO8601DateFormatter {
    static let releaseTool: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

public extension URL {
    var standardizedFilePath: String { standardizedFileURL.path }
}
