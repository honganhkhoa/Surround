//
//  NoticesPlaceholderCover.swift
//  Surround
//
//  Debug-only placeholder for the moderator superchat cover, to probe one
//  overlay window per scene over sheets, popovers, alerts, menus, share
//  sheets, Safari and the keyboard. See NoticesPlaceholderCoverContract for
//  its flags. Every string is verbatim: no localization keys.
//

#if DEBUG && MAIN_APP
import SwiftUI
import UIKit

extension NoticesPlaceholderCoverState {
    /// The probe's state, or nil without its flag. A malformed flag stops the launch.
    static let shared: NoticesPlaceholderCoverState? = {
        let configuration: NoticesPlaceholderCoverConfiguration?
        do {
            configuration = try NoticesPlaceholderCoverConfiguration.parse(ProcessInfo.processInfo.arguments)
        } catch {
            preconditionFailure("Invalid placeholder cover launch arguments: \(error)")
        }
        guard let configuration else { return nil }
        let state = NoticesPlaceholderCoverState(configuration: configuration)
        NoticesPlaceholderCoverDarwinCommands.start()
        let variants = configuration.variants.map(\.rawValue).sorted().joined(separator: ",")
        SceneCoverLog.record("NOTICES-COVER enabled raiseAfter=\(configuration.raiseAfterLaunch.map { "\($0)" } ?? "none") "
            + "reraise=\(configuration.reraiseDelay) variants=\(variants.isEmpty ? "none" : variants)")
        return state
    }()
}

/// Darwin commands. Their callbacks arrive on the main run loop.
private enum NoticesPlaceholderCoverDarwinCommands {
    private final class Token {}
    private static let token = Token()

    static func start() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(token).toOpaque())
        for command in NoticesPlaceholderCoverContract.Command.allCases {
            CFNotificationCenterAddObserver(
                center, observer,
                { _, _, name, _, _ in
                    guard let name,
                          let command = NoticesPlaceholderCoverContract.Command(rawValue: name.rawValue as String)
                    else { return }
                    DispatchQueue.main.async {
                        NoticesPlaceholderCoverState.shared?.perform(command)
                    }
                },
                command.rawValue as CFString, nil, .deliverImmediately
            )
        }
    }
}

/// Mounts the placeholder cover in every scene. Nothing without the flag.
struct NoticesPlaceholderCoverProbe: ViewModifier {
    func body(content: Content) -> some View {
        if let state = NoticesPlaceholderCoverState.shared {
            content.modifier(NoticesPlaceholderCoverMount(state: state))
        } else {
            content
        }
    }
}

private struct NoticesPlaceholderCoverMount: ViewModifier {
    @ObservedObject var state: NoticesPlaceholderCoverState

    func body(content: Content) -> some View {
        content
            #if targetEnvironment(macCatalyst)
            // AppKit draws the toolbar outside the cover window, so disable the
            // SwiftUI content (toolbar items included) while covered.
            .disabled(state.isRaised && !state.configuration.variants.contains(.keepContentEnabled))
            #endif
            .background {
                SceneCoverAnchor(isRaised: state.isRaised, options: state.configuration.coverOptions) {
                    NoticesPlaceholderCoverView(state: state)
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
    }
}

/// After the canvas's moderator cover (Inline.dc.html, "The one
/// interruption"): a header, the conversation and a reply box, plus Debug
/// controls and what the cover rose over.
private struct NoticesPlaceholderCoverView: View {
    private typealias ID = NoticesPlaceholderCoverContract.AccessibilityID

    @ObservedObject var state: NoticesPlaceholderCoverState
    @EnvironmentObject private var cover: SceneCoverContext
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "[Moderator's message]")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 18))
                    report
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            Divider()
            composer
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ID.cover)
        // A scene's first rise can land before this view first renders, so act
        // on the initial value too; the guard skips a render made while lowered.
        .onChange(of: cover.raiseCount, initial: true) { _, _ in
            guard cover.isRaised, state.configuration.variants.contains(.focusReply) else { return }
            replyFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Moderator chat")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Placeholder cover (Debug). Surround is locked until the moderator ends this chat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button { state.lower() } label: { Text(verbatim: "Lower") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(ID.lower)
                Button { state.lowerThenRaiseAgain() } label: {
                    Text(verbatim: "Lower, raise in \(Int(state.configuration.reraiseDelay)) s")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(ID.reraise)
            }
        }
        .padding(16)
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(cover.report.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ID.report)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(text: $reply, prompt: Text(verbatim: "Reply")) {
                Text(verbatim: "Reply to the moderator")
            }
            .textFieldStyle(.roundedBorder)
            .focused($replyFocused)
            .accessibilityIdentifier(ID.reply)
            Button { reply = "" } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(reply.isEmpty)
            .accessibilityLabel(Text(verbatim: "Send"))
            .accessibilityIdentifier(ID.send)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }
}

/// Debug menu on Mac and in the iPadOS 26 menu bar; empty without the flag.
struct NoticesPlaceholderCoverCommands: Commands {
    var body: some Commands {
        if let state = NoticesPlaceholderCoverState.shared {
            NoticesPlaceholderCoverMenu(state: state)
        }
    }
}

private struct NoticesPlaceholderCoverMenu: Commands {
    @ObservedObject var state: NoticesPlaceholderCoverState

    var body: some Commands {
        CommandMenu(Text(verbatim: "Cover Probe")) {
            Button { state.raise() } label: { Text(verbatim: "Raise Placeholder Cover") }
                .keyboardShortcut("k", modifiers: [.command, .control, .option])
            Button { state.raise(after: state.configuration.reraiseDelay) } label: {
                Text(verbatim: "Raise Placeholder Cover in \(Int(state.configuration.reraiseDelay)) Seconds")
            }
            Button { state.lower() } label: { Text(verbatim: "Lower Placeholder Cover") }
                .keyboardShortcut("l", modifiers: [.command, .control, .option])
        }
        // The probe's question: can the app disable New Window while covered?
        // The action does not check the state, so a menu that fails to
        // refresh shows up as a window opening under the cover.
        CommandGroup(replacing: .newItem) {
            Button {
                UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest()) { error in
                    SceneCoverLog.record("NOTICES-COVER newWindow failed: \(error.localizedDescription)")
                }
            } label: { Text(verbatim: "New Window") }
            .keyboardShortcut("n")
            .disabled(state.isRaised)
        }
    }
}
#endif
