// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import WebKit
import XCTest
@testable import Kartei

// MARK: - Pure logic

final class StudyLogicTests: XCTestCase {
    private func node(_ text: String) -> Anki_CardRendering_RenderedTemplateNode {
        var n = Anki_CardRendering_RenderedTemplateNode(); n.text = text; return n
    }
    private func replacement(_ field: String, _ current: String) -> Anki_CardRendering_RenderedTemplateNode {
        var r = Anki_CardRendering_RenderedTemplateReplacement(); r.fieldName = field; r.currentText = current
        var n = Anki_CardRendering_RenderedTemplateNode(); n.replacement = r; return n
    }

    func testFlattenPutsQuestionIntoFrontSide() {
        let nodes = [replacement("FrontSide", ""), node("<hr id=answer>"), replacement("Back", "B")]
        XCTAssertEqual(CardText.flatten(nodes, frontSide: "Q"), "Q<hr id=answer>B")
        XCTAssertEqual(CardText.flatten(nodes, frontSide: nil), "<hr id=answer>B")
    }

    func testPlayRefsBecomeLabelledButtons() {
        let html = CardText.playButtons("a [anki:play:q:0] b [anki:play:a:12]")
        XCTAssertTrue(html.contains("kartei.play('q:0')"))
        XCTAssertTrue(html.contains("kartei.play('a:12')"))
        XCTAssertTrue(html.contains(#"aria-label="Play audio 13""#))
        XCTAssertFalse(html.contains("[anki:play"))
        XCTAssertEqual(CardText.playButtons("no audio"), "no audio")
    }

    func testPlayRequestParsing() {
        XCTAssertTrue(CardText.playRequest("play:q:2")! == (true, 2))
        XCTAssertTrue(CardText.playRequest("play:a:0")! == (false, 0))
        XCTAssertNil(CardText.playRequest("play:x:0"))
        XCTAssertNil(CardText.playRequest("play:q:-1"))
        XCTAssertNil(CardText.playRequest("nonsense"))
    }

    func testTypeAnswerModifiers() {
        XCTAssertEqual(TypeAnswer.find(in: "x [[type:Back]] y"), TypeAnswer(field: "Back"))
        XCTAssertEqual(TypeAnswer.find(in: "[[type:cloze:Text]]"), TypeAnswer(field: "Text", cloze: true))
        XCTAssertEqual(TypeAnswer.find(in: "[[type:nc:ci:Word]]"), TypeAnswer(field: "Word", combining: false, ignoreCase: true))
        XCTAssertNil(TypeAnswer.find(in: "plain"))
        XCTAssertEqual(TypeAnswer.question("Q [[type:Back]]"), "Q ")
    }

    func testTypeAnswerKeepsComparisonOnTheAnswerHalf() {
        // Anki's hack: the <hr id=answer> moves in front of the comparison.
        let out = TypeAnswer.answer("Q [[type:Back]]<hr id=answer>B", comparison: "DIFF")
        XCTAssertEqual(out, "Q <hr id=answer>DIFFB")
        XCTAssertEqual(TypeAnswer.answer("Q<hr id=answer>[[type:Back]]", comparison: "D"), "Q<hr id=answer>D")
        XCTAssertEqual(TypeAnswer.answer("A [[type:Back]]", comparison: nil), "A ")
        // A $ in the learner's text must not be read as a template reference.
        XCTAssertEqual(TypeAnswer.answer("[[type:B]]", comparison: "$1 \\0"), "$1 \\0")
    }

    func testTypedDiffLayout() {
        let wrong = TypedDiff.html(compared: "<code id=typeans><span class=typeGood>Mark W</span><span class=typeBad>is</span>" + TypedDiff.arrow + "<span class=typeGood>Mark W</span><span class=typeMissed>eis</span></code>", typed: "Mark Wiser")
        XCTAssertTrue(wrong.contains("You typed"))
        XCTAssertTrue(wrong.contains("<span class=typeBad>is</span>"))
        XCTAssertTrue(wrong.contains("<span class=typeMissed>eis</span>"))
        XCTAssertTrue(wrong.contains("You decide how it counts."))
        XCTAssertTrue(wrong.contains("You typed: Mark Wiser. Answer: Mark Weis"))
        let exact = TypedDiff.html(compared: "<code id=typeans><span class=typeGood>Ok</span></code>", typed: "Ok")
        XCTAssertTrue(exact.contains("Exact match"))
        let empty = TypedDiff.html(compared: "<code id=typeans>Paris</code>", typed: "")
        XCTAssertTrue(empty.contains("Nothing typed"))
        XCTAssertTrue(TypedDiff.html(compared: "x", typed: "<b>").contains("&lt;b&gt;"))
    }

    func testExamLookupWalksUpTheDeckTree() {
        let names: [Int64: String] = [1: "Default", 10: "Bio", 11: "Bio::Cells", 12: "Bio::Cells::Mitosis", 20: "Chem", 21: "Biology"]
        let exam = Date(timeIntervalSince1970: 2_000_000_000), other = Date(timeIntervalSince1970: 2_100_000_000)
        XCTAssertEqual(ExamLookup.examDate(deck: 12, names: names, exams: [10: exam]), exam)
        XCTAssertEqual(ExamLookup.examDate(deck: 12, names: names, exams: [10: exam, 11: other]), other, "nearest ancestor wins")
        XCTAssertEqual(ExamLookup.examDate(deck: 12, names: names, exams: [12: exam, 10: other]), exam, "own deck wins")
        XCTAssertNil(ExamLookup.examDate(deck: 12, names: names, exams: [20: exam]), "unrelated deck")
        XCTAssertNil(ExamLookup.examDate(deck: 21, names: names, exams: [10: exam]), "name prefix is not a parent")
        XCTAssertNil(ExamLookup.examDate(deck: 99, names: names, exams: [10: exam]), "unknown deck")
        XCTAssertNil(ExamLookup.examDate(deck: 10, names: names, exams: [11: exam]), "children do not count")
    }

    func testDaysLeftCountsCalendarDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let f = ISO8601DateFormatter()
        let lateEvening = f.date(from: "2026-03-28T23:30:00+01:00")!
        let examMorning = f.date(from: "2026-03-30T08:00:00+02:00")!  // across the DST switch
        XCTAssertEqual(ExamLookup.daysLeft(until: examMorning, from: lateEvening, calendar: cal), 2)
        XCTAssertEqual(ExamLookup.daysLeft(until: lateEvening, from: lateEvening, calendar: cal), 0)
        XCTAssertEqual(ExamLookup.daysLeft(until: lateEvening, from: examMorning, calendar: cal), -2)
    }

    func testExamNoteWording() {
        var c = DateComponents(); c.year = 2027; c.month = 2; c.day = 12; c.hour = 12
        XCTAssertEqual(ExamLookup.note(Calendar.current.date(from: c)!), "Shorter because of the exam on 12 Feb")
    }

    private func review(_ days: UInt32) -> Anki_Scheduler_SchedulingState {
        var s = Anki_Scheduler_SchedulingState()
        var r = Anki_Scheduler_SchedulingState.Review(); r.scheduledDays = days
        s.normal.review = r
        return s
    }

    func testCapStatesWrapperCallsTheRustCore() {
        var states = Anki_Scheduler_SchedulingStates()
        states.again = review(1); states.hard = review(10); states.good = review(30); states.easy = review(60)
        var learning = Anki_Scheduler_SchedulingState(); learning.normal.learning = .init(); learning.normal.learning.scheduledSecs = 600
        states.current = learning
        let capped = Backend.capStates(states, daysLeft: 7)  // 43% of 7 days -> 3
        XCTAssertEqual(capped.good.normal.review.scheduledDays, 3)
        XCTAssertEqual(capped.easy.normal.review.scheduledDays, 3)
        XCTAssertEqual(capped.hard.normal.review.scheduledDays, 3)
        XCTAssertEqual(capped.again.normal.review.scheduledDays, 1)
        XCTAssertEqual(capped.current, states.current, "the current state is never touched")
        XCTAssertEqual(Backend.capStates(states, daysLeft: 0), states, "exam today: no cap")
        XCTAssertEqual(Backend.capStates(states, daysLeft: -3), states, "exam past: no cap")
        XCTAssertEqual(Backend.capStates(states, daysLeft: 350).good.normal.review.scheduledDays, 28)  // 8% of 350
    }

    func testCardPageShowsImageOcclusionAnswerOnce() {
        let q = #"<div id="image-occlusion-container"><img src="a.png"></div>"#
        let page = CardPage.html(question: q, answer: q + "<button id=toggle>Toggle</button>", css: "")
        XCTAssertEqual(page.components(separatedBy: "image-occlusion-container").count - 1, 1)
        XCTAssertTrue(page.contains("kartei-card.js"))
        let basic = CardPage.html(question: "Q", answer: "Q<hr id=answer>A", css: "")
        XCTAssertTrue(basic.contains("<div class=\"k-q small\">Q</div><div class=\"k-a\">A</div>"))
    }
}

// MARK: - Against Anki's backend

/// A fresh collection in a temporary folder (or KARTEI_STUDY_FIXTURE, kept, for running the app on it).
final class TestCollection {
    let backend: Backend
    let dir: URL
    var media: URL { dir.appendingPathComponent("media") }

    init(dir: URL? = nil) throws {
        self.dir = dir ?? FileManager.default.temporaryDirectory.appendingPathComponent("kartei-study-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: self.dir.appendingPathComponent("media"), withIntermediateDirectories: true)
        backend = try Backend()
        var open = Anki_Collection_OpenCollectionRequest()
        open.collectionPath = self.dir.appendingPathComponent("collection.anki2").path
        open.mediaFolderPath = media.path
        open.mediaDbPath = self.dir.appendingPathComponent("media.db").path
        try backend.run(CollectionMethods.openCollection, open)
    }

    func close() {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = false
        try? backend.run(CollectionMethods.closeCollection, req)
    }

    func deck(_ name: String) throws -> Int64 {
        var deck: Anki_Decks_Deck = try backend.call(DecksMethods.newDeck)
        deck.name = name
        let added: Anki_Collection_OpChangesWithId = try backend.call(DecksMethods.addDeck, deck)
        return added.id
    }

    @discardableResult
    func note(_ notetype: String, _ fields: [String], deck: Int64 = 1) throws -> Int64 {
        var name = Anki_Generic_String(); name.val = notetype
        let ntid: Anki_Notetypes_NotetypeId = try backend.call(NotetypesMethods.getNotetypeIdByName, name)
        var note: Anki_Notes_Note = try backend.call(NotesMethods.newNote, ntid)
        note.fields = fields
        var req = Anki_Notes_AddNoteRequest(); req.note = note; req.deckID = deck
        let added: Anki_Notes_AddNoteResponse = try backend.call(NotesMethods.addNote, req)
        return added.noteID
    }

    func cards(_ search: String) throws -> [Int64] {
        var req = Anki_Search_SearchRequest(); req.search = search
        let res: Anki_Search_SearchResponse = try backend.call(SearchMethods.searchCards, req)
        return res.ids
    }

    func card(_ id: Int64) throws -> Anki_Cards_Card {
        var cid = Anki_Cards_CardId(); cid.cid = id
        return try backend.call(CardsMethods.getCard, cid)
    }

    /// A short sine tone as 16-bit mono WAV.
    func tone(_ name: String, seconds: Double = 0.3) throws {
        let rate = 22050, n = Int(Double(rate) * seconds)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        for i in 0..<n { u16(UInt16(bitPattern: Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 8000))) }
        try d.write(to: media.appendingPathComponent(name))
    }

    /// A 400x300 diagram as PNG, for image occlusion.
    func diagram(_ url: URL) throws {
        let w = 400, h = 300
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.27, green: 0.52, blue: 0.53, alpha: 1)); ctx.fill(CGRect(x: 40, y: 180, width: 120, height: 80))
        ctx.setFillColor(CGColor(red: 0.84, green: 0.36, blue: 0.05, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 180, y: 60, width: 90, height: 90))
        ctx.setFillColor(CGColor(red: 0.4, green: 0.36, blue: 0.33, alpha: 1)); ctx.fill(CGRect(x: 290, y: 40, width: 80, height: 220))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// Rect (c1), ellipse (c2), polygon (c3); "hide all, guess one" when `hideAll`.
    func occlusionNote(hideAll: Bool) throws {
        let image = dir.appendingPathComponent("diagram.png")
        try diagram(image)
        let oi = hideAll ? ":oi=1" : ""
        var req = Anki_ImageOcclusion_AddImageOcclusionNoteRequest()
        req.imagePath = image.path
        req.occlusions = "{{c1::image-occlusion:rect:left=.1:top=.1333:width=.3:height=.2667\(oi)}}"
            + "{{c2::image-occlusion:ellipse:left=.45:top=.5:rx=.1125:ry=.15\(oi)}}"
            + "{{c3::image-occlusion:polygon:left=.7:top=.1:points=.7,.1 .95,.1 .825,.6\(oi)}}"
        req.header = "Name the part"
        req.backExtra = "Kartei test diagram"
        let _: Anki_Collection_OpChanges = try backend.call(ImageOcclusionMethods.addImageOcclusionNote, req)
    }
}

final class RecordingAudio: CardAudioOutput {
    var onPlayingChange: ((Bool) -> Void)?
    var played: [[Anki_CardRendering_AVTag]] = []
    var stops = 0
    func play(_ tags: [Anki_CardRendering_AVTag]) { played.append(tags) }
    func stop() { stops += 1 }
}

private func names(_ tags: [Anki_CardRendering_AVTag]) -> [String] {
    tags.map { tag in
        switch tag.value {
        case .soundOrVideo(let f): f
        case .tts(let t): "tts:\(t.lang):\(t.fieldText)"
        case nil: "?"
        }
    }
}

final class StudyBackendTests: XCTestCase {
    private var col: TestCollection!

    override func setUpWithError() throws { col = try TestCollection() }
    override func tearDown() { col.close(); try? FileManager.default.removeItem(at: col.dir) }

    private func wait(_ what: String, timeout: TimeInterval = 20, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    private func session(_ deck: Int64 = 1, exams: [Int64: Date] = [:]) -> (ReviewSession, RecordingAudio) {
        let s = ReviewSession(backend: col.backend, deckID: deck, deckName: "Test", exams: exams)
        let audio = RecordingAudio()
        s.attach(audio: audio)
        s.start()
        return (s, audio)
    }

    func testTypedAnswerComparesButNeverGrades() throws {
        try col.note("Basic (type in the answer)", ["Who is the father of ubiquitous computing?", "Mark Weiser"])
        let (s, _) = session()
        wait("question") { s.isQuestion }
        XCTAssertEqual(s.typeAnswer, TypeAnswer(field: "Back"))
        XCTAssertFalse(s.questionHTML.contains("[[type:"))
        s.typed = "Mark Wiser"
        s.showAnswer()
        wait("answer") { s.isAnswer }
        XCTAssertTrue(s.answerHTML.contains("k-typed"), s.answerHTML)
        XCTAssertTrue(s.answerHTML.contains("typeBad") || s.answerHTML.contains("typeMissed"), s.answerHTML)
        XCTAssertTrue(s.answerHTML.contains("You decide how it counts."))
        XCTAssertFalse(s.answerHTML.contains("[[type:"))
        // The comparison lands below the rule, on the answer half.
        let page = CardPage.html(question: s.questionHTML, answer: s.answerHTML, css: s.css)
        let parts = page.components(separatedBy: "<div class=\"k-a\">")
        XCTAssertEqual(parts.count, 2); XCTAssertTrue(parts[1].contains("k-typed"))
        // Still waiting for the learner's grade.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(s.isAnswer)
        XCTAssertEqual(s.answered, 0)
        s.answer(.forgot)
        wait("next") { s.answered == 1 }
    }

    func testTypedExactAndEmpty() throws {
        try col.note("Basic (type in the answer)", ["Capital of France?", "Paris"])
        let (s, _) = session()
        wait("question") { s.isQuestion }
        s.typed = "Paris"
        s.showAnswer()
        wait("answer") { s.isAnswer }
        XCTAssertTrue(s.answerHTML.contains("typeGood"))
        XCTAssertTrue(s.answerHTML.contains("Exact match"))
    }

    func testAudioPlaysEachSideAndReplaysBoth() throws {
        try col.tone("q.wav"); try col.tone("a.wav")
        try col.note("Basic", ["Hear this [sound:q.wav]", "And this [sound:a.wav] [anki:tts lang=de_DE]Guten Tag[/anki:tts]"])
        let (s, audio) = session()
        wait("question") { s.isQuestion }
        XCTAssertEqual(names(s.questionAudio), ["q.wav"])
        XCTAssertEqual(audio.played.map(names), [["q.wav"]], "question audio autoplays")
        XCTAssertTrue(s.questionHTML.contains("[anki:play:q:0]"))
        XCTAssertTrue(CardPage.html(question: s.questionHTML, answer: nil, css: "").contains("kartei.play('q:0')"))
        s.showAnswer()
        wait("answer") { s.isAnswer }
        XCTAssertEqual(names(audio.played.last!), ["a.wav", "tts:de_DE:Guten Tag"], "answer side autoplays only its own audio")
        XCTAssertEqual(names(s.replayTags), ["q.wav", "a.wav", "tts:de_DE:Guten Tag"], "replay includes the question (Anki's replayq)")
        s.play("play:q:0")
        XCTAssertEqual(names(audio.played.last!), ["q.wav"])
        let stops = audio.stops
        s.answer(.good)
        XCTAssertGreaterThan(audio.stops, stops, "audio stops when moving on")
    }

    func testRealPlayerReportsPlayback() throws {
        try col.tone("t.wav", seconds: 0.2)
        let player = CardAudioPlayer(mediaFolder: col.media)
        var states: [Bool] = []
        player.onPlayingChange = { states.append($0) }
        var tag = Anki_CardRendering_AVTag(); tag.soundOrVideo = "t.wav"
        var missing = Anki_CardRendering_AVTag(); missing.soundOrVideo = "missing.mp3"
        player.play([missing, tag])
        wait("playback to finish", timeout: 10) { states == [true, false] }
        XCTAssertEqual(CardAudioPlayer.bcp47("en_US"), "en-US")
    }

    func testExamCapsIntervalsFromAParentDeck() throws {
        let parent = try col.deck("Exam")
        let child = try col.deck("Exam::Chapter 1")
        let nid = try col.note("Basic", ["Q", "A"], deck: child)
        let cid = try col.cards("nid:\(nid)")[0]
        var due = Anki_Scheduler_SetDueDateRequest(); due.cardIds = [cid]; due.days = "0"
        let _: Anki_Collection_OpChanges = try col.backend.call(SchedulerMethods.setDueDate, due)
        let exam = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now))!

        // Without an exam: Good is more than one day out.
        let (free, _) = session(child)
        wait("question") { free.isQuestion }
        XCTAssertTrue(free.cappedRatings.isEmpty)
        XCTAssertNil(free.examNote)

        let (s, _) = session(child, exams: [parent: exam])
        wait("question") { s.isQuestion }
        XCTAssertTrue(s.cappedRatings.contains(.good), "\(s.intervals)")
        XCTAssertEqual(s.intervals[Rating.good.rawValue].filter { $0 != "\u{2068}" && $0 != "\u{2069}" }, "1d")
        XCTAssertTrue(s.examNote?.hasPrefix("Shorter because of the exam on") ?? false)
        s.showAnswer()
        s.answer(.good)
        wait("answered") { s.answered == 1 }
        XCTAssertEqual(try col.card(cid).interval, 1, "the capped state is what was sent")
    }

    func testImageOcclusionRendersMasks() throws {
        try col.occlusionNote(hideAll: true)
        let (s, _) = session()
        wait("question") { s.isQuestion }
        XCTAssertTrue(s.questionHTML.contains("image-occlusion-canvas"))
        XCTAssertTrue(s.questionHTML.contains(#"class="cloze""#))
        XCTAssertTrue(s.questionHTML.contains(#"class="cloze-inactive""#))
        let q = try WebProbe.render(CardPage.html(question: s.questionHTML, answer: nil, css: s.css), media: col.media)
        XCTAssertEqual(q.drawn, "3", "one asked and two hidden shapes on the question side: \(q.debug)")
        XCTAssertNil(q.hiddenToggle, "the toggle button is answer-side only")
        s.showAnswer()
        wait("answer") { s.isAnswer }
        XCTAssertTrue(s.answerHTML.contains("cloze-highlight"))
        let a = try WebProbe.render(CardPage.html(question: s.questionHTML, answer: s.answerHTML, css: s.css), media: col.media)
        XCTAssertEqual(a.drawn, "3", "highlight plus two hidden shapes on the answer side")
        XCTAssertEqual(a.containers, 1, "the image is shown once")
        XCTAssertEqual(a.hiddenToggle, false, "hide-all notes offer the mask toggle")
        if let out = ProcessInfo.processInfo.environment["KARTEI_STUDY_SHOTS"] {
            try q.png.write(to: URL(fileURLWithPath: out).appendingPathComponent("io-question.png"))
            try a.png.write(to: URL(fileURLWithPath: out).appendingPathComponent("io-answer.png"))
        }
    }

    func testImageOcclusionHideOneDrawsOnlyTheAskedShape() throws {
        try col.occlusionNote(hideAll: false)
        let (s, _) = session()
        wait("question") { s.isQuestion }
        let q = try WebProbe.render(CardPage.html(question: s.questionHTML, answer: nil, css: s.css), media: col.media)
        XCTAssertEqual(q.drawn, "1")
    }

    /// Builds a collection to run the app against: KARTEI_STUDY_FIXTURE=/folder (via TEST_RUNNER_ in xcodebuild).
    func testBuildFixtureWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["KARTEI_STUDY_FIXTURE"] else { throw XCTSkip("no fixture requested") }
        try? FileManager.default.removeItem(atPath: path)
        let f = try TestCollection(dir: URL(fileURLWithPath: path))
        defer { f.close() }
        let typed = try f.deck("Study fixture::1 Typed")
        let audio = try f.deck("Study fixture::2 Audio")
        let io = try f.deck("Study fixture::3 Occlusion")
        let exam = try f.deck("Study fixture::4 Exam")
        try f.note("Basic (type in the answer)", ["Who is known as the father of ubiquitous computing?", "Mark Weiser"], deck: typed)
        try f.tone("tone.wav", seconds: 1.0)
        try f.note("Basic", ["What does this tone sound like? [sound:tone.wav]", "A 440 Hz A. [anki:tts lang=en_US]Concert pitch[/anki:tts]"], deck: audio)
        var cur = Anki_Decks_DeckId(); cur.did = io
        let _: Anki_Collection_OpChanges = try f.backend.call(DecksMethods.setCurrentDeck, cur)
        try f.occlusionNote(hideAll: true)
        let nid = try f.note("Basic", ["What did Cepeda et al. (2008) vary?", "The gap between study sessions, against the test delay."], deck: exam)
        var due = Anki_Scheduler_SetDueDateRequest(); due.cardIds = try f.cards("nid:\(nid)"); due.days = "0"
        let _: Anki_Collection_OpChanges = try f.backend.call(SchedulerMethods.setDueDate, due)
        f.backend.setConfig(StudyPrefs.onboardedKey, true)
        f.backend.setConfig(StudyPrefs.detailKey, ProcessInfo.processInfo.environment["KARTEI_STUDY_DETAIL"] ?? "simple")
        print("fixture decks: typed \(typed) audio \(audio) io \(io) exam \(exam)")
    }
}

/// Loads a card page in an offscreen WKWebView with the app's scheme handler and reads back what the JS drew.
enum WebProbe {
    struct Result { var drawn: String?; var hiddenToggle: Bool?; var containers: Int; var png: Data; var debug: String }

    static func render(_ html: String, media: URL) throws -> Result {
        let handler = CardSchemeHandler()
        handler.mediaFolder = media
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: "kartei")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 560), configuration: config)
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.backgroundColor = NSColor(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255, alpha: 1)
        web.setValue(false, forKey: "drawsBackground")
        web.loadHTMLString(html, baseURL: URL(string: "kartei://media/"))
        func eval(_ js: String) -> Any? {
            var out: Any?, done = false
            web.evaluateJavaScript(js) { v, _ in out = v; done = true }
            let end = Date().addingTimeInterval(5)
            while !done && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            return out
        }
        let end = Date().addingTimeInterval(20)
        var drawn: String?
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            drawn = eval("(document.getElementById('image-occlusion-canvas')||{}).dataset?.karteiDrawn ?? null") as? String
            if drawn != nil { break }
        }
        let hidden = eval("(function(){var b=document.getElementById('toggle');return b?b.style.display==='none':null})()") as? Bool
        let containers = (eval("document.querySelectorAll('#image-occlusion-container').length") as? Int) ?? 0
        var png = Data(), done = false
        web.takeSnapshot(with: nil) { image, _ in
            if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                png = rep.representation(using: .png, properties: [:]) ?? Data()
            }
            done = true
        }
        let snapEnd = Date().addingTimeInterval(10)
        while !done && Date() < snapEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let debug = (eval("(function(){var i=document.querySelector('#image-occlusion-container img');var c=document.getElementById('image-occlusion-canvas');return JSON.stringify({anki:typeof window.anki,kartei:typeof window.kartei,img:i&&i.src,nw:i&&i.naturalWidth,complete:i&&i.complete,cw:c&&c.clientWidth,ch:c&&c.clientHeight,w:c&&c.width,err:(document.getElementById('err')||{}).innerHTML})})()") as? String) ?? "no debug"
        return Result(drawn: drawn, hiddenToggle: hidden, containers: containers, png: png, debug: debug)
    }
}
