#!/usr/bin/env python3
"""Extracts 佛教念诵集.pdf into the chanting JSON the 诵经 tab reads (DzzReader/ChantingTexts/).

    python3 Scripts/extract-chanting.py ../佛教念诵集.pdf DzzReader/ChantingTexts/佛教念诵集.json

Needs `mutool` (brew install mupdf-tools). Output items:
  {"char": "大", "pinyin": "dà"}            pinyin empty for punctuation and text in （…）
  {"type": "linebreak"}                     a new line: the next row is indented or starts a new passage
                                            (rows that merely wrap at the margin are joined), and in the
                                            middle of a verse row, between its two phrases
  {"type": "passage", "style": "title"}     colour of the text: black normal, red title, violet subtitle
                                            (a new heading size also starts a new title/subtitle passage);
                                            "verse" for black verse rows split into phrases (shown centred)
The PDF draws a few rare characters as graphics; only their pinyin is in the text layer. They are placed
by position and named in chanting-glyphs.json (key p<page>@<x>,<y>); unknown ones come out as □.
The script prints any such glyphs, orphan pinyin and unannotated characters for review.
"""
import json, os, re, subprocess, sys, unicodedata
import xml.etree.ElementTree as ET
from collections import Counter

pdf, out = sys.argv[1], sys.argv[2]
glyphs_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "chanting-glyphs.json")
manual = json.load(open(glyphs_path, encoding="utf-8")) if os.path.exists(glyphs_path) else {}
START_PAGE, NPAGES = 5, 31   # PDF pages: the text with pinyin starts at 大佛顶首楞严神咒 on page 5
PINYIN_RE = re.compile(r"^[a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜüɡńňǹḿ]+$")

def is_cjk(c):
    return unicodedata.category(c) == "Lo"

items, warnings, missing_glyphs = [], [], []
depth = 0
for p in range(START_PAGE, NPAGES + 1):
    xml = subprocess.run(["mutool", "draw", "-F", "stext", pdf, str(p)],
                         capture_output=True, text=True).stdout
    root = ET.fromstring(xml)
    page_items = []  # items on this page, with geometry
    for line in root.iter("line"):
        chars = [(c.get("c"), [float(v) for v in c.get("quad").split()][:5] + [float(c.get("y"))], c.get("color"), round(float(f.get("size"))))
                 for f in line.iter("font") for c in f.iter("char")]
        text = "".join(c[0] for c in chars).strip()
        if not text or text == "《佛教念诵集》" or re.fullmatch(r"-\s*\d+\s*-", text):
            continue
        tok = text.replace(" ", "")
        if PINYIN_RE.match(tok):
            py = tok.replace("ɡ", "g")
            x0, y0, x1, y1 = (float(v) for v in line.get("bbox").split())
            # attach to most recent unannotated CJK char outside parens,
            # skipping back over a just-emitted parenthetical group
            j = len(items) - 1
            d = 0
            while j >= 0:
                it = items[j]
                if it["char"] in "）)": d += 1
                elif it["char"] in "（(": d -= 1
                elif d == 0: break
                j -= 1
            if j >= 0 and is_cjk(items[j]["char"]) and items[j]["pinyin"] == "" and not items[j]["_paren"]:
                items[j]["pinyin"] = py
            else:
                # glyph not in text layer: locate by geometry, insert placeholder
                cx = (x0 + x1) / 2
                row = [it for it in page_items if is_cjk(it["char"]) and not it["_paren"]
                       and 0 < it["_y"] - y1 < 30]
                left = [it for it in row if it["_x1"] <= cx + 2]
                anchor = max(left, key=lambda it: it["_x1"]) if left else None
                key = f"p{p}@{int(cx)},{int(y1)}"
                first = min(row, key=lambda it: it["_x1"]) if row else None
                ref = anchor or first
                ph = {"char": manual.get(key, "□"), "pinyin": py, "_paren": False,
                      "_y": ref["_y"], "_x0": cx - 8, "_x1": cx + 8, "_page": p, "_color": ref["_color"], "_size": ref["_size"]}
                if anchor is None:  # first char of row: insert before leftmost
                    idx = next(i for i, it in enumerate(items) if it is first) if first else len(items)
                else:
                    idx = next(i for i, it in enumerate(items) if it is anchor) + 1
                items.insert(idx, ph); page_items.append(ph)
                missing_glyphs.append((key, py, p, cx, ph))
            continue
        for c, q, col, size in chars:
            if c.isspace():
                continue
            it = {"char": c, "pinyin": "", "_paren": depth > 0 and c not in "（(）)",
                  "_y": q[5], "_x0": q[0], "_x1": q[2], "_page": p, "_color": col, "_size": size}
            if c in "（(": depth += 1; it["_paren"] = False
            elif c in "）)": depth = max(0, depth - 1)
            items.append(it); page_items.append(it)

for i, it in enumerate(items):
    if is_cjk(it["char"]) and not it["_paren"] and it["pinyin"] == "":
        ctx = "".join(x["char"] for x in items[max(0, i-5):i+6])
        warnings.append(f"p{it['_page']}: no pinyin for {it['char']} in …{ctx}…")
STYLE = {"#000000": "normal", "#c00000": "title", "#7030a0": "subtitle"}
# A printed row is a new line only when it starts indented (a new paragraph or verse line; wrapped
# continuation rows start at the left margin) or when it starts a new passage (colour or heading size
# changes). Notes in （…） are dark blue but never count as a colour change.
INDENT_X = 50           # body text starts at x≈28–36; indented rows at x≥58

# A verse row holds two phrases with a wider space between them (妙湛总持不动尊　首楞严王世希有). It is
# split there, so each phrase gets its own line on a phone. Verse rows are indented and stop short of the
# right margin; paragraph rows run to the margin and are spaced out by justification, so they are left alone,
# and so are titles and subtitles.
VERSE_GAP = 11          # the gap between phrases is ≈12–19pt; letter spacing elsewhere stays under ≈10pt
FULL_X1 = 470           # rows that reach the right margin end at x≈476–498; verse rows end by ≈450
verse_splits = set()    # ids of the items that start the second phrase of a verse row
verse_items = set()     # ids of every item in a verse row: they make a "verse" passage
# A short row that ends a verse (南無金刚藏菩萨: one phrase, no gap) belongs to it when it follows a verse
# row at the same indent.
row, verse_x0 = [], None   # verse_x0: indent of the row above when that row is verse
for it in items + [None]:
    if row and (it is None or it["_page"] != row[-1]["_page"] or abs(it["_y"] - row[-1]["_y"]) > 8):
        body = all(STYLE.get(x["_color"]) == "normal" for x in row if is_cjk(x["char"]) and not x["_paren"])
        verse = False
        if body and row[0]["_x0"] > INDENT_X and max(x["_x1"] for x in row) < FULL_X1:
            if len(row) >= 6:
                # The widest gap away from the ends (a row can open with a wide gap after its first character).
                gaps = [(b["_x0"] - a["_x1"], k + 1) for k, (a, b) in enumerate(zip(row, row[1:])) if 3 <= k + 1 <= len(row) - 3]
                gap, k = max(gaps)
                if gap >= VERSE_GAP:
                    verse_splits.add(id(row[k]))
                    verse = True
            if not verse and verse_x0 is not None and abs(row[0]["_x0"] - verse_x0) <= 8:
                verse = True
        if verse:
            verse_items.update(id(x) for x in row)
        verse_x0 = row[0]["_x0"] if verse else None
        row = []
    if it is not None:
        row.append(it)

clean, style, size, prev = [], None, None, None
row_start, row_broken, row_styled = None, False, False
for it in items:
    if prev is not None and (it["_page"] != prev["_page"] or abs(it["_y"] - prev["_y"]) > 8):
        if it["_page"] == prev["_page"] and it["_y"] < prev["_y"] - 8:
            warnings.append(f"p{it['_page']}: row order goes up at {it['char']}")
        row_start, row_broken, row_styled = len(clean), it["_x0"] > INDENT_X, False
        if row_broken:
            clean.append({"type": "linebreak"})
    s_ = STYLE.get(it["_color"]) if is_cjk(it["char"]) and not it["_paren"] else None
    if s_ == "normal" and id(it) in verse_items:
        s_ = "verse"
    if s_ and (s_ != style or (s_ in ("title", "subtitle") and it["_size"] != size)):
        style, size = s_, it["_size"]
        if row_start is not None and not row_broken and not row_styled:
            clean.insert(row_start, {"type": "linebreak"})   # the new passage starts this row
            row_broken = True
        clean.append({"type": "passage", "style": style})
    if s_:
        row_styled = True
    if id(it) in verse_splits:
        clean.append({"type": "linebreak"})
    clean.append({"char": it["char"], "pinyin": it["pinyin"]})
    prev = it

# Inside （…）, Chinese numerals become digits: （五十九） → （59）, （三遍） → （3遍）, （五百声或千声） → （500声或1000声）.
# 两 is left alone (「有两种读音」 reads as a word). A number wrapped across a row break is written whole
# before the break.
CN_DIGITS = {"零": 0, "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
CN_UNITS = {"十": 10, "百": 100, "千": 1000}

def cn_to_int(run):
    if not any(ch in CN_UNITS for ch in run):          # 二〇〇五 style: digit by digit
        return "".join(str(CN_DIGITS[ch]) for ch in run)
    total, cur = 0, 0
    for ch in run:
        if ch in CN_DIGITS:
            cur = CN_DIGITS[ch]
        else:
            total += (cur or 1) * CN_UNITS[ch]
            cur = 0
    return str(total + cur)

def numerals_to_digits(items):
    out, depth, run = [], 0, []          # run: indices into out of the current numeral characters
    def flush():
        if run:
            digits = cn_to_int("".join(out[i]["char"] for i in run))
            first = run[0]
            for i in reversed(run):
                del out[i]
            for k, d in enumerate(digits):
                out.insert(first + k, {"char": d, "pinyin": ""})
            run.clear()
    for it in items:
        c = it.get("char")
        if c is None:                    # linebreak / passage: a number may continue after it
            out.append(it)
            continue
        if depth > 0 and (c in CN_DIGITS or c in CN_UNITS):
            run.append(len(out))
            out.append(it)
            continue
        flush()
        if c in "（(": depth += 1
        elif c in "）)": depth = max(0, depth - 1)
        out.append(it)
    flush()
    return out

clean = numerals_to_digits(clean)
chars_only = [x for x in clean if "char" in x]
with open(out, "w", encoding="utf-8") as f:
    json.dump(clean, f, ensure_ascii=False, indent=1)
print(len(chars_only), "chars;", sum(1 for x in chars_only if x["pinyin"]), "with pinyin;",
      sum(1 for x in clean if x.get("type") == "linebreak"), "linebreaks;",
      Counter(x["style"] for x in clean if x.get("type") == "passage"))
print("colors:", Counter((it["_color"]) for it in items if is_cjk(it["char"]) and not it["_paren"]))
for key, py, p, cx, ph in missing_glyphs:
    i = next(i for i, it in enumerate(items) if it is ph)
    print("MISSING", key, py, "".join(x["char"] for x in items[max(0, i-6):i+4]))
print("\n".join(warnings))
