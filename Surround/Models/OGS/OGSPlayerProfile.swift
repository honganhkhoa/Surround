//
//  OGSPlayerProfile.swift
//  Surround
//

import Foundation

/// The identity and biography fields from OGS's `players/{id}/full` response.
/// Profile-only fields stay separate from the lightweight users shared by games.
struct OGSPlayerProfile: Decodable, Equatable, Identifiable {
    let user: OGSUser
    let about: String?
    let registrationDate: Date?

    var id: Int { user.id }

    init(user: OGSUser, about: String? = nil, registrationDate: Date? = nil) {
        self.user = user
        self.about = about
        self.registrationDate = registrationDate
    }

    private enum CodingKeys: String, CodingKey {
        case user
    }

    private enum UserDetailsKeys: String, CodingKey {
        case about
        case registrationDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(OGSUser.self, forKey: .user)
        guard user.id > 0,
              !user.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .user,
                in: container,
                debugDescription: "A player profile must have a positive ID and a username."
            )
        }

        let details = try container.nestedContainer(
            keyedBy: UserDetailsKeys.self,
            forKey: .user
        )
        about = try details.decodeIfPresent(String.self, forKey: .about)
        if let dateString = try? details.decodeIfPresent(String.self, forKey: .registrationDate),
           !dateString.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                registrationDate = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                registrationDate = formatter.date(from: dateString)
            }
        } else {
            registrationDate = nil
        }
    }
}
