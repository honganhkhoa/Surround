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
                    Link(destination: URL(string: "https://online-go.com/docs/team")!) {
                        (Text("The OGS Team").bold() + Text(", for creating and maintaining an excellent Go Server with open API, and for all the support during the development of the app.").foregroundColor(Color(.label)))
                            .leadingAlignedInScrollView()
                    }
                    Divider()
                    Link(destination: URL(string: "https://github.com/acristescu/OnlineGo")!) {
                        (Text("MrAlex").bold() + Text(", for creating the ").foregroundColor(Color(.label)) + Text("Online GO").bold() + Text(" Android app for OGS and making it open source. The process of creating this Android app, along with the project itself have been great reference materials for me during development.").foregroundColor(Color(.label)))
                            .leadingAlignedInScrollView()
                    }
                    Divider()
                    Link(destination: URL(string: "https://linhpham.me")!) {
                        (Text("Linh Pham").bold() + Text(", for creating the app icon, and providing design advises for the app.").foregroundColor(Color(.label)))
                            .leadingAlignedInScrollView()
                    }
                    Divider()
                    Link(destination: URL(string: "https://forums.online-go.com/t/surround-ios-client-for-ogs/34437")!) {
                        Text("Everyone who participated in the beta testing, for helping me to improve the app with many feedbacks and bug reports.")
                            .foregroundColor(Color(.label))
                            .leadingAlignedInScrollView()
                    }
                }
                Divider().padding(.vertical, 10)
                Group {
                    (Text("Surround").bold() + Text(" includes these open source components:"))
                        .leadingAlignedInScrollView()
                    Link(destination: URL(string: "https://github.com/Alamofire/Alamofire")!) {
                        Text("• Alamofire").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/socketio/socket.io-client-swift")!) {
                        Text("• Socket.IO-Client-Swift").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/elegantchaos/DictionaryCoding")!) {
                        Text("• DictionaryCoding").leadingAlignedInScrollView()
                    }
                    Link(destination: URL(string: "https://github.com/dmytro-anokhin/url-image")!) {
                        Text("• URLImage").leadingAlignedInScrollView()
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
                    (Text("The ") + Text("Online Go Server").bold() + Text(" (OGS) is a popular server to play Go online, accessed by visiting https://online-go.com. OGS features a modern user interface and a friendly, welcoming community of Go players."))
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
                    (Text("Surround").bold() + Text(" is an iOS app that aims to provide the best OGS experience on iOS devices. This app uses OGS's open API to talk to the server, and uses iOS native features to improve some aspects that OGS cannot provide due to their nature being a web app supporting every kinds of devices."))
                        .leadingAlignedInScrollView()
                    Spacer().frame(height: 10)
                    (Text("Currently, ") + Text("Surround").bold() + Text(" only supports a small subset of features on OGS, and I plan to implement support for more features gradually. Following the spirit of OGS, most features are available for free, but I would really appreciate if you decide to support the development of the app."))
                        .leadingAlignedInScrollView()
                    Group {
                        Divider()
                        if ogs.isLoggedIn && SKPaymentQueue.canMakePayments() {
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
        .modifier(RootViewSwitchingMenu())
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
            }
        }
        .environmentObject(OGSService.previewInstance(user: OGSUser(username: "user", id: 0)))
        .environmentObject(NavigationService.shared)
        
    }
}
