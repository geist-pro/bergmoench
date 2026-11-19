// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

/// The bundled course decks: they import, carry five first-session cards, and predict cards ask for typed output.
final class CourseTests: XCTestCase {
    func testEveryCatalogueFileIsBundled() {
        for course in CourseCatalogue.all {
            for file in course.files {
                XCTAssertNotNil(CourseCatalogue.package(file), "\(course.id): \(file).apkg missing from the app bundle")
            }
        }
    }

    func testCourseImportsDeclaredNotesAndOnlyChosenCourse() throws {
        let col = try TempCollection(decks: [])
        let added = try CourseCatalogue.importCourses([CourseCatalogue.gdp], backend: col.backend)
        XCTAssertEqual(added, CourseCatalogue.gdp.notes)
        XCTAssertFalse(try col.cardIDs("\"deck:\(CourseCatalogue.gdp.root)\"").isEmpty)
        XCTAssertTrue(try col.cardIDs("\"deck:\(CourseCatalogue.coopsys.root)\"").isEmpty, "only the chosen course comes in")
        // Re-importing the same package updates nothing and adds nothing (stable GUIDs).
        XCTAssertEqual(try CourseCatalogue.importCourses([CourseCatalogue.gdp], backend: col.backend), 0)
    }

    func testFirstSessionHasFiveCardsAndRemovingItSendsThemHome() throws {
        for course in [CourseCatalogue.gdp, CourseCatalogue.gdpEnglish, CourseCatalogue.coopsys] {
            let col = try TempCollection(decks: [])
            try CourseCatalogue.importCourses([course], backend: col.backend)
            XCTAssertEqual(try col.cardIDs(CourseCatalogue.firstSearch(course)).count, 5, course.id)
            let deck = try XCTUnwrap(try CourseCatalogue.makeFirstSession(course, backend: col.backend), course.id)
            XCTAssertEqual(try col.cardIDs("deck:\"\(CourseCatalogue.firstSessionName)\"").count, 5, course.id)
            CourseCatalogue.removeFirstSession(deck, backend: col.backend)
            XCTAssertEqual(try col.cardIDs("deck:filtered").count, 0)
            XCTAssertEqual(try col.cardIDs(CourseCatalogue.firstSearch(course)).count, 5, "cards are back in the course")
        }
    }

    func testFirstSessionCoursePrefersGdP() {
        XCTAssertNil(CourseCatalogue.firstSessionCourse([]))
        XCTAssertEqual(CourseCatalogue.firstSessionCourse([CourseCatalogue.coopsys, CourseCatalogue.gdp])?.id, "gdp")
    }

    func testPredictCardAsksForTypedOutputInCodeFont() throws {
        let col = try TempCollection(decks: [])
        try CourseCatalogue.importCourses([CourseCatalogue.gdp], backend: col.backend)
        let id = try XCTUnwrap(try col.cardIDs("tag:typ::predict").first)
        var req = Anki_CardRendering_RenderExistingCardRequest()
        req.cardID = id
        let out: Anki_CardRendering_RenderCardResponse = try col.backend.call(CardRenderingMethods.renderExistingCard, req)
        let question = out.questionNodes.map { $0.text }.joined()
        XCTAssertNotNil(TypeAnswer.find(in: question), "predict cards carry {{type:Output}}")
        XCTAssertEqual(TypeAnswer.find(in: question)?.field, "Output")
        XCTAssertTrue(out.css.contains("--k-font-code"), "code follows the app's code face")
        XCTAssertFalse(out.css.contains("Fira"), "the Lehre fonts are not used")
    }

    func testTypedOutputIsComparedLineByLineLikeAnki() {
        XCTAssertEqual(TypedText.forComparison("0.0\n5"), "0.0 5")
        XCTAssertEqual(TypedText.forComparison("0.0  \r\n5\n\n"), "0.0 5")
        XCTAssertEqual(TypedText.forComparison("Hallo"), "Hallo")
    }

    func testCodeFontPerFamily() {
        XCTAssertEqual(ThemeFamily.geist.codeFont, "Courier Prime")
        XCTAssertEqual(ThemeFamily.gruvbox.codeFont, "DM Mono")
        for family in ThemeFamily.allCases {
            for dark in [true, false] {
                XCTAssertTrue(CardTheme(family: family, dark: dark).rootCSS.contains("--k-font-code:\"\(family.codeFont)\""))
            }
            XCTAssertTrue(BundledFonts.has(family.codeFont), "\(family.codeFont) is bundled")
        }
    }

    func testCoachHasALineForEachOfTheFiveCards() {
        for i in 0..<5 {
            XCTAssertNotNil(FirstSessionCoach.line(index: i, answerShown: false, typed: false))
            XCTAssertNotNil(FirstSessionCoach.line(index: i, answerShown: true, typed: false))
        }
        XCTAssertNil(FirstSessionCoach.line(index: 5, answerShown: false, typed: false))
        XCTAssertTrue(FirstSessionCoach.line(index: 1, answerShown: false, typed: true)!.contains("exact output"))
    }

    func testRemovingADeckRemovesItsSubdecksAndCards() throws {
        let col = try TempCollection(decks: [])
        try CourseCatalogue.importCourses([CourseCatalogue.coopsys], backend: col.backend)
        let before = try col.cardIDs("deck:*").count
        XCTAssertGreaterThan(before, 0)
        var names = Anki_Decks_GetDeckNamesRequest()
        names.includeFiltered = false
        let all: Anki_Decks_DeckNames = try col.backend.call(DecksMethods.getDeckNames, names)
        let root = try XCTUnwrap(all.entries.first { $0.name == CourseCatalogue.coopsys.root })
        var req = Anki_Decks_DeckIds()
        req.dids = [root.id]
        let removed: Anki_Collection_OpChangesWithCount = try col.backend.call(DecksMethods.removeDecks, req)
        XCTAssertEqual(Int(removed.count), before, "all cards of the course and its lecture subdecks go")
        XCTAssertEqual(try col.cardIDs("deck:*").count, 0)
    }
}
