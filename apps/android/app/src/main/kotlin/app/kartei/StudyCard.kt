// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import anki.card_rendering.RenderedTemplateNode
import anki.scheduler.SchedulingStates
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Finishing the backend's partial render the way Anki's Python layer does (pylib/anki/template.py):
 * text nodes as they are, {{FrontSide}} replaced by the question, other pending filters left as the field text.
 */
object CardText {
    fun flatten(nodes: List<RenderedTemplateNode>, frontSide: String?): String = buildString {
        for (n in nodes) when (n.valueCase) {
            RenderedTemplateNode.ValueCase.TEXT -> append(n.text)
            RenderedTemplateNode.ValueCase.REPLACEMENT ->
                append(if (n.replacement.fieldName == "FrontSide" && frontSide != null) frontSide else n.replacement.currentText)
            else -> {}
        }
    }

    private val playRef = Regex("""\[anki:play:(q|a):(\d+)]""")

    /** Replace the backend's [anki:play:q:0] references with replay buttons that post "play:q:0" to the app. */
    fun playButtons(html: String): String = html.replace(playRef) { m ->
        val (side, index) = m.destructured
        val n = (index.toIntOrNull() ?: 0) + 1
        """<a class="k-play" href="#" role="button" aria-label="Play audio $n" onclick="return kartei.play('$side:$index')"><svg viewBox="0 0 64 64" aria-hidden="true"><path d="M18 10 L54 32 L18 54 Z"/></svg></a>"""
    }

    /** Parse "play:q:3" from the page into side (true = question) and index. */
    fun playRequest(message: String): Pair<Boolean, Int>? {
        val parts = message.split(":")
        if (parts.size != 3 || parts[0] != "play" || (parts[1] != "q" && parts[1] != "a")) return null
        val i = parts[2].toIntOrNull() ?: return null
        return if (i < 0) null else (parts[1] == "q") to i
    }
}

/** {{type:Field}} as Anki's reviewer handles it (qt/aqt/reviewer.py typeAnsQuestionFilter / typeAnsAnswerFilter). */
data class TypeAnswer(val field: String, val cloze: Boolean = false, val combining: Boolean = true, val ignoreCase: Boolean = false) {
    companion object {
        private val pattern = Regex("""\[\[type:(.+?)]]""")

        /** The first [[type:…]] in the question, with its modifiers (cloze, nc, ci). */
        fun find(html: String): TypeAnswer? {
            val inner = pattern.find(html)?.groupValues?.get(1) ?: return null
            // Field names cannot contain a colon, so everything before the last one is a modifier.
            val colon = inner.lastIndexOf(':')
            if (colon < 0) return TypeAnswer(inner)
            val mods = inner.substring(0, colon).split(":")
            return TypeAnswer(inner.substring(colon + 1), cloze = "cloze" in mods, combining = "nc" !in mods, ignoreCase = "ci" in mods)
        }

        fun replace(html: String, replacement: String): String = html.replace(pattern) { replacement }

        /** Question side: Kartei shows a native text field below the card, so the marker goes. */
        fun question(html: String) = replace(html, "")

        /** Answer side: the comparison goes where [[type:…]] is, with Anki's <hr id=answer> hack. */
        fun answer(html: String, comparison: String?): String {
            if (comparison == null) return replace(html, "")
            val hr = "<hr id=answer>"
            val without = html.replace(hr, "")
            val hadHr = without.length != html.length
            if (hadHr && find(without) == null) return html
            return replace(without, (if (hadHr) hr else "") + comparison)
        }
    }
}

/** The typed-answer comparison laid out as mockups/screens/typed.html; the learner still grades. */
object TypedDiff {
    const val ARROW = "<br><span id=typearrow>&darr;</span><br>"

    fun html(compared: String, typed: String): String {
        val inner = compared.removePrefix("<code id=typeans>").removeSuffix("</code>")
        val cut = inner.indexOf(ARROW)
        val (typedHtml, answerHtml, note) = when {
            cut >= 0 -> Triple(inner.substring(0, cut), inner.substring(cut + ARROW.length), "You decide how it counts.")
            typed.isEmpty() -> Triple("<span class=meta>nothing</span>", inner, "Nothing typed. Grade how well you recalled it.")
            else -> Triple(inner, inner, "Exact match. You still decide how it counts.")
        }
        val spoken = "You typed: ${if (typed.isEmpty()) "nothing" else escape(typed)}. Answer: ${plain(answerHtml)}. $note"
        return "<div class=\"k-typed\"><span class=\"k-sr\">$spoken</span>" +
            "<div class=\"ln\" aria-hidden=\"true\"><span class=\"meta\">You typed</span><span class=\"v\">$typedHtml</span></div>" +
            "<div class=\"ln\" aria-hidden=\"true\"><span class=\"meta\">Answer</span><span class=\"v\">$answerHtml</span></div>" +
            "<div class=\"note\" aria-hidden=\"true\">$note</div></div>"
    }

    fun escape(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
    fun plain(html: String) = html.replace(Regex("<[^>]+>"), "")
}

/** Which exam applies to a card: its own deck's, else the nearest ancestor's (deck names nest with "::"). */
object ExamLookup {
    fun examDate(deck: Long, names: Map<Long, String>, exams: Map<Long, LocalDate>): LocalDate? {
        exams[deck]?.let { return it }
        val name = names[deck] ?: return null
        val byName = names.entries.associate { it.value to it.key }
        val parts = name.split("::").toMutableList()
        while (parts.size > 1) {
            parts.removeAt(parts.size - 1)
            val id = byName[parts.joinToString("::")] ?: continue
            exams[id]?.let { return it }
        }
        return null
    }

    /** Calendar days from today to the exam day (0 = today, negative = past). */
    fun daysLeft(exam: LocalDate, today: LocalDate = LocalDate.now()): Int =
        java.time.temporal.ChronoUnit.DAYS.between(today, exam).toInt()

    private val dayMonth = DateTimeFormatter.ofPattern("d MMM", Locale.UK)

    fun note(exam: LocalDate) = "Shorter because of the exam on ${exam.format(dayMonth)}"
}

/**
 * Cap the answer states for an exam `daysLeft` days away (core/ffi/src/exam.rs, Cepeda et al. 2008).
 * `native` is Native.capStates on the device; tests pass a stand-in since the core is built for Android only.
 */
fun capStates(states: SchedulingStates, daysLeft: Int, native: (ByteArray, Int) -> ByteArray): SchedulingStates {
    if (daysLeft <= 0) return states
    return runCatching { SchedulingStates.parseFrom(native(states.toByteArray(), daysLeft)) }.getOrDefault(states)
}
