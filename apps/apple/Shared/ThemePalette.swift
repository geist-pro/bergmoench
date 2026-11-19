// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Shared by the app and the widget extension. The values are hand-copied from core/themes.json (the one source for
// both apps and the card page); ThemeTests parses that file from the source tree and checks every value here.

import CoreText
import SwiftUI

/// The two looks. Each has a dark and a light palette and its own type.
enum ThemeFamily: String, CaseIterable, Codable, Identifiable {
    case gruvbox, geist

    var id: String { rawValue }
    var title: String { self == .gruvbox ? "Gruvbox" : "GEIST" }
    /// GEIST is the default look, so pickers list it first.
    static let pickerOrder: [ThemeFamily] = [.geist, .gruvbox]

    /// Font family names, as registered from the bundled files (themes.json "fonts").
    var fonts: (display: String, body: String, data: String) {
        switch self {
        case .gruvbox: ("Bricolage Grotesque", "DM Sans", "DM Mono")
        case .geist: ("Nunito", "Noto Serif", "Courier Prime")
        }
    }

    /// The bundled .ttf files each family needs (resource names without extension).
    /// The monospace face for code on cards and in typed answers.
    var codeFont: String {
        switch self {
        case .gruvbox: "DM Mono"
        case .geist: "Courier Prime"
        }
    }

    var fontFiles: [String] {
        switch self {
        case .gruvbox: ["BricolageGrotesque", "DMSans", "DMMono"]
        case .geist: ["Nunito", "NotoSerif", "CourierPrime"]
        }
    }
}

/// One palette as "#rrggbb" strings, keys as in themes.json.
struct Palette: Equatable {
    var bg, surface, surface2, rule, text, muted, display, accent, onAccent, accentRule, forgot, onForgot, new, learning, control: String

    static let keys = ["bg", "surface", "surface2", "rule", "text", "muted", "display", "accent", "onAccent", "accentRule", "forgot", "onForgot", "new", "learning", "control"]

    /// Keyed like themes.json, for the tests and the card page's custom properties.
    var values: [String: String] {
        ["bg": bg, "surface": surface, "surface2": surface2, "rule": rule, "text": text, "muted": muted, "display": display,
         "accent": accent, "onAccent": onAccent, "accentRule": accentRule, "forgot": forgot, "onForgot": onForgot, "new": new, "learning": learning, "control": control]
    }

    static func of(_ family: ThemeFamily, dark: Bool) -> Palette {
        switch (family, dark) {
        case (.gruvbox, true): gruvboxDark
        case (.gruvbox, false): gruvboxLight
        case (.geist, true): geistDark
        case (.geist, false): geistLight
        }
    }

    static let gruvboxDark = Palette(bg: "#282828", surface: "#32302f", surface2: "#3c3836", rule: "#504945", text: "#ebdbb2", muted: "#a89984", display: "#ebdbb2",
                                     accent: "#fabd2f", onAccent: "#1d2021", accentRule: "#fabd2f", forgot: "#fb6a57", onForgot: "#1d2021", new: "#83a598", learning: "#fe8019", control: "#928374")
    static let gruvboxLight = Palette(bg: "#fbf1c7", surface: "#f2e5bc", surface2: "#ebdbb2", rule: "#d5c4a1", text: "#282828", muted: "#665c54", display: "#282828",
                                      accent: "#282828", onAccent: "#fbf1c7", accentRule: "#b57614", forgot: "#9d0006", onForgot: "#fbf1c7", new: "#076678", learning: "#af3a03", control: "#7c6f64")
    static let geistDark = Palette(bg: "#0b1220", surface: "#121b30", surface2: "#1a2540", rule: "#26335a", text: "#f4f7fb", muted: "#aab7d2", display: "#8fb3f2",
                                   accent: "#29b7ea", onAccent: "#161616", accentRule: "#29b7ea", forgot: "#ff7a6b", onForgot: "#161616", new: "#6fcdf2", learning: "#f2a865", control: "#5a6ea6")
    static let geistLight = Palette(bg: "#ffffff", surface: "#f2f6fb", surface2: "#e4ebf5", rule: "#d6deea", text: "#161616", muted: "#3a4a66", display: "#193f82",
                                    accent: "#193f82", onAccent: "#ffffff", accentRule: "#1687b5", forgot: "#b42318", onForgot: "#ffffff", new: "#0a6e96", learning: "#a14a00", control: "#7f8ea9")

    /// The stronger-contrast variant: secondary text halfway to the text colour, dividers in the control colour,
    /// control outlines in what was the secondary text colour.
    var strongContrast: Palette {
        var p = self
        p.muted = Palette.blend(muted, text, 0.5)
        p.rule = control
        p.control = muted
        return p
    }

    /// `a` moved the fraction `t` of the way to `b`, as "#rrggbb".
    static func blend(_ a: String, _ b: String, _ t: Double) -> String {
        let x = rgb(a), y = rgb(b)
        func mix(_ u: Double, _ v: Double) -> Int { Int(((u + (v - u) * t) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", mix(x.r, y.r), mix(x.g, y.g), mix(x.b, y.b))
    }

    /// Anki's flag colours, the same in every theme (themes.json "flags"): red, orange, green, blue, pink, turquoise, purple.
    static let flags = ["#e5484d", "#f08c2e", "#46a758", "#3e8ed0", "#d6409f", "#12a594", "#8e4ec6"]
    static let flagNames = ["Red", "Orange", "Green", "Blue", "Pink", "Turquoise", "Purple"]

    /// First launch: GEIST, dark (themes.json "defaults").
    static let defaultFamily = ThemeFamily.geist
    static let defaultMode = "dark"

    /// "#rrggbb" to 0–1 sRGB components.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
}

extension Color {
    /// A fixed sRGB colour from a palette string. Only the theme code uses this; screens use `Ink`.
    init(themeHex hex: String) {
        let c = Palette.rgb(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b)
    }
}

/// The bundled font files, opened from the files themselves rather than looked up by family name: a static
/// "Nunito" or "Noto Serif" installed on the device would otherwise win the name lookup and drop the variable axes.
enum BundledFonts {
    static let files = ["Bricolage Grotesque": "BricolageGrotesque", "DM Sans": "DMSans", "Nunito": "Nunito", "Noto Serif": "NotoSerif", "Courier Prime": "CourierPrime", "DM Mono": "DMMono"]

    private static let descriptors: [String: CTFontDescriptor] = {
        var out: [String: CTFontDescriptor] = [:]
        for (family, file) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf"),
                  let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = all.first else { continue }
            out[family] = first
        }
        return out
    }()

    static func has(_ family: String) -> Bool { descriptors[family] != nil }

    /// The family at `weight` (and optical size where the font has that axis), or nil when the file is not bundled.
    static func font(_ family: String, size: CGFloat, weight: CGFloat) -> CTFont? {
        guard let base = descriptors[family] else { return nil }
        let wght = 2003265652, opsz = 1869640570  // 'wght', 'opsz' axis tags; a font without an axis ignores it
        let axes: [Int: CGFloat] = [wght: weight, opsz: min(max(size, 9), 96)]
        let d = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: axes] as CFDictionary)
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }
}
