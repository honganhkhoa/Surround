//
//  OGSAutomatchEntry.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/02/2021.
//

import Foundation

struct OGSAutomatchEntry: Codable {
    var sizeOptions: Set<Int>
    var timeControlSpeed: TimeControlSpeed
    var uuid: String
    
    init(sizeOptions: Set<Int>, timeControlSpeed: TimeControlSpeed) {
        self.sizeOptions = sizeOptions
        self.timeControlSpeed = timeControlSpeed
        self.uuid = UUID().uuidString.lowercased()
    }
    
    init?(_ jsonObject: [String: Any]) {
        if let sizeSpeedOptions = jsonObject["size_speed_options"] as? [[String: String]] {
            sizeOptions = Set<Int>()
            timeControlSpeed = .live
            for sizeSpeedOption in sizeSpeedOptions {
                if let sizeString = sizeSpeedOption["size"] as String? {
                    if let size = Int(sizeString.split(separator: "x").first ?? "") {
                        sizeOptions.insert(size)
                    }
                }
                if let speedString = sizeSpeedOption["speed"] {
                    if let speed = TimeControlSpeed(rawValue: speedString) {
                        timeControlSpeed = speed
                        continue
                    }
                }
                
                // In case speed parameter is invalid
                return nil
            }
            if let uuid = jsonObject["uuid"] as? String {
                self.uuid = uuid
            } else {
                return nil
            }
            return
        }
        return nil
    }
    
    var jsonObject: [String: Any] {
        [
            "upper_rank_diff": 3,
            "lower_rank_diff": 3,
            "size_speed_options": Array(sizeOptions).map {
                ["size": "\($0)x\($0)", "speed": timeControlSpeed.rawValue]
            },
            "rules": [
                "condition": "no-preference",
                "value": "japanese"
            ],
            "time_control": [
                "condition": "no-preference",
                "value": [
                    "system": timeControlSpeed == .correspondence ? "fischer" : "byoyomi"
                ]
            ],
            "handicap": [
                "condition": "no-preference",
                "value": timeControlSpeed == .blitz ? "disabled" : "enabled"
            ],
            "uuid": uuid
        ]
    }
}


extension OGSAutomatchEntry {
    static var sampleEntry: OGSAutomatchEntry {
        let data = #"""
            {
              "uuid": "f0050bcf-f5fc-46c8-9ed6-01dfd898e0d0",
              "size_speed_options": [
                {
                  "size": "9x9",
                  "speed": "live"
                },
                {
                  "size": "13x13",
                  "speed": "live"
                }
              ],
              "lower_rank_diff": 3,
              "upper_rank_diff": 3,
              "rules": {
                "condition": "no-preference",
                "value": "japanese"
              },
              "time_control": {
                "condition": "no-preference",
                "value": {
                  "system": "byoyomi"
                }
              },
              "handicap": {
                "condition": "no-preference",
                "value": "enabled"
              }
            }
        """#
        let jsonObject = try! JSONSerialization.jsonObject(with: data.data(using: .utf8)!) as! [String: Any]
        return OGSAutomatchEntry(jsonObject)!
    }
}
