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
        searchBar.searchTextField.accessibilityIdentifier = SurroundUITestContract.AccessibilityID.opponentSearch
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }
}

struct UserSelectionView: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject private var navigation: StackRouter
    
    var user: Binding<OGSUser?> = .constant(nil)
    var selection: OpponentSelection? = nil
    @State var searchText = ""
    @State var searchResultByKeyword = [String: [OGSUser]]()
    @State var searchRequestByKeyword = [String: AnyCancellable]()
    @State private var rootSelection: RootOpponentSelection?

    private var currentSelection: OpponentSelection? { selection ?? rootSelection?.selection }
    private var selectedUser: OGSUser? { currentSelection?.selectedUser() ?? user.wrappedValue }
    
    func selectUser(_ user: OGSUser) {
        if let selection = currentSelection {
            navigation.selectOpponent(user, selectionID: selection.id, viewerID: ogs.user?.id)
        }
    }
    
    func userRow(_ user: OGSUser) -> some View {
        HStack(spacing: 0) {
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
                    if user.id == selectedUser?.id {
                        Image(systemName: "checkmark")
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(
                user.id == selectedUser?.id ? .isSelected : []
            )
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.opponentSelection(user.id))

            if user.id > 0 {
                Button {
                    if let selection = currentSelection {
                        navigation.openProfile(user, selectionID: selection.id)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(
                    Text(
                        "View \(user.username)’s profile",
                        comment: "Accessibility label for a button that opens a player's profile"
                    )
                )
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profilePickerEntry(user.id))
                .padding(.trailing, 8)
            }
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
                if ogs.friendsError != nil || ogs.friendsLoading {
                    VStack(spacing: 8) {
                        if ogs.friendsError != nil {
                            Text("Couldn’t load friends")
                                .foregroundStyle(.secondary)
                        }
                        if ogs.friendsLoading {
                            ProgressView()
                        } else {
                            Button("Try Again") { ogs.fetchFriends() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
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
                if !ogs.friends.isEmpty || ogs.friendsLoading || ogs.friendsError != nil {
                    friendList
                }
            } else {
                searchResult
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenOpponentPicker)
        .onAppear {
            guard selection == nil else { return }
            if let rootSelection, navigation.selections[rootSelection.selection.id] != nil { return }
            rootSelection = navigation.registerRootPicker(user: user)
        }
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

    return AppNavigationStack {
        UserSelectionView(user: $selectedUser)
    }
    .environmentObject(NavigationService())
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

    return AppNavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: searchText,
            searchResultByKeyword: [searchText: users]
        )
    }
    .environmentObject(NavigationService())
    .environmentObject(OGSService.previewInstance())
}

#Preview("Opponent selection — Searching") {
    @Previewable @State var selectedUser: OGSUser?
    let searchText = "rin"

    return AppNavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: searchText,
            searchRequestByKeyword: [searchText: AnyCancellable {}]
        )
    }
    .environmentObject(NavigationService())
    .environmentObject(OGSService.previewInstance())
}

#Preview("Opponent selection — No results") {
    @Previewable @State var selectedUser: OGSUser?

    return AppNavigationStack {
        UserSelectionView(
            user: $selectedUser,
            searchText: "unknown-player"
        )
    }
    .environmentObject(NavigationService())
    .environmentObject(OGSService.previewInstance())
}
#endif
