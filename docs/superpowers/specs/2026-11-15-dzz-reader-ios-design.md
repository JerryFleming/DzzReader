# DzzReader: iOS plain-text reader for the 大正藏 — Design

Date: 2026-11-15
Status: draft, awaiting owner approval

## Intent

A personal iOS app for reading the 大正藏 (the `dzz` corpus: 2,982 UTF-8 txt files, 488 MB) on a phone, with the ordinary comforts of an e-book reader. The owner is the only user. All books ship inside the app bundle; nothing is downloaded. Additional txt books can be imported at runtime.

The owner wants: bookshelf, themes, font settings, bookmarks, progress jumping, chapter list and chapter jumping, text selection with copy and share, and runtime import of txt files.

## Goals

- Open any of the 2,982 bundled texts from a shelf organised by 部, and resume exactly where reading stopped.
- Comfortable scrolling reading of classical Chinese: adjustable font, size, line spacing, margins; light, sepia, dark and black themes.
- Chapter (卷) list for every book; jump to any chapter; jump to any point by a progress slider.
- Bookmarks that return to an exact position and show a text excerpt.
- Native iOS text selection across paragraphs with copy, look up and share.
- Import any `.txt` file from the Files app or the share sheet; imported books live on the same shelf.
- A 5 MB text must open and scroll without stutter.

## Non-goals

- Sync across devices (iCloud). Single phone.
- Highlights, notes, annotations. Bookmarks only.
- Full-text search inside a book or across the canon. (Shelf search by title and 经号 is in scope.)
- Traditional/simplified conversion, dictionary lookup beyond the system Look Up, text-to-speech.
- Page-turn (paginated) mode. Decided: scrolling only.
- Correcting corpus defects (the one empty file, the three corrupted texts, the missing 2722). Show what is there.
- App Store distribution. Installed via Xcode onto the owner's device.

## Anti-goals (would make it a failure even if it works)

- A shelf that is a flat list of 2,982 titles. It must be browsable by 部 and searchable.
- Losing reading position, or a bookmark that lands somewhere other than where it was set.
- Loading a whole 5 MB file into one text view and freezing.
- Chapter lists with duplicated 卷 entries (the corpus marks each 卷 twice; see Corpus facts).

## Constraints

- Xcode 27.2, iOS 26.5 and 27.0 simulators available. Target iOS 26.0 minimum.
- Swift, SwiftUI shell, UIKit `UITextView` (TextKit 2) for the reading surface.
- The `dzz` folder is its own git repository (`dzz/.git` is 135 MB) and must not be copied into the bundle.
- Bundle size will be roughly 490 MB uncompressed. Acceptable for a personal install.
- Builder has the Xcode MCP tools (`XcodeNewProject`, `BuildProject`, `RunProject`, simulator interaction) and may use them.

## Corpus facts the builder relies on

Verified on 2026-11-15 against `/Users/jerry/projects/buddhism-kb/dzz`.

- Layout: `dzz/NN/<经号><title>.txt`, NN = `00`…`29`. 2,982 files. All decode as strict UTF-8. No private-use characters.
- `dzz/toc.txt` (3,159 lines): a preamble, a 部 summary table, then one line per text:
  `经号 \t 卷号 \t 页码 \t 经名 \t (N卷) \t 〖朝代 \t 译者〗 \t (注释, optional)`
  e.g. `0026\t01\tP0421\t中阿含经\t(60卷)\t〖东晋\t瞿昙僧伽提婆译〗`. The 部 summary table maps 经号 ranges to 部 names (阿含部 0001–0151, 本缘部 0152–0219, …, 疑似部 2865–2920; 31 部 in total). Some 经号 carry a letter suffix (`0894a`). Entries can exist in toc.txt that have no file (listed under MISSING) and vice-versa; the shelf shows only texts whose file exists.
- File header: line 1 is usually `大正藏 No. NNNN <title>` (2,428 files) but 480 续藏 files start `No. NNNN <title>` and about 40 start with a chapter mark before the header (`第0章 大正藏 No. …`). Then `　　<朝代> <译者>`, blank lines, `　　N卷` (missing in 525 files), blank lines, then body. Paragraphs are single lines beginning with two full-width spaces (`　　`); verse lines are also indented with `　　` and use `　　` between hemistichs. Blank lines separate sections.
- Chapter marks: 994 files contain lines beginning `第0章 ` (always `0`, 24,433 occurrences). The mark prefix must be stripped for display. Marks fall into three kinds:
  - **卷 headings**, e.g. `第0章 　　　　佛说长阿含经卷第一`. **Each 卷 is marked twice**: on its opening heading line and again on the closing line at the end of the 卷. In 444 files the closing line differs from the opening one only by a parenthetical, e.g. `中阿含经卷第一` vs `中阿含经卷第一(八千一百九字)(初一日诵)`.
  - **品 sub-headings**, marked once, e.g. `第0章 　　阎浮提州品第一`, in 680 of the marked files. 266 marked files have only 品 marks (single-卷 texts divided into 品).
  - **False marks** on ordinary body paragraphs (about 2,100 occurrences; e.g. `第0章 　　昔有一国王深识罪福…`). Heading-length distribution, after collapsing whitespace: 22,300 marks are under 30 characters, almost everything 50 characters or longer is a body paragraph. Legitimate titles longer than 30 characters carry a parenthetical note, e.g. `佛说须真天子经卷第一(文殊师利所报…)`.
- Unmarked files: 1,873 are single-卷 (header says `1卷` or absent): the whole body is one chapter. 115 are multi-卷; most contain `…卷第[一二三…]` or `…卷[上中下]` heading lines, again appearing as opening/closing pairs. A few have none; they get a single chapter.
- Sizes: median 22 KB, 23 files above 2 MB, largest 5.3 MB. Most large files split into 卷 of 10–30K characters, but 29 files (续诸宗部 commentaries mostly) have a single chapter over 100K characters; the largest single chapter is about 510K characters (2263论第一卷同学钞). One file is 0 bytes.
- toc.txt also contains 76 sub-entry lines numbered `0310#N` with fewer fields, three entries whose 卷数 reads `(第1-200卷)` (0220a/b/c) and one `1卷` without parentheses.

## Approaches considered

1. **Scrolling reader on `UITextView` (TextKit 2), SwiftUI shell — chosen.** One chapter loaded at a time into a `UITextView`; vertical scroll; footer link and toolbar for previous/next 卷. Native selection, copy, Look Up and Share come free and work across paragraphs. Themes and fonts are attributes on an `NSAttributedString`. Progress is (chapter index, character offset of first visible glyph).
2. **Paginated reader, iBooks style.** TextKit 2 lays each chapter into fixed pages, shown in a `UIPageViewController`. Book-like feel, page numbers for progress. Rejected by the owner in favour of scrolling; also re-layout on every font/orientation change is markedly more work.
3. **Pure SwiftUI `Text` in a `LazyVStack`.** Dropped: selection cannot span paragraphs and there is no share menu.
4. **`WKWebView` rendering HTML.** Dropped: heavier, and copy/share menus are awkward to control.

The owner chose approach 1 ("scroll please").

## Decided design

### Project shape

- New Xcode project at `/Users/jerry/projects/buddhism-kb/DzzReader/`, app target `DzzReader`, display name `大藏经`, bundle id `com.jerryfleming.dzzreader`. Swift 6 language mode, iOS 26.0 deployment target, iPhone and iPad device family (iPad gets whatever the iPhone layout gives; no iPad-specific work).
- Unit test target `DzzReaderTests` using Swift Testing.
- Bundled corpus: a **Run Script build phase** that `rsync`s `../dzz/toc.txt` and `../dzz/[0-9][0-9]/*.txt` into `$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books/`, excluding `.git`, `README.md`, `TODO`. Input/output file lists so incremental builds skip it. Not an Xcode folder reference, so `.git` can never leak in.
- Imported books live in `Documents/Imported/<uuid>.txt`.
- Persistence: **SwiftData** for `Book`, `Chapter` index cache, `ReadingProgress`, `Bookmark`. Reader appearance settings in `UserDefaults` via `@AppStorage`.

### Domain model

```
Book
  id: String            // canon: "T0026" (T + 经号 incl. suffix); imported: UUID string
  title: String
  source: .bundled | .imported
  relativePath: String  // "Books/00/0026中阿含经.txt" or "Imported/<uuid>.txt"
  section: String?      // 部, canon only
  juanCount: Int?       // from toc "(60卷)"
  author: String?       // "东晋 瞿昙僧伽提婆译"
  catalogOrder: Int     // sort key: 经号 numeric, suffix letters after
  byteSize: Int
  dateAdded: Date
  lastOpened: Date?
  chapters: [Chapter]   // empty until first open; filled by ChapterIndexer and cached
  encodingName: String  // "utf-8", "gb18030", ... (imports)

Chapter                 // the loading unit: one 卷 (or a synthetic part of an oversized 卷)
  index: Int
  title: String         // display title, mark prefix stripped, trimmed
  startOffset: Int      // UTF-16 offset into the decoded full SOURCE text (NSString units)
  endOffset: Int
  sections: [Section]   // 品 sub-headings inside this chapter, in order (may be empty)

Section
  title: String
  offset: Int           // UTF-16 offset in the SOURCE text of the heading line start

ReadingProgress  (one per Book)
  chapterIndex: Int
  characterOffset: Int  // UTF-16 SOURCE offset within the chapter of the first visible character
  fraction: Double      // 0…1 over the whole book, derived, for the shelf

Bookmark
  bookID, chapterIndex, characterOffset (SOURCE offset within the chapter), excerpt (≈40 chars), createdAt
```

Offsets are UTF-16 (`NSString`/`NSRange`) units throughout, because `UITextView` speaks `NSRange`. Persisted offsets are always **source-text** offsets, so a change to how text is rendered can never move a bookmark. The rendered chapter text differs from the source only by the removed `第0章 ` prefixes, and a small offset map converts between the two (see Text rendering).

### Catalog (shelf data)

`CatalogLoader` runs on first launch (and whenever the bundled toc.txt changes, detected by a stored hash):
1. Parse the 部 summary table of toc.txt into (name, 经号 range) pairs.
2. Parse each text entry line. Skip preamble, blank and `MISSING` lines, and the separator rows of 卍.
3. Enumerate `Books/NN/*.txt` in the bundle; join by 经号 parsed from the filename prefix (digits plus optional letter). Files without a toc entry still appear, with title from the filename and section inferred from the 经号 range. Toc entries without a file are skipped.
4. Upsert `Book` rows. Chapters are left empty.

Imported books are added by `Importer` at import time.

### Chapter indexing

`ChapterIndexer.index(text: String) -> [Chapter]` is pure and unit-tested. Runs in a background task the first time a book is opened, then cached in SwiftData (and invalidated if `byteSize` changes).

Rules:
1. **Normalise** a candidate line: strip the mark prefix (`^第\d+章\s*`), collapse runs of `　` and ASCII whitespace to one space, trim. Its **comparison key** additionally removes every parenthetical `(…)` / `（…）`.
2. **Candidates:**
   a. Marked file (contains at least one `第0章` line): every marked line is a candidate. A candidate whose comparison key is longer than 30 characters is a **false mark**: not a heading, rendered as an ordinary paragraph with the prefix removed.
   b. Unmarked file: lines whose normalised text matches `^.{0,30}卷第[一二三四五六七八九十百千〇零]+$` or `^.{0,30}卷[上中下]$` (comparison key, parentheticals removed) are candidates.
3. **Kind:** a candidate is a **卷 heading** when its comparison key matches `卷第[一二三四五六七八九十百千〇零]+$`, `卷[上中下]$`, or `卷$`; otherwise it is a **品 section heading**.
4. **Pair collapse (卷 only):** walking in order, a 卷 candidate whose comparison key equals the previous accepted 卷's key is a closing line: dropped as a heading, rendered as a plain paragraph (prefix removed). 品 candidates are never collapsed.
5. **Chapters:** each accepted 卷 heading starts a chapter at its line start and ends at the next accepted 卷 heading's start or EOF. 品 headings become `Section`s of the chapter that contains them.
6. **Front matter:** text before the first 卷 heading becomes chapter 0 titled `卷首` **only if** it contains at least one non-blank line beyond the header block (the header block is the first non-blank lines up to and including the `N卷` line, or the first three non-blank lines when there is no `N卷` line). Otherwise it is merged into the first chapter. A 品 heading inside front matter stays a section of whichever chapter the text ends up in.
7. **No 卷 at all** (single-卷 texts, 品-only texts, texts with no headings): one chapter covering the whole text, titled with the book title, carrying any 品 sections.
8. **Short false positive:** a chapter under 200 characters that is not the last is merged into the following chapter (its sections move too).
9. **Oversized chapters:** a chapter longer than 120,000 UTF-16 units is split into parts at the blank line nearest to each multiple of 100,000 units (falling back to a line boundary). Parts are titled `<title>（1/4）`, `<title>（2/4）`…; sections stay with the part that contains them. This keeps the reader to one attributed string of at most ~120K characters.

Display title for a chapter or section: the normalised heading text (prefix removed, whitespace collapsed; parentheticals kept).

### Text rendering

- `ChapterTextView`: `UIViewRepresentable` wrapping a `UITextView` (TextKit 2, `isEditable = false`, `isSelectable = true`, `isScrollEnabled = true`, `textContainerInset` from the margin setting).
- Content: the chapter's source substring, **verbatim except that every `第0章 ` prefix is removed**, as an `NSAttributedString` with one paragraph style: `lineSpacing` from settings, `paragraphSpacing` ≈ 0.6 em, no indent attributes. The source's leading `　　` (two full-width spaces) are kept as characters; they are 2 em wide in any CJK font, so indentation and verse alignment scale with the font automatically.
- `RenderedChapter` carries the rendered string plus an **offset map**: the sorted list of (renderedOffset, removedCount) for each stripped prefix. `sourceOffset(forRendered:)` and `renderedOffset(forSource:)` are binary searches over it. Every offset that leaves the text view (progress, bookmark, selection start) is converted to source coordinates before it is stored; every stored offset is converted back before scrolling.
- The 卷 heading line (chapter start, non-front-matter) is rendered bold at 1.2× size and centred, with extra space below. 品 section heading lines are rendered bold at 1.1× size, left-aligned. Closing 卷 lines and false marks are plain paragraphs.
- Fonts: a short curated list of fonts present on iOS: 系统 (PingFang SC), 宋体 (Songti SC), 楷体 (Kaiti SC), 黑体 (Heiti SC), 圆体 (Yuanti SC), plus "其它" showing every installed family that contains CJK glyphs. Size 14–40 pt, default 20. Line spacing multiplier 1.2–2.2, default 1.6. Margin 8–40 pt, default 20. Settings apply live by re-attributing the stored text (no re-indexing).
- Themes: `light` (paper white, near-black text), `sepia` (#F4ECD8 / #5B4636), `dark` (#1C1C1E / #D0D0D0), `black` (#000 / #BBB), and "跟随系统" switching light/dark. Theme sets `backgroundColor`, text color, and the SwiftUI chrome tint; status bar style follows.
- End of chapter: append a final attributed "link" line `→ 下一卷　<title>` with a custom URL scheme handled in `UITextViewDelegate.textView(_:shouldInteractWith:…)`; at the last chapter show `全书完`.
- Toolbar prev/next buttons also move between chapters.
- Progress tracking: on `scrollViewDidScroll` (debounced 300 ms) and on `DidEndDecelerating`/`DidEndDragging`, compute the character offset of the first visible glyph via `textLayoutManager.textLayoutFragment(for: point)` → `NSTextRange` location → offset. Save to `ReadingProgress`. Restore on open by scrolling so that glyph is at the top of the viewport.

### Screens

**Shelf (`ShelfView`)** — root `NavigationStack`.
```
┌──────────────────────────────┐
│ 大藏经                 ⬇︎ 导入 │
│ 🔍 搜索经名或经号              │
│ 最近阅读                      │
│  ▸ 长阿含经   卷第三  · 12%    │
│  ▸ 金刚经              · 100% │
│ 导入的书                      │
│  ▸ 我的笔记.txt         · 4%  │
│ 阿含部  (151)                ›│
│ 本缘部  (68)                 ›│
│ 般若部  (42)                 ›│
│ …                            │
└──────────────────────────────┘
```
- "最近阅读": up to 5 books with `lastOpened`, newest first; row shows title, current chapter title, percent.
- "导入的书": imported books, newest first; swipe to delete (deletes file, progress, bookmarks).
- One row per 部 → `SectionView`: list of books sorted by `catalogOrder`; row shows `经号 · 题名`, subtitle `N卷 · 作者`, trailing percent if any progress.
- Search field filters across all books by title substring or 经号 prefix; results shown as a flat list while searching.
- Import button opens `fileImporter` for `.plainText`/`.text`, multiple selection allowed.

**Reader (`ReaderView`)** — full screen, pushed.
```
┌──────────────────────────────┐  chrome shown
│ ‹  长阿含经 · 佛说长阿含经卷第三 │
│                              │
│   如是我闻。一时。佛在…         │
│   …                          │
│                              │
│ ☰目录   🔖  ‹ ──●──── › 23%  Aa │
└──────────────────────────────┘
```
- Chrome (top bar + bottom bar) hidden by default; single tap in the middle third of the screen toggles it; starts hidden when resuming.
- Bottom bar: `目录` (chapter list sheet), `🔖` (add bookmark at current position; long-press opens bookmark list), `‹ ›` prev/next 卷 flanking the progress slider, percent label, `Aa` (appearance sheet).
- Progress slider: value 0…1 over the whole book, computed from chapter `startOffset` + in-chapter offset over total length. Dragging shows a floating label "卷第N · 23%"; release jumps (loading the target chapter if different). Reader also shows chapter position as "3/22" next to the slider.
- Chapter list sheet: one row per chapter (卷), with its 品 sections as indented rows beneath it; the current chapter is highlighted and scrolled into view, and the current section (the last one whose offset is at or before the visible offset) is highlighted too. Tapping a chapter jumps to its start; tapping a section jumps to that offset inside its chapter. For front matter show `卷首`. For 品-only single-chapter books the sheet shows the book title row with all 品 beneath it.
- Bookmark list sheet: rows of excerpt + chapter title + date; tap jumps; swipe to delete.
- Appearance sheet: theme segmented picker, font picker, size slider with live preview, line spacing slider, margin slider. Applies instantly to the reader behind it.
- Selection edit menu: system items (Copy, Look Up, Translate, Search Web, Share) plus one custom item `添加书签`, which creates a bookmark at the selection start with the selected text (first 40 chars) as excerpt.
- Keep screen awake while reader is visible (`isIdleTimerDisabled`).

**Import** (`Importer`)
- Sources: `fileImporter` from the shelf, and `onOpenURL` for files handed via the share sheet / "Open in". Info.plist declares the app as a viewer for `public.plain-text` and `public.text` (`CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace = NO`).
- Decoding: try UTF-8 (with BOM stripping), then UTF-16 with BOM, then Foundation's encoding detection (`NSString.stringEncoding(for:encodingOptions:…)`) with GB18030 and Big5 as the suggested encodings, since GB18030 accepts almost any byte string and cannot simply be tried first. Normalise `\r\n` and `\r` to `\n`. Record `encodingName`. If nothing decodes, show an error and skip the file.
- Title: filename without extension. If the file's first non-blank line, with any chapter mark removed, matches `^(?:大正藏\s*)?No\.\s*\S+\s+(.+)$`, use the captured title instead.
- Copy to `Documents/Imported/<uuid>.txt` (re-encoded as UTF-8 so the reader has one decoding path), insert `Book`, index chapters immediately, open the book if a single file was imported.

### Performance plan

- Never hold more than the current book's full text in memory, plus the current chapter's attributed string (≤ ~120K characters thanks to the oversized-chapter split). Full text is loaded once per open (5 MB is fine) and chapters are substrings by `NSRange`.
- Chapter indexing of the largest file must finish under 1 s on device; indexing is line-regex based, O(n).
- Font/theme change re-attributes the current chapter only.
- Catalog load (toc parse + bundle enumeration of 2,982 files) runs once; subsequent launches hit SwiftData.

### Testing

Swift Testing unit tests, run on the simulator:
- `ChapterIndexerTests`: marked file with open/close pairs → one chapter per 卷, titles stripped; closing line with extra parenthetical still collapses; 品 marks become sections of the right chapter; false marks (long) are not headings; unmarked multi-卷 with 卷第N → correct count; unmarked single-卷 → one chapter; 品-only file → one chapter with sections; front matter rule; short-chapter merge; oversized chapter split into parts; empty file → one empty chapter, no crash. Fixtures are small hand-made strings plus a couple of real excerpts committed with the tests.
- A corpus-wide sanity run (not a unit test, env-var gated) that indexes all 2,982 files and reports chapter counts against the toc 卷数.
- `TocParserTests`: 部 table, entry line with and without 注释, suffix 经号 `0894a`, `0310#N` sub-entries skipped, `(第1-200卷)` and bare `1卷` tolerated, MISSING block skipped.
- `ProgressMapperTests`: (chapter, offset) ↔ book fraction round-trips; slider at 1.0 lands in the last chapter; out-of-range clamps.
- `TextDecoderTests`: UTF-8 BOM, GB18030 sample, Big5 sample, CRLF normalised, undecodable bytes rejected.
- `ChapterRendererTests`: prefix stripping with offset map round-trip, heading/section ranges, body text otherwise verbatim.
- Manual verification on the simulator with the Xcode MCP tools is required before completion: open 长阿含经, jump to 卷第三, set a bookmark, kill the app, relaunch, confirm position and bookmark.

### Left to the builder

- Exact colour values beyond the four themes' intent; app icon.
- Whether chapter heading detection for the 115 unmarked multi-卷 files needs extra patterns after inspecting them; keep the regex table in one place.
- Debounce intervals, animation details, haptics.
- Project generation tool (Xcode MCP `XcodeNewProject`, or a hand-written `project.pbxproj`, or XcodeGen). Must produce a plain `.xcodeproj` the owner can open.

## Builder-check round (2026-11-15)

A fresh reviewer read the draft and verified it against the corpus. Two findings changed the design; both were settled as the designer's calls because the owner had asked for the build to proceed:

1. Chapter marks also cover 品 sub-headings and some body paragraphs. Decided: chapters are 卷, 品 are jumpable sections inside them, marks over 30 characters (parentheticals removed) are body text. Rejected alternatives: 卷-only with 品 ignored (loses navigation in 266 品-only texts), and a flat list mixing 卷 and 品 (unusable for 600-卷 texts, shows sentence fragments as chapters).
2. Some commentaries have a single chapter of up to 510K characters. Decided: split chapters over 120K characters into synthetic parts in the indexer, rather than building intra-chapter windowing into the reader.

Smaller fixes from the same round: persisted offsets are source offsets with an offset map; `　　` is kept verbatim instead of being replaced by indent attributes; header and toc parsing tolerate the 续藏 `No.` header, missing `N卷` lines, `0310#N` sub-entries and `(第1-200卷)`; encoding detection uses Foundation's detector instead of trying GB18030 before Big5.

## Open questions for the owner

None.
