//
//  UserDefaults+SurroundModels.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation
import Combine
import SwiftUI

let userDefaultsSuite = "group.com.honganhkhoa.Surround"
let userDefaults = UserDefaults(suiteName: userDefaultsSuite) ?? UserDefaults.standard

// From https://www.swiftbysundell.com/articles/the-power-of-subscripts-in-swift/
struct SettingKey<Value> {
    var name: String
    var _defaultValue: Value?
    var encoded: Bool = false
    var defaultValue: Value {
        _defaultValue!
    }
    
    internal init(name: String, encoded: Bool = false, defaultValue: Value? = nil) {
        self.name = "com.honganhkhoa.Surround.\(name)"
        self.encoded = encoded
        self._defaultValue = defaultValue
    }
}

extension UserDefaults {
    subscript<T>(key: SettingKey<T>) -> T? where T: Codable {
        get {
            if !key.encoded {
                return value(forKey: key.name) as? T ?? key._defaultValue
            } else {
                if let result = data(forKey: key.name) {
                    return try? JSONDecoder().decode(T.self, from: result)
                } else {
                    return key._defaultValue
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

extension SettingKey {
    static var ogsUIConfig: SettingKey<OGSUIConfig> {
        return .init(name: "ogsUIConfig", encoded: true)
    }
    
    static var ogsSessionId: SettingKey<String> {
        return .init(name: "ogsSessionId")
    }
    
    static var latestOGSOverview: SettingKey<Data> {
        return .init(name: "latestOGSOverview")
    }
    
    static var latestOGSOverviewTime: SettingKey<Date> {
        return .init(name: "latestOGSOverviewTime")
    }
    
    #if !WIDGET
    static var homeViewDisplayMode: SettingKey<GameCell.CellDisplayMode> {
        return .init(name: "homeViewDisplayMode")
    }
    #endif
    
    static var hapticsFeedback: SettingKey<Bool> {
        return .init(name: "hapticsFeedback", defaultValue: true)
    }
    
    static var autoSubmitForLiveGames: SettingKey<Bool> {
        return .init(name: "autoSubmitForLiveGames", defaultValue: false)
    }
    
    static var autoSubmitForCorrespondenceGames: SettingKey<Bool> {
        return .init(name: "autoSubmitForCorrespondenceGames", defaultValue: false)
    }
    
    static var voiceCountdown: SettingKey<Bool> {
        return .init(name: "voiceCountdown", defaultValue: false)
    }
    
    static var notificationEnabled: SettingKey<Bool> {
        return .init(name: "notification.enabled", defaultValue: false)
    }
    
    static var notificationOnUserTurn: SettingKey<Bool> {
        return .init(name: "notification.onUserTurn", defaultValue: true)
    }
    
    static var notificationOnNewGame: SettingKey<Bool> {
        return .init(name: "notification.onNewGame", defaultValue: true)
    }
        
    static var notiticationOnGameEnd: SettingKey<Bool> {
        return .init(name: "notification.onGameEnd", defaultValue: true)
    }

    static var notificationOnTimeRunningOut: SettingKey<Bool> {
        return .init(name: "notification.onTimeRunningOut", defaultValue: true)
    }
    
    static var notificationOnChallengeReceived: SettingKey<Bool> {
        return .init(name: "notification.onChallengeReceived", defaultValue: true)
    }
    
    static var latestNotificationCheck: SettingKey<Date> {
        return .init(name: "latestNotificationCheck")
    }
}

@propertyWrapper
struct Setting<Value> where Value: Codable {
    var settingKey: SettingKey<Value>
    
    init(key: SettingKey<Value>) {
        self.settingKey = key
    }
    
    var wrappedValue: Value? {
        get {
            return userDefaults[settingKey]
        }
        set {
            userDefaults[settingKey] = newValue
        }
    }
}

@propertyWrapper
struct SettingWithDefault<Value> where Value: Codable {
    var settingKey: SettingKey<Value>
    
    init(key: SettingKey<Value>) {
        self.settingKey = key
    }
    
    var wrappedValue: Value {
        get {
            return userDefaults[settingKey]!
        }
        set {
            userDefaults[settingKey] = newValue
        }
    }
    
    var binding: Binding<Value> {
        return Binding<Value>(
            get: {
                return self.wrappedValue
            },
            set: { newValue in
                userDefaults[settingKey] = newValue
            }
        )
    }
}
