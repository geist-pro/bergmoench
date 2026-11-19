// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.sync

import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncTextTest {
    private val anyHttp: (String) -> Boolean = { true }
    private val noHttp: (String) -> Boolean = { false }
    private fun ok(raw: String, http: (String) -> Boolean = anyHttp) = (checkServerUrl(raw, http) as ServerCheck.Ok).url
    private fun bad(raw: String, http: (String) -> Boolean = anyHttp) = (checkServerUrl(raw, http) as ServerCheck.Bad).why

    @Test fun normalisesAddresses() {
        assertEquals("https://sync.example.org/", ok("https://sync.example.org"))
        assertEquals("https://sync.example.org/", ok("  sync.example.org  "))
        assertEquals("https://example.org/anki/", ok("example.org/anki"))
        assertEquals("http://10.0.2.2:27703/", ok("10.0.2.2:27703"))
        assertEquals("http://192.168.1.20:8080/", ok("192.168.1.20:8080/"))
        assertEquals("http://localhost:27701/", ok("localhost:27701"))
        assertEquals("http://nas.local/", ok("nas.local"))
        assertEquals("https://Sync.Example.org/".lowercase(), ok("HTTPS://Sync.Example.org"))
        assertEquals("http://[::1]:8080/", ok("http://[::1]:8080"))
        assertEquals("https://8.8.8.8/", ok("8.8.8.8"))
    }

    @Test fun refusesBadAddresses() {
        assertTrue(bad("").startsWith("Enter"))
        assertTrue(bad("my server").contains("spaces"))
        assertEquals(ANKIWEB_REFUSAL, bad("https://ankiweb.net"))
        assertEquals(ANKIWEB_REFUSAL, bad("sync.ankiweb.net"))
        assertEquals(ANKIWEB_REFUSAL, bad("https://SYNC2.AnkiWeb.net/"))
        assertTrue(bad("ftp://example.org").contains("http://"))
        assertTrue(bad("https://user@example.org").contains("user name"))
        assertTrue(bad("https://example.org/?x=1").contains("?"))
        assertTrue(bad("https://example.org/#top").contains("#"))
        assertTrue(bad("http://").isNotEmpty())
    }

    @Test fun plainHttpOnlyWherePolicyAllows() {
        assertTrue(bad("http://10.0.2.2:27703", noHttp).contains("unencrypted"))
        assertTrue(bad("10.0.2.2:27703", noHttp).contains("unencrypted"))
        assertEquals("https://example.org/", ok("https://example.org", noHttp))
        assertEquals("http://10.0.2.2:27703/", ok("10.0.2.2:27703") { it == "10.0.2.2" })
        assertTrue(bad("http://example.org") { it == "10.0.2.2" }.contains("unencrypted"))
    }

    @Test fun localHosts() {
        for (h in listOf("10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.0.1", "127.0.0.1", "localhost", "box.lan", "x.home.arpa"))
            assertTrue(h, isLocalHost(h))
        for (h in listOf("172.32.0.1", "8.8.8.8", "example.org", "256.1.1.1", "192.169.0.1"))
            assertTrue(h, !isLocalHost(h))
    }

    private val zone = ZoneId.of("Europe/Berlin")
    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int) = LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant().toEpochMilli()

    @Test fun syncedAgoWording() {
        val now = at(2026, 11, 14, 12, 0)
        fun ago(t: Long?) = syncedAgo(t, now, zone, Locale.UK)
        assertEquals("Not synced yet", ago(null))
        assertEquals("Not synced yet", ago(0))
        assertEquals("Synced just now", ago(now - 59_000))
        assertEquals("Synced just now", ago(now + 5_000)) // clock skew
        assertEquals("Synced 1 min ago", ago(now - 60_000))
        assertEquals("Synced 59 min ago", ago(now - 59 * 60_000))
        assertEquals("Synced 1 h ago", ago(now - 60 * 60_000))
        assertEquals("Synced 11 h ago", ago(at(2026, 11, 14, 0, 30)))
        // Last night, under six hours ago: hours read better than "yesterday".
        assertEquals("Synced 3 h ago", syncedAgo(at(2026, 11, 13, 23, 0), at(2026, 11, 14, 2, 0), zone, Locale.UK))
        assertEquals("Synced yesterday", ago(at(2026, 11, 13, 9, 0)))
        assertEquals("Synced on 3 Nov", ago(at(2026, 11, 3, 9, 0)))
        assertEquals("Synced on 3 Nov 2025", ago(at(2025, 11, 3, 9, 0)))
    }

    @Test fun plainErrors() {
        assertEquals("The server didn't accept that user name and password.", plainSyncError("Email or password was incorrect; please try again.", loggingIn = true))
        assertTrue(plainSyncError("Email or password was incorrect; please try again.").contains("Log out and log in again"))
        assertTrue(plainSyncError("Please check your internet connection.").startsWith("Can't reach the server"))
        assertTrue(plainSyncError("A network error occurred.\n\nError details: error sending request: Connection refused (os error 111)").startsWith("Can't reach"))
        assertTrue(plainSyncError("Connection timed out. Please try again.").contains("too long"))
        assertTrue(plainSyncError("AnkiWeb encountered a problem. Please try again in a few minutes.").contains("server ran into a problem"))
        assertTrue(plainSyncError("Unable to sync - your clock is not set to the correct time.").contains("clock"))
        assertTrue(plainSyncError("Invalid sync server specified. Please check the preferences.").contains("address"))
        assertTrue(plainSyncError("A network error occurred.\n\nError details: builder error: invalid URL, scheme is not http").contains("https"))
        val other = plainSyncError("weird thing\nsecond line")
        assertEquals("Sync didn't finish. The server said: weird thing", other)
        // Never sends people to AnkiWeb.
        for (m in listOf("AnkiWeb encountered a problem.", "Email or password was incorrect")) assertTrue(!plainSyncError(m).contains("AnkiWeb"))
    }

    @Test fun loginRoundTrip() {
        val l = SyncLogin("kai|x", "http://10.0.2.2:27703/", "abc123")
        assertEquals(l, SyncLogin.decode(l.encode()))
        assertTrue(!l.encode().contains("abc123"))
        assertNull(SyncLogin.decode("garbage"))
        assertNull(SyncLogin.decode(""))
        assertNull(SyncLogin("u", "e", "").encode().let(SyncLogin::decode))
    }
}
