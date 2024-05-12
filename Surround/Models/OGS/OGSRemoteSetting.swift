//
//  OGSRemoteStorage.swift
//  Surround
//
//  Created by Anh Khoa Hong on 2024/2/29.
//

import Foundation
import DictionaryCoding

enum OGSRemoteReplication: Int, Codable {
    case None = 0
    case LocalOverwritesRemote
    case RemoteOverwritesLocal
    case RemoteOnly
}

struct OGSRemoteSettingValue<T>: Codable where T: Codable {
    var value: T
    var replication: OGSRemoteReplication
    var modified: Date
}

protocol OGSRemoteSettingKeyProtocol {
    func saveIfValid(settings: [String: Any], replication: OGSRemoteReplication, modified: Date) -> Bool
    func saveIfValid(settings: [[String: Any]], replication: OGSRemoteReplication, modified: Date) -> Bool
    func reset()
}

struct OGSRemoteSettingKey<T>: OGSRemoteSettingKeyProtocol where T: Codable {
    var name: String
    var remoteName: String
    
    internal init(remoteName: String) {
        self.remoteName = remoteName
        self.name = "com.honganhkhoa.Surround.ogs.\(remoteName)"
    }
    
    @discardableResult
    func saveIfValid(settings: [String: Any], replication: OGSRemoteReplication, modified: Date) -> Bool {
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let settings = try? decoder.decode(T.self, from: settings) {
            do {
                try userDefaults.setValue(
                    JSONEncoder().encode(
                        OGSRemoteSettingValue(
                            value: settings,
                            replication: replication,
                            modified: modified)),
                    forKey: self.name)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    @discardableResult
    func saveIfValid(settings: [[String: Any]], replication: OGSRemoteReplication, modified: Date) -> Bool {
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let settingsWrapper = try? decoder.decode([String: T].self, from: ["a": settings]) {
            do {
                try userDefaults.setValue(
                    JSONEncoder().encode(
                        OGSRemoteSettingValue(
                            value: settingsWrapper["a"]!,
                            replication: replication,
                            modified: modified)),
                    forKey: self.name)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    func reset() {
        userDefaults.removeObject(forKey: self.name)
    }
}

class OGSRemoteSetting {
    static var shared = OGSRemoteSetting()
    var settingByRemoteName: [String: Any] = [:]
    var dictionaryDecoder: DictionaryDecoder = {
        let decoder = DictionaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    private init() {
        let allSettingKeys: [OGSRemoteSettingKey] = [.preferredGameSettings]
        for key in allSettingKeys {
            settingByRemoteName[key.remoteName] = key
        }
    }
    
    subscript<T>(key: OGSRemoteSettingKey<T>) -> T? where T: Codable {
        get {
            if let result = userDefaults.data(forKey: key.name) {
                return try? JSONDecoder().decode(OGSRemoteSettingValue<T>.self, from: result).value
            } else {
                return nil
            }
        }
    }
    
    public func remoteName<T>(key: OGSRemoteSettingKey<T>) -> String where T: Codable {
        return key.remoteName
    }
    
    @discardableResult
    public func saveIfValid(settings: Any, remoteName: String, replication: OGSRemoteReplication, modified: Date) -> Bool {
        if let settingKey = settingByRemoteName[remoteName] as? OGSRemoteSettingKeyProtocol {
            if let settings = settings as? [String: Any] {
                return settingKey.saveIfValid(settings: settings, replication: replication, modified: modified)
            } else if let settings = settings as? [[String: Any]] {
                return settingKey.saveIfValid(settings: settings, replication: replication, modified: modified)
            }
        }
        return false
    }
    
    public func resetAllSettings() {
        for settingKey in settingByRemoteName.values {
            if let settingKey = settingKey as? OGSRemoteSettingKeyProtocol {
                settingKey.reset()
            }
        }
    }
}

extension OGSRemoteSettingKey {
    static var preferredGameSettings: OGSRemoteSettingKey<[OGSChallengeTemplate]> {
        return .init(remoteName: "preferred-game-settings")
    }
}
