// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

// Small building blocks shared by Browse, Stats, Pace and onboarding, following mockups/css/app.css.

/// Bar at the top of a pushed screen: back, title, optional trailing action (.nav in the mockups).
struct ScreenNav<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                NavCircleButton(symbol: "chevron.left", label: "Back", action: back)
                    .keyboardShortcut(.cancelAction)
            }
            Text(title).font(Type.body(17, 500)).foregroundStyle(Ink.text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .frame(minHeight: 44)
        // Without a back button the title starts on the content's 20 pt margin, like the text under it.
        .padding(.leading, back == nil ? 20 : 14).padding(.trailing, 14).padding(.vertical, 2)
    }
}

extension ScreenNav where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) { self.init(title: title, back: back) { EmptyView() } }
}

/// One label/value line with a rule under it (.facts .f).
struct FactRow: View {
    let label: String
    let value: String
    var weight: CGFloat = 700

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Type.body(15)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value).font(Type.body(15, weight)).monospacedDigit().foregroundStyle(Ink.text).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }
}

struct Rule: View {
    var body: some View { Rectangle().fill(Ink.rule).frame(height: 1) }
}

/// Small muted caption above a chart or group (.cap).
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Type.body(12, 500)).foregroundStyle(Ink.muted) }
}

/// Muted explanatory line (.meta).
struct Meta: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Type.body(14)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
}

/// The big full-width button: label left, number right (.btn); `quiet` is the surface version.
struct WideButton: View {
    let title: String
    var detail: String?
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if quiet {
                HStack {
                    Text(title).font(Type.display(20, heavy: true)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    if let detail { Text(detail).font(Type.body(15, 500)).monospacedDigit().lineLimit(1) }
                }
                .foregroundStyle(Ink.text)
                .padding(.horizontal, GlassLook.on ? 26 : 20).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 56)
                .quietSurface()
            } else {
                PrimaryLabel(title: title, detail: detail)
            }
        }
        .buttonStyle(.plain)
    }
}

/// − value + with 44 pt targets (.stepper).
struct CountStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var unit = ""
    var format: ((Int) -> String)?

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                .accessibilityLabel("Fewer")
            Text(verbatim: shown).font(Type.body(17, 700)).lineLimit(1).minimumScaleFactor(0.7).monospacedDigit().foregroundStyle(Ink.text)
                .frame(minWidth: 52, minHeight: 44)
                .overlay(alignment: .leading) { Rectangle().fill(Ink.control).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Ink.control).frame(width: 1) }
            stepButton("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
                .accessibilityLabel("More")
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(shown)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var shown: String { format?(value) ?? "\(value)\(unit)" }

    private func stepButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Type.symbol(16)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? Ink.text : Ink.control).disabled(!enabled)
    }
}

/// A radio choice with a title and one line of explanation (.opt).
struct OptionRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Circle().stroke(selected ? Ink.text : Ink.muted, lineWidth: 1.5).frame(width: 20, height: 20)
                    .overlay { if selected { Circle().fill(Ink.text).frame(width: 10, height: 10) } }
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Type.body(16, 700)).foregroundStyle(Ink.text)
                    Text(detail).font(Type.body(14)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row that can be ticked on and off, for choosing several things (the course picker).
struct CheckRow: View {
    let title: String
    let detail: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).stroke(checked ? Ink.accent : Ink.muted, lineWidth: 1.5).frame(width: 20, height: 20)
                    .background { if checked { RoundedRectangle(cornerRadius: 2).fill(Ink.accent) } }
                    .overlay { if checked { Image(systemName: "checkmark").font(Type.symbol(12, .bold)).foregroundStyle(Ink.onAccent) } }
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Type.body(16, 700)).foregroundStyle(Ink.text)
                    Text(detail).font(Type.body(14)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tappable list line with a muted value and chevron (.list .li).
struct ListLine: View {
    let title: String
    var detail: String?
    var value: String?
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Type.body(16, 500)).foregroundStyle(Ink.text)
                if let detail { Text(detail).font(Type.body(13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(Type.body(15)).foregroundStyle(Ink.muted).lineLimit(Type.isLarge ? 3 : 1).multilineTextAlignment(.trailing) }
            if action != nil { Image(systemName: "chevron.right").font(Type.symbol(13, .medium)).foregroundStyle(Ink.muted) }
        }
        .padding(.vertical, 8)
        .frame(minHeight: detail == nil ? 48 : 64)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rule() }

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Format a count with a thin space as thousands separator, as in the mockups ("1 240").
func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{202F}"
    f.usesGroupingSeparator = true
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// Pretty day/minute spans for intervals: "10 min", "4 d", "3 mo", "1.2 y".
func spanText(seconds: Double) -> String {
    let s = abs(seconds)
    if s < 3_600 { return "\(max(1, Int((s / 60).rounded()))) min" }
    if s < 86_400 { return "\(Int((s / 3_600).rounded())) h" }
    let d = s / 86_400
    if d < 30 { return "\(Int(d.rounded())) d" }
    if d < 365 { return "\(Int((d / 30).rounded())) mo" }
    let y = d / 365
    return y < 10 ? String(format: "%.1f y", y) : "\(Int(y.rounded())) y"
}
