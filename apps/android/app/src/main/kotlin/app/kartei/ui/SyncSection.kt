// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import app.kartei.DeckStore
import app.kartei.Phase
import app.kartei.sync.ANKIWEB_REFUSAL
import app.kartei.sync.FullChoice
import app.kartei.sync.SyncCenter
import app.kartei.sync.syncedAgo
import java.time.ZoneId
import kotlinx.coroutines.delay

/** Ticks once a minute so "Synced N min ago" stays true. */
@Composable
private fun rememberNow(): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }
    return now
}

private fun statusLine(now: Long): String = when {
    SyncCenter.busy != null -> SyncCenter.busy + "…"
    SyncCenter.choice != null -> "Waiting for your choice of copy"
    else -> syncedAgo(SyncCenter.lastSync.takeIf { it > 0 }, now, ZoneId.systemDefault())
}

/** Settings → Sync: self-hosted Anki sync server only. */
@Composable
fun SyncSection(store: DeckStore) {
    val context = LocalContext.current
    remember { SyncCenter.init(context) }
    val login = SyncCenter.login
    val busy = SyncCenter.busy
    ReachHeading("Sync")
    if (login == null) {
        var server by rememberSaveable { mutableStateOf(SyncCenter.lastServer) }
        var user by rememberSaveable { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        ReachNote("Keep this phone and your other Anki apps in step through your own Anki sync server: the one built into Anki desktop, or a separate install of it. $ANKIWEB_REFUSAL")
        ReachField("Server address", server, { server = it }, placeholder = "https://sync.example.org/", keyboard = KeyboardType.Uri)
        ReachField("User name", user, { user = it })
        ReachField("Password", password, { password = it }, secret = true, keyboard = KeyboardType.Password)
        Row(Modifier.padding(top = 16.dp)) {
            ReachButton(if (busy != null) "$busy…" else "Log in", primary = true, enabled = busy == null && store.phase == Phase.Ready) {
                SyncCenter.logIn(store, server, user, password)
                password = ""
            }
        }
        ReachNote("Bergmönch keeps only a login key from the server, encrypted on this phone. Your password is not stored.")
    } else {
        val now = rememberNow()
        ReachNote("Logged in as ${login.username} on ${login.endpoint}", color = Ink.text)
        ReachNote(statusLine(now))
        Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (busy == null) {
                ReachButton("Sync now", primary = true, enabled = store.phase == Phase.Ready) { SyncCenter.sync(store) }
                ReachButton("Log out") { SyncCenter.logOut() }
            } else {
                ReachButton("Stop") { SyncCenter.stop(store) }
            }
        }
        ReachNote("Bergmönch syncs when it starts and when you tap Sync now. Pictures and sounds sync after the cards.")
        SyncCenter.choice?.let { FullSyncDialog(store, it) }
    }
    SyncCenter.error?.let { ReachNote(it, color = Ink.learning) }
    SyncCenter.note?.let { ReachNote(it) }
}

/** Shown when the server needs a one-way sync. Nothing is replaced without the person choosing which copy to keep. */
@Composable
fun FullSyncDialog(store: DeckStore, choice: FullChoice) {
    Dialog(onDismissRequest = { SyncCenter.skipFull() }) {
        Column(Modifier.fillMaxWidth().background(Ink.bg, RoundedCornerShape(8.dp)).padding(20.dp)) {
            BasicText(if (choice.uploadOk && choice.downloadOk) "Choose which copy to keep" else if (choice.uploadOk) "Send this phone's copy to the server" else "Get the server's copy",
                style = reachText(20, 700))
            val why = when {
                choice.uploadOk && choice.downloadOk ->
                    "This phone and the server can't be merged this time. That happens on the first sync, or after note types changed on one side. The copy you keep replaces the other one; reviews made only in the other copy are lost."
                choice.uploadOk -> "The server has no cards yet, so it takes this phone's collection."
                else -> "This phone has no cards yet, so it takes the server's collection."
            }
            ReachNote(why)
            Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (choice.uploadOk) ReachButton("Keep this phone's copy (upload)", primary = !choice.downloadOk, modifier = Modifier.fillMaxWidth()) { SyncCenter.full(store, upload = true) }
                if (choice.downloadOk) ReachButton("Keep the server's copy (download)", primary = !choice.uploadOk, modifier = Modifier.fillMaxWidth()) { SyncCenter.full(store, upload = false) }
                ReachButton("Not now", modifier = Modifier.fillMaxWidth()) { SyncCenter.skipFull() }
            }
        }
    }
}

/**
 * Home top row: sync state as a quiet link between the date and "Import deck"; tap to sync.
 * Also starts the sync-on-launch once the collection is open. Shows nothing when no server is set up.
 */
@Composable
fun SyncStatusLink(store: DeckStore, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    remember { SyncCenter.init(context) }
    LaunchedEffect(store.phase) { if (store.phase == Phase.Ready) SyncCenter.syncOnStart(store) }
    if (SyncCenter.login == null) return
    var ask by remember { mutableStateOf(false) }
    val now = rememberNow()
    val label = when {
        SyncCenter.busy != null -> "Syncing…"
        SyncCenter.choice != null -> "Sync needs a choice"
        SyncCenter.error != null -> "Couldn't sync"
        else -> syncedAgo(SyncCenter.lastSync.takeIf { it > 0 }, now, ZoneId.systemDefault())
    }
    val color = if (SyncCenter.error != null || SyncCenter.choice != null) Ink.learning else Ink.muted
    BasicText(label, maxLines = 1, style = reachText(13, 500, color).copy(textDecoration = if (SyncCenter.busy == null) TextDecoration.Underline else null),
        modifier = modifier.heightIn(min = 48.dp).clickable(enabled = SyncCenter.busy == null, role = Role.Button, onClickLabel = "Sync now") {
            if (SyncCenter.choice != null) ask = true else SyncCenter.sync(store)
        }.padding(start = 12.dp).wrapContentHeight())
    val choice = SyncCenter.choice
    if (ask && choice != null) FullSyncDialog(store, choice)
    if (choice == null && ask) ask = false
}
