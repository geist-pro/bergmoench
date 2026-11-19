// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Browse (browse.html): Anki's search syntax in one field, quick filters, results by due date, and card actions.
struct BrowseView: View {
    let store: DeckStore
    @State private var model: BrowseModel
    @State private var info: Int64?
    @State private var debounce: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    /// Opens a review session; "Study these as a deck" goes straight into the new filtered deck.
    var study: ((DeckRow) -> Void)? = nil

    init(store: DeckStore, study: ((DeckRow) -> Void)? = nil, model: BrowseModel = BrowseModel()) {
        self.study = study
        self.store = store
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let info {
                CardInfoView(backend: store.backend, cardID: info, model: model) { self.info = nil }
            } else {
                list
            }
        }
        .background(Ink.bg)
        .onAppear { model.attach(store.backend) }
        .onChange(of: store.backend == nil) { model.attach(store.backend) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField.padding(.top, 12)
            filters.padding(.top, 12)
            HStack {
                Text(countText).font(Type.body(13)).foregroundStyle(Ink.muted).monospacedDigit()
                Spacer()
                if model.searching { ProgressView().controlSize(.small) }
            }
            .frame(minHeight: 28)
            .padding(.top, 4)
            if let e = model.error {
                Meta("Anki could not read that search: \(e)").padding(.vertical, 8)
            }
            results
            if let msg = model.message {
                Meta(msg).padding(.vertical, 6)
            }
            if !model.ids.isEmpty {
                WideButton(title: "Study these as a deck", detail: "\(grouped(model.ids.count)) cards", quiet: true) {
                    model.studyAsDeck { name in
                        guard let name else { return }
                        store.refresh()
                        guard let study, let backend = store.backend else { return }
                        var key = Anki_Generic_String()
                        key.val = name
                        if let id: Anki_Decks_DeckId = try? backend.call(DecksMethods.getDeckIdByName, key) {
                            study(DeckRow(id: id.did, name: name, depth: 0, hasChildren: false, filtered: true, new: 0, learning: 0, due: 0))
                        }
                    }
                }
                .padding(.vertical, 12)
                .accessibilityHint("Makes a filtered deck from this search, as in Anki. It keeps the cards' own scheduling.")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private var countText: String {
        let n = model.ids.count
        return "\(grouped(n)) card\(n == 1 ? "" : "s"), sorted by due"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(Type.symbol(16)).foregroundStyle(Ink.text).accessibilityHidden(true)
            TextField("", text: $model.text, prompt: Text("deck:Intro is:due tag:exam").foregroundColor(Ink.muted))
                .textFieldStyle(.plain)
                .font(Type.data(14))
                .foregroundStyle(Ink.text)
                .focused($searchFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .onSubmit { model.run() }
                .onChange(of: model.text) { scheduleSearch() }
                .accessibilityLabel("Search cards")
                .accessibilityHint("Anki search syntax works, for example deck:name, tag:exam or is:due.")
            if !model.text.isEmpty {
                Button { model.text = ""; model.run() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(searchFocused ? Ink.accent : Ink.text, lineWidth: 1))
    }

    private func scheduleSearch() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { model.run() }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BrowseFilter.allCases) { f in
                    let on = model.filter == f
                    Button {
                        model.filter = on ? nil : f
                        model.run()
                    } label: {
                        Text(f.title).font(Type.body(13, 500)).foregroundStyle(on ? Ink.bg : Ink.muted)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(on ? Ink.text : .clear)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(f == .slipping ? "Cards forgotten 8 times or more" : "")
                }
            }
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.ids, id: \.self) { id in
                    BrowseRowView(row: model.rows[id])
                        .onAppear { model.needRow(id) }
                        .onTapGesture { info = id }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Card info") { info = id }
                        .contextMenu { actions(id) }
                }
            }
        }
        .overlay {
            if model.ids.isEmpty && !model.searching && model.error == nil {
                Meta(model.search.isEmpty ? "No cards yet." : "No cards match.").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func actions(_ id: Int64) -> some View {
        Button("Card info") { info = id }
        Menu("Flag") {
            ForEach(1...7, id: \.self) { f in
                Button((model.rows[id]?.flag == f ? "✓ " : "") + Flags.names[f - 1]) { model.setFlag(f, on: id) }
            }
            if (model.rows[id]?.flag ?? 0) > 0 { Button("Remove flag") { model.setFlag(model.rows[id]?.flag ?? 0, on: id) } }
        }
        if model.rows[id]?.status.suspended == true {
            Button("Unsuspend") { model.setSuspended(false, [id]) }
        } else {
            Button("Suspend") { model.setSuspended(true, [id]) }
        }
    }
}

/// One result row: flag square, question, deck and tags, due and state.
struct BrowseRowView: View {
    let row: BrowseRow?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FlagShape().fill(row.flatMap { Flags.colour($0.flag) } ?? .clear)
                .frame(width: 10, height: 12)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(row?.question ?? " ").font(Type.body(15, 500)).lineLimit(1)
                    .foregroundStyle(row?.status.suspended == true ? Ink.muted : Ink.text)
                Text(meta).font(Type.body(12)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row?.status.due ?? "").font(Type.body(13, 500)).foregroundStyle(Ink.text)
                Text(row?.status.state ?? "").font(Type.body(12)).foregroundStyle(Ink.muted)
            }
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rule() }
        .redacted(reason: row == nil ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var meta: String {
        guard let row else { return " " }
        let tags = row.tags.split(separator: " ").joined(separator: ", ")
        return tags.isEmpty ? row.deck : "\(row.deck)   \(tags)"
    }

    private var spoken: String {
        guard let row else { return "Loading" }
        var parts = [row.question, row.deck, "due \(row.status.due)", row.status.state]
        if let flag = Flags.name(row.flag) { parts.append("\(flag) flag") }
        return parts.joined(separator: ", ")
    }
}
