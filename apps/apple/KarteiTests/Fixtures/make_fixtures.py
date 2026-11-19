#!/usr/bin/env python3
"""Build the two small decks the tests import (sample-01.apkg, sample-02.apkg).
Plain arithmetic, so there is nothing to license. Fixed ids and timestamp: same input, same notes.
usage: python3 make_fixtures.py   (needs genanki)"""
from pathlib import Path
import genanki

HERE = Path(__file__).resolve().parent
MODEL = genanki.Model(
    1764039001, "Sample Basic",
    fields=[{"name": "Front"}, {"name": "Back"}],
    templates=[{"name": "Card 1", "qfmt": "{{Front}}", "afmt": '{{FrontSide}}<hr id="answer">{{Back}}'}],
)


def deck(deck_id: int, name: str, cards: list[tuple[str, str]], file: str) -> None:
    d = genanki.Deck(deck_id, name)
    for i, (front, back) in enumerate(cards):
        d.add_note(genanki.Note(model=MODEL, fields=[front, back], guid=genanki.guid_for("bergmoench-sample", file, i)))
    genanki.Package(d).write_to_file(HERE / file, timestamp=1763078400)
    print(file, len(cards), "notes")


times = []
for a in range(2, 17):
    for b in range(1, 11):
        if a == 12:
            times.append((f"How many eggs are in {b} dozen?", f"<b>{a * b}</b>"))
        else:
            times.append((f"What is {a} × {b}?", f"<b>{a * b}</b>"))
deck(1764039101, "Sample::01 Times tables", times, "sample-01.apkg")
deck(1764039102, "Sample::02 Squares", [(f"What is {n} squared?", f"<b>{n * n}</b>") for n in range(1, 21)], "sample-02.apkg")
