// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import anki.card_rendering.RenderedTemplateNode
import anki.card_rendering.RenderedTemplateReplacement
import anki.scheduler.SchedulingState
import anki.scheduler.SchedulingStates
import app.kartei.ui.CardPage
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class StudyTest {
    private fun text(t: String) = RenderedTemplateNode.newBuilder().setText(t).build()
    private fun repl(f: String, cur: String) = RenderedTemplateNode.newBuilder()
        .setReplacement(RenderedTemplateReplacement.newBuilder().setFieldName(f).setCurrentText(cur)).build()

    @Test fun flattenPutsQuestionIntoFrontSide() {
        val nodes = listOf(repl("FrontSide", ""), text("<hr id=answer>"), repl("Back", "B"))
        assertEquals("Q<hr id=answer>B", CardText.flatten(nodes, "Q"))
        assertEquals("<hr id=answer>B", CardText.flatten(nodes, null))
    }

    @Test fun playRefsBecomeLabelledButtons() {
        val html = CardText.playButtons("a [anki:play:q:0] b [anki:play:a:12]")
        assertTrue(html.contains("kartei.play('q:0')"))
        assertTrue(html.contains("kartei.play('a:12')"))
        assertTrue(html.contains("aria-label=\"Play audio 13\""))
        assertFalse(html.contains("[anki:play"))
        assertEquals(true to 2, CardText.playRequest("play:q:2"))
        assertEquals(false to 0, CardText.playRequest("play:a:0"))
        assertNull(CardText.playRequest("play:x:0"))
        assertNull(CardText.playRequest("play:q:-1"))
        assertNull(CardText.playRequest("nonsense"))
    }

    @Test fun typeAnswerModifiers() {
        assertEquals(TypeAnswer("Back"), TypeAnswer.find("x [[type:Back]] y"))
        assertEquals(TypeAnswer("Text", cloze = true), TypeAnswer.find("[[type:cloze:Text]]"))
        assertEquals(TypeAnswer("Word", combining = false, ignoreCase = true), TypeAnswer.find("[[type:nc:ci:Word]]"))
        assertNull(TypeAnswer.find("plain"))
        assertEquals("Q ", TypeAnswer.question("Q [[type:Back]]"))
    }

    @Test fun typeAnswerKeepsComparisonOnTheAnswerHalf() {
        assertEquals("Q <hr id=answer>DIFFB", TypeAnswer.answer("Q [[type:Back]]<hr id=answer>B", "DIFF"))
        assertEquals("Q<hr id=answer>D", TypeAnswer.answer("Q<hr id=answer>[[type:Back]]", "D"))
        assertEquals("A ", TypeAnswer.answer("A [[type:Back]]", null))
        assertEquals("$1 \\0", TypeAnswer.answer("[[type:B]]", "$1 \\0"))
    }

    @Test fun typedDiffLayout() {
        val wrong = TypedDiff.html("<code id=typeans><span class=typeGood>Mark W</span><span class=typeBad>is</span>" + TypedDiff.ARROW +
            "<span class=typeGood>Mark W</span><span class=typeMissed>eis</span></code>", "Mark Wiser")
        assertTrue(wrong.contains("<span class=typeBad>is</span>"))
        assertTrue(wrong.contains("<span class=typeMissed>eis</span>"))
        assertTrue(wrong.contains("You decide how it counts."))
        assertTrue(wrong.contains("You typed: Mark Wiser. Answer: Mark Weis"))
        assertTrue(TypedDiff.html("<code id=typeans><span class=typeGood>Ok</span></code>", "Ok").contains("Exact match"))
        assertTrue(TypedDiff.html("<code id=typeans>Paris</code>", "").contains("Nothing typed"))
        assertTrue(TypedDiff.html("x", "<b>").contains("&lt;b&gt;"))
    }

    @Test fun examLookupWalksUpTheDeckTree() {
        val names = mapOf(1L to "Default", 10L to "Bio", 11L to "Bio::Cells", 12L to "Bio::Cells::Mitosis", 20L to "Chem", 21L to "Biology")
        val exam = LocalDate.of(2027, 2, 12); val other = LocalDate.of(2027, 3, 1)
        assertEquals(exam, ExamLookup.examDate(12, names, mapOf(10L to exam)))
        assertEquals(other, ExamLookup.examDate(12, names, mapOf(10L to exam, 11L to other)))
        assertEquals(exam, ExamLookup.examDate(12, names, mapOf(12L to exam, 10L to other)))
        assertNull(ExamLookup.examDate(12, names, mapOf(20L to exam)))
        assertNull(ExamLookup.examDate(21, names, mapOf(10L to exam)))
        assertNull(ExamLookup.examDate(99, names, mapOf(10L to exam)))
        assertNull(ExamLookup.examDate(10, names, mapOf(11L to exam)))
    }

    @Test fun daysLeftAndNote() {
        val today = LocalDate.of(2026, 3, 28)
        assertEquals(2, ExamLookup.daysLeft(LocalDate.of(2026, 3, 30), today))
        assertEquals(0, ExamLookup.daysLeft(today, today))
        assertEquals(-1, ExamLookup.daysLeft(LocalDate.of(2026, 3, 27), today))
        assertEquals("Shorter because of the exam on 12 Feb", ExamLookup.note(LocalDate.of(2027, 2, 12)))
    }

    private fun review(days: Int) = SchedulingState.newBuilder().setNormal(
        SchedulingState.Normal.newBuilder().setReview(SchedulingState.Review.newBuilder().setScheduledDays(days))).build()

    @Test fun capStatesWrapperRoundTripsBytes() {
        val states = SchedulingStates.newBuilder().setAgain(review(1)).setGood(review(30)).build()
        var seen = -1
        // Stand-in for Native.capStates: cap every review at 3 days, as the core does for 7 days left.
        val capped = capStates(states, 7) { bytes, days ->
            seen = days
            val s = SchedulingStates.parseFrom(bytes)
            s.toBuilder().setGood(review(minOf(3, s.good.normal.review.scheduledDays))).build().toByteArray()
        }
        assertEquals(7, seen)
        assertEquals(3, capped.good.normal.review.scheduledDays)
        assertEquals(1, capped.again.normal.review.scheduledDays)
        assertSame(states, capStates(states, 0) { _, _ -> error("not called for an exam today") })
        assertSame(states, capStates(states, 5) { _, _ -> byteArrayOf(0x7f, 0x7f) })  // garbage back: keep the states
    }

    @Test fun cardPageShowsImageOcclusionAnswerOnce() {
        val q = """<div id="image-occlusion-container"><img src="a.png"></div>"""
        val page = CardPage.html(q, q + "<button id=toggle>Toggle</button>", "")
        assertEquals(1, page.split("image-occlusion-container").size - 1)
        assertTrue(page.contains("kartei-card.js"))
        assertTrue(CardPage.html("Q", "Q<hr id=answer>A", "").contains("<div class=\"k-q small\">Q</div><div class=\"k-a\">A</div>"))
    }
}
