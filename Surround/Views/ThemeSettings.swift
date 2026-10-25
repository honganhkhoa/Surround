import SwiftUI

/// Wears one theme whatever the screen around it wears, so each tile in a
/// picker previews its own theme. Unlike `surroundTheme(_:)`, it sets no
/// window style or toolbar scheme.
private struct ThemePreviewEnvironment: ViewModifier {
    let theme: SurroundTheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let scheme = theme.colorScheme ?? colorScheme
        content
            .environment(\.surroundTheme, theme)
            .environment(\.boardAppearance, theme.board(for: scheme))
            .environment(\.colorScheme, scheme)
    }
}

/// The theme's own scene and the corner of its board, drawn live. Drawing it
/// decodes the theme's full-size art, so pickers show a thumbnail exported
/// from this view instead, and fall back to it only for a theme without one.
struct ThemeLivePreview: View {
    let theme: SurroundTheme

    /// A few stones near the corner the tile shows.
    private static let position: BoardPosition = {
        let position = BoardPosition(width: 9, height: 9)
        position.putStone(row: 1, column: 1, color: .black)
        position.putStone(row: 1, column: 2, color: .white)
        position.putStone(row: 2, column: 1, color: .white)
        position.putStone(row: 2, column: 3, color: .black)
        position.putStone(row: 3, column: 2, color: .white)
        position.putStone(row: 0, column: 3, color: .white)
        return position
    }()

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            // Cells stay above the 14 pt cutoff, so stones and board art are
            // drawn in detail rather than in the small-board flat colors.
            let boardSide = max(side * 2, 150)
            ZStack(alignment: .topLeading) {
                if theme == .surroundStudio {
                    // Anchor the lower tree to the tile, not the oversized
                    // board whose corner fills this preview.
                    GameDetailBackdrop().frame(width: side, height: side)
                } else {
                    GameDetailBackdrop()
                }
                BoardView(boardPosition: Self.position)
                    .frame(width: boardSide, height: boardSide)
                    .offset(x: side * 0.22, y: side * 0.22)
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(ThemePreviewEnvironment(theme: theme))
    }
}

/// A theme's preview tile, following Light and Dark as the theme does.
struct ThemePreviewTile: View {
    let theme: SurroundTheme
    @Environment(\.colorScheme) private var colorScheme

    /// Themes with an exported thumbnail; looked up once.
    private static let thumbnailThemes = Set(SurroundTheme.allCases.filter {
        UIImage(named: $0.previewImageName) != nil
    })

    var body: some View {
        // The square takes its size from the column; the thumbnail fills it.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if Self.thumbnailThemes.contains(theme) {
                    Image(theme.previewImageName)
                        .resizable()
                        .scaledToFill()
                        // Only the scheme, so the asset's Light or Dark variant
                        // follows the theme without resolving its board art.
                        .environment(\.colorScheme, theme.colorScheme ?? colorScheme)
                } else {
                    ThemeLivePreview(theme: theme)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.themePreview(theme.rawValue))
    }
}

/// A grid of theme tiles; choosing one applies it at once. Dark-only themes
/// carry a moon, and Debug builds mark the unreleased themes.
struct ThemePicker: View {
    @Binding var selection: SurroundTheme
    var themes = SurroundTheme.available
    var columns = 4
    @Environment(\.surroundTheme) private var surroundingTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Fewer, wider columns at large text sizes keep theme names whole.
    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return min(columns, 2) }
        if dynamicTypeSize >= .xxLarge { return min(columns, 3) }
        return columns
    }

    private var markColor: Color {
        surroundingTheme == .standard ? .accentColor : surroundingTheme.selectionMark
    }

    /// Plain rows rather than a lazy grid: every tile stays mounted, and
    /// reachable by accessibility, while the screen scrolls.
    private var rows: [[SurroundTheme]] {
        stride(from: 0, to: themes.count, by: columnCount).map {
            Array(themes[$0..<min($0 + columnCount, themes.count)])
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { theme in
                        tile(theme).frame(maxWidth: .infinity)
                    }
                    // A short last row keeps the columns' width.
                    ForEach(row.count..<columnCount, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
        // Rows keep their full height. Offered less, each row would squeeze
        // its squares by a different amount under labels of different
        // heights; a host too short for the picker scrolls it instead.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Theme", comment: "Heading and accessibility label for the choice of theme"))
    }

    private func tile(_ theme: SurroundTheme) -> some View {
        let selected = theme == selection
        return Button { selection = theme } label: {
            VStack(spacing: 6) {
                ThemePreviewTile(theme: theme)
                    .overlay(alignment: .bottomLeading) {
                        if theme.colorScheme == .dark {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .padding(4)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(4)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(markColor, lineWidth: 2.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(surroundingTheme.panel, markColor)
                                .font(.system(size: 20))
                                .padding(8)
                                .accessibilityHidden(true)
                        }
                    }
                Text(verbatim: theme.title)
                    .font(.caption)
                    // Beyond this size, "Surround" outgrows a two-column tile.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                #if DEBUG
                if theme.isDebugOnly {
                    Text(verbatim: "Debug")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
                #endif
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The button itself is the one element: its name, whether the theme
        // stays dark, and whether it is chosen.
        .accessibilityLabel(Text(verbatim: theme.title))
        .accessibilityValue(theme.colorScheme == .dark ? String(localized: "Always dark", comment: "Accessibility value of a theme that stays dark in Light Mode") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.themeOption(theme.rawValue))
    }
}

/// Whole app or Games only, and what each means. Classic looks the same
/// everywhere, so the choice waits for another theme.
struct ThemeScopePicker: View {
    @Binding var appliesToWholeApp: Bool
    let theme: SurroundTheme

    private var caption: Text {
        if theme == .standard {
            return Text("Classic looks the same on every screen.", comment: "Caption under the theme scope choice while Classic is selected")
        }
        return appliesToWholeApp
            ? Text("Home and Settings use it too.", comment: "Caption for Whole app: the chosen theme also applies to Home and Settings")
            : Text("Only games use it. Home and Settings stay Classic.", comment: "Caption for Games only; Classic is the default theme's name")
    }

    private var useTheThemeOn: Text {
        Text("Use the theme on", comment: "Label before the choice of where the theme applies: Games only or Whole app")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            useTheThemeOn
            Picker(selection: $appliesToWholeApp) {
                Text("Games only", comment: "Choice: the theme applies only to game screens").tag(false)
                Text("Whole app", comment: "Choice: the theme applies to games, Home and Settings").tag(true)
            } label: {
                useTheThemeOn
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(theme == .standard)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.themeScope)
            caption
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Binds a picker to the stored theme, ignoring one this build does not offer.
private func storedThemeBinding(_ themeID: Binding<String>) -> Binding<SurroundTheme> {
    Binding(
        get: { SurroundTheme.current(storedID: themeID.wrappedValue) },
        set: { themeID.wrappedValue = $0.rawValue }
    )
}

/// Settings' Appearance group: the theme, and where the app wears it.
struct AppearanceSettings: View {
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var themeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var appliesToWholeApp = true

    var body: some View {
        let theme = storedThemeBinding($themeID)
        GroupBox(label: Text("Appearance", comment: "The app's look: a Settings group with the theme, and a Home button with the game layout and theme")) {
            VStack(alignment: .leading, spacing: 14) {
                ThemePicker(selection: theme)
                if theme.wrappedValue.colorScheme == .dark {
                    Text("\(theme.wrappedValue.title) is always dark, even in Light Mode.", comment: "Note under the theme picker; %@ is a theme name")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                ThemeScopePicker(appliesToWholeApp: $appliesToWholeApp, theme: theme.wrappedValue)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal)
    }
}

/// The theme in a game's Options sheet. Whether Home and Settings wear it too
/// stays a Settings choice.
struct GameThemeSettings: View {
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var themeID = SurroundTheme.standard.rawValue

    var body: some View {
        GroupBox(label: Text("Theme", comment: "Heading and accessibility label for the choice of theme")) {
            ThemePicker(selection: storedThemeBinding($themeID))
                .padding(.top, 6)
        }
        .padding(.horizontal)
    }
}

/// Home's Appearance popover: how games are laid out, and the theme. Where
/// else the theme applies stays a Settings choice; with Games only, Home keeps
/// Classic, so the popover says why it does not change.
struct HomeAppearanceOptions: View {
    @Binding var displayMode: GameCell.CellDisplayMode
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var themeID = SurroundTheme.standard.rawValue
    @AppStorage(SettingKey<Bool>.themeAppliesToWholeApp.name, store: userDefaults)
    private var appliesToWholeApp = true

    var body: some View {
        // A popover too short for the options scrolls them.
        ViewThatFits(in: .vertical) {
            options
            ScrollView { options }
        }
        // Narrower popovers, on the smallest phones, narrow the columns.
        .frame(idealWidth: 340, maxWidth: 340)
        #if DEBUG
        .frame(maxHeight: SurroundUITestContract.appearancePopoverHeight)
        #endif
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display mode")
                    .font(.subheadline.weight(.semibold))
                Picker(selection: $displayMode.animation()) {
                    Text("Compact").tag(GameCell.CellDisplayMode.compact)
                    Text("Large").tag(GameCell.CellDisplayMode.full)
                } label: {
                    Text("Display mode")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.homeDisplayMode)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme", comment: "Heading and accessibility label for the choice of theme")
                    .font(.subheadline.weight(.semibold))
                ThemePicker(selection: storedThemeBinding($themeID))
                if !appliesToWholeApp {
                    Text("Only games use the theme. Change this in Settings.", comment: "Note in Home's Appearance popover while the theme is set to Games only")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
    }
}

#if DEBUG && MAIN_APP
/// Renders `ThemeLivePreview` for every theme and appearance into the app's
/// `Documents/ThemePreviews/`, for `.github/ci-tools/update-theme-previews.py` to copy
/// into the asset catalog. Launch with `--surround-ui-testing
/// --surround-theme-preview-export`; a `done` file marks the end.
@MainActor
enum ThemePreviewExport {
    static let argument = "--surround-theme-preview-export"
    /// Sharp at 3× for the usual tiles (60–120 pt); the two-column tiles at
    /// accessibility text sizes scale it up slightly.
    static let side: CGFloat = 128
    static let scale: CGFloat = 3

    static var isRequested: Bool {
        SurroundUITestContract.isEnabled && ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func run() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThemePreviews", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for theme in SurroundTheme.allCases {
            // An always-dark theme has one thumbnail; the others, one each.
            let schemes: [ColorScheme] = theme.colorScheme.map { [$0] } ?? [.light, .dark]
            for scheme in schemes {
                let renderer = ImageRenderer(content: ThemeLivePreview(theme: theme)
                    .frame(width: side, height: side)
                    .environment(\.colorScheme, scheme))
                renderer.scale = scale
                renderer.isOpaque = true
                guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.85) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let name = "\(theme.rawValue)-\(scheme == .dark ? "dark" : "light").jpg"
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
        }
        try Data("done\n".utf8).write(to: folder.appendingPathComponent("done"), options: .atomic)
        return folder
    }
}

/// The export's whole window: its status, and nothing else.
struct ThemePreviewExportView: View {
    @State private var status = "Exporting theme previews…"

    var body: some View {
        Text(verbatim: status)
            .padding()
            .accessibilityIdentifier("uitest.themePreviewExportStatus")
            .task {
                // Let launch finish before the first render.
                await Task.yield()
                do {
                    status = "Exported to \(try ThemePreviewExport.run().path)"
                } catch {
                    status = "Export failed: \(error.localizedDescription)"
                }
            }
    }
}
#endif

#if DEBUG
#Preview("Appearance settings") {
    ScrollView {
        AppearanceSettings()
    }
}

#Preview("Home appearance") {
    HomeAppearanceOptions(displayMode: .constant(.compact))
}
#endif
