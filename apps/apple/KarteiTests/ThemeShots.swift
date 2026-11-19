// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Kartei

/// Renders the key screens in all four looks (Gruvbox/GEIST × dark/light) inside the app process and writes PNGs.
/// Opt-in: TEST_RUNNER_KARTEI_THEME_SHOTS=/out/dir TEST_RUNNER_KARTEI_THEME_SHOTS_DATA=/scratch/collection xcodebuild test …
/// Card pages are WKWebViews, which a hosting view's bitmap cache leaves empty, so each is snapshotted and laid in.
final class ThemeShots: XCTestCase {
    private var out: URL!

    private func wait(_ seconds: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func webViews(in view: NSView) -> [WKWebView] {
        if let w = view as? WKWebView { return [w] }
        return view.subviews.flatMap(webViews)
    }

    private func present<V: View>(dark: Bool, height: CGFloat, _ view: V) -> (NSHostingView<some View>, NSWindow) {
        let host = NSHostingView(rootView: view.frame(width: 390, height: height).background(Ink.bg).environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(x: 0, y: 0, width: 390, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.orderFront(nil)
        return (host, window)
    }

    private func capture(_ host: NSView, _ name: String, settle: Double) {
        wait(settle)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        for web in webViews(in: host) where web.alphaValue > 0 {
            var image: NSImage?, done = false
            web.takeSnapshot(with: nil) { i, _ in image = i; done = true }
            wait(10) { done }
            guard let image else { continue }
            var rect = web.convert(web.bounds, to: host)
            if host.isFlipped { rect.origin.y = host.bounds.height - rect.maxY }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
    }

    private func shot<V: View>(_ name: String, dark: Bool, height: CGFloat = 844, settle: Double = 2.5, _ view: V) {
        let (host, window) = present(dark: dark, height: height, view)
        capture(host, name, settle: settle)
        window.orderOut(nil)
    }

    @MainActor
    func testRenderThemes() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["KARTEI_THEME_SHOTS"], let data = env["KARTEI_THEME_SHOTS_DATA"] else { throw XCTSkip("set KARTEI_THEME_SHOTS and KARTEI_THEME_SHOTS_DATA") }
        out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        setenv("KARTEI_TEST_PAINT_OCCLUDED", "1", 1)
        let fresh = !FileManager.default.fileExists(atPath: data + "/collection.anki2")
        setenv("KARTEI_DATA_DIR", data, 1)
        let store = DeckStore()
        store.load()
        wait(60) { if case .ready = store.phase { return true } else { return false } }
        let backend = try XCTUnwrap(store.backend)
        if fresh { try ScreensShots.addHistory(backend) }
        store.refresh()
        wait(2)
        let prefs = StudyPrefs()
        prefs.load(backend)

        // Review fixtures in their own scratch collection: a basic card, a typed answer, image occlusion.
        let col = try TestCollection()
        defer { col.close(); try? FileManager.default.removeItem(at: col.dir) }
        let basic = try col.deck("Theme::Basic"), typed = try col.deck("Theme::Typed"), io = try col.deck("Theme::Occlusion")
        try col.note("Basic", ["What does spacing do to <b>long-term</b> retention?", "It improves it: reviews spread out beat reviews massed together."], deck: basic)
        try col.note("Basic (type in the answer)", ["Who is known as the father of ubiquitous computing?", "Mark Weiser"], deck: typed)
        var cur = Anki_Decks_DeckId(); cur.did = io
        let _: Anki_Collection_OpChanges = try col.backend.call(DecksMethods.setCurrentDeck, cur)
        try col.occlusionNote(hideAll: true)
        let reviewPrefs = StudyPrefs()
        reviewPrefs.load(col.backend)

        let theme = ThemeStore.shared
        let saved = (theme.family, theme.mode)
        defer { theme.family = saved.0; theme.mode = saved.1 }

        for family in ThemeFamily.allCases {
            for dark in [true, false] {
                theme.family = family
                theme.mode = dark ? .dark : .light
                let tag = "\(family.rawValue)-\(dark ? "dark" : "light")"
                shot("\(tag)-home", dark: dark, HomeView(store: store, study: { _ in }))
                shot("\(tag)-stats", dark: dark, height: 1180, StatsView(store: store))
                shot("\(tag)-settings", dark: dark, height: 1400, settle: 3.5, SettingsView(store: store, prefs: prefs))
                shot("\(tag)-browse", dark: dark, BrowseView(store: store))

                for (deck, name) in [(basic, "basic"), (typed, "typed"), (io, "occlusion")] {
                    let s = ReviewSession(backend: col.backend, deckID: deck, deckName: "Theme", exams: [:])
                    s.attach(audio: RecordingAudio())
                    // One view for both sides: ReviewView starts the session from its .task.
                    let (host, window) = present(dark: dark, height: 844, ReviewView(session: s, mediaFolder: col.media) {}.environment(reviewPrefs))
                    wait(20) { s.isQuestion }
                    capture(host, "\(tag)-\(name)-question", settle: 3)
                    if name == "typed" { s.typed = "Mark Wieser" }
                    s.showAnswer()
                    wait(20) { s.isAnswer }
                    capture(host, "\(tag)-\(name)-answer", settle: 3)
                    window.orderOut(nil)
                }

                let snap = ReachCoordinator.snapshot(now: .now, studied: [0, -1, -2, -4, -7, -8, -11, -14], forecast: [90, 40], secondsPerCard: 8, family: family)
                let ink = WidgetInk(family, dark: dark)
                WidgetType.register()
                let widget = ReachWidgetContent(snapshot: snap, date: .now, size: .medium).padding(16).frame(width: 364, height: 170).background(ink.bg)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let r = ImageRenderer(content: widget)
                r.scale = 2
                if let cg = r.cgImage {
                    try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(tag)-widget.png"))
                }
            }
        }
    }
}
