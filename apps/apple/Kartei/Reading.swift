// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Observation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Reading settings, per device (UserDefaults), plus the system settings they sit on top of: text size, Bold Text and
/// Increase Contrast. `Type` and `Ink` read this store, so every view that draws text or colour re-renders when the
/// person changes a system setting or one of the switches on the Reading page.
@Observable
final class ReadingPrefs {
    static let shared = ReadingPrefs()

    /// Card text steps: on top of the system text size.
    static let cardScales: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5]

    @ObservationIgnored private let defaults: UserDefaults

    /// Index into `cardScales`.
    var cardStep: Int { didSet { defaults.set(cardStep, forKey: "kartei.reading.cardScale") } }
    /// Questions in Regular instead of the thin display weight.
    var regularQuestions: Bool { didSet { defaults.set(regularQuestions, forKey: "kartei.reading.regularQuestions") } }
    /// Brighter secondary text and visible dividers, whatever the system says.
    var strongContrast: Bool { didSet { defaults.set(strongContrast, forKey: "kartei.reading.strongContrast") } }
    /// Names beside flags and queue counts, so colour is never the only cue.
    var labelColours: Bool { didSet { defaults.set(labelColours, forKey: "kartei.reading.labelColours") } }

    /// How much the system text size enlarges body text (1 at the default size). Always 1 on macOS.
    private(set) var systemScale: Double = 1
    private(set) var systemBold = false
    private(set) var systemContrast = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        let step = defaults.object(forKey: "kartei.reading.cardScale") == nil ? 1 : defaults.integer(forKey: "kartei.reading.cardScale")
        cardStep = min(max(step, 0), Self.cardScales.count - 1)
        regularQuestions = flag("kartei.reading.regularQuestions", false)
        strongContrast = flag("kartei.reading.strongContrast", false)
        labelColours = flag("kartei.reading.labelColours", true)
        #if os(iOS)
        readSystem()
        let centre = NotificationCenter.default
        for name in [UIContentSizeCategory.didChangeNotification, UIAccessibility.boldTextStatusDidChangeNotification,
                     UIAccessibility.darkerSystemColorsStatusDidChangeNotification] {
            centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.readSystem() }
        }
        #endif
    }

    #if os(iOS)
    private func readSystem() {
        let scale = Double(UIFontMetrics(forTextStyle: .body).scaledValue(for: 100)) / 100
        if scale != systemScale { systemScale = scale }
        if UIAccessibility.isBoldTextEnabled != systemBold { systemBold = UIAccessibility.isBoldTextEnabled }
        if UIAccessibility.isDarkerSystemColorsEnabled != systemContrast { systemContrast = UIAccessibility.isDarkerSystemColorsEnabled }
    }
    #endif

    /// Debug and tests: pretend the system text size is this factor.
    func overrideSystemScale(_ scale: Double) { systemScale = scale }

    // MARK: what the app draws with

    /// Body and label text grow with the system up to twice their size; past that the layouts stop holding.
    static let maxTextScale = 2.0
    /// Display type (titles, the hero numeral) grows less, so it does not push the content off the screen.
    static let maxDisplayScale = 1.3
    /// From this factor on, tight rows switch to their stacked layout (`isLarge`).
    static let largeLayoutScale = 1.3

    var textScale: Double { min(max(systemScale, 0.8), Self.maxTextScale) }
    var displayScale: Double { min(max(systemScale, 0.9), Self.maxDisplayScale) }
    var isLarge: Bool { textScale >= Self.largeLayoutScale }
    var bold: Bool { systemBold }
    var contrast: Bool { strongContrast || systemContrast }

    /// The card page's text size against its design size: system text size times the card step.
    var cardScale: Double { textScale * Self.cardScales[cardStep] }
    /// Questions in Regular: asked for, or implied by Bold Text or stronger contrast.
    var regularQuestionWeight: Bool { regularQuestions || systemBold || contrast }

    /// Point size for a design size, by role.
    func size(_ design: CGFloat, display: Bool) -> CGFloat { (design * (display ? displayScale : textScale)).rounded() }

    /// Bold Text moves every weight up one step of the scale the app uses.
    static func weight(_ design: CGFloat, bold: Bool) -> CGFloat {
        guard bold else { return design }
        switch design {
        case ..<300: return 400
        case ..<450: return 600
        case ..<600: return 700
        default: return 800
        }
    }
}
