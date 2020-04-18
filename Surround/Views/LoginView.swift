//
//  LoginView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import SwiftUI
import Combine

struct LoginView: View {
    @State var username = ""
    @State var password = ""
    @Binding var isLoggedIn: Bool
    
    @State var loggingIn: AnyCancellable?
    
    func loginToOGS() {
        loggingIn = OGSService.shared.login(username: username, password: password)
            .sink(receiveCompletion: {completion in
                if case .failure(let error) = completion {
                    print(error)
                }
            }, receiveValue: { config in
                print(config)
                self.isLoggedIn = OGSService.shared.isLoggedIn()
            })
    }
    
    var body: some View {
        Form {
            TextField("Username", text: $username)
                .autocapitalization(.none)
            SecureField("Password", text: $password)
        }.navigationBarTitle(Text("Login to OGS"))
        .navigationBarItems(trailing:
            Button(action: self.loginToOGS) {
                Text("Login")
            }.disabled(username.count == 0 || password.count == 0)
        )
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LoginView(isLoggedIn: .constant(false))
        }
    }
}
