// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import WebKit

/// Builds the page for one side of a card. The deck's own CSS is kept, then Kartei's type and colours are laid over it
/// so that plain decks match the app. The question is set in the display face, the answer below one rule.
/// What the card page needs from the theme: the palette for the current family and mode, and the family's faces.
struct CardTheme: Equatable {
    var family: ThemeFamily
    var dark: Bool
    /// Text size against the design size: system text size times the Reading page's card step.
    var scale: Double = 1
    /// Questions in Regular instead of the thin display weight.
    var regularQuestions = false
    /// The stronger-contrast palette variant.
    var strong = false
    /// BCP 47 language of the deck's cards, for VoiceOver's voice and hyphenation; nil leaves it to the system.
    var lang: String?

    var palette: Palette {
        let p = Palette.of(family, dark: dark)
        return strong ? p.strongContrast : p
    }

    /// The card as the Reading settings and the current mode want it.
    static func current(dark: Bool, lang: String? = nil) -> CardTheme {
        let reading = ReadingPrefs.shared
        return CardTheme(family: ThemeStore.shared.family, dark: dark, scale: reading.cardScale,
                         regularQuestions: reading.regularQuestionWeight, strong: reading.contrast, lang: lang)
    }

    /// iOS WebKit scales text alone with text-size-adjust; macOS has no such property, so the page is zoomed there.
    var scaleCSS: String {
        let percent = Int((scale * 100).rounded())
        #if os(iOS)
        return "-webkit-text-size-adjust:\(percent)%"
        #else
        return "-webkit-text-size-adjust:100%;zoom:\(percent)%"
        #endif
    }

    static let gruvboxDark = CardTheme(family: .gruvbox, dark: true)

    /// The palette as CSS custom properties (--k-bg, --k-text, …, plus translucent fills for the typed-answer diff).
    var rootCSS: String {
        let p = palette
        func soft(_ hex: String, _ alpha: Double) -> String {
            let c = Palette.rgb(hex)
            return "rgba(\(Int((c.r * 255).rounded())),\(Int((c.g * 255).rounded())),\(Int((c.b * 255).rounded())),\(alpha))"
        }
        let f = family.fonts
        let vars: [(String, String)] = [
            ("bg", p.bg), ("surface", p.surface), ("surface2", p.surface2), ("rule", p.rule), ("text", p.text), ("muted", p.muted),
            ("display", p.display), ("accent", p.accent), ("on-accent", p.onAccent), ("accent-rule", p.accentRule),
            ("forgot", p.forgot), ("on-forgot", p.onForgot), ("new", p.new), ("learning", p.learning), ("control", p.control),
            // Typed-answer diff: the wrong letters on a wash of the fail colour, the missing ones over the accent rule.
            ("bad-bg", soft(p.forgot, dark ? 0.35 : 0.18)), ("missed-bg", soft(p.accentRule, dark ? 0.22 : 0.28)),
            ("font-display", "\"\(f.display)\",sans-serif"), ("font-body", "\"\(f.body)\",\(family == .geist ? "serif" : "sans-serif")"),
            ("font-data", family == .geist ? "\"\(f.data)\",monospace" : "ui-monospace,monospace"),
            ("font-code", "\"\(family.codeFont)\",ui-monospace,monospace"),
        ]
        return ":root{color-scheme:\(dark ? "dark" : "light");" + vars.map { "--k-\($0.0):\($0.1)" }.joined(separator: ";") + "}"
    }
}

/// Builds the page for one side of a card. The deck's own CSS is kept, then Kartei's type and colours are laid over it
/// so that plain decks match the app. The question is set in the display face, the answer below one rule.
/// Colours come from the theme as custom properties; the shared kartei-card.css (also used on Android) carries Gruvbox
/// dark literals, so the rules after it point those at the custom properties.
enum CardPage {
    static func html(question: String, answer: String?, css: String, theme: CardTheme = .gruvboxDark) -> String {
        var front = clean(question)
        var back = ""
        var whole = false
        if let answer {
            let full = clean(answer)
            // Anki answer templates usually repeat the question above <hr id=answer>.
            if let cut = full.range(of: #"<hr[^>]*id=["']?answer["']?[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
                front = String(full[..<cut.lowerBound])
                back = String(full[cut.upperBound...])
            } else if repeatsQuestion(full, question: front) {
                // The answer template carries the question itself (image occlusion does): show it once, as Anki does.
                front = ""
                back = full
                whole = true
            } else {
                back = full
            }
        }
        let plainLength = plain(front).count
        let size = answer != nil || plainLength > 110 ? "small" : ""
        let answerBlock = answer == nil ? "" : "<div class=\"k-a\(whole ? " k-whole" : "")\">\(back)</div>"
        // Anki's night-mode classes only in dark mode, so deck CSS written for .nightMode does not darken a light page.
        let bodyClass = theme.dark ? "card nightMode night_mode" : "card"
        return """
        <!doctype html><html\(theme.lang.map { " lang=\"\($0)\"" } ?? "")><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        @font-face{font-family:"Bricolage Grotesque";src:url(kartei://app/BricolageGrotesque.ttf);font-weight:200 800}
        @font-face{font-family:"DM Sans";src:url(kartei://app/DMSans.ttf);font-weight:100 1000}
        @font-face{font-family:"Nunito";src:url(kartei://app/Nunito.ttf);font-weight:200 1000}
        @font-face{font-family:"Noto Serif";src:url(kartei://app/NotoSerif.ttf);font-weight:100 900;font-stretch:62.5% 100%}
        @font-face{font-family:"Courier Prime";src:url(kartei://app/CourierPrime.ttf);font-weight:400}
        @font-face{font-family:"DM Mono";src:url(kartei://app/DMMono.ttf);font-weight:400}
        \(theme.rootCSS)
        \(css)
        html,body{margin:0;background:transparent!important}
        body.card{background:transparent!important;color:var(--k-text)!important;padding:0!important;font-family:var(--k-font-body)!important;text-align:left!important;\(theme.scaleCSS)}
        .k-q{font:\(theme.regularQuestions ? 400 : 200) 36px/41px var(--k-font-display);letter-spacing:-.01em;text-wrap:balance}
        .k-q.small{font-size:26px;line-height:33px}
        .k-a{border-top:1px solid var(--k-rule);margin-top:20px;padding-top:20px;font:500 20px/28px var(--k-font-body)}
        .k-a.k-whole{border-top:0;margin-top:0;padding-top:0}
        .k-a small{font:400 13px/18px var(--k-font-body);color:var(--k-muted)!important}
        img{max-width:100%;height:auto}a{color:var(--k-accent)}
        .cloze{font-weight:700;color:var(--k-text)!important;border-bottom:2px solid var(--k-accent-rule)}
        .k-warn{font:400 15px/20px var(--k-font-body);color:var(--k-forgot)}
        </style>
        <link rel="stylesheet" href="kartei://app/kartei-card.css">
        <style>
        .k-play{border-color:var(--k-control);color:var(--k-text)!important}
        .k-play:active{background:var(--k-surface2)}
        .k-typed{border-top-color:var(--k-rule)}
        .k-typed .meta,.k-typed .note{font-family:var(--k-font-body);color:var(--k-muted)}
        .k-typed .v{font-family:var(--k-font-body);color:var(--k-text)}
        .k-typed .typeGood,.k-typed .typeBad{color:var(--k-text)}
        .k-typed .typeBad{background:var(--k-bad-bg);text-decoration-color:var(--k-forgot)}
        .k-typed .typeMissed{border-bottom-color:var(--k-accent-rule);background:var(--k-missed-bg)}
        #image-occlusion-canvas{--highlight-shape-border:3px \(theme.palette.accentRule)}
        #toggle{font-family:var(--k-font-body);color:var(--k-text);background:var(--k-surface2);border:1px solid var(--k-control)}
        .k-whole{font-family:var(--k-font-body)}
        </style>
        <script src="kartei://app/kartei-card.js"></script>
        </head><body class="\(bodyClass)">
        \(front.isEmpty && whole ? "" : "<div class=\"k-q \(size)\">\(front)</div>")\(answerBlock)
        </body></html>
        """
    }

    /// True when the answer already contains the question: an image occlusion page, or a template that repeats
    /// the front without <hr id=answer>.
    static func repeatsQuestion(_ answer: String, question: String) -> Bool {
        if answer.contains("image-occlusion-container") { return true }
        let q = plain(question).trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && plain(answer).contains(q)
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Audio references become replay buttons; any raw tag left over is taken out of the text.
    private static func clean(_ html: String) -> String {
        CardText.playButtons(html)
            .replacingOccurrences(of: #"\[sound:[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[anki:(play|tts)[^\]]*\]"#, with: "", options: .regularExpression)
    }
}

/// Serves the app's fonts (kartei://app/…) and the collection's media folder (kartei://media/…) to the card page.
final class CardSchemeHandler: NSObject, WKURLSchemeHandler {
    var mediaFolder: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let name = url.lastPathComponent
        let file: URL? = url.host == "app" ? Self.bundleFile(named: name) : mediaFolder.flatMap { Self.mediaFile(named: name, in: $0) }
        guard let file, let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["ttf": "font/ttf", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp", "mp3": "audio/mpeg", "css": "text/css", "js": "text/javascript"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Type": types[file.pathExtension.lowercased()] ?? "application/octet-stream",
            "Content-Length": "\(data.count)", "Access-Control-Allow-Origin": "*",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// A file directly inside the media folder, or nil. The name comes from the card's HTML, which an imported
    /// deck controls: a decoded "../collection.anki2" must not reach the collection next to the folder.
    static func mediaFile(named name: String, in folder: URL) -> URL? {
        guard isPlainName(name) else { return nil }
        let file = folder.appendingPathComponent(name).standardizedFileURL
        guard file.deletingLastPathComponent().path == folder.standardizedFileURL.path else { return nil }
        return file
    }

    private static func bundleFile(named name: String) -> URL? {
        isPlainName(name) ? Bundle.main.url(forResource: name, withExtension: nil) : nil
    }

    /// One path segment: no separators, not "." or "..", no NUL.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
}

/// A drag over the card page (iOS), reported so the review screen can grade by swipe.
enum CardPan {
    case changed(CGSize)
    case ended(CGSize)
    case cancelled
}

struct CardWebView {
    let html: String
    let mediaFolder: URL?
    /// Messages from the page, e.g. "play:q:0" from a replay button.
    var onMessage: (String) -> Void = { _ in }
    /// Swipe to grade: nil leaves the page's own scrolling alone.
    var onPan: ((CardPan) -> Void)? = nil
    /// Up and down count only when the page does not scroll, so a long answer still scrolls.
    var allowVertical = false
    /// Tap to show the answer.
    var onTap: (() -> Void)? = nil
    /// Room kept free under the page for a bar that floats over it: a short card ends above the bar, a long one scrolls under.
    var bottomInset: CGFloat = 0

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let handler = CardSchemeHandler()
        var shown = ""
        var onMessage: (String) -> Void = { _ in }
        var onPan: ((CardPan) -> Void)?
        var onTap: (() -> Void)?
        var allowVertical = false
        weak var web: WKWebView?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let text = message.body as? String { onMessage(text) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    fileprivate func makeWeb(_ context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        context.coordinator.handler.mediaFolder = mediaFolder
        config.setURLSchemeHandler(context.coordinator.handler, forURLScheme: "kartei")
        // Weak proxy: the content controller retains its handlers, and the coordinator owns nothing of the web view.
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "kartei")
        context.coordinator.onMessage = onMessage
        let web = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.showsHorizontalScrollIndicator = false
        // A card that fits does not rubber-band up and down, so a vertical swipe moves the card, not its text.
        web.scrollView.alwaysBounceVertical = false
        web.scrollView.alwaysBounceHorizontal = false
        context.coordinator.web = web
        context.coordinator.onPan = onPan
        context.coordinator.onTap = onTap
        context.coordinator.allowVertical = allowVertical
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        web.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        web.addGestureRecognizer(tap)
        #else
        web.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        // Screenshot runs on a locked or headless Mac: WebKit stops painting occluded windows, so tests can turn that off.
        if ProcessInfo.processInfo.environment["KARTEI_TEST_PAINT_OCCLUDED"] != nil { web.setValue(false, forKey: "windowOcclusionDetectionEnabled") }
        #endif
        #endif
        return web
    }

    fileprivate func update(_ web: WKWebView, _ context: Context) {
        context.coordinator.onMessage = onMessage
        context.coordinator.onPan = onPan
        context.coordinator.onTap = onTap
        context.coordinator.allowVertical = allowVertical
        #if os(iOS)
        if web.scrollView.contentInset.bottom != bottomInset {
            web.scrollView.contentInset.bottom = bottomInset
            web.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
        #endif
        guard context.coordinator.shown != html else { return }
        context.coordinator.shown = html
        web.loadHTMLString(html, baseURL: URL(string: "kartei://media/"))
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

#if os(iOS)
extension CardWebView.Coordinator: UIGestureRecognizerDelegate {
    /// The page keeps its own scrolling and taps; the swipe runs alongside them.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UITapGestureRecognizer { return onTap != nil }
        guard onPan != nil, let pan = g as? UIPanGestureRecognizer, let web else { return false }
        let v = pan.velocity(in: web)
        if abs(v.x) >= abs(v.y) * 1.2 { return true }
        // Vertical: only when allowed and the page itself has nothing to scroll.
        let scroll = web.scrollView
        let scrolls = scroll.contentSize.height + scroll.contentInset.bottom > scroll.bounds.height + 1
        return allowVertical && !scrolls && abs(v.y) > abs(v.x) * 1.2
    }

    @objc func pan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        let size = CGSize(width: t.x, height: allowVertical ? t.y : 0)
        switch g.state {
        case .began, .changed: onPan?(.changed(size))
        case .ended: onPan?(.ended(size))
        default: onPan?(.cancelled)
        }
    }

    @objc func tap(_ g: UITapGestureRecognizer) {
        if g.state == .ended { onTap?() }
    }
}

extension CardWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWeb(context) }
    func updateUIView(_ web: WKWebView, context: Context) { update(web, context) }
}
#else
extension CardWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWeb(context) }
    func updateNSView(_ web: WKWebView, context: Context) { update(web, context) }
}
#endif
