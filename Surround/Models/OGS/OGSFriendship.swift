import Foundation

/// A valid list envelope can still contain individual entries we cannot read.
/// Those entries must not hide the usable rows or prove a relationship ended.
struct OGSFriendshipList<Element: Decodable>: Decodable {
    let elements: [Element]
    let isComplete: Bool

    private init(elements: [Element], isComplete: Bool) {
        self.elements = elements
        self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var isComplete = true
        while !container.isAtEnd {
            let entry = try container.superDecoder()
            if let element = try? Element(from: entry) {
                elements.append(element)
            } else {
                isComplete = false
            }
        }
        self.init(elements: elements, isComplete: isComplete)
    }

    func validating(_ predicate: (Element) -> Bool) -> Self {
        let valid = elements.filter(predicate)
        return Self(elements: valid, isComplete: isComplete && valid.count == elements.count)
    }
}

enum OGSProfileFriendship: Equatable {
    case none
    case requestSent
    case requestReceived
    case friends

    init?(isFriend: Bool?, requestSent: Bool?, requestReceived: Bool?) {
        if isFriend == true {
            self = .friends
        } else if requestReceived == true {
            self = .requestReceived
        } else if requestSent == true {
            self = .requestSent
        } else if isFriend == false, requestSent == false, requestReceived == false {
            self = .none
        } else {
            return nil
        }
    }
}

enum OGSFriendshipAction: Equatable {
    case send
    case accept
    case reject(notifyRequestor: Bool)
    case remove

    func isAvailable(for friendship: OGSProfileFriendship?) -> Bool {
        switch (self, friendship) {
        case (.send, .some(.none)), (.accept, .requestReceived),
             (.reject, .requestReceived), (.remove, .friends):
            return true
        default:
            return false
        }
    }
}

struct OGSFriendInvitation: Decodable, Identifiable, Equatable {
    let fromUser: OGSUser
    let accepted: Bool
    let created: Date?
    var id: Int { fromUser.id }

    init(fromUser: OGSUser, accepted: Bool = false, created: Date? = nil) {
        self.fromUser = fromUser
        self.accepted = accepted
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case fromUser, accepted, created
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromUser = try container.decode(OGSUser.self, forKey: .fromUser)
        guard fromUser.id > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .fromUser, in: container,
                debugDescription: "An invitation must identify its sender."
            )
        }
        accepted = try container.decode(Bool.self, forKey: .accepted)
        let dateString = try? container.decodeIfPresent(String.self, forKey: .created)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalDate = dateString.flatMap(formatter.date(from:))
        formatter.formatOptions = [.withInternetDateTime]
        created = fractionalDate ?? dateString.flatMap(formatter.date(from:))
    }
}

struct OGSFriendshipNotice: Identifiable {
    let id = UUID()
    let action: OGSFriendshipAction
}

struct OGSFriendshipFailure: Identifiable {
    let id = UUID()
    let action: OGSFriendshipAction
    let user: OGSUser
    let message: String
}

struct OGSFriendshipError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
