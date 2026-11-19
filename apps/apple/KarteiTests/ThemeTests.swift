// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import XCTest
@testable import Kartei

/// The Swift palettes are hand-copied from core/themes.json; these tests keep them equal and check the contrast,
/// the per-device store, and what the card page receives.
final class ThemeTests: XCTestCase {
    private static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()  // apps/apple
    private static let themesJSON = sourceRoot.appendingPathComponent("../../core/themes.json").standardizedFileURL

    private func json() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.themesJSON)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: (1) Swift values equal themes.json

    func testPalettesEqualThemesJSON() throws {
        let root = try json()
        let families = try XCTUnwrap(root["families"] as? [String: Any])
        XCTAssertEqual(Set(families.keys), Set(ThemeFamily.allCases.map(\.rawValue)))
        for family in ThemeFamily.allCases {
            let f = try XCTUnwrap(families[family.rawValue] as? [String: Any])
            for (mode, dark) in [("dark", true), ("light", false)] {
                let expected = try XCTUnwrap(f[mode] as? [String: String]).mapValues { $0.lowercased() }
                let actual = Palette.of(family, dark: dark).values
                XCTAssertEqual(actual, expected, "\(family.rawValue) \(mode)")
                XCTAssertEqual(Set(Palette.keys), Set(expected.keys), "\(family.rawValue) \(mode): key list")
            }
            let fonts = try XCTUnwrap(f["fonts"] as? [String: String])
            XCTAssertEqual(fonts["display"], family.fonts.display)
            XCTAssertEqual(fonts["body"], family.fonts.body)
            XCTAssertEqual(fonts["data"], family.fonts.data)
        }
        XCTAssertEqual((root["flags"] as? [String])?.map { $0.lowercased() }, Palette.flags)
        let defaults = try XCTUnwrap(root["defaults"] as? [String: String])
        XCTAssertEqual(defaults["family"], Palette.defaultFamily.rawValue)
        XCTAssertEqual(defaults["mode"], Palette.defaultMode)
        XCTAssertNotNil(ThemeMode(rawValue: Palette.defaultMode))
    }

    func testFontFilesAreBundled() {
        for family in ThemeFamily.allCases {
            for name in family.fontFiles { XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf"), name) }
        }
    }

    // MARK: (2) WCAG contrast

    static func luminance(_ hex: String) -> Double {
        let c = Palette.rgb(hex)
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testContrastMath() {
        XCTAssertEqual(Self.contrast("#000000", "#ffffff"), 21, accuracy: 0.01)
        XCTAssertEqual(Self.contrast("#777777", "#ffffff"), 4.48, accuracy: 0.01)
    }

    func testContrastOverAllPalettes() {
        let pairs: [(KeyPath<Palette, String>, KeyPath<Palette, String>, Double, String)] = [
            (\.text, \.bg, 4.5, "text/bg"), (\.text, \.surface, 4.5, "text/surface"),
            (\.muted, \.bg, 4.5, "muted/bg"), (\.muted, \.surface, 4.5, "muted/surface"),
            (\.new, \.bg, 4.5, "new/bg"), (\.learning, \.bg, 4.5, "learning/bg"),
            (\.onAccent, \.accent, 4.5, "onAccent/accent"), (\.onForgot, \.forgot, 4.5, "onForgot/forgot"),
            (\.display, \.bg, 3, "display/bg"), (\.accentRule, \.bg, 3, "accentRule/bg"), (\.control, \.bg, 3, "control/bg"),
        ]
        var failures: [String] = []
        for family in ThemeFamily.allCases {
            for dark in [true, false] {
                let p = Palette.of(family, dark: dark)
                for (a, b, min, name) in pairs {
                    let r = Self.contrast(p[keyPath: a], p[keyPath: b])
                    if r < min { failures.append("\(family.rawValue)-\(dark ? "dark" : "light") \(name) \(String(format: "%.2f", r)) < \(min)") }
                }
            }
        }
        XCTAssertEqual(failures, [], "contrast failures (report, do not change the palette here)")
    }

    // MARK: (3) ThemeStore

    private func scratchDefaults() -> UserDefaults {
        let name = "kartei-theme-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testThemeStoreDefaultsToGeistDark() {
        let store = ThemeStore(defaults: scratchDefaults())
        XCTAssertEqual(store.family, .geist)
        XCTAssertEqual(store.mode, .dark)
    }

    func testThemeStorePersistsPerDevice() {
        let d = scratchDefaults()
        let a = ThemeStore(defaults: d)
        a.family = .gruvbox
        a.mode = .system
        XCTAssertEqual(d.string(forKey: ThemeStore.familyKey), "gruvbox")
        XCTAssertEqual(d.string(forKey: ThemeStore.modeKey), "system")
        let b = ThemeStore(defaults: d)
        XCTAssertEqual(b.family, .gruvbox)
        XCTAssertEqual(b.mode, .system)
        b.mode = .light
        XCTAssertEqual(ThemeStore(defaults: d).mode, .light)
    }

    func testThemeStoreIgnoresUnknownValues() {
        let d = scratchDefaults()
        d.set("solarized", forKey: ThemeStore.familyKey)
        d.set("sepia", forKey: ThemeStore.modeKey)
        let s = ThemeStore(defaults: d)
        XCTAssertEqual(s.family, .geist)
        XCTAssertEqual(s.mode, .dark)
    }

    func testModeMapsToColorScheme() {
        XCTAssertNil(ThemeMode.system.colorScheme)
        XCTAssertEqual(ThemeMode.light.colorScheme, .light)
        XCTAssertEqual(ThemeMode.dark.colorScheme, .dark)
        XCTAssertEqual(ThemeMode.allCases.map(\.title), ["Match system", "Light", "Dark"])
    }

    /// Ink resolves per family (from the shared store) and per colour scheme (from the environment).
    func testInkResolvesPerFamilyAndScheme() {
        let shared = ThemeStore.shared
        let saved = shared.family
        defer { shared.family = saved }
        for family in ThemeFamily.allCases {
            shared.family = family
            for dark in [true, false] {
                var env = EnvironmentValues()
                env.colorScheme = dark ? .dark : .light
                let r = Ink.bg.resolve(in: env)
                let want = Palette.rgb(Palette.of(family, dark: dark).bg)
                XCTAssertEqual(Double(r.red), want.r, accuracy: 0.01, "\(family) dark=\(dark)")
                XCTAssertEqual(Double(r.green), want.g, accuracy: 0.01, "\(family) dark=\(dark)")
                XCTAssertEqual(Double(r.blue), want.b, accuracy: 0.01, "\(family) dark=\(dark)")
            }
        }
    }

    // MARK: (4) Card page

    func testCardPageCarriesPaletteAsCustomProperties() {
        for family in ThemeFamily.allCases {
            for dark in [true, false] {
                let theme = CardTheme(family: family, dark: dark)
                let page = CardPage.html(question: "Q", answer: "Q<hr id=answer>A", css: "", theme: theme)
                let p = theme.palette
                for (key, prop) in [(p.bg, "bg"), (p.surface, "surface"), (p.surface2, "surface2"), (p.rule, "rule"), (p.text, "text"),
                                    (p.muted, "muted"), (p.display, "display"), (p.accent, "accent"), (p.accentRule, "accent-rule"), (p.forgot, "forgot")] {
                    XCTAssertTrue(page.contains("--k-\(prop):\(key)"), "\(family) dark=\(dark): --k-\(prop)")
                }
                XCTAssertTrue(page.contains("color-scheme:\(dark ? "dark" : "light")"))
                XCTAssertTrue(page.contains("--k-font-display:\"\(family.fonts.display)\""))
                XCTAssertTrue(page.contains("--k-font-body:\"\(family.fonts.body)\""))
                XCTAssertEqual(page.contains("nightMode"), dark, "Anki's night-mode class only in dark mode")
                XCTAssertTrue(page.contains("--highlight-shape-border:3px \(p.accentRule)"))
                // The page's own rules use the properties, not literals; the overrides come after the shared CSS.
                XCTAssertTrue(page.contains("color:var(--k-text)!important"))
                let link = page.range(of: "kartei-card.css")!, overrides = page.range(of: ".k-typed .typeBad{background:var(--k-bad-bg)")!
                XCTAssertLessThan(link.lowerBound, overrides.lowerBound)
            }
        }
        let geistLight = CardPage.html(question: "Q", answer: nil, css: "", theme: CardTheme(family: .geist, dark: false))
        for gruvbox in ["#ebdbb2", "#504945", "#a89984", "#fabd2f", "#fb4934"] { XCTAssertFalse(geistLight.contains(gruvbox), gruvbox) }
    }

    func testCardPageChangesWithThemeSoTheWebViewReloads() {
        let pages = ThemeFamily.allCases.flatMap { f in [true, false].map { CardPage.html(question: "Q", answer: nil, css: "", theme: CardTheme(family: f, dark: $0)) } }
        XCTAssertEqual(Set(pages).count, 4)
    }

    // MARK: Widget snapshot

    func testSnapshotCarriesFamilyAndOldSnapshotsStillDecode() throws {
        let old = #"{"days":[{"cards":3,"day":"2026-11-14","minutes":1}],"studied":[],"version":1,"written":"2026-11-14T08:00:00Z"}"#
        let decoded = try XCTUnwrap(ReachSnapshot.decode(Data(old.utf8)))
        XCTAssertNil(decoded.family)
        XCTAssertEqual(decoded.themeFamily, Palette.defaultFamily)
        let snap = ReachCoordinator.snapshot(now: .now, studied: [0], forecast: [5], secondsPerCard: 8, family: .gruvbox)
        XCTAssertEqual(ReachSnapshot.decode(try snap.encoded())?.themeFamily, .gruvbox)
    }

    // MARK: No colour outside the theme

    func testNoHexColoursOutsideTheTheme() throws {
        let fm = FileManager.default
        let allowed: Set<String> = ["ThemePalette.swift", "Theme.swift"]
        var hits: [String] = []
        let pattern = try NSRegularExpression(pattern: #"0x[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{6}\b|Color\((red|white):|NSColor\(red|UIColor\(red|Color\.(black|white|red|orange|yellow|green|blue|gray)\b"#)
        for folder in ["Kartei", "Shared", "KarteiWidget"] {
            let dir = Self.sourceRoot.appendingPathComponent(folder)
            for name in try fm.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".swift") && !allowed.contains(name) {
                let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
                for (i, line) in text.components(separatedBy: "\n").enumerated() where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    hits.append("\(folder)/\(name):\(i + 1)")
                }
            }
        }
        XCTAssertEqual(hits, [])
    }
}
