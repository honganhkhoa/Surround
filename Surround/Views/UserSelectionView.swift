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
    @Environment(\.dismiss) private var dismiss
    
    var user: Binding<OGSUser?> = .constant(nil)
    @State var searchText = ""
    @State var searchResultByKeyword = [String: [OGSUser]]()
    @State var searchRequestByKeyword = [String: AnyCancellable]()
    
    func selectUser(_ user: OGSUser) {
        if user.id != ogs.user?.id {
            self.user.wrappedValue = user
            dismiss()
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
                    if !Setting(.hidesRank).wrappedValue {
                        Text(verbatim: "[\(user.formattedRank)]").font(.subheadline)
                    }
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
        .onChange(of: searchText) { _, keyword in
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

#if DEBUG
#Preview("Opponent selection — Friends") {
    @Previewable @State var selectedUser: OGSUser? = OGSUser(
        username: "kata-bot",
        id: 592684,
        ranking: 27
    )
    let friend = OGSUser(
        username: "kata-bot",
        id: 592684,
        ranking: 27
    )

    return NavigationStack {
        UserSelectionView(user: $selectedUser)
    }
    .environmentObject(
        OGSService.previewInstance(
            friends: [friend]
        )
    )
}

#Preview("Opponent selection — Search results") {
    @Previewable @State var selectedUser: OGSUser?
    let searchText = "rin"
    let users = [
        OGSUser(username: "Rin", id: 101, ranking: 30),
        OGSUser(username: "RinGo", id: 102, ranking: 18)
    ]

    return NavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: searchText,
            searchResultByKeyword: [searchText: users]
        )
    }
    .environmentObject(OGSService.previewInstance())
}

#Preview("Opponent selection — Searching") {
    @Previewable @State var selectedUser: OGSUser?
    let searchText = "rin"

    return NavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: searchText,
            searchRequestByKeyword: [searchText: AnyCancellable {}]
        )
    }
    .environmentObject(OGSService.previewInstance())
}

#Preview("Opponent selection — No results") {
    @Previewable @State var selectedUser: OGSUser?

    return NavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: "unknown-player"
        )
    }
    .environmentObject(OGSService.previewInstance())
}
#endif
