// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Appearance: the look (Gruvbox or GEIST) and the mode (match system, light, dark), each with a small live swatch.
/// Stored per device in UserDefaults (ThemeStore), not in the collection, so a phone and a Mac can differ.
struct AppearanceSection: View {
    var theme = ThemeStore.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Appearance")
            Caption("Look").padding(.top, 4).padding(.bottom, ChoiceLayout.captionGap)
            ChoiceGrid(count: ThemeFamily.pickerOrder.count) { i in
                let family = ThemeFamily.pickerOrder[i]
                ChoiceTile(selected: theme.family == family, label: family.title, accessibility: "\(family.title) look") {
                    theme.family = family
                } swatch: {
                    FamilySwatch(palette: Palette.of(family, dark: scheme == .dark), family: family)
                }
            }
            Caption("Mode").padding(.top, ChoiceLayout.sectionGap).padding(.bottom, ChoiceLayout.captionGap)
            ChoiceGrid(count: ThemeMode.allCases.count) { i in
                let mode = ThemeMode.allCases[i]
                ChoiceTile(selected: theme.mode == mode, label: mode.title, accessibility: mode.title) {
                    theme.mode = mode
                } swatch: {
                    ModeSwatch(family: theme.family, mode: mode)
                }
            }
            AppIconPicker()
            Meta("Saved on this device only. Cards follow the look too.").padding(.top, ChoiceLayout.sectionGap)
        }
    }
}

/// Three equal columns for every picker in Appearance, so tiles line up from row to row whether a row has
/// two choices or three (empty columns stay empty).
enum ChoiceLayout {
    static let columns = 3
    static let spacing: CGFloat = 12
    static let captionGap: CGFloat = 8
    static let sectionGap: CGFloat = 20
    static let swatchHeight: CGFloat = 56
}

struct ChoiceGrid<Tile: View>: View {

    let count: Int
    @ViewBuilder let tile: (Int) -> Tile

    var body: some View {
        Grid(horizontalSpacing: ChoiceLayout.spacing, verticalSpacing: ChoiceLayout.spacing) {
            GridRow(alignment: .top) {
                ForEach(0..<ChoiceLayout.columns, id: \.self) { i in
                    if i < count { tile(i) } else { Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical) }
                }
            }
        }
    }
}

/// One choice: a swatch of fixed height, its label left-aligned under it. Selection draws on the swatch itself
/// (2 pt in the accent, inside the edge) and bolds the label, so choosing never moves anything.
struct ChoiceTile<Swatch: View>: View {
    let selected: Bool
    let label: String
    let accessibility: String
    let action: () -> Void
    @ViewBuilder let swatch: () -> Swatch

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                swatch().frame(maxWidth: .infinity).frame(height: ChoiceLayout.swatchHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(selected ? Ink.accent : Ink.control, lineWidth: selected ? 2 : 1))
                HStack(spacing: 6) {
                    Text(label).font(Type.body(14, selected ? 700 : 500)).foregroundStyle(selected ? Ink.text : Ink.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if selected {
                        Image(systemName: "checkmark").font(Type.symbol(11, .bold)).foregroundStyle(Ink.accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A family's page in the current mode: its display face over its background, an accent bar, a body line.
private struct FamilySwatch: View {
    let palette: Palette
    let family: ThemeFamily

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Aa").font(Type.display(22, heavy: true, family: family)).foregroundStyle(Color(themeHex: palette.display))
            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(Color(themeHex: palette.accentRule)).frame(width: 28, height: 2)
                Rectangle().fill(Color(themeHex: palette.muted)).frame(width: 40, height: 2)
                Rectangle().fill(Color(themeHex: palette.accent)).frame(width: 18, height: 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(themeHex: palette.bg))
    }
}

/// Light, dark, or both halves for "Match system", in the chosen family.
private struct ModeSwatch: View {
    let family: ThemeFamily
    let mode: ThemeMode

    var body: some View {
        HStack(spacing: 0) {
            if mode != .dark { half(Palette.of(family, dark: false)) }
            if mode != .light { half(Palette.of(family, dark: true)) }
        }
    }

    private func half(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color(themeHex: p.text)).frame(width: 20, height: 3)
            Rectangle().fill(Color(themeHex: p.accentRule)).frame(width: 12, height: 2)
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(themeHex: p.bg))
    }
}
