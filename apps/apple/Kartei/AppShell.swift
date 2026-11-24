// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import UniformTypeIdentifiers

enum Tab: String, CaseIterable {
    case decks = "Decks", browse = "Browse", stats = "Stats", settings = "Settings"

    /// The Mac has no Settings tab: settings are a window of their own, under Command-comma.
    static var shown: [Tab] {
        #if os(macOS)
        [.decks, .browse, .stats]
        #else
        allCases
        #endif
    }
}

/// Top-level navigation: onboarding on first run, otherwise the four tabs, and the review screen over everything.
struct AppShell: View {
    @Bindable var store: DeckStore
    let prefs: StudyPrefs
    @Bindable var router: Router
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
                        switch router.tab {
                        case .decks: HomeView(store: store, study: study).frame(maxWidth: Self.pageWidth).frame(maxWidth: .infinity)
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
        // A guided first session that was cut short leaves its filtered deck behind; send its cards home.
        .onChange(of: CourseCatalogue.leftoverFirstSessions(store.rows), initial: true) { _, leftover in
            guard !leftover.isEmpty, session == nil, firstSessionDeck == nil, let backend = store.backend else { return }
            Task.detached {
                for deck in leftover { CourseCatalogue.removeFirstSession(deck, backend: backend) }
                await MainActor.run { store.refresh() }
            }
        }
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
        .onChange(of: session != nil || (prefs.loaded && !prefs.onboarded), initial: true) { _, busy in router.busy = busy }
        // A deck opened from the Finder or Files ("Open with"), or dropped on the window.
        .onOpenURL { open($0) }
        .onChange(of: store.backend == nil) { _, missing in
            if !missing { router.pendingPackages.forEach(store.importPackage); router.pendingPackages = [] }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            let packages = urls.filter { $0.pathExtension.lowercased() == "apkg" }
            packages.forEach(open)
            return !packages.isEmpty
        }
        .fileImporter(isPresented: $router.importing, allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data]) { result in
            if case .success(let url) = result { open(url) }
        }
        .toolbar {
            if session == nil && prefs.loaded && prefs.onboarded {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $router.tab) {
                        ForEach(Tab.shown, id: \.self) { Text($0 == .stats ? "Statistics" : $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .help("Switch between your decks, the card browser and the statistics")
                }
            }
        }
        #endif
    }

    /// Home keeps a readable column in a wide window; the phone uses its whole width.
    private static var pageWidth: CGFloat {
        #if os(macOS)
        720
        #else
        .infinity
        #endif
    }

    private func open(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "apkg" else { return }
        router.tab = .decks
        if store.backend == nil { router.pendingPackages.append(url) } else { store.importPackage(url) }
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
        #if os(macOS)
        // The Mac switches screens in the window toolbar and from the View menu.
        content()
        #else
        if GlassLook.on {
            content().safeAreaInset(edge: .bottom, spacing: 0) {
                glassTabBar.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4).scrollFade(above: 20)
            }
        } else {
            VStack(spacing: 0) { content(); tabBar }
        }
        #endif
    }

    private var glassTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.shown, id: \.self) { t in
                Button { router.tab = t } label: {
                    Text(t.rawValue).font(Type.body(13, router.tab == t ? 700 : 500)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(router.tab == t ? Ink.text : Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background { if router.tab == t { Capsule().fill(Ink.text.opacity(0.1)) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(router.tab == t ? [.isSelected] : [])
            }
        }
        .padding(6)
        .glass(in: Capsule())
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.shown, id: \.self) { t in
                Button { router.tab = t } label: {
                    Text(t.rawValue).font(Type.body(13, router.tab == t ? 700 : 500))
                        .foregroundStyle(router.tab == t ? Ink.text : Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .top) { Rectangle().fill(router.tab == t ? Ink.text : .clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(router.tab == t ? .isSelected : [])
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }
}
