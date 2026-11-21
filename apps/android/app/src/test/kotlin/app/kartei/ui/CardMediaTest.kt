// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
package app.kartei.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class CardMediaTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun mediaRequestsStayInsideTheMediaFolder() {
        val media = File(tmp.root, "collection.media").apply { mkdirs() }
        File(tmp.root, "collection.anki2").writeText("private")
        File(media, "fig 1.png").writeText("png")
        assertEquals(File(media, "fig 1.png"), mediaFile("fig 1.png", media))
        // what a card's "..%2Fcollection.anki2" arrives as
        for (name in listOf("../collection.anki2", "..", ".", "", "a/b.png", "../../x")) assertNull(name, mediaFile(name, media))
    }
}
