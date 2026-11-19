// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.sync

import android.content.Context
import android.security.NetworkSecurityPolicy
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kartei.DeckStore
import app.kartei.core.Backend
import app.kartei.core.SyncMethods
import anki.sync.SyncCollectionResponse.ChangesRequired
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A full sync the server asked for: which directions are possible, and the media USN to carry on with. */
data class FullChoice(val uploadOk: Boolean, val downloadOk: Boolean, val serverMediaUsn: Int)

/**
 * Sync with a self-hosted Anki sync server through Anki's own backend: log in once (host key kept sealed),
 * then normal sync, a full upload or download when the server needs one, and media in the background.
 * One per process; state is Compose state so the home row and settings both follow it.
 */
object SyncCenter {
    var login by mutableStateOf<SyncLogin?>(null); private set
    /** What is happening now ("Syncing", "Logging in"…), or null when idle. */
    var busy by mutableStateOf<String?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    /** A note that is not an error, such as a server message or "Media is still syncing". */
    var note by mutableStateOf<String?>(null); private set
    var lastSync by mutableLongStateOf(0L); private set
    var choice by mutableStateOf<FullChoice?>(null); private set

    private var auth: AuthStore? = null
    private var autoStarted = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun init(context: Context) {
        if (auth != null) return
        val a = AuthStore(context.applicationContext)
        auth = a
        login = a.load()
        lastSync = if (login != null) a.lastSyncMillis else 0L
    }

    val lastServer: String get() = auth?.lastServer.orEmpty()

    fun check(raw: String): ServerCheck = checkServerUrl(raw) { host ->
        NetworkSecurityPolicy.getInstance().isCleartextTrafficPermitted(host)
    }

    private fun proto(l: SyncLogin) = anki.sync.SyncAuth.newBuilder().setHkey(l.hkey).setEndpoint(l.endpoint).build()

    fun logIn(store: DeckStore, server: String, username: String, password: String) {
        val backend = store.backend
        if (busy != null) return
        val url = when (val c = check(server)) {
            is ServerCheck.Bad -> { error = c.why; return }
            is ServerCheck.Ok -> c.url
        }
        if (username.isBlank() || password.isEmpty()) { error = "Enter your user name and password."; return }
        if (backend == null) { error = "Your collection isn't open yet. Try again in a moment."; return }
        auth?.lastServer = url
        busy = "Logging in"; error = null; note = null
        scope.launch {
            try {
                val result = backend.call(SyncMethods.syncLogin,
                    anki.sync.SyncLoginRequest.newBuilder().setUsername(username.trim()).setPassword(password).setEndpoint(url).build(),
                    anki.sync.SyncAuth.parser())
                val l = SyncLogin(username.trim(), url, result.hkey)
                auth?.save(l)
                login = l
                busy = null
                sync(store)
            } catch (e: Throwable) {
                busy = null
                error = plainSyncError(e.message ?: e.toString(), loggingIn = true)
            }
        }
    }

    fun logOut() {
        if (busy != null) return
        auth?.clear()
        login = null; lastSync = 0L; error = null; note = null; choice = null
    }

    /** Sync once per process when the collection is ready and someone is logged in. Never starts a full sync on its own. */
    fun syncOnStart(store: DeckStore) {
        if (autoStarted || login == null || store.backend == null) return
        autoStarted = true
        sync(store)
    }

    fun sync(store: DeckStore) {
        val l = login ?: return
        val backend = store.backend ?: run { error = "Your collection isn't open yet. Try again in a moment."; return }
        if (busy != null) return
        busy = "Syncing"; error = null; note = null; choice = null
        scope.launch {
            try {
                val r = backend.call(SyncMethods.syncCollection,
                    anki.sync.SyncCollectionRequest.newBuilder().setAuth(proto(l)).setSyncMedia(true).build(),
                    anki.sync.SyncCollectionResponse.parser())
                if (r.hasNewEndpoint() && r.newEndpoint.isNotBlank()) {
                    val moved = l.copy(endpoint = r.newEndpoint)
                    auth?.save(moved); login = moved
                }
                if (r.serverMessage.isNotBlank()) note = "The server says: ${r.serverMessage}"
                when (r.required) {
                    ChangesRequired.FULL_SYNC -> choice = FullChoice(true, true, r.serverMediaUsn)
                    ChangesRequired.FULL_DOWNLOAD -> choice = FullChoice(false, true, r.serverMediaUsn)
                    ChangesRequired.FULL_UPLOAD -> choice = FullChoice(true, false, r.serverMediaUsn)
                    else -> {
                        busy = "Syncing media"
                        waitForMedia(backend)
                        finished(store)
                    }
                }
            } catch (e: Throwable) {
                error = plainSyncError(e.message ?: e.toString())
            } finally {
                busy = null
            }
        }
    }

    /** Carry out the full sync the person chose. Upload replaces the server's copy, download replaces this phone's. */
    fun full(store: DeckStore, upload: Boolean) {
        val l = login ?: return
        val c = choice ?: return
        val backend = store.backend ?: return
        if (busy != null || (upload && !c.uploadOk) || (!upload && !c.downloadOk)) return
        choice = null
        busy = if (upload) "Uploading your collection" else "Downloading the server's collection"
        error = null
        scope.launch {
            try {
                backend.call(SyncMethods.fullUploadOrDownload,
                    anki.sync.FullUploadOrDownloadRequest.newBuilder().setAuth(proto(l)).setUpload(upload).setServerUsn(c.serverMediaUsn).build(),
                    anki.generic.Empty.parser())
                busy = "Syncing media"
                waitForMedia(backend)
                finished(store)
            } catch (e: Throwable) {
                error = plainSyncError(e.message ?: e.toString())
            } finally {
                busy = null
            }
        }
    }

    fun skipFull() { choice = null }

    fun stop(store: DeckStore) {
        val backend = store.backend ?: return
        scope.launch { runCatching { backend.run(SyncMethods.abortSync) }; runCatching { backend.run(SyncMethods.abortMediaSync) } }
    }

    private fun finished(store: DeckStore) {
        val now = System.currentTimeMillis()
        auth?.lastSyncMillis = now
        lastSync = now
        store.refresh()
    }

    /** Media syncs on a backend thread; wait for it so its errors reach the person. Cards are already synced by now. */
    private suspend fun waitForMedia(backend: Backend) {
        try {
            while (true) {
                val s = backend.call(SyncMethods.mediaSyncStatus, anki.generic.Empty.getDefaultInstance(), anki.sync.MediaSyncStatusResponse.parser())
                if (!s.active) return
                delay(400)
            }
        } catch (e: Throwable) {
            note = "Cards synced, but pictures and sounds didn't: " + plainSyncError(e.message ?: e.toString()).replaceFirstChar { it.lowercase() }
        }
    }
}
