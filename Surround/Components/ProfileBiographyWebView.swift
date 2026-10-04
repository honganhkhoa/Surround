import SwiftUI
import WebKit

/// Untrusted biography content never shares the authenticated OGS browser.
struct ProfileBiographyWebView: UIViewRepresentable {
    let fragment: String
    let baseURL: URL
    var isSummary = false
    @Binding var height: CGFloat
    @Binding var scrollOffset: CGFloat
    let onLink: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.add(context.coordinator,
            contentWorld: .defaultClient, name: "biographyHeight")
        let labelData = try! JSONSerialization.data(withJSONObject: String(localized: "Unable to load image"), options: .fragmentsAllowed)
        let failureLabel = String(decoding: labelData, as: UTF8.self)
        // Only this app-owned isolated script may measure content or repair a
        // failed image. Author scripts and event attributes are removed first.
        let script = """
        const report = () => window.webkit.messageHandlers.biographyHeight.postMessage(document.body.getBoundingClientRect().height);
        for (const img of Array.from(document.images)) {
            const failed = () => {
                const placeholder = document.createElement('span');
                placeholder.className = 'image-failure';
                placeholder.textContent = \(failureLabel) + (img.alt ? ': ' + img.alt : '');
                img.replaceWith(placeholder);
                report();
            };
            img.addEventListener('error', failed, {once:true});
            img.addEventListener('load', report, {once:true});
            if (img.complete && img.naturalWidth === 0) failed();
        }
        new ResizeObserver(report).observe(document.body);
        report();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.delegate = context.coordinator
        view.scrollView.isScrollEnabled = !isSummary
        view.scrollView.bounces = !isSummary
        view.allowsLinkPreview = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.accessibilityIdentifier = isSummary
            ? SurroundUITestContract.AccessibilityID.profileBiographySummary
            : SurroundUITestContract.AccessibilityID.profileBiographyContent
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        let html = documentHTML
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        context.coordinator.isLoadingDocument = true
        view.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.scrollView.delegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(
            forName: "biographyHeight", contentWorld: .defaultClient)
    }

    private var fontSize: CGFloat {
        let category: UIContentSizeCategory
        switch dynamicTypeSize {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: 17,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    private var documentHTML: String {
        let dark = colorScheme == .dark
        let foreground = dark ? "#f2f2f7" : "#1c1c1e"
        let secondary = dark ? "#b6b6bf" : "#626269"
        let link = dark ? "#9e9eff" : "#4440be"
        let images = allowsRemoteActivity ? "https: http:" : "'none'"
        let summaryCSS = isSummary ? "body { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; } p { margin:0; }" : ""
        return """
        <!doctype html><html dir="auto"><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(images); style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
        <meta name="referrer" content="no-referrer">
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        html, body { margin:0; padding:0; background:transparent; }
        body { font: \(fontSize)px -apple-system, BlinkMacSystemFont, sans-serif; line-height:1.45; color:\(foreground); overflow-wrap:anywhere; }
        p, ul, ol, blockquote, pre, table, figure { margin:0 0 0.85em; }
        h1,h2,h3,h4,h5,h6 { font-size:1.2em; line-height:1.3; margin:1em 0 0.4em; }
        h1:first-child,h2:first-child,p:first-child { margin-top:0; }
        mark { background:transparent; font-weight:bold; }
        a { color:\(link); text-decoration:underline; }
        img { display:block; max-width:100%; width:auto; height:auto; margin:0.65em 0; }
        ul,ol { padding-left:1.5em; } blockquote { margin-left:0; padding-left:0.8em; border-left:3px solid \(secondary); }
        pre { white-space:pre-wrap; } code { font-size:0.92em; }
        table { width:100%; border-collapse:collapse; } th,td { padding:0.35em; border:1px solid \(secondary); }
        .image-failure { display:block; color:\(secondary); padding:0.65em; border:1px solid \(secondary); border-radius:0.4em; margin:0.65em 0; }
        \(summaryCSS)
        </style></head><body>\(fragment)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: ProfileBiographyWebView
        var html: String?
        var isLoadingDocument = false
        init(_ parent: ProfileBiographyWebView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard parent.isSummary, message.frameInfo.isMainFrame, let height = message.body as? NSNumber,
                  height.doubleValue.isFinite else { return }
            let measured = max(1, CGFloat(height.doubleValue))
            if abs(parent.height - measured) > 0.5 { parent.height = measured }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !parent.isSummary {
                let maximum = max(0, webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
                webView.scrollView.setContentOffset(CGPoint(x: 0, y: min(parent.scrollOffset, maximum)), animated: false)
            }
            isLoadingDocument = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !parent.isSummary, !isLoadingDocument else { return }
            parent.scrollOffset = max(0, scrollView.contentOffset.y)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.navigationType == .other && isLoadingDocument
                && (url.absoluteString == "about:blank" || url == parent.baseURL) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                    let fragment = components?.fragment
                    components?.fragment = nil
                    if !parent.isSummary, components?.url == parent.baseURL, let fragment {
                        webView.callAsyncJavaScript("""
                            const target = document.getElementById(fragment);
                            if (target) target.scrollIntoView();
                            return Boolean(target);
                            """, arguments: ["fragment": fragment], in: nil, in: .defaultClient) { [weak self] result in
                                if case .success(let found) = result, found as? Bool == true { return }
                                self?.parent.onLink(url)
                            }
                    } else { parent.onLink(url) }
                }
            }
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}
