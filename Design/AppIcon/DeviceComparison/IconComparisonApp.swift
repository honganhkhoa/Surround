import SwiftUI
import UIKit

@main
struct IconComparisonApp: App {
    private let title = Bundle.main.object(forInfoDictionaryKey: "ComparisonTitle") as? String ?? "Surround icon"
    private let detail = Bundle.main.object(forInfoDictionaryKey: "ComparisonDescription") as? String ?? ""
    private var preview: UIImage? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "ComparisonPreview") as? String,
              let path = Bundle.main.path(forResource: name, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 24) {
                    Text("SURROUND ICON STUDY")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
                            .accessibilityLabel(title)
                    }
                    VStack(spacing: 10) {
                        Text(title).font(.largeTitle.bold())
                        Text(detail).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Compare on your Home Screen")
                        .font(.headline)
                    Text("Place the Go comparison apps together. Try light, dark, clear, and tinted icons, and compare both small and large icon sizes.")
                        .foregroundStyle(.secondary)
                    Text("This app only identifies the design. The Home Screen shows the live system-rendered icon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}
