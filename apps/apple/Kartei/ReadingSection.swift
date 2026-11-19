// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Reading: how large and how heavy the cards are set, stronger contrast, names beside colours, and the language the
/// cards are in. Text size and motion follow the system and need no switch here. Stored per device (ReadingPrefs),
/// except the card language, which belongs to the deck and lives in the collection.
struct ReadingSection: View {
    let store: DeckStore
    var reading = ReadingPrefs.shared

    static let languages: [(code: String?, name: String)] = [(nil, "Automatic"), ("de", "Deutsch"), ("en", "English")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Reading")
            Caption("Card text").padding(.top, 4).padding(.bottom, 8)
            sizePicker
            Meta("On top of your system text size.").padding(.top, 6)
            preview.padding(.top, 12).padding(.bottom, 8)
            toggle("Regular weight questions", "Instead of the thin display weight. Always on with Bold Text.", isOn: Bindable(reading).regularQuestions)
            toggle("Stronger contrast", "Brighter secondary text and visible dividers. Also follows Increase Contrast.", isOn: Bindable(reading).strongContrast)
            toggle("Label colours", "Names beside flags and queue counts.", isOn: Bindable(reading).labelColours)
            Caption("Card language").padding(.top, 24).padding(.bottom, 4)
            Meta("VoiceOver reads a deck's cards in this language. Subdecks follow their deck.")
            let decks = store.rows.filter { $0.depth == 0 && !$0.filtered }
            if decks.isEmpty {
                Meta("No decks yet.").padding(.top, 12)
            } else {
                ForEach(decks) { deck in languageRow(deck) }
            }
        }
    }

    /// Five steps, each an "A" at its own size; the chosen one is filled in the accent.
    private var sizePicker: some View {
        HStack(spacing: 0) {
            ForEach(ReadingPrefs.cardScales.indices, id: \.self) { i in
                let on = reading.cardStep == i
                Button { reading.cardStep = i } label: {
                    Text("A").font(.system(size: 17 * ReadingPrefs.cardScales[i], weight: on ? .bold : .medium, design: .rounded))
                        .foregroundStyle(on ? Ink.onAccent : Ink.text)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(on ? Ink.accent : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.control).frame(width: 1) } }
                .accessibilityLabel("Card text \(Int((ReadingPrefs.cardScales[i] * 100).rounded())) percent")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1) }
    }

    /// A question and an answer line as the card would set them.
    private var preview: some View {
        let scale = ReadingPrefs.cardScales[reading.cardStep] * reading.textScale
        let family = ThemeStore.shared.family
        return VStack(alignment: .leading, spacing: 8) {
            Text("Was ist ein Stack?")
                .font(BundledFonts.font(family.fonts.display, size: 26 * scale, weight: reading.regularQuestionWeight ? 400 : 200).map { Font($0) } ?? .system(size: 26 * scale))
            Text("Ein Stapel: zuletzt hinein, zuerst heraus.")
                .font(BundledFonts.font(family.fonts.body, size: 20 * scale, weight: 500).map { Font($0) } ?? .system(size: 20 * scale))
        }
        .foregroundStyle(Ink.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of card text")
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

    private func languageRow(_ deck: DeckRow) -> some View {
        let current = store.deckLanguages[deck.id]
        let name = Self.languages.first { $0.code == current }?.name ?? current ?? "Automatic"
        return Menu {
            ForEach(Self.languages, id: \.name) { choice in
                Button { store.setLanguage(choice.code, for: deck.id) } label: {
                    if choice.code == current { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(deck.name).font(Type.body(16, 500)).foregroundStyle(Ink.text).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(name).font(Type.body(15)).foregroundStyle(Ink.muted)
                Image(systemName: "chevron.up.chevron.down").font(Type.symbol(12, .medium)).foregroundStyle(Ink.muted)
            }
            .padding(.vertical, 8).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityLabel("\(deck.name), card language")
        .accessibilityValue(name)
    }
}
