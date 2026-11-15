//
//  PrivateMessageComposerState.swift
//  Surround
//
//  What a private conversation's composer allows (in-app notices):
//  when its field and Send are on, and when they read "Reconnecting…". The
//  moderator superchat cover's composer turns off while offline. Messages
//  never sets `isOffline`, so its composer keeps today's rule. Pure, so
//  every combination is unit-tested; PrivateMessageComposer applies it.
//

/// What a conversation's composer allows. Pure, so SurroundTests can check
/// the offline rule with remote activity allowed (UI tests never allow it).
struct PrivateMessageComposerState: Equatable {
    var draftIsEmpty: Bool
    var allowsRemoteActivity: Bool
    var isOffline: Bool

    /// The reply box is disabled while offline.
    var fieldIsEnabled: Bool { !isOffline }
    var sendIsEnabled: Bool { !draftIsEmpty && allowsRemoteActivity && !isOffline }
    /// The field and Send read "Reconnecting…".
    var readsReconnecting: Bool { isOffline }
}
