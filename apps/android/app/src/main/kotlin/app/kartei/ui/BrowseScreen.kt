// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.kartei.BrowseRow
import app.kartei.DeckStore
import app.kartei.Insights
import app.kartei.Phase
import app.kartei.Timing
import app.kartei.browseRow
import app.kartei.searchCardIds
import app.kartei.setFlag
import app.kartei.setSuspended
import app.kartei.timing
import app.kartei.useBrowserColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** One queue for row reads, so a fast scroll doesn't flood the backend with parallel calls. */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
private val rowReads = Dispatchers.IO.limitedParallelism(1)

/** Browse: Anki search syntax, quick filters, a result list with flag and suspend, and card info on tap. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BrowseScreen(store: DeckStore) {
    var text by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf<Insights.Filter?>(Insights.Filter.DueToday) }
    var ids by remember { mutableStateOf<List<Long>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var timing by remember { mutableStateOf<Timing?>(null) }
    val rows = remember { mutableStateMapOf<Long, BrowseRow>() }
    var open by remember { mutableStateOf<Long?>(null) }
    var actions by remember { mutableStateOf<Long?>(null) }
    var generation by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    val search = Insights.buildSearch(text, filter)

    LaunchedEffect(store.phase, search, generation) {
        val backend = store.backend ?: return@LaunchedEffect
        if (store.phase != Phase.Ready) return@LaunchedEffect
        delay(300)
        withContext(Dispatchers.IO) {
            runCatching {
                backend.useBrowserColumns()
                timing = backend.timing()
                backend.searchCardIds(search)
            }.onSuccess { ids = it; error = null; rows.clear() }
             .onFailure { error = it.message ?: "That search didn't work." }
        }
    }

    fun reload(id: Long) {
        val backend = store.backend ?: return
        val t = timing ?: return
        scope.launch(rowReads) { runCatching { backend.browseRow(id, t) }.onSuccess { rows[id] = it } }
    }
    fun act(block: (app.kartei.core.Backend) -> Unit, id: Long) {
        val backend = store.backend ?: return
        scope.launch(Dispatchers.IO) { runCatching { block(backend) }; reload(id); store.refresh() }
    }

    val current = open
    if (current != null) {
        BackHandler { open = null; reload(current) }
        CardInfoScreen(store, current, close = { open = null; reload(current) })
        return
    }

    Column(Modifier.fillMaxSize().background(Ink.bg).systemBarsPadding().imePadding().padding(horizontal = 20.dp)) {
        KTitle("Browse")
        SearchField(text) { text = it }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (f in Insights.Filter.entries) {
                val on = f == filter
                Box(
                    Modifier.heightIn(min = 48.dp).semantics { selected = on }.clickable(role = Role.Tab) { filter = if (on) null else f }, contentAlignment = Alignment.Center,
                ) {
                    BasicText(f.label, style = kBody(14, 500, if (on) Ink.bg else Ink.text),
                        modifier = Modifier.background(if (on) Ink.text else Color.Transparent, RoundedCornerShape(16.dp))
                            .border(1.dp, if (on) Ink.text else Ink.control, RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 7.dp))
                }
            }
        }
        val list = ids
        val n = list?.size ?: 0
        BasicText(when {
            error != null -> "Anki couldn't read that search: $error"
            list == null -> "Searching…"
            n == 0 -> if (search.isBlank()) "No cards yet. Import a deck from the Decks tab." else "No cards match ${search.ifBlank { "this" }}."
            else -> "$n ${if (n == 1) "card" else "cards"}, sorted by due" + if (search.isNotBlank()) " · $search" else ""
        }, style = kBody(13, color = if (error != null) Ink.forgot else Ink.muted), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 4.dp))
        KRule()
        LazyColumn(Modifier.weight(1f)) {
            items(list.orEmpty(), key = { it }) { id ->
                val row = rows[id]
                if (row == null) {
                    LaunchedEffect(id, timing) { reload(id) }
                    Box(Modifier.fillMaxWidth().height(64.dp))
                    KRule()
                } else {
                    ResultRow(row,
                        onOpen = { open = id },
                        onActions = { actions = if (actions == id) null else id },
                        onFlag = { f -> act({ it.setFlag(id, if (row.flag == f) 0 else f) }, id) },
                        onSuspend = { act({ it.setSuspended(id, row.state != Insights.State.Suspended) }, id) })
                    if (actions == id) ActionStrip(row,
                        onFlag = { f -> act({ it.setFlag(id, f) }, id) },
                        onSuspend = { act({ it.setSuspended(id, row.state != Insights.State.Suspended) }, id); actions = null })
                }
            }
        }
    }
}

@Composable
private fun SearchField(text: String, onChange: (String) -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).background(Ink.surface2, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
        if (text.isEmpty()) BasicText("Search, e.g. deck:Biology tag:exam", style = kBody(15, color = Ink.muted))
        BasicTextField(text, onChange, singleLine = true, textStyle = kBody(15).copy(fontFamily = Type.data), cursorBrush = SolidColor(Ink.accent),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search cards, Anki search syntax" })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ResultRow(row: BrowseRow, onOpen: () -> Unit, onActions: () -> Unit, onFlag: (Int) -> Unit, onSuspend: () -> Unit) {
    val suspended = row.state == Insights.State.Suspended
    val flagName = KFlagNames.getOrNull(row.flag - 1)
    Column(
        Modifier.combinedClickable(onClickLabel = "Card info", onLongClickLabel = "Flag or suspend", onLongClick = onActions, onClick = onOpen)
            .semantics(mergeDescendants = true) {
                contentDescription = "${row.question}. ${row.deck}. ${row.state.label}, due ${row.due}" + (flagName?.let { ". $it flag" } ?: "")
                customActions = listOf(
                    CustomAccessibilityAction(if (suspended) "Unsuspend" else "Suspend") { onSuspend(); true },
                    CustomAccessibilityAction(if (row.flag == 1) "Remove red flag" else "Flag red") { onFlag(1); true },
                    CustomAccessibilityAction("Flag or suspend…") { onActions(); true },
                )
            },
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clickable(role = Role.Button, onClickLabel = "Flag or suspend", onClick = onActions), contentAlignment = Alignment.CenterStart) {
                KFlagMark(row.flag)
            }
            Column(Modifier.weight(1f)) {
                BasicText(row.question.ifBlank { "(empty question)" }, style = kBody(15, 500, if (suspended) Ink.muted else Ink.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicText(row.deck, style = kBody(13, color = Ink.muted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Column(Modifier.padding(start = 10.dp), horizontalAlignment = Alignment.End) {
                BasicText(row.due, style = kBody(14, 500, if (suspended) Ink.muted else Ink.text))
                BasicText(row.state.label, style = kBody(13, color = stateColour(row.state)))
            }
        }
        KRule()
    }
}

internal fun stateColour(s: Insights.State) = when (s) {
    Insights.State.New -> Ink.new
    Insights.State.Learning, Insights.State.Relearning -> Ink.learning
    else -> Ink.muted
}

/** Seven flags, no flag, and suspend / unsuspend: shown under a row after a long press or a tap on its flag square. */
@Composable
internal fun ActionStrip(row: BrowseRow, onFlag: (Int) -> Unit, onSuspend: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Ink.surface2).padding(horizontal = 8.dp, vertical = 4.dp)) {
        KFlagGrid(row.flag, Modifier.padding(8.dp), onFlag = onFlag)
        val suspended = row.state == Insights.State.Suspended
        KLink(if (suspended) "Unsuspend: bring it back into reviews" else "Suspend: leave it out of reviews", Modifier.padding(start = 8.dp), onClick = onSuspend)
    }
}
