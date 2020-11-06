//
//  SurroundService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/28/20.
//

import Foundation
import Alamofire

class SurroundService: ObservableObject {
    static var shared = SurroundService()
    static var instances = [String: SurroundService]()
    
    static func instance(forSceneWithID sceneID: String) -> SurroundService {
        if let result = instances[sceneID] {
            return result
        } else {
            let result = SurroundService()
            instances[sceneID] = result
            return result
        }
    }
    
//    static let sgsRoot = "http://192.168.44.101:8000"
    static let sgsRoot = "https://surround.honganhkhoa.com"
    
    private var sgsRoot = SurroundService.sgsRoot
    
    func isProductionEnvironment() -> Bool {
        if let provisionPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
            if let provisionData = try? Data(contentsOf: URL(fileURLWithPath: provisionPath)) {
                if let provisionString = String(data: provisionData, encoding: .ascii) {
                    let noBlankProvisionString = provisionString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\t", with: "")
//                    print(noBlankProvisionString)
                    return !noBlankProvisionString.contains("<key>aps-environment</key><string>development</string>")
                }
            }
        }
        return true
    }
    
    func registerDeviceIfLoggedIn(pushToken: Data) {
        if let uiconfig = userDefaults[.ogsUIConfig],
           let ogsSessionId = userDefaults[.ogsSessionId],
           let ogsCsrfToken = uiconfig.csrfToken {
            let ogsUserId = uiconfig.user.id
            let ogsUsername = uiconfig.user.username
            var headers = HTTPHeaders()
            if let accessToken = userDefaults[.sgsAccessToken] {
                headers = [.authorization(accessToken)]
            }
            AF.request(
                "\(self.sgsRoot)/register",
                method: .post,
                parameters: [
                    "ogsUserId": ogsUserId,
                    "ogsUsername": ogsUsername,
                    "ogsCsrfToken": ogsCsrfToken,
                    "ogsSessionId": ogsSessionId,
                    "pushToken": pushToken.map { String(format: "%02hhx", $0) }.joined(),
                    "production": isProductionEnvironment()
                ],
                headers: headers
            ).responseJSON { response in
                switch response.result {
                case .success:
                    if let accessToken = (response.value as? [String: Any])?["accessToken"] as? String {
                        userDefaults[.sgsAccessToken] = accessToken
                    }
                case .failure(let error):
                    print(error)
                }
            }
        }
    }
}
