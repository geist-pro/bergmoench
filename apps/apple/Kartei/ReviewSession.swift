// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation
import Observation

enum Rating: Int, CaseIterable { case forgot = 0, hard, good, easy }

/// One study session on one deck. All scheduling comes from Anki's backend; this only asks for the next card and reports the answer.
@Observable
final class ReviewSession {
    enum Phase { case loading, question, answer, done, failed(String) }

    let deckName: String
    var phase: Phase = .loading
    var questionHTML = ""
    var answerHTML = ""
    var css = ""
    var intervals: [String] = ["", "", "", ""]
    var counts = (new: 0, learning: 0, review: 0)
    var activeQueue = Anki_Scheduler_QueuedCards.Queue.new
    var answered = 0
    var remembered = 0
    var canUndo = false
    /// Anki's flag on the current card: 0 none, 1 red … 7 purple.
    var flag = 0
    let started = Date()

    /// Set when the template asks for a typed answer ({{type:Field}}) and the field has text.
    var typeAnswer: TypeAnswer?
    /// What the learner typed on the question side.
    var typed = ""
    /// Which answers an exam date shortened, and the note that says so.
    var cappedRatings: Set<Rating> = []
    var examNote: String?
    /// [sound:] and TTS tags of each side, in order (Anki's question_av_tags / answer_av_tags).
    var questionAudio: [Anki_CardRendering_AVTag] = []
    var answerAudio: [Anki_CardRendering_AVTag] = []
    var audioPlaying = false
    /// Deck options: autoplay (Anki default on) and replaying question audio with the answer (Anki default on).
    var autoplay = true
    var replayQuestionOnAnswer = true

    var remaining: Int { counts.new + counts.learning + counts.review }
    var progress: Double { answered + remaining == 0 ? 1 : Double(answered) / Double(answered + remaining) }
    var minutesSpent: Int { max(1, Int((Date().timeIntervalSince(started) + 30) / 60)) }

    var isQuestion: Bool { if case .question = phase { true } else { false } }
    var isAnswer: Bool { if case .answer = phase { true } else { false } }
    /// The tags the replay button plays on the side being shown.
    var replayTags: [Anki_CardRendering_AVTag] {
        if isAnswer { return (replayQuestionOnAnswer ? questionAudio : []) + answerAudio }
        return isQuestion ? questionAudio : []
    }

    private let backend: Backend
    private let deckID: Int64
    private var current: Anki_Scheduler_QueuedCards.QueuedCard?
    /// The current card's answer states after exam capping; these are what gets sent.
    private var states = Anki_Scheduler_SchedulingStates()
    private var rawAnswer = ""
    private var expected: String?
    private(set) var revealing = false
    private var shownAt = Date()
    private let work = DispatchQueue(label: "app.kartei.review")
    private var deckNames: [Int64: String] = [:]
    private var deckOptions: [Int64: (autoplay: Bool, replayQuestion: Bool)] = [:]
    private var audio: CardAudioOutput?
    /// Stands in for "today" in tests.
    var now: () -> Date = { Date() }

    /// Exam dates per deck id, used to cap intervals before an exam (see core/ffi/src/exam.rs).
    let exams: [Int64: Date]

    init(backend: Backend, deckID: Int64, deckName: String, exams: [Int64: Date] = [:]) {
        self.exams = exams
        self.backend = backend
        self.deckID = deckID
        self.deckName = deckName
    }

    /// Give the session somewhere to play sound. Without one, cards are silent.
    func attach(audio: CardAudioOutput) {
        self.audio = audio
        audio.onPlayingChange = { [weak self] playing in self?.audioPlaying = playing }
    }

    func start() {
        perform {
            var deck = Anki_Decks_DeckId()
            deck.did = self.deckID
            let _: Anki_Collection_OpChanges = try self.backend.call(DecksMethods.setCurrentDeck, deck)
            if !self.exams.isEmpty {
                var req = Anki_Decks_GetDeckNamesRequest()
                req.skipEmptyDefault = false
                req.includeFiltered = true
                let names: Anki_Decks_DeckNames = try self.backend.call(DecksMethods.getDeckNames, req)
                let map = Dictionary(names.entries.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                DispatchQueue.main.sync { self.deckNames = map }
            }
        }
    }

    func showAnswer() {
        guard case .question = phase, !revealing else { return }
        stopAudio()
        guard let spec = typeAnswer, let expected else { reveal(TypeAnswer.answer(rawAnswer, comparison: nil)); return }
        revealing = true
        let typed = self.typed
        work.async {
            var req = Anki_CardRendering_CompareAnswerRequest()
            req.expected = expected
            req.provided = TypedText.forComparison(typed)
            req.combining = spec.combining
            req.ignoreCase = spec.ignoreCase
            let compared: Anki_Generic_String? = try? self.backend.call(CardRenderingMethods.compareAnswer, req)
            let diff = TypedDiff.html(compared: compared?.val ?? "<code id=typeans>\(TypedDiff.escape(expected))</code>", typed: typed)
            DispatchQueue.main.async {
                self.revealing = false
                self.reveal(TypeAnswer.answer(self.rawAnswer, comparison: diff))
            }
        }
    }

    private func reveal(_ html: String) {
        guard case .question = phase else { return }
        answerHTML = html
        phase = .answer
        if autoplay { audio?.play(answerAudio) }
    }

    func replay() { audio?.play(replayTags) }
    func stopAudio() { audio?.stop() }
    func toggleAudio() { audioPlaying ? stopAudio() : replay() }

    /// A replay button in the card page was pressed ("play:q:0").
    func play(_ message: String) {
        guard let (question, index) = CardText.playRequest(message) else { return }
        let tags = question ? questionAudio : answerAudio
        guard index < tags.count else { return }
        audio?.play([tags[index]])
    }

    func answer(_ rating: Rating) {
        guard case .answer = phase, let card = current else { return }
        let taken = UInt32(min(Date().timeIntervalSince(shownAt), 60) * 1000)
        let states = self.states
        stopAudio()
        phase = .loading
        perform {
            var answer = Anki_Scheduler_CardAnswer()
            answer.cardID = card.card.id
            answer.currentState = card.states.current
            switch rating {
            case .forgot: answer.newState = states.again; answer.rating = .again
            case .hard: answer.newState = states.hard; answer.rating = .hard
            case .good: answer.newState = states.good; answer.rating = .good
            case .easy: answer.newState = states.easy; answer.rating = .easy
            }
            answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
            answer.millisecondsTaken = taken
            let _: Anki_Collection_OpChanges = try self.backend.call(SchedulerMethods.answerCard, answer)
            DispatchQueue.main.sync {
                self.answered += 1
                if rating != .forgot { self.remembered += 1 }
                self.canUndo = true
            }
        }
    }

    /// Set or clear (same flag again) the current card's flag. Stays on the card in Anki too.
    func setFlag(_ value: Int) {
        guard let card = current else { return }
        let newFlag = flag == value ? 0 : value
        flag = newFlag
        work.async {
            var req = Anki_Cards_SetFlagRequest()
            req.cardIds = [card.card.id]
            req.flag = UInt32(newFlag)
            let _: Anki_Collection_OpChangesWithCount? = try? self.backend.call(CardsMethods.setFlag, req)
        }
    }

    /// Bury until tomorrow, or suspend until brought back in the browser. Either way the next card follows.
    func put(away suspend: Bool) {
        guard let card = current else { return }
        stopAudio()
        phase = .loading
        perform {
            var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
            req.cardIds = [card.card.id]
            req.mode = suspend ? .suspend : .buryUser
            let _: Anki_Collection_OpChangesWithCount = try self.backend.call(SchedulerMethods.buryOrSuspendCards, req)
            DispatchQueue.main.sync { self.canUndo = true }
        }
    }

    func undo() {
        guard canUndo else { return }
        stopAudio()
        perform {
            let _: Anki_Collection_OpChangesAfterUndo = try self.backend.call(CollectionMethods.undo)
            DispatchQueue.main.sync {
                self.answered = max(0, self.answered - 1)
                self.canUndo = false
            }
        }
    }

    /// Run a backend step off the main thread, then load whichever card is next.
    private func perform(_ step: @escaping () throws -> Void) {
        work.async {
            do {
                try step()
                try self.loadNext()
            } catch {
                DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Everything shown for one card, built off the main thread.
    private struct Prepared {
        var question = "", answer = "", css = ""
        var questionAudio: [Anki_CardRendering_AVTag] = [], answerAudio: [Anki_CardRendering_AVTag] = []
        var typeAnswer: TypeAnswer?, expected: String?
        var states = Anki_Scheduler_SchedulingStates()
        var capped: Set<Rating> = [], examNote: String?
        var labels: [String] = []
        var options = (autoplay: true, replayQuestion: true)
    }

    private func loadNext() throws {
        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = 1
        let queued: Anki_Scheduler_QueuedCards = try backend.call(SchedulerMethods.getQueuedCards, req)
        let counts = (Int(queued.newCount), Int(queued.learningCount), Int(queued.reviewCount))
        guard let next = queued.cards.first else {
            DispatchQueue.main.async { self.current = nil; self.counts = counts; self.phase = .done }
            return
        }
        let names = DispatchQueue.main.sync { deckNames }
        let p = try prepare(next, names: names)
        DispatchQueue.main.async {
            self.current = next
            self.counts = counts
            self.activeQueue = next.queue
            self.questionHTML = p.question
            self.rawAnswer = p.answer
            self.answerHTML = ""
            self.css = p.css
            self.questionAudio = p.questionAudio
            self.answerAudio = p.answerAudio
            self.typeAnswer = p.typeAnswer
            self.expected = p.expected
            self.typed = ""
            self.states = p.states
            self.cappedRatings = p.capped
            self.examNote = p.examNote
            self.autoplay = p.options.autoplay
            self.replayQuestionOnAnswer = p.options.replayQuestion
            self.flag = Int(next.card.flags & 0b111)
            self.intervals = p.labels.count == 4 ? p.labels : ["", "", "", ""]
            self.shownAt = Date()
            self.phase = .question
            if p.options.autoplay { self.audio?.play(p.questionAudio) }
        }
    }

    private func prepare(_ next: Anki_Scheduler_QueuedCards.QueuedCard, names: [Int64: String]) throws -> Prepared {
        var p = Prepared()
        var render = Anki_CardRendering_RenderExistingCardRequest()
        render.cardID = next.card.id
        render.partialRender = true
        let rendered: Anki_CardRendering_RenderCardResponse = try backend.call(CardRenderingMethods.renderExistingCard, render)
        p.css = rendered.css

        // Same order as pylib/anki/template.py: question first, its text becomes {{FrontSide}}.
        let q = try avTags(CardText.flatten(rendered.questionNodes, frontSide: nil), question: true)
        let a = try avTags(CardText.flatten(rendered.answerNodes, frontSide: q.text), question: false)
        p.questionAudio = q.avTags
        p.answerAudio = a.avTags
        p.answer = a.text
        p.question = q.text
        if let spec = TypeAnswer.find(in: q.text) {
            switch try expectedAnswer(spec, card: next.card) {
            case .text(let value):
                p.typeAnswer = spec; p.expected = value
                p.question = TypeAnswer.question(q.text)
            case .empty:
                p.question = TypeAnswer.question(q.text)
            case .problem(let warning):
                p.question = TypeAnswer.replace(q.text, with: "<p class=k-warn>\(warning)</p>")
            }
        }

        let home = next.card.originalDeckID != 0 ? next.card.originalDeckID : next.card.deckID
        p.options = options(home)
        p.states = next.states
        if let exam = ExamLookup.examDate(deck: home, names: names, exams: exams) {
            let capped = Backend.capStates(next.states, daysLeft: ExamLookup.daysLeft(until: exam, from: now()))
            p.capped = Set(Rating.allCases.filter { Self.state($0, capped) != Self.state($0, next.states) })
            p.states = capped
            if !p.capped.isEmpty { p.examNote = ExamLookup.note(exam) }
        }
        let labels: Anki_Generic_StringList = try backend.call(SchedulerMethods.describeNextStates, p.states)
        p.labels = labels.vals
        return p
    }

    static func state(_ r: Rating, _ s: Anki_Scheduler_SchedulingStates) -> Anki_Scheduler_SchedulingState {
        switch r { case .forgot: s.again; case .hard: s.hard; case .good: s.good; case .easy: s.easy }
    }

    private func avTags(_ text: String, question: Bool) throws -> Anki_CardRendering_ExtractAvTagsResponse {
        var req = Anki_CardRendering_ExtractAvTagsRequest()
        req.text = text
        req.questionSide = question
        return try backend.call(CardRenderingMethods.extractAvTags, req)
    }

    private enum Expected { case text(String), empty, problem(String) }

    /// The field the learner should type, narrowed to this card's cloze when the template says {{type:cloze:…}}.
    private func expectedAnswer(_ spec: TypeAnswer, card: Anki_Cards_Card) throws -> Expected {
        var nid = Anki_Notes_NoteId()
        nid.nid = card.noteID
        let note: Anki_Notes_Note = try backend.call(NotesMethods.getNote, nid)
        var ntid = Anki_Notetypes_NotetypeId()
        ntid.ntid = note.notetypeID
        let notetype: Anki_Notetypes_Notetype = try backend.call(NotetypesMethods.getNotetype, ntid)
        guard let index = notetype.fields.firstIndex(where: { $0.name == spec.field }), index < note.fields.count else {
            return spec.cloze ? .problem("This cloze has nothing to type. Check the note for empty cards.") : .problem("Type answer: unknown field \(TypedDiff.escape(spec.field))")
        }
        var value = note.fields[index]
        if spec.cloze {
            var req = Anki_CardRendering_ExtractClozeForTypingRequest()
            req.text = value
            req.ordinal = card.templateIdx + 1
            let cloze: Anki_Generic_String = try backend.call(CardRenderingMethods.extractClozeForTyping, req)
            value = cloze.val
        }
        return value.isEmpty ? .empty : .text(value)
    }

    /// Autoplay and question replay from the card's home deck options, read once per deck.
    private func options(_ deck: Int64) -> (autoplay: Bool, replayQuestion: Bool) {
        if let cached = deckOptions[deck] { return cached }
        var result = (autoplay: true, replayQuestion: true)
        var did = Anki_Decks_DeckId()
        did.did = deck
        if let d: Anki_Decks_Deck = try? backend.call(DecksMethods.getDeck, did), case .normal(let normal)? = d.kind {
            var dcid = Anki_DeckConfig_DeckConfigId()
            dcid.dcid = normal.configID
            if let conf: Anki_DeckConfig_DeckConfig = try? backend.call(DeckConfigMethods.getDeckConfig, dcid) {
                result = (!conf.config.disableAutoplay, !conf.config.skipQuestionWhenReplayingAnswer)
            }
        }
        deckOptions[deck] = result
        return result
    }
}

/// What the learner typed, made comparable with Anki's expected text: Anki turns line breaks in the expected
/// field into single spaces (rslib typeanswer.rs strip_expected), so typed lines are joined the same way, with
/// trailing spaces and empty lines dropped.
enum TypedText {
    static func forComparison(_ typed: String) -> String {
        let lines = typed.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return lines.count <= 1 ? (lines.first ?? typed.trimmingCharacters(in: .whitespacesAndNewlines)) : lines.joined(separator: " ")
    }
}
