//
//  AboutView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 15/03/2021.
//

import SwiftUI
import StoreKit

struct ThanksView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Group {
                    Text("[**The OGS Team**](https://online-go.com/docs/team), for creating and maintaining an excellent Go Server with open API, and for all the support during the development of the app.")
                        .foregroundColor(Color(.label))
                        .leadingAlignedInScrollView()
                    Divider()
                    Text("[**Alexandru Cristescu**](https://github.com/acristescu), for creating the [**Sente**](https://github.com/acristescu/OnlineGo) Android app for OGS and making it open source. The process of creating this Android app, along with the project itself have been great reference materials for me during development.").foregroundColor(Color(.label))
                        .leadingAlignedInScrollView()
                    Divider()
                    Text("[**Linh Pham**](https://linhpham.me), for creating the app icon, and providing design advises for the app.").foregroundColor(Color(.label))
                        .leadingAlignedInScrollView()
                    Divider()
                    Text("Everyone who participated in the [beta testing](https://forums.online-go.com/t/surround-ios-client-for-ogs/34437), for helping me to improve the app with many feedbacks and bug reports.")
                        .foregroundColor(Color(.label))
                        .leadingAlignedInScrollView()
                    Divider()
                    Text("[**Raphaël Assenat**](https://www.raphnet.net/index_en.php), for kickstarting the effort to translate this app to multiple languages, and for translating the app to Japanese.")
                        .foregroundColor(Color(.label))
                        .leadingAlignedInScrollView()
                }
                Divider().padding(.vertical, 10)
                Group {
                    (Text("**Surround** includes these open source components:"))
                        .leadingAlignedInScrollView()
                    Link(destination: URL(string: "https://github.com/Alamofire/Alamofire")!) {
                        Text("• Alamofire").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/elegantchaos/DictionaryCoding")!) {
                        Text("• DictionaryCoding").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/dmytro-anokhin/url-image")!) {
                        Text("• URLImage").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/online-go/score-estimator")!) {
                        Text("• OGS's score-estimator").leadingAlignedInScrollView()
                    }
                }
            }
            .frame(maxWidth: 600)
            .padding()
        }
        .navigationTitle("Thanks to")
    }
}

struct AboutView: View {
    @EnvironmentObject var ogs: OGSService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    Image("ogs")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                    (Text("The **Online Go Server** (OGS) is a popular server to play Go online, accessed by visiting https://online-go.com. OGS features a modern user interface and a friendly, welcoming community of Go players."))
                        .leadingAlignedInScrollView()
                    Divider()
                    Link(destination: URL(string: "https://online-go.com/user/supporter")!) {
                        HStack {
                            Text("Support OGS").bold()
                            Spacer()
                        }
                    }
                    Divider()
                }
                Spacer().frame(height: 20)
                Group {
                    Image("Surround")
                        .cornerRadius(10)
                    (Text("**Surround** is an iOS app that aims to provide the best OGS experience on iOS devices. This app uses OGS's open API to talk to the server, and uses iOS native features to improve some aspects that OGS cannot provide due to their nature being a web app supporting every kinds of devices."))
                        .leadingAlignedInScrollView()
                    Spacer().frame(height: 10)
                    (Text("Currently, **Surround** only supports a small subset of features on OGS, and I plan to implement support for more features gradually. Following the spirit of OGS, most features are available for free, but I would really appreciate if you decide to support the development of the app."))
                        .leadingAlignedInScrollView()
                    Group {
                        Divider()
                        if SKPaymentQueue.canMakePayments() {
                            NavigationLink(destination: SupporterView()) {
                                HStack {
                                    Text("Support Surround").bold()
                                    Spacer()
                                    Image(systemName: "chevron.forward")
                                }
                            }
                            Divider()
                        }
                        NavigationLink(destination: ThanksView()) {
                            HStack {
                                Text("Thanks to").bold()
                                Spacer()
                                Image(systemName: "chevron.forward")
                            }
                        }
                        Divider()
                        NavigationLink(destination: OGSBrowserView(initialURL: URL(string: "https://files.honganhkhoa.com/SurroundTerms.html")!).navigationBarTitleDisplayMode(.inline)) {
                            HStack {
                                Text("Terms of Use").bold()
                                Spacer()
                                Image(systemName: "chevron.forward")
                            }
                        }
                        Divider()
                        NavigationLink(destination: OGSBrowserView(initialURL: URL(string: "https://files.honganhkhoa.com/SurroundPrivacyPolicy.html")!).navigationBarTitleDisplayMode(.inline)) {
                            HStack {
                                Text("Privacy Policy").bold()
                                Spacer()
                                Image(systemName: "chevron.forward")
                            }
                        }
                        Divider()
                        Link(destination: URL(string: "mailto:khoahong@hey.com")!) {
                            HStack {
                                Text("Contact").bold()
                                Spacer()
                            }
                        }
                        Divider()
                    }
                }
            }
            .frame(maxWidth: 600)
            .padding()
        }
        .navigationTitle("About")
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationService.shared.main.rootView = .about
        return Group {
            NavigationView {
                ThanksView()
            }
            NavigationView {
                AboutView()
                    .modifier(RootViewSwitchingMenu())
            }
        }
        .environmentObject(OGSService.previewInstance(user: OGSUser(username: "user", id: 0)))
        .environmentObject(NavigationService.shared)
        
    }
}
