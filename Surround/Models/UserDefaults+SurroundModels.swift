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
    var mainName: String {
        if let lastPart = name.split(separator: ".").last {
            return String(lastPart)
        }
        return name
    }
    
    internal init(name: String, encoded: Bool = false, defaultValue: Value? = nil) {
        self.name = "com.honganhkhoa.Surround.\(name)"
        self.encoded = encoded
        self._defaultValue = defaultValue
    }
}

// Cannot make this conforms to `ObservableObject` when testing because if will not compile...,
// so we include two implementation here
//
// Related: https://stackoverflow.com/questions/56169303/redundant-conformance-to-protocol-in-unit-test-only
//
#if !TESTING
extension UserDefaults: ObservableObject {
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
            self.objectWillChange.send()
        }
    }
    
    func updateLatestOGSOverview(overviewData: Data) {
        self[.latestOGSOverview] = overviewData
        self[.latestOGSOverviewTime] = Date()
        self[.latestOGSOverviewOutdated] = false
    }
    
    func reset<T>(_ setting: SettingKey<T>) where T: Codable {
        if setting._defaultValue != nil {
            self[setting] = setting._defaultValue
        } else {
            self[setting] = nil
        }
    }
}
#else
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
    
    func updateLatestOGSOverview(overviewData: Data) {
        self[.latestOGSOverview] = overviewData
        self[.latestOGSOverviewTime] = Date()
        self[.latestOGSOverviewOutdated] = false
    }
    
    func reset<T>(_ setting: SettingKey<T>) where T: Codable {
        if setting._defaultValue != nil {
            self[setting] = setting._defaultValue
        } else {
            self[setting] = nil
        }
    }
}
#endif

extension SettingKey {
    static var ogsUIConfig: SettingKey<OGSUIConfig> {
        return .init(name: "ogsUIConfig", encoded: true)
    }
    
    static var ogsSessionId: SettingKey<String> {
        return .init(name: "ogsSessionId")
    }
    
    static var ogsCsrfCookie: SettingKey<String> {
        return .init(name: "ogsCsrfCookie")
    }
    
    static var latestOGSOverview: SettingKey<Data> {
        return .init(name: "latestOGSOverview")
    }
    
    static var latestOGSOverviewTime: SettingKey<Date> {
        return .init(name: "latestOGSOverviewTime")
    }
    
    static var latestOGSOverviewOutdated: SettingKey<Bool> {
        return .init(name: "latestOGSOverviewOutdated", defaultValue: false)
    }
    
#if MAIN_APP
    static var homeViewDisplayMode: SettingKey<String> {
        return .init(name: "homeViewDisplayMode")
    }
#endif
    
    static var hapticsFeedback: SettingKey<Bool> {
        return .init(name: "hapticsFeedback", defaultValue: true)
    }
    
    static var showsBoardCoordinates: SettingKey<Bool> {
        return .init(name: "showsBoardCoordinates", defaultValue: false)
    }
    
    static var showsActiveGamesCarousel: SettingKey<Bool> {
        return .init(name: "showsActiveGamesCarousel", defaultValue: true)
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
    
    static var soundOnStonePlacement: SettingKey<Bool> {
        return .init(name: "soundOnStonePlacement", defaultValue: false)
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
    
    static var hidesRank: SettingKey<Bool> {
        return .init(name: "hidesRank", defaultValue: false)
    }
    
    static var sgsAccessToken: SettingKey<String> {
        return .init(name: "sgsAccessToken")
    }
    
    static var cachedOGSGames: SettingKey<[Int: Data]> {
        return .init(name: "cachedOGSGames", encoded: true, defaultValue: [Int: Data]())
    }
    
    static var lastSeenChatIdByOGSGameId: SettingKey<[Int: String]> {
        return .init(name: "lastSeenChatIdByOGSGameId", encoded: true, defaultValue: [Int: String]())
    }
    
    static var lastAutomatchEntry: SettingKey<OGSAutomatchEntry> {
        return .init(name: "lastAutomatchEntry", encoded: true)
    }
    
    static var lastSeenPrivateMessageByOGSUserId: SettingKey<[Int: Double]> {
        return .init(name: "lastSeenPrivateMessageByOGSUserId", encoded: true, defaultValue: [Int: Double]())
    }
    
    static var supporterProductId: SettingKey<String> {
        return .init(name: "supporterProductId")
    }
    
    static var lastSentReceiptData: SettingKey<String> {
        return .init(name: "lastSentReceiptData")
    }
    
    static var supporterProductExpiryDate: SettingKey<Date> {
        return .init(name: "supporterProductExpiryDate")
    }
    
    static var ogsRemoteStorageLastSync: SettingKey<Date> {
        return .init(name: "ogsRemoteStorageLastSync", defaultValue: Date(timeIntervalSince1970: 946684800)) // 2000/01/01 00:00 GMT
    }
    
    // Reminder: When adding a key, check if it needs to be reset on logout.
}

@propertyWrapper
struct OptionalSetting<Value> where Value: Codable {
    var settingKey: SettingKey<Value>
    
    init(_ key: SettingKey<Value>) {
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
struct Setting<Value> where Value: Codable {
    var settingKey: SettingKey<Value>
    
    init(_ key: SettingKey<Value>) {
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
