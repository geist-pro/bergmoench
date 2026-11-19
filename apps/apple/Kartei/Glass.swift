// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// The iOS look: Liquid Glass on the navigation layer only (round nav buttons, the tab bar, the grade bar), content
/// stays flat. One glass surface per group; what sits on it is drawn with fills, never glass again. The primary action
/// is a solid accent capsule, so its label keeps a fixed contrast whatever scrolls underneath. macOS keeps the flat look.
enum GlassLook {
    static var on: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
}

/// A neutral glass surface behind the content. iOS 26 and later use the system material, which handles Reduce
/// Transparency and Increase Contrast itself; earlier systems get a thin material with a hairline rim, or a solid
/// surface with a control-colour outline when transparency is reduced or contrast is raised.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), !ReadingPrefs.shared.strongContrast {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else if reduceTransparency || ReadingPrefs.shared.contrast {
            content.background(Ink.surface2, in: shape).overlay { shape.strokeBorder(Ink.control, lineWidth: 1) }
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Ink.text.opacity(0.14), lineWidth: 1) }
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        }
    }
}

extension View {
    /// Neutral glass behind this view (see `GlassSurface`).
    func glass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive))
    }

    /// The shape and fill of a primary action: a solid accent capsule on iOS, the flat 2 pt rectangle on macOS.
    func primarySurface(_ fill: Color = Ink.accent) -> some View {
        modifier(PrimarySurface(fill: fill))
    }

    /// A quiet action: surface fill with a control-colour outline, in the platform's button shape.
    func quietSurface() -> some View {
        modifier(QuietSurface())
    }

    /// Hides scrolling content behind a floating bar: solid page colour behind the bar itself, fading out over
    /// `extra` points above it, so text never shows through the bar's labels.
    func scrollFade(above extra: CGFloat = 28) -> some View {
        background(alignment: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(colors: [Ink.bg.opacity(0), Ink.bg], startPoint: .top, endPoint: .bottom).frame(height: extra)
                Ink.bg
            }
            .padding(.top, -extra).padding(.horizontal, -40).ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}

struct PrimarySurface: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        if GlassLook.on {
            content.background(fill, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1).blendMode(.plusLighter) }
                .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
                .contentShape(Capsule())
        } else {
            content.background(fill, in: RoundedRectangle(cornerRadius: 2)).contentShape(Rectangle())
        }
    }
}

struct QuietSurface: ViewModifier {
    func body(content: Content) -> some View {
        if GlassLook.on {
            content.background(Ink.surface2, in: Capsule()).overlay { Capsule().strokeBorder(Ink.control, lineWidth: 1) }.contentShape(Capsule())
        } else {
            content.background(Ink.surface2, in: RoundedRectangle(cornerRadius: 2))
                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1) }.contentShape(Rectangle())
        }
    }
}

/// A round 44 pt navigation button: glass on iOS, a plain symbol on macOS.
struct NavCircleButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(Type.symbol(17, .medium)).foregroundStyle(Ink.text)
                .frame(width: 44, height: 44).contentShape(Circle())
                .modifier(NavCircleSurface())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35).disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct NavCircleSurface: ViewModifier {
    func body(content: Content) -> some View {
        if GlassLook.on { content.glass(in: Circle(), interactive: true) } else { content }
    }
}

/// The full-width primary action: label left, detail right.
struct PrimaryLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(Type.display(20, heavy: true)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(Type.body(15, 500)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }
        }
        .foregroundStyle(Ink.onAccent)
        .padding(.horizontal, GlassLook.on ? 26 : 20).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56)
        .primarySurface()
    }
}
