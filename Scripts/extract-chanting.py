#!/usr/bin/env python3
"""Extracts 佛教念诵集.pdf into the chanting JSON the 诵经 tab reads (DzzReader/ChantingTexts/).

    python3 Scripts/extract-chanting.py ../佛教念诵集.pdf DzzReader/ChantingTexts/佛教念诵集.json

Needs `mutool` (brew install mupdf-tools). Output items:
  {"char": "大", "pinyin": "dà"}            pinyin empty for punctuation and text in （…）
  {"type": "linebreak"}                     end of a printed row of Chinese text
  {"type": "passage", "style": "title"}     colour of the text: black normal, red title, violet subtitle
                                            (a new heading size also starts a new title/subtitle passage)
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
                      "_y": ref["_y"], "_x1": cx + 8, "_page": p, "_color": ref["_color"], "_size": ref["_size"]}
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
                  "_y": q[5], "_x1": q[2], "_page": p, "_color": col, "_size": size}
            if c in "（(": depth += 1; it["_paren"] = False
            elif c in "）)": depth = max(0, depth - 1)
            items.append(it); page_items.append(it)

for i, it in enumerate(items):
    if is_cjk(it["char"]) and not it["_paren"] and it["pinyin"] == "":
        ctx = "".join(x["char"] for x in items[max(0, i-5):i+6])
        warnings.append(f"p{it['_page']}: no pinyin for {it['char']} in …{ctx}…")
STYLE = {"#000000": "normal", "#c00000": "title", "#7030a0": "subtitle"}
clean, style, size, prev = [], None, None, None
for it in items:
    if prev is not None and (it["_page"] != prev["_page"] or abs(it["_y"] - prev["_y"]) > 8):
        if it["_page"] == prev["_page"] and it["_y"] < prev["_y"] - 8:
            warnings.append(f"p{it['_page']}: row order goes up at {it['char']}")
        clean.append({"type": "linebreak"})
    s_ = STYLE.get(it["_color"]) if is_cjk(it["char"]) and not it["_paren"] else None
    if s_ and (s_ != style or (s_ != "normal" and it["_size"] != size)):
        style, size = s_, it["_size"]
        clean.append({"type": "passage", "style": style})
    elif style is None and s_ is None and not clean:
        pass
    clean.append({"char": it["char"], "pinyin": it["pinyin"]})
    prev = it
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
