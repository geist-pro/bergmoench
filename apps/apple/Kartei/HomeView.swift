// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let store: DeckStore
    let study: (DeckRow) -> Void
    @State private var importing = false
    @State private var deleting: DeckRow?
    @State private var swipedOpen: Int64?
    @State private var examDeck: DeckRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Type.body(13)).foregroundStyle(Ink.muted)
                Spacer(minLength: 8)
                SyncStatusLine(store: store).padding(.trailing, 12)
                // Course decks shipped with the app, or the person's own Anki package.
                Menu {
                    Section("Course decks") {
                        ForEach(CourseCatalogue.all) { course in
                            Button(course.title) { store.importCourses([course]) }
                        }
                    }
                    Button("Import an Anki deck…") { importing = true }
                } label: {
                    Text("Add cards").font(Type.body(15, 500)).foregroundStyle(Ink.text).underline()
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).fixedSize()
                .accessibilityHint("Add a course deck or import an Anki deck")
            }
            .frame(minHeight: 44)
            if let msg = store.importMessage {
                Text(msg).font(Type.body(13)).foregroundStyle(Ink.muted).padding(.bottom, 4)
            }
            switch store.phase {
            case .loading(let what):
                Spacer()
                Text(what).font(Type.display(22, heavy: false)).foregroundStyle(Ink.text)
                Spacer()
            case .failed(let why):
                Spacer()
                Text("The collection could not be opened.").font(Type.display(22, heavy: false)).foregroundStyle(Ink.text)
                Text(why).font(Type.body(13)).foregroundStyle(Ink.muted).padding(.top, 8)
                Spacer()
            case .ready:
                // One scroll for the whole page, so it still works at large text sizes. Study now stays in reach:
                // it floats over the end of the list, and the list scrolls under it.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        table
                    }
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let first = store.rows.firstToStudy, store.cardsToday > 0 {
                        Button { study(first) } label: { PrimaryLabel(title: "Study now", detail: "\(store.cardsToday) cards") }
                            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                            .padding(.top, 8).padding(.bottom, 8)
                            .scrollFade()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.bg)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data]) { result in
            if case .success(let url) = result { store.importPackage(url) }
        }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { row in
            Button("Delete deck", role: .destructive) { store.deleteDeck(row); swipedOpen = nil }
            Button("Cancel", role: .cancel) { swipedOpen = nil }
        } message: { row in
            Text(row.hasChildren ? "Its subdecks, cards and review history are deleted from this device. This can't be undone."
                                 : "Its cards and review history are deleted from this device. This can't be undone.")
        }
        .sheet(item: $examDeck) { deck in
            ExamSheet(deck: deck, initial: store.examDates[deck.id]) { date in
                store.setExam(date, for: deck.id)
                examDeck = nil
            } cancel: { examDeck = nil }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(store.minutesToday)").font(Type.display(96, heavy: true)).tracking(-3).lineLimit(1).fixedSize()
                    Text("min").font(Type.display(50, heavy: false)).tracking(-1).lineLimit(1).fixedSize()
                }
                .foregroundStyle(Ink.display)
                Spacer(minLength: 12)
                // At large text sizes the calendar gives its room to the words; Stats still has the history.
                if !Type.isLarge { StudyCalendar(studied: store.studiedDays).padding(.bottom, 10) }
            }
            .padding(.top, 12)
            Text("today, about \(store.cardsToday) cards across \(store.topLevelDecks) \(store.topLevelDecks == 1 ? "deck" : "decks"). \(store.totals.new) of them are new.")
                .font(Type.body(14)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            retentionLine.padding(.top, 10)
        }
        .padding(.bottom, 16)
    }

    private var retentionLine: some View {
        let layout = Type.isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(spacing: 0) {
            layout {
                Text("Remembered, last 30 days").font(Type.body(15)).foregroundStyle(Ink.text)
                if !Type.isLarge { Spacer() }
                HStack(alignment: .firstTextBaseline) {
                    if let r = store.retention {
                        Text("\(Int((r * 100).rounded()))%").font(Type.body(15, 700)).monospacedDigit().foregroundStyle(Ink.text)
                        Text("target \(Int((store.retentionTarget * 100).rounded()))%").font(Type.body(15)).foregroundStyle(Ink.muted)
                    } else {
                        Text("shown after 20 reviews").font(Type.body(15)).foregroundStyle(Ink.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4)
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var table: some View {
        VStack(spacing: 0) {
            // The stacked rows at large text sizes label their own counts, so the column heads go.
            if !Type.isLarge {
                HStack(spacing: 6) {
                    Text("Deck").frame(maxWidth: .infinity, alignment: .leading)
                    Text("New").frame(width: DeckRowView.countWidth, alignment: .trailing)
                    Text("Learn").frame(width: DeckRowView.countWidth, alignment: .trailing)
                    Text("Due").frame(width: DeckRowView.countWidth, alignment: .trailing)
                }
                .font(Type.body(13, 500)).foregroundStyle(Ink.muted).lineLimit(1)
                .frame(minHeight: 32)
                .accessibilityHidden(true)
            }
            Rectangle().fill(Ink.accentRule).frame(height: 2)
            Group {
                LazyVStack(spacing: 0) {
                    ForEach(store.rows) { row in
                        // A tap gesture, not a Button: a Button takes the touch first, so a sideways drag would open the deck
                        // instead of swiping. The tap fails once the finger moves, which leaves the drag to SwipeToDelete.
                        SwipeToDelete(id: row.id, open: $swipedOpen, delete: { deleting = row }) {
                            DeckRowView(row: row, exam: store.examDates[row.id])
                                .contentShape(Rectangle())
                                .onTapGesture { study(row) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { study(row) }
                        .accessibilityHint("Study this deck")
                        .accessibilityAction(named: "Delete deck") { deleting = row }
                        .contextMenu {
                            Button(store.examDates[row.id] == nil ? "Set exam date…" : "Change exam date…") { examDeck = row }
                            if store.examDates[row.id] != nil {
                                Button("Remove exam date") { store.setExam(nil, for: row.id) }
                            }
                            Button("Delete deck…", role: .destructive) { deleting = row }
                        }
                        Rectangle().fill(Ink.rule).frame(height: 1)
                    }
                }
            }
        }
    }
}

/// "exam in 13 weeks", "exam in 9 days", "exam tomorrow", "exam today"; nothing once the date has passed.
func examCountdown(_ exam: Date?) -> String? {
    guard let exam else { return nil }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: exam)).day ?? -1
    switch days {
    case ..<0: return nil
    case 0: return "exam today"
    case 1: return "exam tomorrow"
    case 2..<14: return "exam in \(days) days"
    default: return "exam in \(days / 7) weeks"
    }
}

private struct DeckRowView: View {
    let row: DeckRow
    let exam: Date?

    /// Width of one count column; grows a little with text size.
    static var countWidth: CGFloat { Type.scaled(38) }

    var body: some View {
        Group {
            if Type.isLarge { stacked } else { columns }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name)\(examCountdown(exam).map { ", " + $0 } ?? ""): \(row.new) new, \(row.learning) learning, \(row.due) due")
    }

    private var name: some View {
        Text(row.name)
            .font(Type.body(row.depth == 0 ? 16 : 15, row.depth == 0 ? 500 : 400))
            .foregroundStyle(Ink.text)
            .lineLimit(Type.isLarge ? 3 : 2)
    }

    private var columns: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                name
                if let line = examCountdown(exam) {
                    Text(line).font(Type.body(13)).foregroundStyle(Ink.muted)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            count(row.new, Ink.new)
            count(row.learning, Ink.learning)
            count(row.due, Ink.text)
        }
        .padding(.vertical, 4)
        .frame(minHeight: row.depth == 0 ? 56 : 44)
    }

    /// Large text: the name, then one labelled line of counts (zero counts left out), then the exam line.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            name
            if row.new + row.learning + row.due > 0 {
                HStack(spacing: 6) {
                    if row.new > 0 { labelled(row.new, "new", Ink.new) }
                    if row.learning > 0 { labelled(row.learning, "learn", Ink.learning) }
                    if row.due > 0 { labelled(row.due, "due", Ink.text) }
                }
            } else {
                Text("nothing due").font(Type.body(13)).foregroundStyle(Ink.muted)
            }
            if let line = examCountdown(exam) { Text(line).font(Type.body(13)).foregroundStyle(Ink.muted) }
        }
        .padding(.leading, CGFloat(row.depth) * 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func labelled(_ n: Int, _ word: String, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(n)").font(Type.body(13, 700)).monospacedDigit().foregroundStyle(colour)
            Text(word).font(Type.body(13)).foregroundStyle(Ink.muted)
        }
        .lineLimit(1)
    }

    private func count(_ n: Int, _ colour: Color) -> some View {
        Text(n == 0 ? "–" : "\(n)")
            .font(Type.body(15, 500)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(n == 0 ? Ink.muted : colour)
            .frame(width: Self.countWidth, alignment: .trailing)
    }
}

/// Days studied over the last five weeks, Monday first, this week in the bottom row. No streak number: a missed day is just an empty square.
struct StudyCalendar: View {
    let studied: Set<Int>

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7  // Monday = 0
        let count = studied.filter { $0 > -35 }.count
        VStack(alignment: .trailing, spacing: 6) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                        Text(letter).font(Type.body(11, 500)).foregroundStyle(Ink.muted).frame(width: 16)
                    }
                }
                ForEach(0..<5, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { day in
                            let offset = (week - 4) * 7 + day - weekday
                            cell(offset)
                        }
                    }
                }
            }
            Text("\(count) \(count == 1 ? "day" : "days") in 5 weeks").font(Type.body(13)).foregroundStyle(Ink.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Studied on \(count) of the last 35 days")
    }

    @ViewBuilder private func cell(_ offset: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1)
        // Days not studied are outlined in the control colour so the grid reads as a calendar; days still to come
        // are dotted rather than faded.
        if offset > 0 {
            shape.strokeBorder(Ink.control, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 16, height: 16)
        } else if offset == 0 {
            shape.fill(studied.contains(0) ? Ink.text : .clear).overlay(shape.strokeBorder(Ink.accentRule, lineWidth: 2)).frame(width: 16, height: 16)
        } else if studied.contains(offset) {
            shape.fill(Ink.text).frame(width: 16, height: 16)
        } else {
            shape.strokeBorder(Ink.control, lineWidth: 1).frame(width: 16, height: 16)
        }
    }
}

private struct ExamSheet: View {
    let deck: DeckRow
    let save: (Date) -> Void
    let cancel: () -> Void
    @State private var date: Date

    init(deck: DeckRow, initial: Date?, save: @escaping (Date) -> Void, cancel: @escaping () -> Void) {
        self.deck = deck
        self.save = save
        self.cancel = cancel
        _date = State(initialValue: initial ?? Calendar.current.date(byAdding: .weekOfYear, value: 8, to: .now)!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exam date").font(Type.body(13)).foregroundStyle(Ink.muted)
            Text(deck.name).font(Type.display(28, heavy: true)).foregroundStyle(Ink.text)
            DatePicker("Exam date", selection: $date, in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden().tint(Ink.accent)
            if let line = examCountdown(date) { Text(line.prefix(1).uppercased() + line.dropFirst() + ".").font(Type.body(15)).foregroundStyle(Ink.text) }
            HStack {
                Button("Cancel", action: cancel).buttonStyle(.plain).font(Type.body(15, 500)).foregroundStyle(Ink.text).frame(minHeight: 44)
                Spacer()
                Button { save(date) } label: {
                    Text("Save").font(Type.display(18, heavy: true)).foregroundStyle(Ink.onAccent)
                        .padding(.horizontal, 24).frame(minHeight: 48).primarySurface()
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
        .background(Ink.bg)
    }
}

/// Swipe a row left to reveal Delete (a deck list is a plain stack, so List's swipeActions are not available).
/// Only one row is open at a time; a tap elsewhere on the row, or swiping back, closes it.
struct SwipeToDelete<Content: View>: View {
    let id: Int64
    @Binding var open: Int64?
    let delete: () -> Void
    @ViewBuilder let content: Content

    @State private var drag: CGFloat = 0
    private let width: CGFloat = 88

    private var offset: CGFloat { min(0, max(-width * 1.4, (open == id ? -width : 0) + drag)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(action: delete) {
                    Text("Delete").font(Type.body(15, 700)).foregroundStyle(Ink.onForgot)
                        .frame(width: max(width, -offset)).frame(maxHeight: .infinity)
                        .background(Ink.forgot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
            // The close-on-tap layer moves with the row (overlay before offset), so it never covers Delete.
            content
                .background(Ink.bg)
                .allowsHitTesting(open != id)
                .overlay { if open == id { Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(.snappy) { open = nil } } } }
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    drag = v.translation.width
                }
                .onEnded { v in
                    let total = (open == id ? -width : 0) + drag
                    withAnimation(.snappy) {
                        if total < -width * 1.3 { open = nil; drag = 0; delete(); return }
                        open = total < -width / 2 ? id : (open == id ? nil : open)
                        drag = 0
                    }
                }
        )
    }
}
