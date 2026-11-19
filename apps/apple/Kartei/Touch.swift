// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Touch controls, per device (UserDefaults): swipe to grade on the answer side, right Got it (Good), left Forgot
/// (Again). Easy (up) and Hard (down) are opt-in and only in Full detail: Hard pressed after a lapse bends the
/// schedule (F3), so it gets no gesture unless asked for. Swipes before the answer do nothing, so recall comes first (F1).
@Observable
final class TouchPrefs {
    static let shared = TouchPrefs()

    @ObservationIgnored private let defaults: UserDefaults

    var swipeToGrade: Bool { didSet { defaults.set(swipeToGrade, forKey: "kartei.touch.swipe") } }
    var swipeEasy: Bool { didSet { defaults.set(swipeEasy, forKey: "kartei.touch.easy") } }
    var swipeHard: Bool { didSet { defaults.set(swipeHard, forKey: "kartei.touch.hard") } }
    var tapToReveal: Bool { didSet { defaults.set(tapToReveal, forKey: "kartei.touch.tap") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "kartei.touch.haptics") } }
    /// How many answers have shown the swipe hint; it shows for the first `hintAnswers`.
    var hintsShown: Int { didSet { defaults.set(hintsShown, forKey: "kartei.touch.hints") } }
    static let hintAnswers = 3

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        swipeToGrade = flag("kartei.touch.swipe", true)
        swipeEasy = flag("kartei.touch.easy", false)
        swipeHard = flag("kartei.touch.hard", false)
        tapToReveal = flag("kartei.touch.tap", true)
        haptics = flag("kartei.touch.haptics", true)
        hintsShown = defaults.integer(forKey: "kartei.touch.hints")
    }

    var showHint: Bool { swipeToGrade && hintsShown < Self.hintAnswers }
    func vertical(_ detail: StudyPrefs.Detail) -> Bool { detail == .full && (swipeEasy || swipeHard) }
}

/// Which grade a drag on the answer side points at, and whether it has gone far enough to grade.
enum SwipeGrade {
    /// Horizontal swipes grade past a third of the card's width; vertical ones past a fifth of its height.
    static func threshold(_ size: CGSize, vertical: Bool) -> CGFloat {
        vertical ? max(80, size.height / 5) : max(80, size.width / 3)
    }

    /// The grade the drag points at (nil: no direction, or that direction has no gesture).
    static func candidate(_ t: CGSize, detail: StudyPrefs.Detail, prefs: TouchPrefs) -> Rating? {
        let dx = t.width, dy = t.height
        guard dx != 0 || dy != 0 else { return nil }
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .good : .forgot
        }
        guard detail == .full else { return nil }
        if dy < 0 { return prefs.swipeEasy ? .easy : nil }
        return prefs.swipeHard ? .hard : nil
    }

    /// The grade to give when the finger lifts, or nil to spring back.
    static func release(_ t: CGSize, size: CGSize, detail: StudyPrefs.Detail, prefs: TouchPrefs) -> Rating? {
        guard let r = candidate(t, detail: detail, prefs: prefs) else { return nil }
        let vertical = r == .easy || r == .hard
        return abs(vertical ? t.height : t.width) >= threshold(size, vertical: vertical) ? r : nil
    }

    /// 0…1, how far towards the grading point; drives the label's strength and the haptic tick.
    static func progress(_ t: CGSize, size: CGSize, rating: Rating) -> CGFloat {
        let vertical = rating == .easy || rating == .hard
        return min(1, abs(vertical ? t.height : t.width) / threshold(size, vertical: vertical))
    }

    static func label(_ r: Rating, detail: StudyPrefs.Detail) -> String {
        switch r {
        case .forgot: "Forgot"
        case .hard: "Hard"
        case .good: detail == .simple ? "Got it" : "Good"
        case .easy: "Easy"
        }
    }
}

/// Settings → Touch controls (touch.html): one map of the four directions, then the switches.
struct TouchSection: View {
    let prefs: StudyPrefs
    var touch = TouchPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Touch controls")
            Meta("Swipes grade the card once the answer shows. The buttons stay, so nothing depends on a gesture.")
                .padding(.bottom, 16)
            DirectionMap(touch: touch, full: prefs.detail == .full)
                .padding(.bottom, 16)
            toggle("Swipe to grade", "Right is Got it, left is Forgot", isOn: Bindable(touch).swipeToGrade)
            toggle("Swipe up for Easy", "Full detail only. Easy stretches the gap a lot", isOn: Bindable(touch).swipeEasy)
                .disabled(!touch.swipeToGrade)
            toggle("Swipe down for Hard", "Full detail only. Off by default: Hard after forgetting skews the schedule", isOn: Bindable(touch).swipeHard)
                .disabled(!touch.swipeToGrade)
            toggle("Tap the card to show the answer", "Swipes before the answer do nothing", isOn: Bindable(touch).tapToReveal)
            toggle("Haptic tick at the grading point", nil, isOn: Bindable(touch).haptics)
            Meta(prefs.detail == .full ? "Undo brings back the last card from any gesture. Right always means remembered, whichever hand you use."
                                       : "You are in Simple detail, so up and down do nothing. Undo brings back the last card from any gesture.")
                .padding(.top, 16)
        }
    }

    private func toggle(_ title: String, _ detail: String?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Type.body(16, 500)).foregroundStyle(Ink.text)
                if let detail { Text(detail).font(Type.body(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Ink.accent)
        }
        .padding(.vertical, 10).frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rule() }
    }
}

/// The four directions and what each does now (touch.html .dirmap).
private struct DirectionMap: View {
    let touch: TouchPrefs
    let full: Bool

    var body: some View {
        let on = touch.swipeToGrade
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell("Easy", active: on && full && touch.swipeEasy, style: .neutral); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                .frame(minHeight: 52)
            GridRow {
                cell("Forgot", active: on, style: .forgot)
                Text("answer\nshown").font(Type.body(13)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.surface).overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1))
                cell(full ? "Good" : "Got it", active: on, style: .good)
            }
            .frame(minHeight: 72)
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell("Hard", active: on && full && touch.swipeHard, style: .neutral); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                .frame(minHeight: 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        guard touch.swipeToGrade else { return "Swipe to grade is off." }
        var parts = ["Right: \(full ? "Good" : "Got it")", "Left: Forgot"]
        parts.append("Up: Easy, \(full && touch.swipeEasy ? "on" : "off")")
        parts.append("Down: Hard, \(full && touch.swipeHard ? "on" : "off")")
        return parts.joined(separator: ". ")
    }

    enum Style { case good, forgot, neutral }

    @ViewBuilder private func cell(_ title: String, active: Bool, style: Style) -> some View {
        let fill: Color = !active ? .clear : style == .good ? Ink.accent : style == .forgot ? Ink.forgot : Ink.surface2
        let ink: Color = !active ? Ink.muted : style == .good ? Ink.onAccent : style == .forgot ? Ink.onForgot : Ink.text
        VStack(spacing: 1) {
            Text(title).font(Type.body(15, active ? 700 : 500))
            if !active { Text("off").font(Type.body(12)) }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill)
        .overlay { if !active { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
