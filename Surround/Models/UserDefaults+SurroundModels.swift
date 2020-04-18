//
//  UserDefaults+SurroundModels.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation
import Combine

// From https://www.swiftbysundell.com/articles/the-power-of-subscripts-in-swift/
extension UserDefaults {
    struct Key<Value> {
        var name: String
        var encoded: Bool = false
    }

    subscript<T>(key: Key<T>) -> T? where T: Codable {
        get {
            if !key.encoded {
                return value(forKey: key.name) as? T
            } else {
                if let result = data(forKey: key.name) {
                    return try? JSONDecoder().decode(T.self, from: result)
                } else {
                    return nil
                }
            }
        }
        set {
            if newValue == nil {
                removeObject(forKey: key.name)
            } else {
                if !key.encoded {
                    setValue(newValue, forKey: key.name)
                } else {
                    if let json = try? JSONEncoder().encode(newValue) {
                        setValue(json, forKey: key.name)
                    }
                }
            }
        }
    }
}

extension UserDefaults.Key {
    static var ogsUIConfig: UserDefaults.Key<OGSUIConfig> {
        return .init(name: "ogsUIConfig", encoded: true)
    }
}
