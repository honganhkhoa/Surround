//
//  ProfileBiographyTests.swift
//  SurroundTests
//

import Foundation
import Testing

@Suite struct ProfileBiographyTests {
    private let root = URL(string: "https://online-go.com")!
    private let locale = Locale(identifier: "en_GB")
    private let paris = TimeZone(identifier: "Europe/Paris")!

    private func document(_ source: String) -> ProfileBiographyDocument {
        ProfileBiographyDocument(source: source, baseURL: root, locale: locale, timeZone: paris)
    }

    @Test func testMarkdownKeepsFormattingAndBlockSemantics() {
        let result = document("#Heading\n\nHello **bold** *italic* ~~deleted~~ `code`.\n\n- First\n- Second\n\n> A quote\n\n```swift\nlet a = \"<b>\"\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        for fragment in ["<h1>Heading</h1>", "<strong>bold</strong>", "<em>italic</em>", "<del>deleted</del>", "<code>code</code>",
                         "<ul>", "<li>", "<blockquote>", "<pre><code>", "&lt;b&gt;", "<table>", "<th>A</th>", "<td>1</td>"] {
            #expect(result.bodyHTML.contains(fragment), Comment(rawValue: fragment + " in " + result.bodyHTML))
        }
    }

    @Test func testHTMLSanitizerDropsScriptsControlsAndAuthoredPresentation() {
        let result = document("""
        <div style="color:white;background:url(https://evil.example/a)" class="spoof" onclick="alert(1)">
        <p><strong>Readable</strong><font color="white"> text</font></p>
        <script>steal()</script><style>body{display:none}</style><iframe src="https://evil.example"></iframe>
        <form action="https://evil.example"><input name="password">secret control</form>
        <svg><a xlink:href="javascript:evil()">bad svg</a></svg><math><mtext>bad math</mtext></math>
        <object data="https://evil.example">bad object</object><template>bad template</template>
        </div>
        """)
        #expect(result.bodyHTML.contains("<strong>Readable</strong>"))
        #expect(result.bodyHTML.contains(" text"))
        for unwanted in ["onclick", "style=", "class=\"spoof", "color=", "evil.example", "steal", "<script", "<style", "<iframe", "<form", "<svg", "<math", "bad object", "bad template", "secret control"] {
            #expect(!(result.bodyHTML.contains(unwanted)), Comment(rawValue: unwanted + " in " + result.bodyHTML))
        }
    }

    @Test func testPureHTMLAndMixedMarkdownPreserveTextAndInlineFormatting() {
        let html = document("<div><b>Pure HTML</b> biography.<p>Paragraph <i>two</i>.</p></div>")
        #expect(html.bodyHTML.contains("<b>Pure HTML</b> biography."), Comment(rawValue: html.bodyHTML))
        #expect(html.bodyHTML.contains("<p>Paragraph <i>two</i>.</p>"), Comment(rawValue: html.bodyHTML))
        #expect(html.summaryText == "Pure HTML biography.")
        let mixed = document("Markdown **bold** and <em>HTML emphasis</em> with [game](/game/42).")
        #expect(mixed.bodyHTML.contains("<strong>bold</strong>"))
        #expect(mixed.bodyHTML.contains("<em>HTML emphasis</em>"))
        #expect(mixed.bodyHTML.contains("href=\"https://online-go.com/game/42\""))
        #expect(mixed.summaryText == "Markdown bold and HTML emphasis with game.")
    }

    @Test func testMalformedHTMLCannotRestoreUnsafeElementsOrAttributes() {
        let sources = [
            "<p>safe<a href='javascript:alert(1)' onmouseover='evil()'><b>label</p></a><img src=x onerror=evil()>",
            "<svg><style><img src=x onerror=evil()></style></svg><p>safe</p>",
            "<math><mtext><table><mglyph><style><!--</style><img src=x onerror=evil()></table></mtext></math><p>safe</p>",
            "<div><script src=https://evil.example/x><img src=x onerror=evil()></script><p>safe</div>",
            "<a href='java&#x0A;script:alert(1)'>safe</a><a href='&#106;avascript:evil()'>safe</a>",
            "<a href='https://name:password@evil.example/'>safe</a>"
        ]
        for source in sources {
            let html = document(source).bodyHTML
            for unwanted in ["<script", "<svg", "<math", "<style", "onerror", "onmouseover", "javascript:", "password@", "evil.example"] {
                #expect(!(html.contains(unwanted)), Comment(rawValue: unwanted + " in " + html))
            }
            #expect(html.contains("safe"), Comment(rawValue: html))
        }
    }

    @Test func testEncodedTextStaysLiteralAndAttributeEscapingIsPreserved() {
        let result = document("Text &lt;script&gt;alert(1)&lt;/script&gt; &amp; safe\n\n<a href='https://example.com/?a=1&amp;b=2' title='author'>A &amp; B</a>")
        #expect(result.bodyHTML.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!(result.bodyHTML.contains("<script>")))
        #expect(result.bodyHTML.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        #expect(result.bodyHTML.contains("A &amp; B"))
        #expect(!(result.bodyHTML.contains("title=")))
    }

    @Test func testAnchorTargetsSurviveWithoutAllowingUnsafeAttributes() {
        let result = document("""
        <p><a id="notes">Notes</a> <a href="#notes">Jump</a></p>
        <a id="empty"></a>
        <a id="linked" href="/player/42" onclick="evil()">Player</a>
        <a id="quote&amp;&quot;" href="javascript:evil()" style="color:white">Safe target</a>
        """)
        for fragment in ["<a id=\"notes\">Notes</a>", "<a href=\"#notes\">Jump</a>", "<a id=\"empty\"></a>",
                         "<a id=\"linked\" href=\"https://online-go.com/player/42\" rel=\"noopener noreferrer\">Player</a>",
                         "<a id=\"quote&amp;&quot;\">Safe target</a>"] {
            #expect(result.bodyHTML.contains(fragment), Comment(rawValue: fragment + " in " + result.bodyHTML))
        }
        for unwanted in ["onclick", "style=", "javascript:"] {
            #expect(!(result.bodyHTML.contains(unwanted)), Comment(rawValue: result.bodyHTML))
        }
        #expect(result.summaryText == "Notes Jump")
        #expect(result.summaryHTML.contains("href=\"#notes\""))
        #expect(!(result.summaryHTML.contains("id=")))
    }

    @Test func testImagesLoadAutomaticallyWithSafeSourcesAndNormalizedSizing() {
        let result = document("![A board](https://example.com/board.png)\n\n<img src='/board.png' alt='OGS board' width=99999 style='position:fixed' onerror='evil()'>\n\n<img src='data:image/svg+xml,evil' alt='Bad image'>")
        #expect(result.bodyHTML.contains("src=\"https://example.com/board.png\""))
        #expect(result.bodyHTML.contains("src=\"https://online-go.com/board.png\""))
        #expect(result.bodyHTML.contains("class=\"profile-biography-image\""))
        #expect(result.bodyHTML.contains("referrerpolicy=\"no-referrer\""))
        #expect(result.bodyHTML.contains(String(localized: "Unable to load image")))
        #expect(result.bodyHTML.contains("Bad image"))
        #expect(!(result.bodyHTML.contains("width=")))
        #expect(!(result.bodyHTML.contains("style=")))
        #expect(!(result.bodyHTML.contains("onerror")))
        #expect(!(result.bodyHTML.contains("data:")))
    }

    @Test func testMissingAndUnsafeImagesUseStyledEscapedFailurePlaceholder() {
        let sources: [String?] = [nil, "", "javascript:evil()", "data:image/svg+xml,evil", "https://name:secret@evil.example/image.png"]
        for source in sources {
            let sourceAttribute = source.map { " src=\"\($0)\"" } ?? ""
            let result = document("<img\(sourceAttribute) alt='Go &lt;board&gt; &amp; &quot;stones&quot;' class='author' onerror='evil()'>")
            #expect(result.bodyHTML.contains("<span class=\"image-failure\">"), Comment(rawValue: result.bodyHTML))
            #expect(result.bodyHTML.contains(String(localized: "Unable to load image")))
            #expect(result.bodyHTML.contains(": Go &lt;board&gt; &amp; &quot;stones&quot;</span>"), Comment(rawValue: result.bodyHTML))
            for unwanted in ["<img", "src=", "onerror", "class=\"author", "javascript:", "data:", "secret@", "evil.example", "<board>"] {
                #expect(result.bodyHTML.contains(unwanted) == false, Comment(rawValue: unwanted + " in " + result.bodyHTML))
            }
        }
    }

    @Test func testFormattedImageAltRemainsOneImageWithCompleteDescription() {
        let result = document("![A **Go** board](https://example.com/board.png)")
        #expect(result.bodyHTML.components(separatedBy: "<img ").count - 1 == 1)
        #expect(result.bodyHTML.contains("alt=\"A Go board\""), Comment(rawValue: result.bodyHTML))
        let adjacent = document("![First](https://example.com/board.png)![Second](https://example.com/board.png)")
        #expect(adjacent.bodyHTML.components(separatedBy: "<img ").count - 1 == 2)
    }

    @Test func testAudioAndVideoBecomeLabeledLinksWithoutPlaybackOrFrames() {
        let result = document("<audio autoplay src='https://example.com/a.mp3'></audio><video controls><source src='/v.mp4'></video><video src='javascript:evil()'></video>")
        #expect(result.bodyHTML.contains(String(localized: "Open audio")))
        #expect(result.bodyHTML.contains(String(localized: "Open video")))
        #expect(result.bodyHTML.contains("href=\"https://online-go.com/v.mp4\""))
        for unwanted in ["<audio", "<video", "<source", "autoplay", "javascript:"] { #expect(!(result.bodyHTML.contains(unwanted))) }
    }

    @Test func testSummaryKeepsFirstTextBlockFormattingAndOmitsImages() {
        let result = document("![Cover](https://example.com/cover.png)\n\nA **short** [player](/player/42) summary.\n\nSecond paragraph.")
        #expect(result.summaryText == "A short player summary.")
        #expect(result.summaryHTML.contains("<strong>short</strong>"))
        #expect(result.summaryHTML.contains("href=\"https://online-go.com/player/42\""))
        #expect(!(result.summaryHTML.contains("img")))
        #expect(!(result.summaryHTML.contains("Second paragraph")))
    }

    @Test func testEmptyAndWhollyUnsafeBiographiesHaveNoSection() {
        #expect(document("").isEmpty)
        #expect(document("  \n\t").isEmpty)
        #expect(document("<script>evil()</script><iframe src='https://evil.example'></iframe>").isEmpty)
        #expect(!(document("![Board](https://example.com/board.png)").isEmpty))
    }

    @Test func testPlainURLsAreLinkedButCodeRemainsCode() {
        let result = document("Visit https://example.com/page and www.example.org.\n\n`https://example.com/code`\n\n```\nhttps://example.com/block\n```")
        #expect(result.bodyHTML.contains("href=\"https://example.com/page\""))
        #expect(result.bodyHTML.contains("href=\"http://www.example.org\""))
        #expect(!(result.bodyHTML.contains("href=\"https://example.com/code\"")))
        #expect(!(result.bodyHTML.contains("href=\"https://example.com/block\"")))
    }

    @Test func testNativeLinksRequireExactCurrentEnvironmentAndUnadornedPaths() {
        #expect(ProfileBiographyLinkTarget.resolve("/player/42", baseURL: root) == .player(42))
        #expect(ProfileBiographyLinkTarget.resolve("https://online-go.com/game/7/", baseURL: root) == .game(7))
        let beta = URL(string: "https://beta.online-go.com")!
        #expect(ProfileBiographyLinkTarget.resolve("/player/42", baseURL: beta) == .player(42))
        for value in ["https://beta.online-go.com/player/42", "/player/42?tab=games", "/game/7#move-9", "/game/7/9", "/player/0", "/player/-1", "/%70layer/42", "https://online-go.com:8443/player/42", "https://online-go.com.evil.example/player/42"] {
            guard case .external = ProfileBiographyLinkTarget.resolve(value, baseURL: root) else {
                Issue.record(Comment(rawValue: value))
                return
            }
        }
        #expect(ProfileBiographyLinkTarget.resolve("#details", baseURL: root) == .fragment("details"))
    }

    @Test func testURLSchemesCredentialsAndControlsAreRejected() {
        for value in ["javascript:alert(1)", "data:text/html,evil", "file:///etc/passwd", "surround://home/42", "blob:https://example.com/id", "https://name:secret@example.com/a", "https://example.com/\r\nInjected", "java\nscript:evil()", "https:\\evil.example\\a"] {
            #expect(ProfileBiographyLinkTarget.resolve(value, baseURL: root) == nil, Comment(rawValue: value))
        }
        #expect(ProfileBiographyLinkTarget.resolve("//online-go.com/player/42", baseURL: root) == .player(42))
        #expect(ProfileBiographyLinkTarget.resolve("mailto:player@example.com", baseURL: root) == .external(URL(string: "mailto:player@example.com")!))
        #expect(ProfileBiographyLinkTarget.safeURL("mailto:player@example.com", baseURL: root, image: true) == nil)
    }

    @Test func testOGSTimeTokensConvertAuthoredZoneToReadersZone() {
        let source = "[date=2024-01-01 time=00:00:00 timezone=UTC format=\"YYYY-MM-DD HH:mm Z\"] and [time='2024-01-01T00:00:00Z'format='YYYY-MM-DD HH:mm']"
        let result = document(source)
        #expect(result.summaryText == "2024-01-01 01:00 +01:00 and 2024-01-01 01:00")
        #expect(!(result.bodyHTML.contains("[time")))
    }

    @Test func testOGSTimeFormatWithoutQuotesKeepsSpacesAndAllTokens() {
        let result = document("[date=2024-01-01 time=00:00:00 timezone=UTC format=YYYY MMM D] and [time='2024-01-01T00:00:00Z' format=YYYY-MM-DD HH:mm]")
        #expect(result.summaryText == "2024 Jan 1 and 2024-01-01 01:00")
    }

    @Test func testMinuteOnlyTimestampsAndDayOfYearFormatting() {
        let result = document("[time='2024-01-01 12:30' format='HH:mm'] and [time='2024-01-01T12:30' format='HH:mm'] and [time='2024-01-10T00:00:00Z' format='DDD DDDD']")
        #expect(result.summaryText == "12:30 and 12:30 and 10 010")
    }

    @Test func testMinimumWeekdayUsesTwoLettersInsteadOfNarrowInitial() {
        #expect(document("[time='2024-01-01T00:00:00Z' format='dd ddd dddd']").summaryText == "Mo Mon Monday")
    }

    @Test func testLocalizedTimeFormatsAndUnsupportedFormatFallbackRemainMeaningful() {
        let french = ProfileBiographyDocument(source: "[time='2024-01-01T00:00:00Z' format='LLLL']", baseURL: root, locale: Locale(identifier: "fr_FR"), timeZone: paris)
        #expect(french.summaryText.contains("lundi"), Comment(rawValue: french.summaryText))
        #expect(french.summaryText.contains("janvier"), Comment(rawValue: french.summaryText))
        let unsupported = document("[time='2024-01-01T00:00:00Z' format='YYYY Q X']")
        #expect(unsupported.summaryText.contains("2024"))
        #expect(unsupported.summaryText.contains(String(localized: "Date format unavailable")))
        #expect(!(unsupported.summaryText.contains("YYYY Q X")))
    }

    @Test func testMalformedTimeIsPreservedAndFormattedLiteralsCannotInjectHTML() {
        let malformed = "[date=2024-02-30 time=00:00:00 timezone=UTC format='L']"
        #expect(document(malformed).summaryText == malformed)
        let literal = document("[time='2024-01-01T00:00:00Z' format='YYYY [<script>evil</script>]']")
        #expect(!(literal.bodyHTML.contains("<script>")))
        #expect(literal.summaryText == "2024 <script>evil</script>")
        #expect(literal.bodyHTML.contains("&lt;script&gt;evil&lt;/script&gt;"))
    }
}
