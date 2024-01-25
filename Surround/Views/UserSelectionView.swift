//
//  UserSelectionView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 06/02/2021.
//

import SwiftUI
import UIKit
import URLImage
import Combine

struct SearchBar: UIViewRepresentable {
    typealias UIViewType = UISearchBar
    @Binding var text: String
    var placeholder: String?

    class Coordinator: NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            self.text = searchText
            searchBar.setShowsCancelButton(text.count > 0, animated: true)
        }
        
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
        
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            self.text = ""
            searchBar.setShowsCancelButton(false, animated: true)
            searchBar.resignFirstResponder()
        }
    }
    
    func makeCoordinator() -> SearchBar.Coordinator {
        return Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.placeholder = placeholder
        searchBar.delegate = context.coordinator
        searchBar.autocapitalizationType = .none
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }
}

struct UserSelectionView: View {
    @EnvironmentObject var ogs: OGSService
    
    var user: Binding<OGSUser?> = .constant(nil)
    var isPresented: Binding<Bool> = .constant(true)
    @State var searchText = ""
    @State var searchResultByKeyword = [String: [OGSUser]]()
    @State var searchRequestByKeyword = [String: AnyCancellable]()
    
    func selectUser(_ user: OGSUser) {
        if user.id != ogs.user?.id {
            self.user.wrappedValue = user
            self.isPresented.wrappedValue = false
        }
    }
    
    func userRow(_ user: OGSUser) -> some View {
        Button(action: { self.selectUser(user) }) {
            HStack {
                if let iconURL = user.iconURL(ofSize: 64) {
                    URLImage(url: iconURL) { $0.resizable() }
                        .frame(width: 64, height: 64)
                        .background(Color.gray)
                        .cornerRadius(10)
                }
                VStack(alignment: .leading) {
                    Text(verbatim: user.username).bold()
                    Text(verbatim: "[\(user.formattedRank)]").font(.subheadline)
                }
                .foregroundColor(user.uiColor)
                Spacer()
                if user.id == self.user.wrappedValue?.id {
                    Image(systemName: "checkmark")
                }
            }
            .padding()
        }
    }
    
    var friendList: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack() {
                    Text("Friends")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    Spacer()
                }
                .background(Color(.systemGray3))
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(ogs.friends, id: \.id) { friend in
                        userRow(friend)
                        Divider()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var searchResult: some View {
        if let users = self.searchResultByKeyword[self.searchText] {
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(users, id: \.id) { user in
                            userRow(user)
                            Divider()
                        }
                    }
                }
            }
        } else {
            if self.searchRequestByKeyword[self.searchText] != nil {
                ProgressView().padding()
            } else {
                Text("No players found.").padding()
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: String(localized: "Search by user name"))
            
            if searchText.count == 0 {
                if ogs.friends.count > 0 {
                    friendList
                }
            } else {
                searchResult
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchText) { keyword in
            if keyword.count > 0 {
                if searchRequestByKeyword[keyword] == nil {
                    searchRequestByKeyword[keyword] = ogs.searchByUsername(keyword: keyword).sink(receiveCompletion: { _ in
                        searchRequestByKeyword[keyword] = nil
                    }, receiveValue: { users in
                        searchResultByKeyword[keyword] = users
                    })
                }
            }
        }
    }
}

struct UserSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            UserSelectionView(user: .constant(OGSUser(
                username: "kata-bot",
                id: 592684,
                ranking: 27,
                icon: "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png"
            )))
        }
        .environmentObject(OGSService.previewInstance(friends: [
            OGSUser(
                username: "kata-bot",
                id: 592684,
                ranking: 27,
                icon: "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png"
            )
        ]))
    }
}
