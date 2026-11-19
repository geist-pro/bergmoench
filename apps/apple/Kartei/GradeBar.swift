// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// One grade button's content: which rating, its label, its key, and in Simple mode the words before the interval.
struct GradeCell {
    let rating: Rating
    let label: String
    let key: KeyEquivalent
    var lead: String?
    var big = false

    init(_ rating: Rating, _ label: String, _ key: KeyEquivalent, lead: String? = nil, big: Bool = false) {
        self.rating = rating; self.label = label; self.key = key; self.lead = lead; self.big = big
    }
}

/// Colours of a grade button. iOS (glass bar): only Good is filled; Forgot keeps the fail colour in its label.
/// macOS (flat bar): Forgot filled in the fail colour, Good in the accent, Hard and Easy on the surface.
struct GradeLook {
    let fill: Color?
    let label: Color
    let detail: Color
    let outlined: Bool

    init(_ rating: Rating) {
        switch (rating, GlassLook.on) {
        case (.good, _): fill = Ink.accent; label = Ink.onAccent; detail = Ink.onAccent; outlined = false
        case (.forgot, true): fill = nil; label = Ink.forgot; detail = Ink.muted; outlined = false
        case (.forgot, false): fill = Ink.forgot; label = Ink.onForgot; detail = Ink.onForgot; outlined = false
        case (_, true): fill = nil; label = Ink.text; detail = Ink.muted; outlined = false
        case (_, false): fill = Ink.surface2; label = Ink.text; detail = Ink.text; outlined = true
        }
    }
}

/// The shape behind one grade: a concentric capsule (or rounded cell in the 2 × 2 grid) inside the glass bar on iOS,
/// the flat 2 pt rectangle on macOS, outlined in the control colour where the fill alone is too faint to see.
struct GradeCellSurface: ViewModifier {
    let look: GradeLook
    let grid: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassLook.on ? (grid ? 20 : 27) : 2, style: .continuous)
        content
            .background { if let fill = look.fill { shape.fill(fill) } }
            .overlay { if look.outlined { shape.strokeBorder(Ink.control, lineWidth: 1) } }
            .contentShape(shape)
    }
}

/// The bar the grades sit on: one glass surface on iOS, nothing on macOS.
struct GradeBarSurface: ViewModifier {
    let grid: Bool

    func body(content: Content) -> some View {
        if GlassLook.on {
            content.padding(5).glass(in: RoundedRectangle(cornerRadius: grid ? 25 : 32, style: .continuous))
        } else {
            content
        }
    }
}

/// A small flag in the flag's colour: the shape says "flag" where the colour alone would not.
struct FlagShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.7, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A card's flag beside other text: the flag shape, and its name in an outlined chip when colours are labelled.
struct FlagChip: View {
    let flag: Int
    var named = true

    var body: some View {
        if let colour = Flags.colour(flag), let name = Flags.name(flag) {
            HStack(spacing: 6) {
                FlagShape().fill(colour).frame(width: 10, height: 12)
                if named { Text(name).font(Type.body(13)).foregroundStyle(Ink.text) }
            }
            .padding(.horizontal, named ? 7 : 0).padding(.vertical, named ? 2 : 0)
            .overlay { if named { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) flag")
        }
    }
}

/// Choose a flag: seven named cells and None, each at least 48 pt high. Tapping the set flag clears it, as before.
struct FlagPicker: View {
    let flag: Int
    let set: (Int) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: Type.isLarge ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...7, id: \.self) { f in
                cell(selected: flag == f, label: "\(Flags.names[f - 1]) flag\(flag == f ? ", set" : "")") { set(f) } content: {
                    FlagShape().fill(Flags.colours[f - 1]).frame(width: 12, height: 16)
                    Text(Flags.names[f - 1]).font(Type.body(13, flag == f ? 700 : 400)).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            cell(selected: false, label: "No flag") { if flag > 0 { set(flag) } } content: {
                Text("None").font(Type.body(13)).foregroundStyle(Ink.muted)
            }
        }
    }

    private func cell<C: View>(selected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { content() }
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(selected ? Ink.text : Ink.control, lineWidth: selected ? 2 : 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
