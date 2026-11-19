// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import CoreText
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Match system, or always light, or always dark.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// For `.preferredColorScheme`: nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The chosen look and mode, per device (UserDefaults, not the collection, so each device can differ).
/// `Ink` and `Type` read `family` through the shared store, so every view that draws with them re-renders when it changes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let familyKey = "kartei.theme.family"
    static let modeKey = "kartei.theme.mode"

    @ObservationIgnored private let defaults: UserDefaults

    var family: ThemeFamily {
        didSet { defaults.set(family.rawValue, forKey: Self.familyKey) }
    }

    var mode: ThemeMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            applyAppearance()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        family = defaults.string(forKey: Self.familyKey).flatMap(ThemeFamily.init) ?? Palette.defaultFamily
        mode = defaults.string(forKey: Self.modeKey).flatMap(ThemeMode.init) ?? ThemeMode(rawValue: Palette.defaultMode) ?? .dark
    }

    func palette(dark: Bool) -> Palette { Palette.of(family, dark: dark) }

    /// macOS: the app-wide appearance, so window chrome, sheets and menus follow too. `preferredColorScheme(nil)` does not
    /// reliably hand a window back to the system after a forced mode on macOS; `NSApp.appearance = nil` does.
    func applyAppearance() {
        #if os(macOS)
        guard self === ThemeStore.shared, let app = NSApp else { return }
        switch mode {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

/// One family's colours as dynamic colours: each resolves to the light or dark value from the view's own colour scheme
/// (the trait collection on iOS, the effective appearance on macOS).
struct InkSet {
    let bg, surface, surface2, rule, text, muted, display, accent, onAccent, accentRule, forgot, onForgot, new, learning, control, scrim: Color

    /// `strong` is the stronger-contrast variant: secondary text halfway to the text colour, dividers in the control
    /// colour, control outlines in what was the secondary text colour. Hues and everything else stay.
    init(_ family: ThemeFamily, strong: Bool = false) {
        var d = Palette.of(family, dark: true), l = Palette.of(family, dark: false)
        if strong { d = d.strongContrast; l = l.strongContrast }
        func c(_ key: KeyPath<Palette, String>) -> Color { Self.dynamic(light: l[keyPath: key], dark: d[keyPath: key]) }
        bg = c(\.bg); surface = c(\.surface); surface2 = c(\.surface2); rule = c(\.rule); text = c(\.text); muted = c(\.muted)
        display = c(\.display); accent = c(\.accent); onAccent = c(\.onAccent); accentRule = c(\.accentRule)
        forgot = c(\.forgot); onForgot = c(\.onForgot); new = c(\.new); learning = c(\.learning); control = c(\.control)
        // Dims the screen under the card actions; lighter in light mode so the page does not turn grey-brown.
        scrim = Self.dynamic(light: "#000000", dark: "#000000", lightAlpha: 0.32, darkAlpha: 0.55)
    }

    static func dynamic(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        let l = Palette.rgb(light), d = Palette.rgb(dark)
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = isDark ? d : l
            return NSColor(srgbRed: v.r, green: v.g, blue: v.b, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let v = isDark ? d : l
            return UIColor(red: v.r, green: v.g, blue: v.b, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #endif
    }
}

/// The app's colours for the chosen family; light or dark follows the colour scheme (core/themes.json).
enum Ink {
    private static let sets: [ThemeFamily: InkSet] = Dictionary(uniqueKeysWithValues: ThemeFamily.allCases.map { ($0, InkSet($0)) })
    private static let strongSets: [ThemeFamily: InkSet] = Dictionary(uniqueKeysWithValues: ThemeFamily.allCases.map { ($0, InkSet($0, strong: true)) })
    /// Reading the family and the contrast setting here registers an Observation dependency for the view whose body asked for a colour.
    static var current: InkSet { (ReadingPrefs.shared.contrast ? strongSets : sets)[ThemeStore.shared.family]! }

    static var bg: Color { current.bg }
    static var surface: Color { current.surface }
    static var surface2: Color { current.surface2 }
    static var rule: Color { current.rule }
    static var text: Color { current.text }
    static var muted: Color { current.muted }
    /// Big titles and numerals (the hero minutes, screen titles).
    static var display: Color { current.display }
    static var accent: Color { current.accent }
    static var onAccent: Color { current.onAccent }
    /// Thin rules and bars in the accent hue (--accent-rule): table header rule, card top bar, chart marks.
    static var accentRule: Color { current.accentRule }
    static var forgot: Color { current.forgot }
    static var onForgot: Color { current.onForgot }
    static var new: Color { current.new }
    static var learning: Color { current.learning }
    /// Outlines and tracks of controls and states (3:1 or more on bg). `rule` is for plain dividers only.
    static var control: Color { current.control }
    static var scrim: Color { current.scrim }
}

/// Anki's flag colours and names, one list for Browse and the review screen.
enum Flags {
    static let colours: [Color] = Palette.flags.map { Color(themeHex: $0) }
    static let names = Palette.flagNames

    static func colour(_ flag: Int) -> Color? { (1...7).contains(flag) ? colours[flag - 1] : nil }
    static func name(_ flag: Int) -> String? { (1...7).contains(flag) ? names[flag - 1] : nil }
}

/// Type per family: Gruvbox sets Bricolage Grotesque (display, 200 and 800) with DM Sans; GEIST sets Nunito (display)
/// with Noto Serif and Courier Prime for data. All but Courier Prime are variable fonts shipped in the bundle.
enum Type {
    static func register() {
        for family in ThemeFamily.allCases {
            for name in family.fontFiles {
                if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }
    }

    /// Sizes are design sizes at the default text size. They follow the system text size and Bold Text through
    /// `ReadingPrefs`: reading it here makes the calling view re-render when either setting changes. Nothing is set
    /// below `floor` points.
    static let floor: CGFloat = 13

    private static func make(_ family: String, _ design: CGFloat, _ designWeight: CGFloat, display: Bool = false) -> Font {
        let reading = ReadingPrefs.shared
        let size = reading.size(max(design, floor), display: display)
        let weight = ReadingPrefs.weight(designWeight, bold: reading.bold)
        if let font = BundledFonts.font(family, size: size, weight: weight) { return Font(font) }
        return .system(size: size, weight: weight >= 700 ? .bold : weight >= 500 ? .medium : weight <= 300 ? .ultraLight : .regular)
    }

    static func display(_ size: CGFloat, heavy: Bool, family: ThemeFamily? = nil) -> Font {
        make((family ?? ThemeStore.shared.family).fonts.display, size, heavy ? 800 : 200, display: true)
    }
    static func body(_ size: CGFloat, _ weight: CGFloat = 400) -> Font { make(ThemeStore.shared.family.fonts.body, size, weight) }
    /// Search syntax and other typed data. Gruvbox keeps the system monospace here.
    static func data(_ size: CGFloat) -> Font {
        let scaled = ReadingPrefs.shared.size(max(size, floor), display: false)
        switch ThemeStore.shared.family {
        case .gruvbox: return .system(size: scaled, design: .monospaced)
        case .geist: return BundledFonts.font("Courier Prime", size: scaled, weight: 400).map { Font($0) } ?? .system(size: scaled, design: .monospaced)
        }
    }
    /// Code and console output (typed answers on code cards): Courier Prime in GEIST, DM Mono in Gruvbox.
    static func code(_ size: CGFloat) -> Font {
        let scaled = ReadingPrefs.shared.size(max(size, floor), display: false)
        return BundledFonts.font(ThemeStore.shared.family.codeFont, size: scaled, weight: 400).map { Font($0) } ?? .system(size: scaled, design: .monospaced)
    }
    /// SF Symbols beside text: the same scaling as body text.
    static func symbol(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: ReadingPrefs.shared.size(size, display: false), weight: weight)
    }
    /// A length that should grow with body text (row heights, icon boxes).
    static func scaled(_ length: CGFloat) -> CGFloat { length * ReadingPrefs.shared.textScale }
    /// True when text is large enough that tight rows should stack.
    static var isLarge: Bool { ReadingPrefs.shared.isLarge }
}

/// The root of every window: applies the chosen mode. iOS uses `preferredColorScheme` (it covers sheets and the status
/// bar); macOS sets the app appearance so window chrome follows and "Match system" really hands back to the system.
struct ThemedRoot<Content: View>: View {
    let content: Content

    var body: some View {
        let theme = ThemeStore.shared
        content
            #if os(iOS)
            .preferredColorScheme(theme.mode.colorScheme)
            #endif
            .onAppear { theme.applyAppearance() }
    }
}

extension View {
    func themed() -> some View { ThemedRoot(content: self) }
}
