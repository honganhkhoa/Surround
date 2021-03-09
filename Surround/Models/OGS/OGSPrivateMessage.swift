//
//  OGSPrivateMessage.swift
//  Surround
//
//  Created by Anh Khoa Hong on 02/03/2021.
//

import Foundation

struct OGSPrivateMessageContent: Codable, Equatable {
    var id: String
    var message: String
    var timestamp: Double
    
    enum CodingKeys: String, CodingKey {
        case id = "i"
        case message = "m"
        case timestamp = "t"
    }
    
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        return formatter
    }()
    
    var dateString: String {
//        return "xx \(Date(timeIntervalSince1970: timestamp))"
        return OGSPrivateMessageContent.dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

struct OGSPrivateMessage: Codable, Equatable {
    var from: OGSUser
    var to: OGSUser
    var content: OGSPrivateMessageContent
    
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case content = "message"
    }
    
    var messageKey: String {
        "\(content.id) \(content.timestamp) \(from.username)"
    }
    
    static func == (lhs: OGSPrivateMessage, rhs: OGSPrivateMessage) -> Bool {
        return lhs.content == rhs.content && lhs.from.id == rhs.from.id && lhs.to.id == rhs.to.id
    }
}


extension OGSPrivateMessage {
    static var sampleData: [OGSPrivateMessage] {
        let rawData = #"""
            {"to":{"id":765826,"username":"hakhoa"},"message":{"i":"kvs.1","m":"Hi :)","t":1614162671},"from":{"country":"un","id":314459,"professional":false,"ratings":{"overall":{"volatility":0.059900000000000002,"deviation":64.5381,"rating":1863.1097}},"username":"HongAnhKhoa","ui_class":"supporter","ranking":29}}
            {"to":{"id":765826,"username":"hakhoa"},"message":{"i":"kvs.2","m":":)","t":1614162736},"from":{"country":"un","id":314459,"professional":false,"ratings":{"overall":{"volatility":0.059900000000000002,"deviation":64.5381,"rating":1863.1097}},"username":"HongAnhKhoa","ui_class":"supporter","ranking":29}}
            {"to":{"id":314459,"username":"HongAnhKhoa"},"message":{"i":"1xch.1","m":"hi","t":1614575486},"from":{"country":"un","id":765826,"professional":false,"ratings":{"overall":{"volatility":0.059999999999999998,"deviation":123.9323,"rating":1536.7655999999999}},"username":"hakhoa","ui_class":"","ranking":24}}
            {"to":{"id":314459,"username":"HongAnhKhoa"},"message":{"i":"l57.1","m":":)","t":1614575997},"from":{"country":"un","id":765826,"professional":false,"ratings":{"overall":{"volatility":0.059999999999999998,"deviation":123.9323,"rating":1536.7655999999999}},"username":"hakhoa","ui_class":"","ranking":24}}
            {"to":{"id":765826,"username":"hakhoa"},"message":{"i":"142l.1","m":"...","t":1614679401},"from":{"country":"un","id":314459,"professional":false,"ratings":{"overall":{"volatility":0.059900000000000002,"deviation":64.5381,"rating":1863.1097}},"username":"HongAnhKhoa","ui_class":"supporter","ranking":29}}
            {"to":{"id":765826,"username":"hakhoa"},"message":{"i":"142l.2","m":":)","t":1614680257},"from":{"country":"un","id":314459,"professional":false,"ratings":{"overall":{"volatility":0.059900000000000002,"deviation":64.5381,"rating":1863.1097}},"username":"HongAnhKhoa","ui_class":"supporter","ranking":29}}
            {"to":{"id":765826,"username":"hakhoa"},"message":{"i":"1ux1.1","m":"The quick brown fox jumps over the lazy dog...","t":1614748606},"from":{"country":"un","id":314459,"professional":false,"ratings":{"overall":{"volatility":0.059900000000000002,"deviation":64.5381,"rating":1863.1097}},"username":"HongAnhKhoa","ui_class":"supporter","ranking":29}}
            {"from":{"id":955348,"username":"khoahong","ranking":24,"ratings":{"version":5,"overall":{"rating":1500,"deviation":350,"volatility":0.06}},"country":"un","professional":false,"ui_class":"provisional"},"to":{"id":765826,"username":"hakhoa"},"message":{"i":"1gfu.1","t":1615195451,"m":"hey :)"}}
        """#
        var result = [OGSPrivateMessage]()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for line in rawData.split(separator: "\n") {
            try! result.append(decoder.decode(OGSPrivateMessage.self, from: line.data(using: .utf8)!))
        }
        return result
    }
}
