// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

enum Tab: String, CaseIterable { case decks = "Decks", browse = "Browse", stats = "Stats", settings = "Settings" }

/// Top-level navigation: onboarding on first run, otherwise the four tabs, and the review screen over everything.
struct AppShell: View {
    @Bindable var store: DeckStore
    @State private var prefs = StudyPrefs()
    @State private var tab: Tab = Self.startTab
    @State private var session: ReviewSession?
    /// The filtered deck behind the guided first session; removed when that session closes so the cards go home.
    @State private var firstSessionDeck: Int64?
    /// Card language of the deck being studied (DeckStore.language), for the card page.
    @State private var studyLanguage: String?

    var body: some View {
        Group {
            if let session {
                ReviewView(session: session, mediaFolder: store.mediaFolder, secondsPerCard: store.secondsPerCard,
                           coach: firstSessionDeck != nil, language: studyLanguage) {
                    self.session = nil
                    if let deck = firstSessionDeck, let backend = store.backend {
                        firstSessionDeck = nil
                        Task.detached { CourseCatalogue.removeFirstSession(deck, backend: backend); await MainActor.run { store.refresh() } }
                    } else {
                        store.refresh()
                    }
                }
            } else if prefs.loaded && !prefs.onboarded {
                OnboardingView(store: store, prefs: prefs) { deck in
                    guard let backend = store.backend else { return }
                    firstSessionDeck = deck
                    studyLanguage = nil
                    session = ReviewSession(backend: backend, deckID: deck, deckName: CourseCatalogue.firstSessionName, exams: store.examDates)
                }
            } else {
                tabs {
                    Group {
                        switch tab {
                        case .decks: HomeView(store: store, study: study)
                        case .browse: BrowseView(store: store, study: study)
                        case .stats: StatsView(store: store)
                        case .settings: SettingsView(store: store, prefs: prefs)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Views read Ink through Observation; the id also rebuilds what caches drawn colours (canvases, web views).
                    .id("\(ThemeStore.shared.family.rawValue)-\(ThemeStore.shared.mode.rawValue)-\(ReadingPrefs.shared.contrast)")
                }
                .background(Ink.bg)
            }
        }
        .environment(prefs)
        .onChange(of: store.backend == nil) { _, missing in
            if !missing, let backend = store.backend { prefs.load(backend); applyDefaults(backend) }
        }
        .onChange(of: prefs.onboarded) { _, done in if done, let backend = store.backend { applyDefaults(backend) } }
        .onChange(of: store.rows.map(\.id)) {
            Reach.storeDidUpdate(store)
            // A full download from the sync server replaces the collection config too.
            if let backend = store.backend { prefs.load(backend) }
        }
        .onChange(of: store.studiedDays) { Reach.storeDidUpdate(store) }
        .onChange(of: store.cardsToday) { Reach.storeDidUpdate(store) }
        // The widget draws in the chosen family; the snapshot carries it.
        .onChange(of: ThemeStore.shared.family) { Reach.storeDidUpdate(store) }
        #if DEBUG
        // Screenshot hook: open a deck's review at launch (KARTEI_TEST_STUDY=deck name), optionally showing the answer.
        .onChange(of: store.rows.count) { _, n in
            guard n > 0, session == nil, let name = ProcessInfo.processInfo.environment["KARTEI_TEST_STUDY"],
                  let row = store.rows.first(where: { $0.name == name }) else { return }
            study(row)
            if ProcessInfo.processInfo.environment["KARTEI_TEST_SHOW_ANSWER"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { session?.showAnswer() }
            }
        }
        // Screenshot hook: switch the mode a few seconds after launch, the way a tap in Appearance would.
        .task {
            if let raw = ProcessInfo.processInfo.environment["KARTEI_TEST_SWITCH_MODE"], let mode = ThemeMode(rawValue: raw) {
                try? await Task.sleep(for: .seconds(4))
                ThemeStore.shared.mode = mode
            }
        }
        #endif
        .onChange(of: session == nil) { _, idle in SyncController.shared.pausedForReview = !idle }
    }

    /// Debug builds can open on a tab for screenshots: KARTEI_TEST_TAB=Settings.
    private static var startTab: Tab {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["KARTEI_TEST_TAB"], let t = Tab(rawValue: name) { return t }
        #endif
        return .decks
    }

    private func applyDefaults(_ backend: Backend) {
        guard prefs.onboarded else { return }
        Task.detached(priority: .utility) { FirstRunDefaults.enableFsrsOnce(backend) }
    }

    private func study(_ row: DeckRow) {
        guard let backend = store.backend else { return }
        studyLanguage = store.language(of: row.id)
        session = ReviewSession(backend: backend, deckID: row.id, deckName: row.name, exams: store.examDates)
    }

    /// iOS: the tab bar floats as glass and the screens scroll under it. macOS: the flat bar under the content.
    @ViewBuilder private func tabs<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if GlassLook.on {
            content().safeAreaInset(edge: .bottom, spacing: 0) {
                glassTabBar.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4).scrollFade(above: 20)
            }
        } else {
            VStack(spacing: 0) { content(); tabBar }
        }
    }

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue).font(Type.body(13, tab == t ? 700 : 500)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(tab == t ? Ink.text : Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background { if tab == t { Capsule().fill(Ink.text.opacity(0.1)) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? [.isSelected] : [])
            }
        }
        .padding(6)
        .glass(in: Capsule())
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue).font(Type.body(13, tab == t ? 700 : 500))
                        .foregroundStyle(tab == t ? Ink.text : Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .top) { Rectangle().fill(tab == t ? Ink.text : .clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }
}
