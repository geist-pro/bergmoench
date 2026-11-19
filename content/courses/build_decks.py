#!/usr/bin/env python3
"""Build the course decks bundled with Bergmönch from the public deck repositories (src/, see sync_decks.sh).

Same cards and the same GUIDs as the decks' own Anki build (genanki.guid_for("ws2627", id)), so a card is the
same card in both. Own note types: flat templates (meta line, prompt, code, <hr id=answer>, answer) styled only through the
app's CSS custom properties (--k-*), with fallbacks so the cards still read in Anki. Predict cards ask for the
exact console output as a typed answer. Figures are re-encoded as WebP.

usage: python3 build_decks.py [--out DIR]   (default: out/)
"""
from __future__ import annotations

import argparse
import html
import io
import sys
from pathlib import Path

import genanki
from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"
sys.path.insert(0, str(SRC / "tools"))
import cardlib  # noqa: E402  (from the deck repositories; its paths resolve inside src/)
from cardlib import code_html, load_lectures, md, output_html, stable_id  # noqa: E402

# ---------------------------------------------------------------- fixed IDs (never change)
MODEL_BASIC = 1764031201
MODEL_CLOZE = 1764031202
MODEL_CODE = 1764031203

# Five cards from lecture 1 per course for the guided first session (tag bergmoench::first), in the order shown.
FIRST = {
    "gdp": ["gdp-vl01-010", "gdp-vl01-001", "gdp-vl01-012", "gdp-vl01-016", "gdp-vl01-002"],
    "gdp-en": ["gdp-en-vl01-010", "gdp-en-vl01-001", "gdp-en-vl01-012", "gdp-en-vl01-016", "gdp-en-vl01-002"],
    "coopsys": ["cs-vl01-009", "cs-vl01-007", "cs-vl01-014", "cs-vl01-018", "cs-vl01-028"],
}
FIRST_TAG = "bergmoench::first"

# Deck file name per course, shared with the apps' course catalogue.
FILES = {"gdp": "course-gdp.apkg", "gdp-en": "course-gdp-en.apkg", "coopsys": "course-coopsys.apkg"}

CSS = r"""
/* Bergmönch course cards. Colours and faces come from the app (--k-*); the fallbacks are GEIST dark/light. */
.card { --t: var(--k-text, #1b2433); --m: var(--k-muted, #55617a); --r: var(--k-rule, #cfd6e4);
  --s: var(--k-surface, #eef1f7); --acc: var(--k-accent-rule, #0b7fb0); --new: var(--k-new, #0b6f9c);
  --lrn: var(--k-learning, #9a5a12); --code: var(--k-font-code, "Courier Prime", ui-monospace, Menlo, monospace);
  font-family: var(--k-font-body, "Noto Serif", Georgia, serif); color: var(--t); background: var(--k-bg, #fafbfd);
  font-size: 20px; line-height: 1.4; text-align: left; margin: 0; padding: 16px; }
.card.nightMode, .nightMode .card { --t: var(--k-text, #f4f7fb); --m: var(--k-muted, #aab7d2); --r: var(--k-rule, #26335a);
  --s: var(--k-surface, #121b30); --acc: var(--k-accent-rule, #29b7ea); --new: var(--k-new, #6fcdf2);
  --lrn: var(--k-learning, #f2a865); background: var(--k-bg, #0b1220); }
.bm-meta { display: block; font: 400 13px/18px var(--k-font-body, Georgia, serif); color: var(--m); margin: 0 0 12px;
  letter-spacing: 0; }
.bm-meta span + span::before { content: " · "; }
.bm-q p { margin: 0 0 .4em; }
.bm-q strong, .bm-a strong { font-weight: 700; }
.bm-a p { margin: 0 0 .5em; }
.bm-x { margin-top: 16px; padding-top: 12px; border-top: 1px solid var(--r); font: 400 16px/24px var(--k-font-body, Georgia, serif);
  color: var(--t); }
.bm-x p { margin: 0 0 .4em; } .bm-x p:last-child { margin-bottom: 0; }
.bm-src { margin-top: 12px; font: 400 13px/18px var(--k-font-body, Georgia, serif); color: var(--m); }
.bm-fig { margin: 16px 0 4px; }
.bm-fig img { max-width: 100%; max-height: 360px; border-radius: 2px; background: #fff; }
ul { margin: .3em 0; padding-left: 1.2em; } li { margin: .15em 0; }
code { font-family: var(--code); font-size: .9em; font-weight: 400; letter-spacing: 0; }
pre.code, pre.out { font-family: var(--code); font-size: 15px; line-height: 22px; font-weight: 400; letter-spacing: 0;
  margin: 16px 0 0; padding: 12px 14px; overflow-x: auto; white-space: pre; border-radius: 2px; text-wrap: nowrap; }
pre.code { background: var(--s); color: var(--t); border-left: 2px solid var(--acc); }
pre.out { background: transparent; color: var(--t); border: 1px solid var(--r); }
pre.out::before { content: attr(data-label); display: block; font: 400 13px/18px var(--k-font-body, Georgia, serif);
  color: var(--m); margin-bottom: 4px; }
.cloze { font-weight: 700; color: var(--t); border-bottom: 2px solid var(--acc); }
pre.code .cloze { font-weight: 700; }
/* Java tokens (Pygments short classes): keywords in the accent, strings, numbers, comments muted. */
pre.code .k, pre.code .kd, pre.code .kt, pre.code .kr, pre.code .kn, pre.code .kc, pre.code .kp { color: var(--acc); font-weight: 700; }
pre.code .s, pre.code .s1, pre.code .s2, pre.code .sc, pre.code .se { color: var(--lrn); }
pre.code .mi, pre.code .mf, pre.code .m, pre.code .il { color: var(--new); }
pre.code .c, pre.code .c1, pre.code .cm, pre.code .cs { color: var(--m); font-style: italic; }
pre.code .nc, pre.code .nn, pre.code .nf, pre.code .na { color: var(--t); font-weight: 700; }
pre.code .err { border: none; }
pre.code .ln { color: var(--m); margin-right: 14px; user-select: none; }
"""

META = '<div class="bm-meta">{{Header}}</div>'
FIG_FRONT = '{{#Figure}}<div class="bm-fig">{{Figure}}</div>{{/Figure}}'
FIG_BACK = ('{{#FigureBack}}<div class="bm-fig">{{FigureBack}}</div>{{/FigureBack}}'
            '{{^FigureBack}}' + FIG_FRONT + '{{/FigureBack}}')
TAIL = ('{{#Extra}}<div class="bm-x">{{Extra}}</div>{{/Extra}}'
        '{{#Source}}<div class="bm-src">{{Source}}</div>{{/Source}}')

BASIC = genanki.Model(
    MODEL_BASIC, "Bergmönch Karte",
    fields=[{"name": n} for n in ["Front", "Back", "Extra", "Figure", "FigureBack", "Header", "Source", "ID"]],
    templates=[{
        "name": "Karte",
        "qfmt": f'{META}<div class="bm-q">{{{{Front}}}}</div>{FIG_FRONT}',
        "afmt": f'{META}<div class="bm-q">{{{{Front}}}}</div>{FIG_BACK}<hr id=answer><div class="bm-a">{{{{Back}}}}</div>{TAIL}',
    }],
    css=CSS,
)

CLOZE = genanki.Model(
    MODEL_CLOZE, "Bergmönch Lückentext",
    fields=[{"name": n} for n in ["Text", "Extra", "Figure", "FigureBack", "Header", "Source", "ID"]],
    templates=[{
        "name": "Lücke",
        "qfmt": f'{META}<div class="bm-q">{{{{cloze:Text}}}}</div>{FIG_FRONT}',
        "afmt": f'{META}<div class="bm-q">{{{{cloze:Text}}}}</div>{FIG_BACK}<hr id=answer>{TAIL}',
    }],
    css=CSS,
    model_type=genanki.Model.CLOZE,
)

# Output: the exact console output as plain text, only on predict cards; it switches on the typed answer.
CODE = genanki.Model(
    MODEL_CODE, "Bergmönch Code",
    fields=[{"name": n} for n in ["Prompt", "Code", "Answer", "Explanation", "Output", "Header", "Source", "ID"]],
    templates=[{
        "name": "Code",
        "qfmt": f'{META}<div class="bm-q">{{{{Prompt}}}}</div>{{{{Code}}}}{{{{#Output}}}}{{{{type:Output}}}}{{{{/Output}}}}',
        "afmt": (f'{META}<div class="bm-q">{{{{Prompt}}}}</div>{{{{Code}}}}<hr id=answer>'
                 '{{#Output}}{{type:Output}}{{/Output}}<div class="bm-a">{{Answer}}</div>'
                 '{{#Explanation}}<div class="bm-x">{{Explanation}}</div>{{/Explanation}}'
                 '{{#Source}}<div class="bm-src">{{Source}}</div>{{/Source}}'),
    }],
    css=CSS,
)

KIND_LABEL = {
    "de": {"predict": "Was gibt es aus?", "bug": "Finde den Fehler", "fill": "Ergänze den Code",
           "error": "Fehlermeldung", "cloze": "Lücke", "figure": "Abbildung", "basic": "Frage"},
    "en": {"predict": "Predict the output", "bug": "Spot the bug", "fill": "Complete the code",
           "error": "Error message", "cloze": "Cloze", "figure": "Figure", "basic": "Question"},
}


class StableNote(genanki.Note):
    @property
    def guid(self):
        return genanki.guid_for("ws2627", self.fields[-1])  # ID is always the last field, as in the decks' own build


def typed_output(text) -> str:
    """Plain console output for {{type:Output}}: line ends trimmed, lines joined by <br> (Anki compares them as spaces)."""
    lines = [l.rstrip() for l in str(text).rstrip().split("\n")]
    return "<br>".join(html.escape(l, quote=False) for l in lines)


class Figures:
    """The card figures from the deck repositories (figures/*.png), re-encoded as WebP."""

    def __init__(self, out_media: Path):
        self.out = out_media
        self.out.mkdir(parents=True, exist_ok=True)

    def _webp(self, name: str | None) -> str | None:
        if not name:
            return None
        src = cardlib.FIGS / name
        if not src.exists():
            raise FileNotFoundError(f"{name}: run sync_decks.sh")
        target = self.out / (Path(name).stem + ".webp")
        if not target.exists():
            img = Image.open(src).convert("RGB")
            if img.width > 1400:
                img = img.resize((1400, round(img.height * 1400 / img.width)), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, "WEBP", quality=82, method=6)
            target.write_bytes(buf.getvalue())
        return target.name

    def pair(self, card: dict) -> tuple[str | None, str | None]:
        front, back = cardlib.figures(card)
        return self._webp(front), self._webp(back)


def img(name: str | None) -> str:
    return f'<img src="{name}">' if name else ""


def header_html(lec: dict, label: str) -> str:
    return f'<span>{html.escape(lec["header"])}</span><span>{html.escape(label)}</span>'


def build_note(course: str, lec: dict, card: dict, figs: Figures, media: set[str]):
    lang = lec["lang"]
    labels = KIND_LABEL[lang]
    fig_f, fig_b = figs.pair(card)
    media.update(x for x in (fig_f, fig_b) if x)
    src = html.escape(card.get("source", ""))
    t, kind = card["type"], card.get("kind")
    label = card.get("label") or labels.get(kind or ("figure" if fig_b else t), labels["basic"])
    head = header_html(lec, label)
    tag = cardlib.COURSES[course]["tag"]
    tags = [f"{tag}::{lec['id'][len(course) + 1:].upper()}", f"typ::{kind or t}"]
    tags += [str(x).replace(" ", "_") for x in card.get("tags", [])]
    if card["id"] in FIRST[course]:
        tags.append(FIRST_TAG)
    if t == "basic":
        return StableNote(model=BASIC, tags=tags, fields=[md(card["front"]), md(card["back"]), md(card.get("extra")),
                                                          img(fig_f), img(fig_b), head, src, card["id"]])
    if t == "cloze":
        return StableNote(model=CLOZE, tags=tags, fields=[md(card["text"]), md(card.get("extra")), img(fig_f), img(fig_b),
                                                          head, src, card["id"]])
    if t == "code":
        code = code_html(card["code"], card.get("lang", "java"), linenos=card.get("linenos", kind in ("bug", "error")))
        if kind == "fill":
            extra = md(card.get("explanation"))
            if card.get("answer"):
                extra = output_html(card["answer"], lang) + extra
            return StableNote(model=CLOZE, tags=tags, fields=[md(card["prompt"]) + code, extra, "", "", head, src, card["id"]])
        if kind == "predict":
            answer, out = output_html(card["answer"], lang), typed_output(card["answer"])
        else:
            answer, out = md(card["answer"]), ""
        return StableNote(model=CODE, tags=tags, fields=[md(card["prompt"]), code, answer, md(card.get("explanation")), out,
                                                         head, src, card["id"]])
    raise ValueError(f"{card['id']}: unknown type {t}")


def build(out: Path) -> dict[str, int]:
    out.mkdir(parents=True, exist_ok=True)
    figs = Figures(out / "media")
    counts: dict[str, int] = {}
    for course, file in FILES.items():
        decks, media, n = [], set(), 0
        seen_first = []
        for _, _, data in load_lectures(course):
            lec = dict(data["lecture"])
            lec["lang"] = lec.get("lang", cardlib.COURSES[course]["lang"])
            name = f'{cardlib.COURSES[course]["root"]}::{lec["deck"]}'
            deck = genanki.Deck(stable_id("deck:" + name), name)
            deck.description = lec.get("description", "")
            for card in data.get("cards", []):
                if card.get("hold"):  # parked in the deck repository: not part of the deck
                    continue
                note = build_note(course, lec, card, figs, media)
                if FIRST_TAG in note.tags:
                    seen_first.append(card["id"])
                deck.add_note(note)
                n += 1
            decks.append(deck)
        missing = set(FIRST[course]) - set(seen_first)
        if missing:
            raise SystemExit(f"{course}: first-session cards not found: {sorted(missing)}")
        pkg = genanki.Package(decks)
        pkg.media_files = [str(figs.out / m) for m in sorted(media)]
        pkg.write_to_file(out / file, timestamp=1763078400)  # fixed timestamp: same input, same package
        counts[course] = n
        print(f"{file}: {n} notes, {len(media)} figures, {(out / file).stat().st_size / 1e6:.1f} MB")
    return counts


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=HERE / "out")
    build(ap.parse_args().out)
