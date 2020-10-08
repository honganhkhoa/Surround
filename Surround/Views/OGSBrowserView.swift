//
//  OGSBrowserView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/8/20.
//

import SwiftUI
import UIKit
import WebKit
import Alamofire
import Combine

struct OGSBrowserView: View {
    @State var title: String?
    @State var isLoading: Bool = true
    
    var body: some View {
        OGSBrowserWebView(isLoading: $isLoading, title: $title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: isLoading ? AnyView(ProgressView()) : AnyView(EmptyView()))
            .navigationTitle(title ?? "")
            .modifier(RootViewSwitchingMenu())
    }
}

struct OGSBrowserWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView
    @EnvironmentObject var ogs: OGSService
    @Binding var isLoading: Bool
    @Binding var title: String?
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let ogsURL = URL(string: OGSService.ogsRoot)!
        
        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: ogsURL)
        
        if ogs.ogsUIConfig != nil {
            if let cookies = Session.default.sessionConfiguration.httpCookieStorage?.cookies {
                for cookie in cookies {
                    webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
                request.url = URL(string: "\(OGSService.ogsRoot)/overview")
            }
        }
        
        context.coordinator.loadingObservation = webView.observe(\.isLoading, options: [.new], changeHandler: { _, change in
            if let newValue = change.newValue {
                if isLoading != newValue {
                    DispatchQueue.main.async {
                        isLoading = newValue
                    }
                }
            }
        })
        context.coordinator.titleObservation = webView.observe(\.title, options: [.new], changeHandler: { _, change in
            if let newTitle = change.newValue {
                if newTitle != title {
                    DispatchQueue.main.async {
                        title = newTitle
                    }
                }
            }
        })
                
        webView.load(request)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OGSBrowserWebView
        var loginCancellable: AnyCancellable?
        var loadingObservation: NSKeyValueObservation?
        var titleObservation: NSKeyValueObservation?

        init(_ parent: OGSBrowserWebView) {
            self.parent = parent
        }
        
        func loginUsingWebviewCredentialsIfNecessary(_ webView: WKWebView) {
            let ogs = parent.ogs
            guard !ogs.isLoggedIn else {
                return
            }

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    if ogs.isOGSDomain(cookie: cookie) && cookie.name == "csrftoken" {
                        self.loginCancellable = ogs.thirdPartyLogin(cookieStore: cookieStore)
                            .sink(receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    print(error)
                                }
                            }, receiveValue: { ogsUIConfig in
                                ogs.loadOverview()
                                print(ogsUIConfig)
                            })
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let ogs = parent.ogs
            if let url = webView.url {
                if ogs.isOGSDomain(url: url) {
                    loginUsingWebviewCredentialsIfNecessary(webView)
                }
            }
        }
    }
}

struct BrowserView_Previews: PreviewProvider {
    static var previews: some View {
        OGSBrowserView()
    }
}
