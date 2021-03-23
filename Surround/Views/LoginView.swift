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
            GroupBox(label: Text("Sign in to your Online-go.com (OGS) account:").leadingAlignedInScrollView()) {
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
            GroupBox(label: Text("If your OGS account was linked to a social account:").leadingAlignedInScrollView()) {
                NavigationLink(destination: ThirdPartyLoginView(type: .facebook), isActive: $isShowingFacebookLogin) {
                    Text("Sign in to OGS with Facebook")
                        .leadingAlignedInScrollView()
                        .padding(.vertical, 5)
                }
                NavigationLink(destination: ThirdPartyLoginView(type: .google), isActive: $isShowingGoogleLogin) {
                    Text("Sign in to OGS with Google")
                        .leadingAlignedInScrollView()
                        .padding(.vertical, 5)
                }
                NavigationLink(destination: ThirdPartyLoginView(type: .twitter), isActive: $isShowingTwitterLogin) {
                    Text("Sign in to OGS with Twitter")
                        .leadingAlignedInScrollView()
                        .padding(.vertical, 5)
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
        .previewLayout(.fixed(width: 300, height: 500))
        .environmentObject(OGSService.previewInstance())
    }
}
