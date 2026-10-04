//
//  ProfileBiographyDocument.swift
//  Surround
//

import Foundation
import libxml2

enum ProfileBiographyLinkTarget: Equatable {
    case player(Int)
    case game(Int)
    case external(URL)
    case fragment(String)

    static func resolve(_ url: URL, baseURL: URL) -> Self? {
        resolve(url.absoluteString, baseURL: baseURL)
    }

    static func resolve(_ value: String, baseURL: URL) -> Self? {
        if value.hasPrefix("#") { return .fragment(String(value.dropFirst())) }
        guard let url = safeURL(value, baseURL: baseURL) else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.host?.lowercased() == baseURL.host?.lowercased(),
              components.port == nil, components.query == nil, components.fragment == nil,
              ["https", "http"].contains(components.scheme?.lowercased() ?? "") else {
            return .external(url)
        }
        let path = components.percentEncodedPath
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 || (parts.count == 4 && parts[3].isEmpty),
              parts[0].isEmpty, parts[2].allSatisfy({ $0.isASCII && $0.isNumber }),
              let id = Int(parts[2]), id > 0 else { return .external(url) }
        switch parts[1] {
        case "player": return .player(id)
        case "game": return .game(id)
        default: return .external(url)
        }
    }

    /// Relative biography URLs belong to OGS. Authored URLs never receive the
    /// app's credentials, and cannot invoke arbitrary system URL handlers.
    static func safeURL(_ value: String, baseURL: URL, image: Bool = false) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.user == nil, components.password == nil else { return nil }
        switch components.scheme?.lowercased() {
        case "https", "http":
            guard let host = components.host, !host.isEmpty else { return nil }
        case "mailto" where !image:
            guard !components.path.isEmpty else { return nil }
        default: return nil
        }
        return url
    }
}

/// Markdown is parsed by Foundation, then HTML is parsed by libxml2 and
/// serialized from a tag/attribute allowlist. No authored HTML is trusted by
/// the biography web view, including HTML produced by Markdown links/images.
struct ProfileBiographyDocument: Equatable {
    let bodyHTML: String
    let summaryHTML: String
    let summaryText: String

    var isEmpty: Bool { bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(source: String, baseURL: URL, locale: Locale = .current, timeZone: TimeZone = .current) {
        let localized = ProfileBiographyTime.localize(source, locale: locale, timeZone: timeZone)
        let markdown = BiographyMarkdown.html(localized)
        let sanitizer = BiographyHTML(baseURL: baseURL)
        bodyHTML = sanitizer.sanitize(markdown)
        let summary = sanitizer.summary(bodyHTML)
        summaryHTML = summary.html
        summaryText = summary.text
    }
}

private enum BiographyMarkdown {
    static func html(_ source: String) -> String {
        // OGS accepts headings without the CommonMark separating space.
        let source = source.replacingOccurrences(of: "(?m)^(#{1,6})([a-zA-Z0-9])", with: "$1 $2", options: .regularExpression)
        guard let markdown = try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible, appliesSourcePositionAttributes: true)) else {
            return "<p>\(escape(source))</p>"
        }
        var html = ""
        var stack: [PresentationIntent.IntentType] = []
        for run in markdown.runs {
            let intent = Array((run.presentationIntent?.components ?? []).reversed())
            let common = zip(stack, intent).prefix { $0.identity == $1.identity }.count
            for component in stack.dropFirst(common).reversed() { html += closing(component.kind, parents: stack) }
            for component in intent.dropFirst(common) { html += opening(component.kind, parents: intent) }
            stack = intent
            let text = String(markdown.characters[run.range])
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.inlineHTML) || inline.contains(.blockHTML) {
                html += text
                continue
            }
            if intent.contains(where: { if case .thematicBreak = $0.kind { return true }; return false }) { continue }
            var content = run.link == nil && run.imageURL == nil && !inline.contains(.code)
                && !intent.contains(where: { if case .codeBlock = $0.kind { return true }; return false })
                ? linkified(text) : escape(text)
            if inline.contains(.lineBreak) { content = "<br>" }
            if inline.contains(.code) { content = "<code>\(content)</code>" }
            if inline.contains(.stronglyEmphasized) { content = "<strong>\(content)</strong>" }
            if inline.contains(.emphasized) { content = "<em>\(content)</em>" }
            if inline.contains(.strikethrough) { content = "<del>\(content)</del>" }
            if let image = run.imageURL {
                content = "<img src=\"\(escape(image.absoluteString))\" alt=\"\(escape(text))\">"
            }
            if let link = run.link { content = "<a href=\"\(escape(link.absoluteString))\">\(content)</a>" }
            html += content
        }
        for component in stack.reversed() { html += closing(component.kind, parents: stack) }
        return html
    }

    private static func linkified(_ text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return escape(text) }
        var result = ""
        var index = text.startIndex
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let url = match.url else { continue }
            result += escape(String(text[index..<range.lowerBound]))
            result += "<a href=\"\(escape(url.absoluteString))\">\(escape(String(text[range])))</a>"
            index = range.upperBound
        }
        return result + escape(String(text[index...]))
    }

    private static func opening(_ kind: PresentationIntent.Kind, parents: [PresentationIntent.IntentType]) -> String {
        switch kind {
        case .paragraph: return "<p>"
        case .header(let level): return "<h\(min(6, max(1, level)))>"
        case .orderedList: return "<ol>"
        case .unorderedList: return "<ul>"
        case .listItem: return "<li>"
        case .codeBlock: return "<pre><code>"
        case .blockQuote: return "<blockquote>"
        case .thematicBreak: return "<hr>"
        case .table: return "<table>"
        case .tableHeaderRow, .tableRow: return "<tr>"
        case .tableCell:
            return parents.contains(where: { if case .tableHeaderRow = $0.kind { return true }; return false }) ? "<th>" : "<td>"
        @unknown default: return ""
        }
    }

    private static func closing(_ kind: PresentationIntent.Kind, parents: [PresentationIntent.IntentType]) -> String {
        switch kind {
        case .paragraph: return "</p>"
        case .header(let level): return "</h\(min(6, max(1, level)))>"
        case .orderedList: return "</ol>"
        case .unorderedList: return "</ul>"
        case .listItem: return "</li>"
        case .codeBlock: return "</code></pre>"
        case .blockQuote: return "</blockquote>"
        case .thematicBreak: return ""
        case .table: return "</table>"
        case .tableHeaderRow, .tableRow: return "</tr>"
        case .tableCell:
            return parents.contains(where: { if case .tableHeaderRow = $0.kind { return true }; return false }) ? "</th>" : "</td>"
        @unknown default: return ""
        }
    }
}

private struct BiographyHTML {
    let baseURL: URL
    private static let allowed: Set<String> = [
        "a", "abbr", "address", "article", "aside", "b", "bdi", "bdo", "blockquote", "br", "caption", "cite", "code",
        "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "i", "ins", "li", "main", "mark", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s", "samp", "section",
        "small", "span", "strong", "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul"
    ]
    private static let discarded: Set<String> = [
        "applet", "base", "button", "canvas", "embed", "form", "frame", "frameset", "head", "iframe", "input", "link", "math", "meta",
        "noscript", "object", "option", "script", "select", "style", "svg", "template", "textarea", "title"
    ]

    func sanitize(_ html: String) -> String {
        withDocument(html) { serialize($0) } ?? ""
    }

    private func serialize(_ first: xmlNodePtr?, inlineOnly: Bool = false, singleNode: Bool = false, depth: Int = 0) -> String {
        guard depth < 64 else { return "" }
        var result = ""
        var current = first
        while let node = current {
            defer { current = singleNode ? nil : node.pointee.next }
            if node.pointee.type == XML_TEXT_NODE {
                if let text = node.pointee.content { result += escape(String(cString: text)) }
                continue
            }
            guard node.pointee.type == XML_ELEMENT_NODE, let name = node.pointee.name else { continue }
            let tag = String(cString: name).lowercased()
            if Self.discarded.contains(tag) { continue }
            if tag == "img" {
                guard !inlineOnly else { continue }
                let alt = attribute("alt", node: node) ?? ""
                if let src = attribute("src", node: node), let url = ProfileBiographyLinkTarget.safeURL(src, baseURL: baseURL, image: true) {
                    result += "<img class=\"profile-biography-image\" src=\"\(escape(url.absoluteString))\" alt=\"\(escape(alt))\" referrerpolicy=\"no-referrer\">"
                } else {
                    result += "<span class=\"image-failure\">\(escape(String(localized: "Unable to load image")))\(alt.isEmpty ? "" : ": " + escape(alt))</span>"
                }
                continue
            }
            if tag == "audio" || tag == "video" {
                guard !inlineOnly else { continue }
                if let url = mediaURL(node) {
                    let label = tag == "audio" ? String(localized: "Open audio") : String(localized: "Open video")
                    result += "<p><a href=\"\(escape(url.absoluteString))\" rel=\"noopener noreferrer\">\(escape(label))</a></p>"
                }
                continue
            }
            let children = serialize(node.pointee.children, inlineOnly: inlineOnly, depth: depth + 1)
            guard Self.allowed.contains(tag) else { result += children; continue }
            var attributes = ""
            if let id = attribute("id", node: node), !inlineOnly { attributes += " id=\"\(escape(id))\"" }
            if tag == "a" {
                if let href = attribute("href", node: node), href.hasPrefix("#") {
                    result += "<a\(attributes) href=\"\(escape(href))\">\(children)</a>"
                } else if let href = attribute("href", node: node), let url = ProfileBiographyLinkTarget.safeURL(href, baseURL: baseURL) {
                    result += "<a\(attributes) href=\"\(escape(url.absoluteString))\" rel=\"noopener noreferrer\">\(children)</a>"
                } else if !attributes.isEmpty {
                    result += "<a\(attributes)>\(children)</a>"
                } else { result += children }
                continue
            }
            if inlineOnly && !["abbr", "b", "br", "cite", "code", "del", "em", "i", "ins", "mark", "s", "small", "span", "strong", "sub", "sup", "u"].contains(tag) {
                result += children
                continue
            }
            if (tag == "td" || tag == "th"), !inlineOnly {
                for key in ["colspan", "rowspan"] {
                    if let value = attribute(key, node: node), let count = Int(value), (1...20).contains(count) { attributes += " \(key)=\"\(count)\"" }
                }
            }
            if tag == "br" || tag == "hr" { result += "<\(tag)>" }
            else if !children.isEmpty { result += "<\(tag)\(attributes)>\(children)</\(tag)>" }
        }
        return result
    }

    func summary(_ html: String) -> (html: String, text: String) {
        withDocument(html) { first in
            let fragment = firstSummaryFragment(first) ?? ""
            let plain = withDocument(fragment) { textContent($0).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") } ?? ""
            // The view clamps this formatted first block to three text lines.
            return (fragment, plain)
        } ?? ("", "")
    }

    private func firstSummaryFragment(_ first: xmlNodePtr?, depth: Int = 0) -> String? {
        guard depth < 64 else { return nil }
        var current = first
        while let node = current {
            defer { current = node.pointee.next }
            let tag = node.pointee.name.map { String(cString: $0).lowercased() } ?? ""
            if ["p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "td", "th", "pre"].contains(tag),
               !textContent(node).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return serialize(node.pointee.children, inlineOnly: true)
            }
            let inlineTags = ["text", "a", "abbr", "b", "br", "cite", "code", "del", "em", "i", "ins", "mark", "s", "small", "span", "strong", "sub", "sup", "u"]
            if inlineTags.contains(tag), !textContent(node).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var fragment = ""
                var sibling: xmlNodePtr? = node
                while let item = sibling {
                    let itemTag = item.pointee.name.map { String(cString: $0).lowercased() } ?? ""
                    guard inlineTags.contains(itemTag) else { break }
                    fragment += serialize(item, inlineOnly: true, singleNode: true)
                    sibling = item.pointee.next
                }
                return fragment
            }
            if let child = firstSummaryFragment(node.pointee.children, depth: depth + 1) { return child }
        }
        return nil
    }

    private func mediaURL(_ node: xmlNodePtr) -> URL? {
        if let src = attribute("src", node: node), let url = ProfileBiographyLinkTarget.safeURL(src, baseURL: baseURL, image: true) { return url }
        var child = node.pointee.children
        while let item = child {
            if item.pointee.name.map({ String(cString: $0).lowercased() }) == "source",
               let src = attribute("src", node: item), let url = ProfileBiographyLinkTarget.safeURL(src, baseURL: baseURL, image: true) { return url }
            child = item.pointee.next
        }
        return nil
    }

    private func attribute(_ name: String, node: xmlNodePtr) -> String? {
        guard let value = xmlGetProp(node, Array(name.utf8) + [0]) else { return nil }
        defer { xmlFree(value) }
        return String(cString: value)
    }

    private func textContent(_ node: xmlNodePtr?) -> String {
        guard let node, let value = xmlNodeGetContent(node) else { return "" }
        defer { xmlFree(value) }
        return String(cString: value)
    }

    private func withDocument<T>(_ html: String, body: (xmlNodePtr?) -> T) -> T? {
        let options = Int32(HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue)
        guard let document = html.withCString({ htmlReadMemory($0, Int32(html.utf8.count), nil, "UTF-8", options) }) else { return nil }
        defer { xmlFreeDoc(document) }
        return body(xmlDocGetRootElement(document))
    }
}

private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private enum ProfileBiographyTime {
    static func localize(_ source: String, locale: Locale, timeZone: TimeZone) -> String {
        let pattern = #"\[\s*(?:time\s*=\s*["'][^"']+["']|date\s*=\s*["']?\d{4}-\d{1,2}-\d{1,2}["']?\s+time\s*=\s*["']?\d{1,2}:\d{1,2}:\d{1,2}["']?\s+timezone\s*=\s*(?:["'][^"']+["']|[A-Za-z0-9/_+-]+))(?:\s*format\s*=\s*(?:["'][^"']*["']|[^\]]+))?\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        var result = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            let token = String(source[range])
            let attributes = timeAttributes(token)
            guard let date = parseDate(attributes, timeZone: timeZone) else { continue }
            let format = attributes["format"]
            let formatted: String
            if let format, let translated = dateFormat(format, locale: locale) {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.dateFormat = translated
                formatted = formatter.string(from: date)
            } else {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.dateStyle = .full
                formatter.timeStyle = .long
                formatted = formatter.string(from: date) + (format == nil ? "" : " (" + String(localized: "Date format unavailable") + ")")
            }
            // Localized text remains literal even when a format has a bracketed literal.
            let literal = formatted.map { "\\`*_{}[]<>".contains($0) ? "\\" + String($0) : String($0) }.joined()
            result.replaceSubrange(Range(match.range, in: result)!, with: literal)
        }
        return result
    }

    private static func timeAttributes(_ token: String) -> [String: String] {
        let pattern = #"(date|time|timezone)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s\]]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var attributes: [String: String] = [:]
        for match in regex.matches(in: token, range: NSRange(token.startIndex..., in: token)) {
            guard let key = Range(match.range(at: 1), in: token) else { continue }
            for group in 2...4 {
                if let value = Range(match.range(at: group), in: token) { attributes[String(token[key])] = String(token[value]); break }
            }
        }
        let content = String(token.dropFirst().dropLast())
        let formatPattern = #"format\s*=\s*(?:"([^"]*)"|'([^']*)'|(.+))\s*$"#
        if let formatRegex = try? NSRegularExpression(pattern: formatPattern),
           let match = formatRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) {
            for group in 1...3 {
                if let value = Range(match.range(at: group), in: content) {
                    attributes["format"] = String(content[value]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        return attributes
    }

    private static func parseDate(_ attributes: [String: String], timeZone: TimeZone) -> Date? {
        guard let time = attributes["time"] else { return nil }
        if let date = attributes["date"], let zone = attributes["timezone"] {
            guard let sourceZone = TimeZone(identifier: zone) else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = sourceZone
            formatter.dateFormat = "yyyy-M-d H:m:s"
            formatter.isLenient = false
            return formatter.date(from: date + " " + time)
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: time) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: time) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
                       "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: time) { return date }
        }
        return nil
    }

    private static func dateFormat(_ format: String, locale: Locale) -> String? {
        let tokens: [String: String] = ["YYYY": "yyyy", "YY": "yy", "MMMM": "MMMM", "MMM": "MMM", "MM": "MM", "M": "M",
            "DDDD": "DDD", "DDD": "D", "DD": "dd", "D": "d", "dddd": "EEEE", "ddd": "EEE", "dd": "EEEEEE", "HH": "HH", "H": "H", "hh": "hh", "h": "h",
            "mm": "mm", "m": "m", "ss": "ss", "s": "s", "A": "a", "a": "a", "ZZ": "xx", "Z": "xxx", "z": "zzz"]
        let localized: [String: String] = ["LTS": "jmmss", "LT": "jmm", "LLLL": "EEEEyMMMMdjmm", "LLL": "yMMMMdjmm", "LL": "yMMMMd", "L": "yMd",
            "llll": "EEEyMMMdjmm", "lll": "yMMMdjmm", "ll": "yMMMd", "l": "yMd"]
        let known = (Array(tokens.keys) + Array(localized.keys)).sorted { $0.count > $1.count }
        var index = format.startIndex
        var result = ""
        while index < format.endIndex {
            if format[index] == "[", let end = format[index...].firstIndex(of: "]") {
                result += "'" + format[format.index(after: index)..<end].replacingOccurrences(of: "'", with: "''") + "'"
                index = format.index(after: end)
            } else if let token = known.first(where: { format[index...].hasPrefix($0) }) {
                if let template = localized[token] { result += DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? template }
                else { result += tokens[token]! }
                index = format.index(index, offsetBy: token.count)
            } else if format[index].isLetter || format[index] == "[" || format[index] == "]" { return nil }
            else {
                result += format[index] == "'" ? "''" : String(format[index])
                index = format.index(after: index)
            }
        }
        return result.isEmpty ? nil : result
    }
}
