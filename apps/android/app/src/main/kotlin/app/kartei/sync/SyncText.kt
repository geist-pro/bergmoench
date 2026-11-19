// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.sync

import java.net.URI
import java.net.URISyntaxException
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/** Pure sync helpers (no Android types), so they can be unit-tested on the JVM. */

const val ANKIWEB_REFUSAL =
    "Bergmönch can't sync with AnkiWeb: its terms allow only Anki's own apps. Use your own Anki sync server instead."

sealed interface ServerCheck {
    data class Ok(val url: String) : ServerCheck
    data class Bad(val why: String) : ServerCheck
}

/** Hosts on this device or the local network, where a missing scheme most likely means plain http. */
internal fun isLocalHost(host: String): Boolean {
    val h = host.lowercase().trim('[', ']')
    if (h == "localhost" || h.endsWith(".local") || h.endsWith(".lan") || h.endsWith(".home.arpa")) return true
    if (h == "::1" || h.startsWith("fe80:") || h.startsWith("fd") && h.contains(':')) return true
    val parts = h.split('.').map { it.toIntOrNull() }
    if (parts.size != 4 || parts.any { it == null || it !in 0..255 }) return false
    val (a, b) = parts[0]!! to parts[1]!!
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b in 16..31) || (a == 169 && b == 254)
}

/**
 * Check and normalise a sync server address. A missing scheme becomes http:// for local hosts and https:// otherwise;
 * the result always ends in "/" because the backend resolves "sync/…" relative to it.
 * [cleartextAllowed] reports whether plain http may be used for a host (Android's network security config).
 */
fun checkServerUrl(raw: String, cleartextAllowed: (String) -> Boolean): ServerCheck {
    val text = raw.trim()
    if (text.isEmpty()) return ServerCheck.Bad("Enter the address of your sync server.")
    if (text.any { it.isWhitespace() }) return ServerCheck.Bad("The address can't contain spaces.")
    val withScheme = if ("://" in text) text else {
        val host = text.substringBefore('/').let { if (it.startsWith("[")) it.substringBefore(']') + "]" else it.substringBefore(':') }
        (if (isLocalHost(host)) "http://" else "https://") + text
    }
    val uri = try { URI(withScheme) } catch (_: URISyntaxException) {
        return ServerCheck.Bad("That doesn't look like a web address. Example: https://sync.example.org/")
    }
    val scheme = uri.scheme?.lowercase()
    if (scheme != "http" && scheme != "https") return ServerCheck.Bad("The address must start with http:// or https://.")
    val host = uri.host?.lowercase()
    if (host.isNullOrEmpty()) return ServerCheck.Bad("That doesn't look like a web address. Example: https://sync.example.org/")
    if (host == "ankiweb.net" || host.endsWith(".ankiweb.net")) return ServerCheck.Bad(ANKIWEB_REFUSAL)
    if (uri.rawUserInfo != null) return ServerCheck.Bad("Leave the user name out of the address and enter it below.")
    if (uri.rawQuery != null || uri.rawFragment != null) return ServerCheck.Bad("Leave out anything after ? or # in the address.")
    if (scheme == "http" && !cleartextAllowed(host.trim('[', ']')))
        return ServerCheck.Bad("Plain http would send your password unencrypted. Use an https:// address.")
    val path = uri.rawPath.orEmpty().let { if (it.endsWith("/")) it else "$it/" }
    val port = if (uri.port == -1) "" else ":${uri.port}"
    val hostPart = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
    return ServerCheck.Ok("$scheme://$hostPart$port$path")
}

/** "Synced just now", "Synced 12 min ago", "Synced 3 h ago", "Synced yesterday", "Synced on 3 Nov"; "Not synced yet". */
fun syncedAgo(lastMillis: Long?, nowMillis: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String {
    if (lastMillis == null || lastMillis <= 0) return "Not synced yet"
    val seconds = (nowMillis - lastMillis) / 1000
    if (seconds < 60) return "Synced just now"
    val minutes = seconds / 60
    if (minutes < 60) return "Synced $minutes min ago"
    val then = Instant.ofEpochMilli(lastMillis).atZone(zone).toLocalDate()
    val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
    val days = ChronoUnit.DAYS.between(then, today)
    if (days == 0L || minutes < 6 * 60) return "Synced ${minutes / 60} h ago"
    if (days == 1L) return "Synced yesterday"
    val pattern = if (then.year == today.year) "d MMM" else "d MMM yyyy"
    return "Synced on " + then.format(DateTimeFormatter.ofPattern(pattern, locale))
}

/**
 * Turn the backend's (English, AnkiWeb-flavoured) error text into plain language about the person's own server.
 * [loggingIn] distinguishes a rejected password from a stored login the server no longer accepts.
 */
fun plainSyncError(message: String, loggingIn: Boolean = false): String {
    val m = message.lowercase()
    return when {
        "password was incorrect" in m || "403" in m && "forbidden" in m ->
            if (loggingIn) "The server didn't accept that user name and password."
            else "The server no longer accepts this login. Log out and log in again."
        "invalid sync server" in m || "relative url" in m || "invalid url" in m && "scheme" !in m ->
            "That server address isn't valid. Check it in Settings."
        "scheme is not http" in m || "invalid url, scheme" in m ->
            "This build of Bergmönch can't use https yet. Use an http:// address on your own network."
        "certificate" in m || "tls" in m || "ssl" in m ->
            "The server's security certificate isn't trusted. Check the server's https setup."
        "timed out" in m || "timeout" in m ->
            "The server took too long to answer. Try again; if it keeps happening, check the server."
        "internet connection" in m || "refused" in m || "unreachable" in m || "dns" in m || "network error occurred" in m ->
            "Can't reach the server. Check that you're online and that the server is running."
        "encountered a problem" in m || "server error" in m ->
            "The server ran into a problem. Try again in a few minutes."
        "too old" in m -> "The server needs a newer sync version than this Bergmönch build has."
        "clock" in m -> "Your phone's clock is off. Set the correct time, then sync again."
        "check database" in m || "sanity" in m ->
            "This phone and the server ended up with different copies. Sync again; if it keeps happening, report it to Bergmönch."
        "sync again" in m -> "Sync again to finish."
        "interrupted" in m || "cancel" in m -> "Sync stopped before it finished."
        "collection not open" in m || "collectionnotopen" in m -> "Your collection isn't open yet. Try again in a moment."
        else -> "Sync didn't finish. The server said: ${message.lineSequence().firstOrNull()?.take(160) ?: message}"
    }
}
