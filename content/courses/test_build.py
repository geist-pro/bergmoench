#!/usr/bin/env python3
"""Checks for build_decks.py: deterministic notes, the deck repositories' GUIDs, five first-session cards per course,
typed output equal to the YAML answer. usage: python3 test_build.py"""
import hashlib, sqlite3, tempfile, zipfile, json
from pathlib import Path
import genanki
import build_decks as B
from cardlib import load_lectures

def notes(apkg: Path):
    with zipfile.ZipFile(apkg) as z, tempfile.TemporaryDirectory() as d:
        z.extract("collection.anki2", d)
        c = sqlite3.connect(Path(d) / "collection.anki2")
        rows = c.execute("select guid, flds, tags from notes").fetchall()
        media = json.loads(z.read("media"))
        c.close()
    return rows, media

with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
    B.build(Path(a)); B.build(Path(b))
    for f in B.FILES.values():
        # Zip entry times differ between runs; the notes themselves must not.
        assert sorted(notes(Path(a) / f)[0]) == sorted(notes(Path(b) / f)[0]), f"{f}: notes differ between two builds"
    for course, f in B.FILES.items():
        rows, media = notes(Path(a) / f)
        ids = {r[1].split("\x1f")[-1]: r for r in rows}
        for cid, (guid, flds, tags) in ids.items():
            assert guid == genanki.guid_for("ws2627", cid), cid
        first = [cid for cid, r in ids.items() if B.FIRST_TAG in r[2].split()]
        assert sorted(first) == sorted(B.FIRST[course]), (course, first)
        # Five notes must make exactly five cards: no multi-gap clozes in the first session.
        import re
        gaps = sum(max(1, len(set(re.findall(r"\{\{c(\d+)::", ids[c][1])))) for c in first)
        assert gaps == 5, (course, "first-session cards make", gaps, "cards")
        predicts = 0
        for _, _, data in load_lectures(course):
            for card in data.get("cards", []):
                if card.get("kind") == "predict" and not card.get("hold"):
                    flds = ids[card["id"]][1].split("\x1f")
                    assert flds[4] == B.typed_output(card["answer"]), card["id"]
                    assert flds[4] and "<pre" not in flds[4]
                    predicts += 1
        assert all(m.endswith(".webp") for m in media.values()), course
        assert not any("Fira" in m for m in media.values())
        print(f"ok {course}: {len(ids)} notes, {predicts} typed predict cards, {len(media)} figures")
print("all checks passed")
