// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import android.annotation.SuppressLint
import android.graphics.Color
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import app.kartei.R
import java.io.File

private const val ORIGIN = "https://kartei.invalid"

/**
 * A file directly inside [folder], or null. The name comes from the card's HTML, which an imported deck controls,
 * and Android hands it over decoded: "..%2Fcollection.anki2" arrives as "../collection.anki2" and must not reach
 * the collection next to the media folder.
 */
internal fun mediaFile(name: String, folder: File): File? {
    if (name.isEmpty() || name == "." || name == ".." || '/' in name || '\\' in name || '\u0000' in name) return null
    val file = File(folder, name)
    return if (file.canonicalFile.parentFile == folder.canonicalFile) file else null
}

/**
 * Builds the page for one side of a card. The deck's own CSS is kept, then Kartei's type and colours are laid over it
 * so that plain decks match the app. The question is set in the display face, the answer below one rule.
 */
object CardPage {
    private val hr = Regex("""<hr[^>]*id=["']?answer["']?[^>]*>""", RegexOption.IGNORE_CASE)
    private val audio = Regex("""\[sound:[^\]]*]|\[anki:(play|tts)[^\]]*]""")
    private val tags = Regex("<[^>]+>")

    private fun clean(html: String) = app.kartei.CardText.playButtons(html).replace(audio, "")

    /** True when the answer already contains the question: an image occlusion page, or a template repeating the front without <hr id=answer>. */
    fun repeatsQuestion(answer: String, question: String): Boolean {
        if ("image-occlusion-container" in answer) return true
        val q = question.replace(tags, "").trim()
        return q.isNotEmpty() && q in answer.replace(tags, "")
    }

    private fun hex(c: Long) = "#%06x".format(c and 0xFFFFFF)
    private fun rgba(c: Long, a: Double) = "rgba(${(c shr 16) and 0xFF},${(c shr 8) and 0xFF},${c and 0xFF},$a)"

    /** "onAccent" to "on-accent": the custom property name for a role. */
    fun cssName(role: String) = role.replace(Regex("[A-Z]")) { "-" + it.value.lowercase() }

    /** The palette as CSS custom properties, --k-<role> for every role in core/themes.json plus two soft fills for the typed-answer diff. */
    fun properties(p: Palette, dark: Boolean): String = buildString {
        append(":root{color-scheme:").append(if (dark) "dark" else "light")
        for ((role, c) in p.roles()) append(";--k-").append(cssName(role)).append(':').append(hex(c))
        append(";--k-forgot-soft:").append(rgba(p.forgot, if (dark) 0.35 else 0.18))
        append(";--k-accent-soft:").append(rgba(p.accentRule, if (dark) 0.22 else 0.28))
        append(";--k-font-code:\"").append(codeFont(ThemeState.family)).append("\",ui-monospace,monospace")
        append('}')
    }

    /** Code and console output on cards: Courier Prime in GEIST, DM Mono in Gruvbox (as the Apple app). */
    fun codeFont(family: Family) = if (family == Family.Geist) "Courier Prime" else "DM Mono"

    private fun fontFaces(family: Family) = if (family == Family.Geist)
        """@font-face{font-family:"Nunito";src:url($ORIGIN/app/nunito.ttf);font-weight:200 1000}
@font-face{font-family:"Noto Serif";src:url($ORIGIN/app/noto_serif.ttf);font-weight:100 900}
@font-face{font-family:"Courier Prime";src:url($ORIGIN/app/courier_prime.ttf);font-weight:400}"""
    else """@font-face{font-family:"Bricolage Grotesque";src:url($ORIGIN/app/bricolage_grotesque.ttf);font-weight:200 800}
@font-face{font-family:"DM Sans";src:url($ORIGIN/app/dm_sans.ttf);font-weight:100 1000}
@font-face{font-family:"DM Mono";src:url($ORIGIN/app/dm_mono.ttf);font-weight:400}"""

    /**
     * [regularQuestions] sets the question in weight 400 instead of the thin 200 (Settings › Reading). [lang] is the deck's
     * language as a BCP 47 tag ("de", "en"); it goes on the root element so TalkBack reads the card in the right voice.
     */
    fun html(question: String, answer: String?, css: String, palette: Palette = ThemeState.palette, family: Family = ThemeState.family,
             dark: Boolean = ThemeState.dark, regularQuestions: Boolean = false, lang: String? = null): String {
        var front = clean(question)
        var back = ""
        var whole = false
        if (answer != null) {
            val full = clean(answer)
            // Anki answer templates usually repeat the question above <hr id=answer>.
            val cut = hr.find(full)
            when {
                cut != null -> { front = full.substring(0, cut.range.first); back = full.substring(cut.range.last + 1) }
                // The answer template carries the question itself (image occlusion does): show it once, as Anki does.
                repeatsQuestion(full, front) -> { front = ""; back = full; whole = true }
                else -> back = full
            }
        }
        val size = if (answer != null || front.replace(tags, "").length > 110) "small" else ""
        val display = if (family == Family.Geist) "\"Nunito\",sans-serif" else "\"Bricolage Grotesque\",sans-serif"
        val body = if (family == Family.Geist) "\"Noto Serif\",serif" else "\"DM Sans\",sans-serif"
        // Anki's own dark-mode classes, so decks that style .nightMode follow the mode too.
        val night = if (dark) " nightMode night_mode" else ""
        val langAttr = lang?.filter { it.isLetterOrDigit() || it == '-' }?.takeIf { it.isNotEmpty() }?.let { " lang=\"$it\"" } ?: ""
        val weight = if (regularQuestions) 400 else 200
        // Line heights are ratios of the old px values (41/36, 33/26, 28/20 …), so they follow the text zoom.
        return """<!doctype html><html$langAttr><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
${fontFaces(family)}
${properties(palette, dark)}
$css
html,body{margin:0;background:transparent!important}
body.card{background:transparent!important;color:var(--k-text)!important;padding:0!important;font-family:$body!important;text-align:left!important}
.k-q{font:$weight 36px/1.14 $display;color:var(--k-text);letter-spacing:-.01em;text-wrap:balance}
.k-q.small{font-size:26px;line-height:1.27}
.k-a{border-top:1px solid var(--k-rule);margin-top:20px;padding-top:20px;font:500 20px/1.4 $body}
.k-a small{font:400 13px/1.38 $body;color:var(--k-muted)!important}
img{max-width:100%;height:auto}a{color:var(--k-accent)}
.cloze{font-weight:700;color:var(--k-text)!important;border-bottom:2px solid var(--k-accent-rule)}
.k-a.k-whole{border-top:0;margin-top:0;padding-top:0}
.k-warn{font:400 15px/1.33 $body;color:var(--k-forgot)}
</style>
<link rel="stylesheet" href="$ORIGIN/app/kartei-card.css">
<style>
/* After the shared sheet, which is written in Gruvbox dark: the same rules in the active palette and fonts. */
.k-play{border-color:var(--k-control);color:var(--k-text)!important}
.k-play:active{background:var(--k-surface2)}
.k-typed{border-top-color:var(--k-rule)}
.k-typed .meta,.k-typed .note{font-family:$body;color:var(--k-muted)}
.k-typed .v{font-family:$body;color:var(--k-text)}
.k-typed .typeGood{color:var(--k-text)}
.k-typed .typeBad{color:var(--k-text);background:var(--k-forgot-soft)}
.k-typed .typeMissed{color:var(--k-text);border-bottom-color:var(--k-accent);background:var(--k-accent-soft)}
#image-occlusion-canvas{--highlight-shape-border:3px ${hex(palette.accent)}}
#toggle{font-family:$body;color:var(--k-text);background:var(--k-surface2)}
.k-whole{font-family:$body}
</style>
<script src="$ORIGIN/app/kartei-card.js"></script>
</head><body class="card$night">
${if (whole) "" else "<div class=\"k-q $size\">$front</div>"}${if (answer == null) "" else "<div class=\"k-a${if (whole) " k-whole" else ""}\">$back</div>"}
</body></html>"""
    }
}

/** A drag over the card page, reported so the review screen can grade by swipe (pixels). */
sealed interface CardDrag {
    data class Changed(val dx: Float, val dy: Float) : CardDrag
    data class Ended(val dx: Float, val dy: Float) : CardDrag
    data object Cancelled : CardDrag
}

/**
 * Shows one card page. Fonts come from the app, images from the collection's media folder.
 * [onDrag] (swipe to grade) takes over a touch once it moves sideways past the touch slop; up and down count only with
 * [allowVertical] and when the page has nothing to scroll. Otherwise the page scrolls and its buttons work as usual.
 * [textZoom] scales all text on the page, so cards follow the system font scale and the card text setting.
 */
@SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
@Composable
fun CardWeb(html: String, mediaFolder: File, modifier: Modifier = Modifier, onMessage: (String) -> Unit = {},
            onDrag: ((CardDrag) -> Unit)? = null, allowVertical: Boolean = false, textZoom: Int = 100, onTap: (() -> Unit)? = null) {
    val latest = androidx.compose.runtime.rememberUpdatedState(onMessage)
    val drag = androidx.compose.runtime.rememberUpdatedState(onDrag)
    val vertical = androidx.compose.runtime.rememberUpdatedState(allowVertical)
    val tap = androidx.compose.runtime.rememberUpdatedState(onTap)
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            WebView(ctx).apply {
                setBackgroundColor(Color.TRANSPARENT)
                isHorizontalScrollBarEnabled = false
                val slop = android.view.ViewConfiguration.get(ctx).scaledTouchSlop.toFloat()
                var downX = 0f; var downY = 0f; var downAt = 0L
                var mode = 0 // 0 undecided, 1 swiping, 2 left to the page
                setOnTouchListener { v, e ->
                    when (e.actionMasked) {
                        android.view.MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; downAt = e.eventTime; mode = 0; false }
                        android.view.MotionEvent.ACTION_MOVE -> {
                            val dx = e.rawX - downX; val dy = e.rawY - downY
                            val handler = drag.value
                            if (mode == 0 && handler != null && (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop)) {
                                val sideways = kotlin.math.abs(dx) >= kotlin.math.abs(dy) * 1.2f
                                val upDown = vertical.value && kotlin.math.abs(dy) > kotlin.math.abs(dx) * 1.2f &&
                                    !v.canScrollVertically(1) && !v.canScrollVertically(-1)
                                mode = if (sideways || upDown) 1 else 2
                                if (mode == 1) v.parent?.requestDisallowInterceptTouchEvent(true)
                            } else if (mode == 0 && handler == null && (kotlin.math.abs(dx) > slop || kotlin.math.abs(dy) > slop)) {
                                mode = 2
                            }
                            if (mode == 1) { handler?.invoke(CardDrag.Changed(dx, if (vertical.value) dy else 0f)); true } else false
                        }
                        android.view.MotionEvent.ACTION_UP -> {
                            val dx = e.rawX - downX; val dy = e.rawY - downY
                            when {
                                mode == 1 -> { drag.value?.invoke(CardDrag.Ended(dx, if (vertical.value) dy else 0f)); true }
                                mode == 0 && e.eventTime - downAt < 400 && tap.value != null -> { tap.value?.invoke(); false }
                                else -> false
                            }
                        }
                        android.view.MotionEvent.ACTION_CANCEL -> { if (mode == 1) drag.value?.invoke(CardDrag.Cancelled); mode = 0; false }
                        else -> false
                    }
                }
                settings.javaScriptEnabled = true
                // Replay buttons post "play:q:0"; the page's JS calls KarteiBridge.post. Only our own pages load here.
                addJavascriptInterface(object {
                    @android.webkit.JavascriptInterface
                    fun post(message: String) { this@apply.post { latest.value(message) } }
                }, "KarteiBridge")
                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                        val url = request.url
                        if (url.host != "kartei.invalid") return null
                        val name = url.lastPathSegment ?: return null
                        val headers = mapOf("Access-Control-Allow-Origin" to "*")
                        return try {
                            when (url.pathSegments.firstOrNull()) {
                                "app" -> if (name.startsWith("kartei-card")) {
                                    val type = if (name.endsWith(".js")) "text/javascript" else "text/css"
                                    WebResourceResponse(type, "utf-8", 200, "OK", headers, ctx.assets.open("web/$name"))
                                } else {
                                    val res = when {
                                        name.startsWith("bricolage") -> R.font.bricolage_grotesque
                                        name.startsWith("nunito") -> R.font.nunito
                                        name.startsWith("noto_serif") -> R.font.noto_serif
                                        name.startsWith("courier") -> R.font.courier_prime
                                        name.startsWith("dm_mono") -> R.font.dm_mono
                                        else -> R.font.dm_sans
                                    }
                                    WebResourceResponse("font/ttf", null, 200, "OK", headers, ctx.resources.openRawResource(res))
                                }
                                else -> {
                                    val file = mediaFile(name, mediaFolder) ?: throw java.io.FileNotFoundException(name)
                                    val type = when (file.extension.lowercase()) {
                                        "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"; "gif" -> "image/gif"
                                        "svg" -> "image/svg+xml"; "webp" -> "image/webp"; "mp3" -> "audio/mpeg"
                                        "css" -> "text/css"; "js" -> "text/javascript"; "wav" -> "audio/wav"; "ogg" -> "audio/ogg"
                                        else -> "application/octet-stream"
                                    }
                                    WebResourceResponse(type, null, 200, "OK", headers, file.inputStream())
                                }
                            }
                        } catch (e: Exception) {
                            WebResourceResponse("text/plain", null, 404, "Not found", headers, "".byteInputStream())
                        }
                    }
                }
            }
        },
        update = { web ->
            // Percent: system font scale times the Reading page's card text size (ReadingPrefs.textZoom).
            if (web.settings.textZoom != textZoom) web.settings.textZoom = textZoom
            if (web.tag != html) {
                web.tag = html
                web.loadDataWithBaseURL("$ORIGIN/media/", html, "text/html", "utf-8", null)
            }
        },
    )
}
