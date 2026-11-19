// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import anki.card_rendering.AVTag
import java.io.File
import java.util.Locale

/** Plays a card's [sound:] files and TTS tags in order. Abstract so sessions can be tested without sound. */
interface CardAudioOutput {
    /** Called on the main thread when playback starts or ends. */
    var onPlayingChange: ((Boolean) -> Unit)?
    fun play(tags: List<AVTag>)
    fun stop()
    fun release() {}
}

/** MediaPlayer for files from the collection's media folder, TextToSpeech for TTS tags. */
class CardAudioPlayer(context: Context, private val mediaFolder: File) : CardAudioOutput {
    override var onPlayingChange: ((Boolean) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<AVTag>()
    private var player: MediaPlayer? = null
    private var playing = false
    private var ttsReady = false
    private var pendingTts: AVTag? = null
    private var utterance = 0
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()

    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        main.post {
            ttsReady = status == TextToSpeech.SUCCESS
            pendingTts?.let { pendingTts = null; if (ttsReady) speak(it) else next() }
        }
    }.apply {
        setAudioAttributes(attributes)
        setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { main.post { if (id == "k$utterance") next() } }
            @Deprecated("Deprecated in Java") override fun onError(id: String?) { main.post { if (id == "k$utterance") next() } }
        })
    }

    override fun play(tags: List<AVTag>) {
        stop()
        if (tags.isEmpty()) return
        queue.addAll(tags)
        setPlaying(true)
        next()
    }

    override fun stop() {
        queue.clear()
        pendingTts = null
        utterance++
        player?.run { runCatching { stop() }; release() }
        player = null
        runCatching { tts.stop() }
        setPlaying(false)
    }

    override fun release() { stop(); tts.shutdown() }

    private fun setPlaying(value: Boolean) {
        if (playing == value) return
        playing = value
        onPlayingChange?.invoke(value)
    }

    private fun next() {
        player?.release(); player = null
        val tag = queue.removeFirstOrNull() ?: run { setPlaying(false); return }
        when (tag.valueCase) {
            AVTag.ValueCase.SOUND_OR_VIDEO -> {
                val file = File(mediaFolder, tag.soundOrVideo)
                if (!file.isFile) { next(); return }
                val p = MediaPlayer()
                runCatching {
                    p.setAudioAttributes(attributes)
                    p.setDataSource(file.path)
                    p.setOnCompletionListener { if (it === player) next() }
                    p.setOnErrorListener { mp, _, _ -> if (mp === player) next(); true }
                    p.prepare()
                    player = p
                    p.start()
                }.onFailure { p.release(); next() }
            }
            AVTag.ValueCase.TTS -> if (ttsReady) speak(tag) else pendingTts = tag
            else -> next()
        }
    }

    private fun speak(tag: AVTag) {
        val t = tag.tts
        val text = t.fieldText.replace(Regex("<[^>]+>"), " ").trim()
        if (text.isEmpty()) { next(); return }
        tts.language = locale(t.lang)
        tts.setSpeechRate(if (t.speed > 0) t.speed else 1f)
        utterance++
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "k$utterance")
    }

    companion object {
        /** Anki's lang is "en_US"; Locale wants "en-US". */
        fun locale(lang: String): Locale = Locale.forLanguageTag(lang.replace('_', '-'))
    }
}
