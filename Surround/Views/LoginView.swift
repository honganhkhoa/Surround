//
//  LoginView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/1/20.
//

import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject var ogs: OGSService
    
    @State var username = ""
    @State var password = ""
    @State var error: String? = nil
    
    @State var loginCancellable: AnyCancellable?
    @State var isShowingFacebookLogin = false
    @State var isShowingGoogleLogin = false
    @State var isShowingTwitterLogin = false
    
    func login() {
        if username.count > 0 && password.count > 0 {
            loginCancellable = ogs.login(username: username, password: password)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            self.error = error.localizedDescription
                        } else {
                            self.error = nil
                        }
                        loginCancellable = nil
                    }, receiveValue: { _ in }
                )
        }
    }
    
    var body: some View {
        VStack {
            GroupBox(label: Text("Sign in to your Online-go.com account")) {
                TextField("Username", text: $username)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                SecureField("Password", text: $password, onCommit: { login() })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    if loginCancellable == nil {
                        Button(action: { login() }) {
                            Text("Sign in")
                                .padding(.vertical, 10)
                        }
                        .disabled(username.count == 0 || password.count == 0)
                    } else {
                        ProgressView()
                            .padding(.vertical, 10)
                    }
                    Spacer()
                }
                if let error = error {
                    HStack {
                        Text(error)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
            GroupBox {
                NavigationLink(destination: ThirdPartyLoginView(type: .facebook), isActive: $isShowingFacebookLogin) {
                    HStack {
                        Text("Sign in with Facebook")
                            .padding(.vertical, 5)
                        Spacer()
                    }
                }
                NavigationLink(destination: ThirdPartyLoginView(type: .google), isActive: $isShowingGoogleLogin) {
                    HStack {
                        Text("Sign in with Google")
                            .padding(.vertical, 5)
                        Spacer()
                    }
                }
                NavigationLink(destination: ThirdPartyLoginView(type: .twitter), isActive: $isShowingTwitterLogin) {
                    HStack {
                        Text("Sign in with Twitter")
                            .padding(.vertical, 5)
                        Spacer()
                    }
                }
            }
            GroupBox {
                Link(destination: URL(string: "\(OGSService.ogsRoot)/register")!) {
                    HStack {
                        Text("New to Online-go.com? Register here.")
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal)
        .onChange(of: ogs.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                isShowingFacebookLogin = false
                isShowingGoogleLogin = false
                isShowingTwitterLogin = false
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                LoginView(error: "Error")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .previewLayout(.fixed(width: 500, height: 500))
        .environmentObject(OGSService.previewInstance())
    }
}
