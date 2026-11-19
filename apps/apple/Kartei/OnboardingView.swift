// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import UniformTypeIdentifiers

/// First run (import.html): one honest note on why intervals grow, which course decks to bring in (or your own
/// Anki deck), Simple or Full, new cards a day with what they cost, then five hand-picked cards with a coach line
/// each. Skippable at every step.
struct OnboardingView: View {
    let store: DeckStore
    let prefs: StudyPrefs
    /// Opens the review screen on the first-session deck (a filtered deck, see CourseCatalogue.makeFirstSession).
    var startFirstSession: (Int64) -> Void = { _ in }

    enum Step { case welcome, setup }
    @State var step: Step = .welcome
    @State private var picking = false
    @State private var newPerDay = Int(PaceDefaults.newPerDay)
    @State private var cards = 0
    @State private var newCards = 0
    @State private var finishing = false
    @State private var chosen: Set<String> = []
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenNav(title: step == .welcome ? "Welcome" : "Set up", back: step == .setup ? { step = .welcome } : nil) {
                Button("Skip") { finish() }
                    .buttonStyle(.plain).font(Type.body(15, 500)).foregroundStyle(Ink.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Starts without cards and with Bergmönch's defaults. Courses can be added from the Decks tab.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .welcome: welcome
                    case .setup: setup
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
                .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }
            footer.padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 560)
        }
        .background(Ink.bg)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.packageTypes) { result in
            if case .success(let url) = result { importOwn(url) }
        }
        .task(id: store.rows.map(\.id)) { countCards() }
    }

    static var packageTypes: [UTType] {
        [UTType(filenameExtension: "apkg"), UTType(filenameExtension: "colpkg")].compactMap { $0 } + [.data]
    }

    // MARK: steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Bergmönch ").font(Type.display(34, heavy: true)) + Text("runs on Anki's own scheduler.").font(Type.display(34, heavy: false)))
                .foregroundStyle(Ink.display).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text("A card you know comes back later each time: tomorrow, in 3 days, in 8, in 3 weeks. Recalling it just before it fades is what makes it last, and trying to recall before you look counts more than reading it again.")
                .font(Type.body(15)).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            Caption("Which course are you taking?").padding(.top, 24).padding(.bottom, 4)
            ForEach(CourseCatalogue.all) { course in
                CheckRow(title: course.title, detail: course.detail, checked: chosen.contains(course.id)) { toggle(course) }
            }
            Meta("Tick one or more. The cards follow the lectures. You can add the others later from the Decks tab.").padding(.top, 8)
            Caption("Your own cards").padding(.top, 24).padding(.bottom, 4)
            ListLine(title: "Import an Anki deck", detail: "An .apkg file exported from Anki, with its review history if it has one.") {
                picking = true
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            (deckCount == 0
                ? Text("No cards yet. ").font(Type.display(34, heavy: true))
                    + Text("Add a course or an Anki deck from the Decks tab.").font(Type.display(34, heavy: false))
                : Text("\(deckCount) deck\(deckCount == 1 ? "" : "s") ").font(Type.display(34, heavy: true))
                    + Text("ready to study.").font(Type.display(34, heavy: false)))
                .foregroundStyle(Ink.display).padding(.top, 8).accessibilityAddTraits(.isHeader)
            if let msg = store.importMessage { Meta(msg).padding(.top, 8) }
            VStack(spacing: 0) {
                FactRow(label: "Cards", value: grouped(cards))
                FactRow(label: "Not seen yet", value: grouped(newCards))
            }
            .padding(.top, 12)

            Caption("How much do you want to see?").padding(.top, 24).padding(.bottom, 4)
            OptionRow(title: DetailCopy.simpleTitle, detail: DetailCopy.simple, selected: prefs.detail == .simple) { prefs.setDetail(.simple) }
            OptionRow(title: DetailCopy.fullTitle, detail: DetailCopy.full, selected: prefs.detail == .full) { prefs.setDetail(.full) }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New cards a day").font(Type.body(15, 700)).foregroundStyle(Ink.text)
                    Meta(newCardsText)
                }
                Spacer()
                CountStepper(label: "New cards a day", value: $newPerDay, range: 0...100)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rule() }
            Meta("New cards are what build a backlog, so Bergmönch starts at 10. FSRS, the scheduler, is switched on. Both can be changed under Settings, Pace.")
                .padding(.top, 12)
        }
    }

    private var chosenCourses: [Course] { CourseCatalogue.all.filter { chosen.contains($0.id) } }
    private var firstCourse: Course? { CourseCatalogue.firstSessionCourse(chosenCourses) }

    private func toggle(_ course: Course) {
        if chosen.contains(course.id) { chosen.remove(course.id) } else { chosen.insert(course.id) }
    }

    /// Decks you can study on their own (a parent deck only groups its lectures).
    private var deckCount: Int { store.rows.filter { !$0.hasChildren && !$0.filtered }.count }

    private var steadyReviews: Int { Workload.steadyReviews(newPerDay: newPerDay) }
    private var steadyMinutes: Int { Workload.minutes(reviews: Double(steadyReviews), secondsPerCard: store.secondsPerCard) }

    private var newCardsText: String {
        newPerDay == 0 ? "Only reviews, no new cards." : "Settles at about \(steadyReviews) reviews a day, about \(steadyMinutes) min."
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .welcome:
            if importing {
                WideButton(title: store.importMessage ?? "Importing", detail: nil) {}.disabled(true)
            } else if chosen.isEmpty {
                WideButton(title: "Continue without a course", detail: nil, quiet: true) { step = .setup }
            } else {
                WideButton(title: chosen.count == 1 ? "Add this course" : "Add \(chosen.count) courses", detail: nil) { addCourses() }
            }
        case .setup:
            if firstCourse != nil && cards > 0 {
                WideButton(title: "Start with five cards", detail: newPerDay == 0 ? nil : "then \(newPerDay) a day") { finish(firstSession: true) }
                    .disabled(finishing)
                    .accessibilityHint("Five hand-picked cards from the first lecture, with a tip for each. After that about \(steadyMinutes) minutes a day")
            } else {
                WideButton(title: newPerDay == 0 ? "Start with reviews only" : "Start with \(newPerDay) new a day",
                           detail: newPerDay == 0 ? nil : "\(steadyMinutes) min") { finish() }
                    .disabled(finishing)
                    .accessibilityHint("About \(steadyMinutes) minutes a day once it settles")
            }
        }
    }

    // MARK: actions

    private func countCards() {
        guard let backend = store.backend else { return }
        Task.detached {
            var req = Anki_Search_SearchRequest()
            req.search = "deck:*"
            let n = ((try? backend.call(SearchMethods.searchCards, req) as Anki_Search_SearchResponse)?.ids.count) ?? 0
            req.search = "deck:* is:new"
            let fresh = ((try? backend.call(SearchMethods.searchCards, req) as Anki_Search_SearchResponse)?.ids.count) ?? 0
            await MainActor.run { cards = n; newCards = fresh }
        }
    }

    private func addCourses() {
        importing = true
        store.importCourses(chosenCourses) { _ in
            importing = false
            step = .setup
        }
    }

    /// The person's own package, after any courses they ticked.
    private func importOwn(_ url: URL) {
        step = .setup
        store.importCourses(chosenCourses) { _ in store.importPackage(url) }
    }

    private func finish(firstSession: Bool = false) {
        finishing = true
        let n = UInt32(newPerDay)
        let course = firstSession ? firstCourse : nil
        if let backend = store.backend {
            Task.detached {
                try? PaceStore.applyStartDefaults(backend, newPerDay: n)
                let deck = course.flatMap { try? CourseCatalogue.makeFirstSession($0, backend: backend) }
                await MainActor.run {
                    store.refresh()
                    prefs.finishOnboarding()
                    if let deck { startFirstSession(deck) }
                }
            }
        } else {
            prefs.finishOnboarding()
        }
    }
}

enum Onboarding {
    /// Remove sample decks, but only while nothing has been reviewed: a collection with history is never touched.
    static func removeSamples(_ backend: Backend, decks: [Int64]) throws {
        guard !decks.isEmpty, (try DB.query(backend, "select count() from revlog", []).first?.first ?? 1) == 0 else { return }
        var req = Anki_Decks_DeckIds()
        req.dids = decks
        let _: Anki_Collection_OpChangesWithCount = try backend.call(DecksMethods.removeDecks, req)
    }
}
