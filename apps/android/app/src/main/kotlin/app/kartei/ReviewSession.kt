// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kartei.core.Backend
import app.kartei.core.CardRenderingMethods
import app.kartei.core.CardsMethods
import app.kartei.core.CollectionMethods
import app.kartei.core.DecksMethods
import app.kartei.core.SchedulerMethods
import app.kartei.core.DeckConfigMethods
import app.kartei.core.NotesMethods
import app.kartei.core.NotetypesMethods
import app.kartei.core.Native
import android.os.Handler
import android.os.Looper
import anki.card_rendering.AVTag
import anki.scheduler.SchedulingState
import anki.scheduler.SchedulingStates
import java.time.LocalDate
import java.util.concurrent.Executors

enum class Rating { Forgot, Hard, Good, Easy }

sealed interface ReviewPhase {
    data object Loading : ReviewPhase
    data object Question : ReviewPhase
    data object Answer : ReviewPhase
    data object Done : ReviewPhase
    data class Failed(val why: String) : ReviewPhase
}

/** One study session on one deck. All scheduling comes from Anki's backend; this only asks for the next card and reports the answer. */
class ReviewSession(
    private val backend: Backend,
    private val deckId: Long,
    val deckName: String,
    /** Exam dates per deck id, used to cap intervals before an exam (see core/ffi/src/exam.rs). */
    val exams: Map<Long, java.time.LocalDate> = emptyMap(),
    /** Language of the deck's cards as a BCP 47 tag, or null to leave it to the device (DeckStore.langFor). */
    val lang: String? = null,
) {
    var phase by mutableStateOf<ReviewPhase>(ReviewPhase.Loading); private set
    var questionHtml by mutableStateOf(""); private set
    var answerHtml by mutableStateOf(""); private set
    var css by mutableStateOf(""); private set
    var intervals by mutableStateOf(listOf("", "", "", "")); private set
    var newCount by mutableStateOf(0); private set
    var learningCount by mutableStateOf(0); private set
    var reviewCount by mutableStateOf(0); private set
    var activeQueue by mutableStateOf(anki.scheduler.QueuedCards.Queue.NEW); private set
    var answered by mutableStateOf(0); private set
    var remembered by mutableStateOf(0); private set
    var canUndo by mutableStateOf(false); private set
    /** Anki's flag on the current card: 0 none, 1 red … 7 purple. */
    var flag by mutableStateOf(0); private set
    val hasCard get() = phase == ReviewPhase.Question || phase == ReviewPhase.Answer

    /** Set when the template asks for a typed answer ({{type:Field}}) and the field has text. */
    var typeAnswer by mutableStateOf<TypeAnswer?>(null); private set
    /** What the learner typed on the question side. */
    var typed by mutableStateOf("")
    /** Which answers an exam date shortened, and the note that says so. */
    var cappedRatings by mutableStateOf(emptySet<Rating>()); private set
    var examNote by mutableStateOf<String?>(null); private set
    /** [sound:] and TTS tags of each side, in order (Anki's question_av_tags / answer_av_tags). */
    var questionAudio by mutableStateOf(emptyList<AVTag>()); private set
    var answerAudio by mutableStateOf(emptyList<AVTag>()); private set
    var audioPlaying by mutableStateOf(false); private set
    /** Deck options: autoplay and replaying question audio with the answer (both on by default in Anki). */
    var autoplay = true; private set
    var replayQuestionOnAnswer = true; private set
    /** The tags the replay button plays on the side being shown. */
    val replayTags: List<AVTag>
        get() = when (phase) {
            ReviewPhase.Answer -> (if (replayQuestionOnAnswer) questionAudio else emptyList()) + answerAudio
            ReviewPhase.Question -> questionAudio
            else -> emptyList()
        }

    val remaining get() = newCount + learningCount + reviewCount
    val progress get() = if (answered + remaining == 0) 1f else answered.toFloat() / (answered + remaining)
    val minutesSpent get() = maxOf(1, ((System.currentTimeMillis() - started + 30_000) / 60_000).toInt())

    private val started = System.currentTimeMillis()
    private var shownAt = started
    private var current: anki.scheduler.QueuedCards.QueuedCard? = null
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    /** The current card's answer states after exam capping; these are what gets sent. */
    private var states: SchedulingStates = SchedulingStates.getDefaultInstance()
    private var rawAnswer = ""
    private var expected: String? = null
    @Volatile private var revealing = false
    private var deckNames: Map<Long, String> = emptyMap()
    private val deckOptions = HashMap<Long, Pair<Boolean, Boolean>>()
    private var audio: CardAudioOutput? = null

    /** Give the session somewhere to play sound. Without one, cards are silent. */
    fun attach(output: CardAudioOutput) {
        audio = output
        output.onPlayingChange = { audioPlaying = it }
    }

    private fun onMain(block: () -> Unit) { main.post(block) }

    fun replay() { val tags = replayTags; onMain { audio?.play(tags) } }
    fun stopAudio() { onMain { audio?.stop() } }
    fun toggleAudio() { if (audioPlaying) stopAudio() else replay() }

    /** A replay button in the card page was pressed ("play:q:0"). */
    fun play(message: String) {
        val (question, index) = CardText.playRequest(message) ?: return
        val tags = if (question) questionAudio else answerAudio
        val tag = tags.getOrNull(index) ?: return
        onMain { audio?.play(listOf(tag)) }
    }

    fun start() = perform {
        backend.call(DecksMethods.setCurrentDeck, anki.decks.DeckId.newBuilder().setDid(deckId).build(), anki.collection.OpChanges.parser())
        if (exams.isNotEmpty()) {
            val names = backend.call(DecksMethods.getDeckNames, anki.decks.GetDeckNamesRequest.newBuilder().setSkipEmptyDefault(false).setIncludeFiltered(true).build(),
                anki.decks.DeckNames.parser())
            deckNames = names.entriesList.associate { it.id to it.name }
        }
    }

    fun showAnswer() {
        if (phase != ReviewPhase.Question || revealing) return
        stopAudio()
        val spec = typeAnswer
        val want = expected
        if (spec == null || want == null) { reveal(TypeAnswer.answer(rawAnswer, null)); return }
        revealing = true
        val typed = this.typed
        work.execute {
            val compared = runCatching {
                backend.call(CardRenderingMethods.compareAnswer, anki.card_rendering.CompareAnswerRequest.newBuilder().setExpected(want).setProvided(TypedText.forComparison(typed))
                    .setCombining(spec.combining).setIgnoreCase(spec.ignoreCase).build(), anki.generic.String.parser()).`val`
            }.getOrElse { "<code id=typeans>${TypedDiff.escape(want)}</code>" }
            val diff = TypedDiff.html(compared, typed)
            onMain { revealing = false; reveal(TypeAnswer.answer(rawAnswer, diff)) }
        }
    }

    private fun reveal(html: String) {
        if (phase != ReviewPhase.Question) return
        answerHtml = html
        phase = ReviewPhase.Answer
        if (autoplay) { val tags = answerAudio; onMain { audio?.play(tags) } }
    }

    fun answer(rating: Rating) {
        val card = current ?: return
        if (phase != ReviewPhase.Answer) return
        val taken = minOf(System.currentTimeMillis() - shownAt, 60_000).toInt()
        val states = this.states
        stopAudio()
        phase = ReviewPhase.Loading
        perform {
            val state = stateFor(rating, states)
            val grade = when (rating) {
                Rating.Forgot -> anki.scheduler.CardAnswer.Rating.AGAIN
                Rating.Hard -> anki.scheduler.CardAnswer.Rating.HARD
                Rating.Good -> anki.scheduler.CardAnswer.Rating.GOOD
                Rating.Easy -> anki.scheduler.CardAnswer.Rating.EASY
            }
            backend.call(
                SchedulerMethods.answerCard,
                anki.scheduler.CardAnswer.newBuilder().setCardId(card.card.id).setCurrentState(card.states.current).setNewState(state)
                    .setRating(grade).setAnsweredAtMillis(System.currentTimeMillis()).setMillisecondsTaken(taken).build(),
                anki.collection.OpChanges.parser(),
            )
            answered += 1
            if (rating != Rating.Forgot) remembered += 1
            canUndo = true
        }
    }

    /** Set or clear (same flag again) the current card's flag. Stays on the card in Anki too. */
    fun toggleFlag(value: Int) {
        val card = current ?: return
        val newFlag = if (flag == value) 0 else value
        flag = newFlag
        work.execute {
            runCatching {
                backend.call(CardsMethods.setFlag, anki.cards.SetFlagRequest.newBuilder().addCardIds(card.card.id).setFlag(newFlag).build(),
                    anki.collection.OpChangesWithCount.parser())
            }
        }
    }

    /** Bury until tomorrow, or suspend until brought back in the browser. Either way the next card follows. */
    fun putAway(suspend: Boolean) {
        val card = current ?: return
        stopAudio()
        phase = ReviewPhase.Loading
        perform {
            backend.call(SchedulerMethods.buryOrSuspendCards,
                anki.scheduler.BuryOrSuspendCardsRequest.newBuilder().addCardIds(card.card.id)
                    .setMode(if (suspend) anki.scheduler.BuryOrSuspendCardsRequest.Mode.SUSPEND else anki.scheduler.BuryOrSuspendCardsRequest.Mode.BURY_USER).build(),
                anki.collection.OpChangesWithCount.parser())
            canUndo = true
        }
    }

    fun undo() {
        if (!canUndo) return
        stopAudio()
        perform {
            backend.call(CollectionMethods.undo, anki.generic.Empty.getDefaultInstance(), anki.collection.OpChangesAfterUndo.parser())
            answered = maxOf(0, answered - 1)
            canUndo = false
        }
    }

    /** Run a backend step off the main thread, then load whichever card is next. */
    private fun perform(step: () -> Unit) {
        work.execute {
            try {
                step()
                loadNext()
            } catch (e: Throwable) {
                phase = ReviewPhase.Failed(e.message ?: e.toString())
            }
        }
    }

    private fun loadNext() {
        val queued = backend.call(SchedulerMethods.getQueuedCards, anki.scheduler.GetQueuedCardsRequest.newBuilder().setFetchLimit(1).build(), anki.scheduler.QueuedCards.parser())
        newCount = queued.newCount; learningCount = queued.learningCount; reviewCount = queued.reviewCount
        val next = queued.cardsList.firstOrNull()
        if (next == null) { current = null; phase = ReviewPhase.Done; return }
        val rendered = backend.call(CardRenderingMethods.renderExistingCard,
            anki.card_rendering.RenderExistingCardRequest.newBuilder().setCardId(next.card.id).setPartialRender(true).build(),
            anki.card_rendering.RenderCardResponse.parser())
        // Same order as pylib/anki/template.py: question first, its text becomes {{FrontSide}}.
        val q = avTags(CardText.flatten(rendered.questionNodesList, null), true)
        val a = avTags(CardText.flatten(rendered.answerNodesList, q.text), false)
        var question = q.text
        var spec: TypeAnswer? = null
        var want: String? = null
        TypeAnswer.find(q.text)?.let { found ->
            when (val e = expectedAnswer(found, next.card)) {
                is Expected.Text -> { spec = found; want = e.value; question = TypeAnswer.question(q.text) }
                Expected.Empty -> question = TypeAnswer.question(q.text)
                is Expected.Problem -> question = TypeAnswer.replace(q.text, "<p class=k-warn>${e.warning}</p>")
            }
        }
        val home = if (next.card.originalDeckId != 0L) next.card.originalDeckId else next.card.deckId
        val (play, replayQ) = options(home)
        var capped = next.states
        var cappedSet = emptySet<Rating>()
        var note: String? = null
        ExamLookup.examDate(home, deckNames, exams)?.let { exam ->
            capped = capStates(next.states, ExamLookup.daysLeft(exam), Native::capStates)
            cappedSet = Rating.entries.filter { stateFor(it, capped) != stateFor(it, next.states) }.toSet()
            if (cappedSet.isNotEmpty()) note = ExamLookup.note(exam)
        }
        val labels = backend.call(SchedulerMethods.describeNextStates, capped, anki.generic.StringList.parser()).valsList
        current = next
        activeQueue = next.queue
        questionHtml = question
        rawAnswer = a.text
        answerHtml = ""
        css = rendered.css
        questionAudio = q.avTagsList
        answerAudio = a.avTagsList
        typeAnswer = spec
        expected = want
        typed = ""
        states = capped
        cappedRatings = cappedSet
        examNote = note
        autoplay = play
        replayQuestionOnAnswer = replayQ
        flag = next.card.flags and 0b111
        intervals = if (labels.size == 4) labels else listOf("", "", "", "")
        shownAt = System.currentTimeMillis()
        phase = ReviewPhase.Question
        if (play) { val tags = q.avTagsList; onMain { audio?.play(tags) } }
    }

    private fun avTags(text: String, question: Boolean) = backend.call(CardRenderingMethods.extractAvTags,
        anki.card_rendering.ExtractAvTagsRequest.newBuilder().setText(text).setQuestionSide(question).build(), anki.card_rendering.ExtractAvTagsResponse.parser())

    private sealed interface Expected {
        data class Text(val value: String) : Expected
        data object Empty : Expected
        data class Problem(val warning: String) : Expected
    }

    /** The field the learner should type, narrowed to this card's cloze for {{type:cloze:…}}. */
    private fun expectedAnswer(spec: TypeAnswer, card: anki.cards.Card): Expected {
        val note = backend.call(NotesMethods.getNote, anki.notes.NoteId.newBuilder().setNid(card.noteId).build(), anki.notes.Note.parser())
        val notetype = backend.call(NotetypesMethods.getNotetype, anki.notetypes.NotetypeId.newBuilder().setNtid(note.notetypeId).build(), anki.notetypes.Notetype.parser())
        val index = notetype.fieldsList.indexOfFirst { it.name == spec.field }
        if (index < 0 || index >= note.fieldsCount) {
            return Expected.Problem(if (spec.cloze) "This cloze has nothing to type. Check the note for empty cards." else "Type answer: unknown field ${TypedDiff.escape(spec.field)}")
        }
        var value = note.getFields(index)
        if (spec.cloze) {
            value = backend.call(CardRenderingMethods.extractClozeForTyping,
                anki.card_rendering.ExtractClozeForTypingRequest.newBuilder().setText(value).setOrdinal(card.templateIdx + 1).build(), anki.generic.String.parser()).`val`
        }
        return if (value.isEmpty()) Expected.Empty else Expected.Text(value)
    }

    /** Autoplay and question replay from the card's home deck options, read once per deck. */
    private fun options(deck: Long): Pair<Boolean, Boolean> = deckOptions.getOrPut(deck) {
        runCatching {
            val d = backend.call(DecksMethods.getDeck, anki.decks.DeckId.newBuilder().setDid(deck).build(), anki.decks.Deck.parser())
            if (!d.hasNormal()) return@runCatching true to true
            val conf = backend.call(DeckConfigMethods.getDeckConfig, anki.deck_config.DeckConfigId.newBuilder().setDcid(d.normal.configId).build(),
                anki.deck_config.DeckConfig.parser()).config
            !conf.disableAutoplay to !conf.skipQuestionWhenReplayingAnswer
        }.getOrDefault(true to true)
    }

    companion object {
        fun stateFor(rating: Rating, s: SchedulingStates): SchedulingState = when (rating) {
            Rating.Forgot -> s.again
            Rating.Hard -> s.hard
            Rating.Good -> s.good
            Rating.Easy -> s.easy
        }
    }
}

/** Typed text made comparable with Anki's expected text: line breaks in the expected field become single spaces
 *  (rslib typeanswer.rs), so typed lines are joined the same way, trailing spaces and empty lines dropped. */
object TypedText {
    fun forComparison(typed: String): String {
        val lines = typed.replace("\r\n", "\n").split("\n").map { it.trimEnd() }.filter { it.isNotEmpty() }
        return if (lines.size <= 1) lines.firstOrNull() ?: typed.trim() else lines.joinToString(" ")
    }
}
