// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct ReviewView: View {
    let session: ReviewSession
    let mediaFolder: URL?
    var secondsPerCard: Double = 8
    /// The guided first session: one tip per card above the card (FirstSessionCoach).
    var coach = false
    /// BCP 47 language of this deck's cards (DeckStore.language), for VoiceOver.
    var language: String?
    let close: () -> Void
    @State private var actions = false
    @Environment(StudyPrefs.self) private var prefs
    @FocusState private var typing: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Swipe to grade (Touch.swift): the card follows the finger over a strip that names the grade.
    private var touch = TouchPrefs.shared
    @State private var drag: CGSize = .zero
    @State private var cardSize: CGSize = .zero
    @State private var pastPoint = false
    /// Height of the controls that float over the card on iOS; the card keeps this much room free at its end.
    @State private var floatHeight: CGFloat = 0
    private var reading = ReadingPrefs.shared


    var body: some View {
        VStack(spacing: 0) {
            nav
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.control)
                    Capsule().fill(Ink.text).frame(width: geo.size.width * session.progress)
                }
            }
            .frame(height: 4).padding(.horizontal, 20)
            .accessibilityLabel("\(session.answered) answered, \(session.remaining) left")
            switch session.phase {
            case .done: done
            case .failed(let why): message("Something went wrong.", why)
            default: card
            }
        }
        .frame(maxWidth: Self.readingWidth).frame(maxWidth: .infinity)
        .background(Ink.bg)
        .overlay { if actions { actionSheet } }
        .task {
            session.attach(audio: CardAudioPlayer(mediaFolder: mediaFolder))
            session.start()
        }
        .onDisappear { session.stopAudio() }
    }

    /// A card in a wide Mac window keeps lines a person can read; phones and tablets use their width.
    private static var readingWidth: CGFloat {
        #if os(macOS)
        820
        #else
        .infinity
        #endif
    }

    private var nav: some View {
        HStack(spacing: 8) {
            NavCircleButton(symbol: "chevron.left", label: "Back to decks", action: close)
                .keyboardShortcut(actions ? nil : .cancelAction)
            Text(session.deckName).font(Type.body(17, 500)).foregroundStyle(Ink.text).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            NavCircleButton(symbol: "arrow.uturn.backward", label: "Undo last answer", enabled: session.canUndo, action: session.undo)
                .keyboardShortcut("z", modifiers: .command)
            NavCircleButton(symbol: "ellipsis", label: "Card actions", enabled: hasCard) { actions = true }
                .keyboardShortcut(typingField ? nil : KeyboardShortcut(".", modifiers: []))
                .background { ankiShortcuts }
        }
        .padding(.horizontal, 14).padding(.bottom, 8).frame(minHeight: 44)
    }

    /// The card, with the grading controls under it. On iOS the controls float over the end of the card as glass:
    /// a short card ends above them, a long one scrolls underneath and fades out behind them.
    private var card: some View {
        VStack(spacing: 0) {
            if prefs.detail == .simple { simpleTop } else { fullTop }
            if coach, let line = FirstSessionCoach.line(index: session.answered, answerShown: isAnswer, typed: session.typeAnswer != nil) {
                Text(line).font(Type.body(15)).foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .accessibilityLabel("Tip: \(line)")
            }
            // While typing, the keyboard already takes the lower half; floating the field over the card would hide the question.
            if floating {
                swipeStage
                    .padding(.top, 24)
                    .overlay(alignment: .bottom) {
                        controls
                            .scrollFade()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { floatHeight = $0 }
                    }
            } else {
                swipeStage.padding(.top, 24)
                controls
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .onChange(of: session.answered) { old, new in
            // The hint shows for the first few answers, however they were given.
            if new > old && touch.showHint { touch.hintsShown += 1 }
        }
        .onChange(of: isAnswer) { _, shown in if shown { announceAnswer() } }
    }

    /// Everything under the card: hint, audio, typing field, exam note, then Show answer or the grades.
    private var controls: some View {
        VStack(spacing: 0) {
            if isAnswer && touch.showHint && !isLoading { swipeHint }
            if !session.replayTags.isEmpty && !isLoading { audioRow }
            if typingField { typeField }
            if isAnswer, let note = session.examNote, !session.cappedRatings.isDisjoint(with: shownRatings) {
                Text(note).font(Type.body(13)).foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }
            if isAnswer {
                (prefs.detail == .simple ? AnyView(simpleBar) : AnyView(rateBar))
                    .opacity(drag == .zero ? 1 : 0.35)
            } else { showButton }
        }
    }

    /// VoiceOver: say that the answer is there, since the page changes without the focus moving.
    private func announceAnswer() {
        AccessibilityNotification.Announcement("Answer shown").post()
    }

    // MARK: swipe to grade

    /// The controls float over the card (iOS), except while typing.
    private var floating: Bool { GlassLook.on && !typingField }

    private var swipeEnabled: Bool {
        #if os(macOS)
        // A drag on the Mac selects text on the card; grading there is the keyboard's and the buttons' job.
        false
        #else
        isAnswer && touch.swipeToGrade && !isLoading && !session.revealing
        #endif
    }
    private var candidate: Rating? { SwipeGrade.candidate(drag, detail: prefs.detail, prefs: touch) }

    /// The card page, and under it the strip in the colour of the grade the drag points at.
    private var swipeStage: some View {
        ZStack {
            if let r = candidate, drag != .zero { underlay(r) }
            CardWebView(html: CardPage.html(question: session.questionHTML, answer: isAnswer ? session.answerHTML : nil, css: session.css,
                                            theme: .current(dark: colorScheme == .dark, lang: language)),
                        mediaFolder: mediaFolder, onMessage: session.play,
                        onPan: swipeEnabled ? handlePan : nil,
                        allowVertical: touch.vertical(prefs.detail),
                        onTap: tapReveals ? { session.showAnswer() } : nil,
                        bottomInset: floating ? floatHeight + 12 : 0)
                .background(Ink.bg)
                .overlay { if drag != .zero { RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.control, lineWidth: 1) } }
                .offset(drag)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 28), anchor: .bottom)
                .opacity(isLoading ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .background { GeometryReader { g in Color.clear.onAppear { cardSize = g.size }.onChange(of: g.size) { _, s in cardSize = s } } }
    }

    private var tapReveals: Bool { !isAnswer && touch.tapToReveal && !typingField && session.replayTags.isEmpty && !isLoading }

    private func underlay(_ r: Rating) -> some View {
        let progress = SwipeGrade.progress(drag, size: cardSize, rating: r)
        let (fill, ink): (Color, Color) = switch r {
        case .good: (Ink.accent, Ink.onAccent)
        case .forgot: (Ink.forgot, Ink.onForgot)
        case .easy, .hard: (Ink.surface2, Ink.text)
        }
        let alignment: Alignment = switch r {
        case .good: .leading
        case .forgot: .trailing
        case .easy: .bottom
        case .hard: .top
        }
        let lead = r == .forgot ? "back in" : "next in"
        return VStack(alignment: r == .forgot ? .trailing : r == .good ? .leading : .center, spacing: 2) {
            Text(SwipeGrade.label(r, detail: prefs.detail)).font(Type.display(22, heavy: true))
            Text("\(lead) \(session.intervals[r.rawValue])").font(Type.body(13)).monospacedDigit()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .background(fill.opacity(0.45 + 0.55 * progress))
        .accessibilityHidden(true)
    }

    private func handlePan(_ pan: CardPan) {
        switch pan {
        case .changed(let t):
            drag = t
            let r = SwipeGrade.candidate(t, detail: prefs.detail, prefs: touch)
            let past = r.map { SwipeGrade.progress(t, size: cardSize, rating: $0) >= 1 } ?? false
            if past != pastPoint {
                pastPoint = past
                if past { tick() }
            }
        case .ended(let t):
            pastPoint = false
            if let r = SwipeGrade.release(t, size: cardSize, detail: prefs.detail, prefs: touch) {
                fling(r)
            } else {
                withAnimation(.spring(duration: 0.3)) { drag = .zero }
            }
        case .cancelled:
            pastPoint = false
            withAnimation(.spring(duration: 0.3)) { drag = .zero }
        }
    }

    /// The card leaves in the swipe's direction, then the grade goes in and the next card loads in place.
    private func fling(_ r: Rating) {
        let far = max(cardSize.width, cardSize.height) * 1.3
        let out: CGSize = switch r {
        case .good: CGSize(width: far, height: drag.height)
        case .forgot: CGSize(width: -far, height: drag.height)
        case .easy: CGSize(width: drag.width, height: -far)
        case .hard: CGSize(width: drag.width, height: far)
        }
        withAnimation(.easeIn(duration: reduceMotion ? 0.01 : 0.18)) { drag = out }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.02 : 0.19)) {
            session.answer(r)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { drag = .zero }
        }
    }

    private func tick() {
        #if os(iOS)
        guard touch.haptics else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// For the first few answers: which way is which, and that the buttons still work.
    private var swipeHint: some View {
        #if os(macOS)
        keyHint
        #else
        touchHint
        #endif
    }

    /// The Mac's version of the hint: the two keys that carry a whole session.
    private var keyHint: some View {
        Text(prefs.detail == .simple ? "Keys: 1 Forgot, Space Got it. More under Help > Keyboard Shortcuts."
                                     : "Keys: 1 Forgot, 2 Hard, Space or 3 Good, 4 Easy.")
            .font(Type.body(13, 500)).foregroundStyle(Ink.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rule() }
    }

    private var touchHint: some View {
        HStack(spacing: 8) {
            Label("Forgot", systemImage: "chevron.left").labelStyle(.titleAndIcon).foregroundStyle(Ink.forgot)
            Text(Type.isLarge ? "or swipe" : "swipe the card, or use the buttons").foregroundStyle(Ink.muted).lineLimit(1).frame(maxWidth: .infinity)
            HStack(spacing: 4) { Text(prefs.detail == .simple ? "Got it" : "Good"); Image(systemName: "chevron.right") }.foregroundStyle(Ink.text)
        }
        .font(Type.body(13, 500))
        .padding(.top, 12)
        .overlay(alignment: .top) { Rule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Swipe the card left for Forgot or right for \(prefs.detail == .simple ? "Got it" : "Good"), or use the buttons")
    }

    /// Full: cards left and Anki's three queue counts above an accent rule. The counts carry one-word labels
    /// (Reading: Label colours), so which is which does not rest on colour and order alone.
    private var fullTop: some View {
        let layout = Type.isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(spacing: 0) {
            layout {
                HStack(spacing: 8) {
                    Text("\(session.remaining) left").font(Type.body(13)).foregroundStyle(Ink.muted)
                    flagMark
                }
                if !Type.isLarge { Spacer(minLength: 8) }
                HStack(spacing: reading.labelColours ? 6 : 12) {
                    queueCount(session.counts.new, "new", Ink.new, .new)
                    if reading.labelColours { Text("·").foregroundStyle(Ink.muted) }
                    queueCount(session.counts.learning, "learn", Ink.learning, .learning)
                    if reading.labelColours { Text("·").foregroundStyle(Ink.muted) }
                    queueCount(session.counts.review, "due", Ink.text, .review)
                }
                .font(Type.body(13))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(session.counts.new) new, \(session.counts.learning) learning, \(session.counts.review) to review")
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).padding(.vertical, 2)
            Rectangle().fill(Ink.accentRule).frame(height: 2)
        }
    }

    /// The card's flag: a flag shape in its colour, with its name when colours are labelled.
    @ViewBuilder private var flagMark: some View {
        if session.flag > 0 {
            FlagChip(flag: session.flag, named: reading.labelColours)
        }
    }

    /// Simple (answer-simple.html): where you are and the minutes left. No queue counts.
    private var simpleTop: some View {
        let total = session.answered + session.remaining
        let minutes = max(1, Int((Double(session.remaining) * secondsPerCard / 60).rounded()))
        let place = session.remaining == 0 ? "Done" : "\(min(session.answered + 1, total)) of \(total)"
        return HStack(spacing: 8) {
            Text(session.remaining > 0 && Type.isLarge ? "\(place) · about \(minutes) min left" : place)
                .font(Type.body(13)).foregroundStyle(Ink.muted)
                .accessibilityLabel("Card \(min(session.answered + 1, total)) of \(total), about \(minutes) minutes left")
            flagMark
            Spacer(minLength: 8)
            if session.remaining > 0 && !Type.isLarge {
                Text("about \(minutes) min left").font(Type.body(13)).foregroundStyle(Ink.muted).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 36)
    }

    /// Anki desktop's review shortcuts: Ctrl+1…7 toggles a flag, "-" buries, "@" suspends.
    private var ankiShortcuts: some View {
        ZStack {
            ForEach(1...7, id: \.self) { f in
                Button("") { session.setFlag(f) }.keyboardShortcut(KeyEquivalent(Character("\(f)")), modifiers: .control)
            }
            Button("") { actions = false; session.put(away: false) }.keyboardShortcut("-", modifiers: [])
            Button("") { actions = false; session.put(away: true) }.keyboardShortcut("@", modifiers: [])
            // Anki's replay key.
            Button("") { session.replay() }.keyboardShortcut("r", modifiers: [])
        }
        .opacity(0).frame(width: 0, height: 0).disabled(!hasCard || typingField).accessibilityHidden(true)
    }

    /// The question asks for a typed answer: plain-key shortcuts are off so they cannot eat the typing.
    private var typingField: Bool { session.isQuestion && session.typeAnswer != nil }

    private var shownRatings: Set<Rating> { prefs.detail == .simple ? [.forgot, .good] : Set(Rating.allCases) }

    /// Native field rather than an <input> in the page: VoiceOver/Dynamic Type for free, no JS round trip to read
    /// the value, and focus can switch the review shortcuts off while typing. Return shows the answer, as in Anki.
    /// Code cards ({{type:Output}}) ask for console output, which can run over several lines: the field grows,
    /// Return starts a new line, and Show answer (or ⌘↩) compares. Other cards keep the one-line field.
    private var multiLineTyping: Bool { session.typeAnswer?.field == "Output" }

    @ViewBuilder private var typeField: some View {
        Group {
            if multiLineTyping {
                TextField("", text: Bindable(session).typed, prompt: Text("Type the exact output").foregroundStyle(Ink.muted), axis: .vertical)
                    .lineLimit(1...8)
                    .font(Type.code(17)).padding(.vertical, 14)
            } else {
                TextField("", text: Bindable(session).typed, prompt: Text("Type the answer").foregroundStyle(Ink.muted))
                    .font(Type.body(20, 500))
                    .onSubmit { session.showAnswer() }
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(Ink.text)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .keyboardType(multiLineTyping ? .asciiCapable : .default)
        #endif
        .focused($typing)
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(Ink.surface)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(typing ? Ink.accent : Ink.control, lineWidth: typing ? 2 : 1))
        .padding(.top, 12)
        .accessibilityLabel(multiLineTyping ? "The program's output" : "Your answer")
        .accessibilityHint("Type it, then show the answer to compare")
        .onAppear { typing = true }
    }

    /// One replay row per side (mockups/screens/answer.html): plays the side's sound and speech in order.
    private var audioRow: some View {
        HStack {
            Button(action: session.toggleAudio) {
                HStack(spacing: 12) {
                    Image(systemName: session.audioPlaying ? "stop.fill" : "play.fill").font(Type.symbol(15))
                    Text(session.audioPlaying ? "Stop" : "Play audio").font(Type.body(15, 500))
                    if session.replayTags.count > 1 {
                        Text("\(session.replayTags.count) clips").font(Type.body(13)).foregroundStyle(Ink.muted)
                    }
                }
                .foregroundStyle(Ink.text).padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.control, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.audioPlaying ? "Stop audio" : "Play audio again")
            Spacer()
        }
        .padding(.top, 12)
    }

    private var hasCard: Bool { switch session.phase { case .question, .answer: true; default: false } }

    private var actionSheet: some View {
        ZStack(alignment: .bottom) {
            Ink.scrim.ignoresSafeArea().onTapGesture { actions = false }
                .accessibilityAddTraits(.isButton).accessibilityLabel("Close card actions")
            Button("") { actions = false }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Flag").font(Type.body(13, 500)).foregroundStyle(Ink.muted).frame(minHeight: 24)
                FlagPicker(flag: session.flag) { session.setFlag($0) }
                    .padding(.vertical, 8)
                Rectangle().fill(Ink.rule).frame(height: 1).padding(.top, 6)
                actionRow("moon", "Bury until tomorrow") { actions = false; session.put(away: false) }
                actionRow("pause", "Suspend card", detail: "until you bring it back") { actions = false; session.put(away: true) }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
            .background(Ink.bg)
            .overlay(alignment: .top) { Rectangle().fill(Ink.accentRule).frame(height: 2) }
        }
    }

    private func actionRow(_ icon: String, _ label: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(Type.symbol(16)).frame(width: Type.scaled(20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(Type.body(16, 500))
                        if let detail { Text(detail).font(Type.body(13)).foregroundStyle(Ink.muted) }
                    }
                    Spacer()
                }
                .foregroundStyle(Ink.text).padding(.vertical, 6).frame(minHeight: 48).contentShape(Rectangle())
                Rectangle().fill(Ink.rule).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var isAnswer: Bool { if case .answer = session.phase { true } else { false } }
    private var isLoading: Bool { if case .loading = session.phase { true } else { false } }

    private func queueCount(_ n: Int, _ word: String, _ colour: Color, _ queue: Anki_Scheduler_QueuedCards.Queue) -> some View {
        HStack(spacing: 4) {
            Text("\(n)").font(Type.body(13, 700)).monospacedDigit().foregroundStyle(colour)
            if reading.labelColours { Text(word).foregroundStyle(Ink.muted) }
        }
        .padding(.bottom, 1)
        .overlay(alignment: .bottom) { if session.activeQueue == queue { Rectangle().fill(colour).frame(height: 2).offset(y: 2) } }
    }

    private var showButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(typingField ? (multiLineTyping ? "Type it exactly as it would print, then look." : "Type it, then look.") : "Try to say it before you look.").font(Type.body(13)).foregroundStyle(Ink.muted)
            Button(action: session.showAnswer) { PrimaryLabel(title: "Show answer") }
                .buttonStyle(.plain).keyboardShortcut(typingField ? KeyboardShortcut(.return, modifiers: .command) : KeyboardShortcut(.space, modifiers: [])).disabled(isLoading)
        }
        .padding(.top, 12)
    }

    /// Full: four grades. iOS: one glass bar with flat segments, Good the only filled one, Forgot in the fail colour.
    /// macOS: the flat bar, Forgot set apart in the fail colour and Good in the accent. At large text sizes four labels
    /// no longer fit in a row, so the grades form a 2 × 2 grid with Forgot top left.
    private var rateBar: some View {
        let cells: [GradeCell] = [
            GradeCell(.forgot, "Forgot", "1"), GradeCell(.hard, "Hard", "2"), GradeCell(.good, "Good", "3"), GradeCell(.easy, "Easy", "4"),
        ]
        return Group {
            if Type.isLarge {
                Grid(horizontalSpacing: GlassLook.on ? 2 : 6, verticalSpacing: GlassLook.on ? 2 : 6) {
                    GridRow { grade(cells[0]); grade(cells[1]) }
                    GridRow { grade(cells[2]); grade(cells[3]) }
                }
            } else {
                HStack(spacing: GlassLook.on ? 2 : 6) {
                    grade(cells[0])
                    if !GlassLook.on { Rectangle().fill(Ink.control).frame(width: 1).padding(.vertical, 6).padding(.horizontal, 3) }
                    grade(cells[1]); grade(cells[2]); grade(cells[3])
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(GradeBarSurface(grid: Type.isLarge))
        .padding(.top, 12)
    }

    /// Simple mode (mockups/screens/answer-simple.html): Forgot and Got it, one to two.
    /// Got it sends Good; the keys stay Anki's 1 and 3, and space also means Got it.
    private var simpleBar: some View {
        HStack(spacing: GlassLook.on ? 2 : 6) {
            grade(GradeCell(.forgot, "Forgot", "1", lead: "back in", big: true))
                .containerRelativeFrame(.horizontal) { w, _ in max(0, (w - 40) / 3) }
            if !GlassLook.on { Rectangle().fill(Ink.control).frame(width: 1).padding(.vertical, 6).padding(.horizontal, 3) }
            grade(GradeCell(.good, "Got it", "3", lead: "next in", big: true))
                .background { Button("") { session.answer(.good) }.keyboardShortcut(.space, modifiers: []).opacity(0).accessibilityHidden(true) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(GradeBarSurface(grid: false))
        .padding(.top, 12)
    }

    /// One grade button. `lead` is spelled out in Simple mode ("next in 10 min") and dropped when text is large.
    private func grade(_ cell: GradeCell) -> some View {
        let interval = session.intervals[cell.rating.rawValue]
        let lead = cell.lead ?? "next in"
        let look = GradeLook(cell.rating)
        return Button { session.answer(cell.rating) } label: {
            VStack(spacing: 2) {
                Text(cell.label).font(cell.big ? Type.display(20, heavy: true) : Type.body(16, 700)).foregroundStyle(look.label)
                Text(cell.lead != nil && !Type.isLarge ? "\(lead) \(interval)" : interval).font(Type.body(13)).monospacedDigit().foregroundStyle(look.detail)
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 4).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: cell.big ? 58 : 52, maxHeight: .infinity)
            .modifier(GradeCellSurface(look: look, grid: Type.isLarge))
        }
        .buttonStyle(.plain).keyboardShortcut(cell.key, modifiers: [])
        .accessibilityLabel("\(cell.label), \(lead) \(interval)\(session.cappedRatings.contains(cell.rating) ? ", shortened for the exam" : "")")
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Done ").font(Type.display(34, heavy: true)) + Text("for today.").font(Type.display(34, heavy: false)))
                .foregroundStyle(Ink.display).padding(.top, 24)
            if session.answered > 0 {
                Text("\(session.answered) cards in \(session.minutesSpent) min.").font(Type.display(34, heavy: false)).foregroundStyle(Ink.text)
                fact("Remembered", "\(session.remembered) of \(session.answered)").padding(.top, 24)
                fact("Forgot", "\(session.answered - session.remembered)")
            } else {
                Text("Nothing is due in this deck right now.").font(Type.body(15)).foregroundStyle(Ink.muted).padding(.top, 12)
            }
            Spacer()
            Button(action: close) { PrimaryLabel(title: "Back to decks") }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fact(_ name: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack { Text(name).font(Type.body(15)); Spacer(); Text(value).font(Type.body(15, 700)).monospacedDigit() }
                .foregroundStyle(Ink.text).frame(minHeight: 44)
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Type.display(22, heavy: false)).foregroundStyle(Ink.text)
            Text(detail).font(Type.body(13)).foregroundStyle(Ink.muted)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// One short tip per card in the first session, from the research notes: retrieve before looking (F1), Forgot is the
/// only fail (F3), feedback after a miss and why intervals grow (F10). Typed code cards get their own tip.
enum FirstSessionCoach {
    static let question = [
        "Say the answer to yourself before you look. Trying first is what makes it stick.",
        "Not sure? Guess anyway. A wrong try followed by the answer still helps you remember.",
        "Pictures count too: name what is hidden before you look.",
        "A short answer is enough. You only need the key idea.",
        "Last one of the five.",
    ]
    static let answer = [
        "Grade honestly: Got it only if you recalled it before looking.",
        "Forgot is the only fail. It brings the card back soon, which is what you want.",
        "Each card you get right comes back later: tomorrow, then in a few days, then weeks.",
        "Cards you know well spread out on their own, so there is no need to drill them now.",
        "That's it. From tomorrow, Bergmönch shows you what is due, a few minutes a day.",
    ]

    static func line(index: Int, answerShown: Bool, typed: Bool) -> String? {
        guard (0..<5).contains(index) else { return nil }
        if typed {
            return answerShown ? "Compare line by line. Got it only if your output matched."
                               : "Type the exact output, line by line. Return starts a new line."
        }
        return answerShown ? answer[index] : question[index]
    }
}
