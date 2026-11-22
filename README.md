# DzzReader（大藏经）

A personal iOS reader for the 大正藏 plain-text corpus at https://github.com/JerryFleming/dzz. The books are not in the app bundle: the 书架 download button fetches a `.tar.gz` (that repo by default, any URL allowed) and unpacks it on the device. More `.txt` books can be imported from the Files app or the share sheet.

Design: `docs/superpowers/specs/2026-11-15-dzz-reader-ios-design.md`.

## Layout

- `DzzCore/` — Swift package with all Foundation-only logic: `.tar.gz` unpacking (`TarGzExtractor`, streaming, no dependencies), toc parsing, chapter indexing (卷 + 品 sections, oversized-卷 splitting), chapter rendering with a source/rendered offset map, text decoding, progress maths. Test with `swift test` on macOS.
- `DzzReader/` — the SwiftUI app: SwiftData models, catalog loader, shelf, reader (TextKit 2 `UITextView`), bookmarks, appearance, import, and the 分享 tab (`Share/`: the vertical quote card ported from `../lecture/index.html`).
- `DzzReaderTests/` — Swift Testing unit tests for the app layer (run on the simulator).
- `DzzReaderUITests/` — XCUITest flows that drive the real app: shelf, reader, chapter list, slider, appearance, bookmarks, relaunch, import.
- `DzzReader/Chanting/` — the 诵经 tab: a shelf of chanting texts (最近阅读, bundled 念诵集, imported) and a pinyin reader. Texts are JSON item lists (`{"char","pinyin"}`, `{"type":"linebreak"}`, `{"type":"passage","style":"normal|title|subtitle|verse"}`) parsed by `DzzCore/ChantDocument`. A passage item sets the style of the rows that follow, up to the next passage item: `title` (red, larger, centred, listed in 目录), `subtitle` (violet, centred), `verse` (body colour, centred: verse lines with one phrase per row) or `normal` (left-aligned body text). The same format is explained in the app: the ? button beside import on 诵经 (`Chanting/ChantFormatHelp.swift`, keep it in step with `ChantDocument`), which also shows the bundled 佛教念诵集.json one item per line as a sample and can share it.
- `DzzReader/Support/` — the 支持 tab: four voluntary tips (小小心意 £0.99, 请杯咖啡 £2.99, 支持一下 £4.99, 慷慨支持 £9.99) sold as StoreKit 2 consumables `com.jerryfleming.dzzreader.tip.{small,coffee,support,generous}`. They unlock nothing. Real prices come from App Store Connect, where the four products must be created; `DzzReader.storekit` (GBR storefront) supplies them when running from Xcode (scheme Run action) and to `TipJarTests` via `SKTestSession`. UI tests get no StoreKit configuration, so the tab shows the fallback prices with the buttons disabled. Debug builds carry `get-task-allow` (`DzzReader/Debug.entitlements`), without which storekitd refuses test sessions on the simulator.
- `DzzReader/ChantingTexts/` — bundled chanting texts (currently `佛教念诵集.json`), copied into the bundle as a folder.
- `Scripts/extract-chanting.py` — regenerates the chanting JSON from `../佛教念诵集.pdf` (needs `mutool`); `Scripts/chanting-glyphs.json` names the rare characters the PDF draws as graphics.
- `Scripts/make-app-icon.py` regenerates `DzzReader/AppIcon.icon` (needs Xcode's `swift` and the Songti SC font); rerunning overwrites manual Icon Composer edits.

## Build

```sh
brew install xcodegen          # once
cd DzzReader
xcodegen generate              # regenerates DzzReader.xcodeproj from project.yml
open DzzReader.xcodeproj       # or:
xcodebuild -project DzzReader.xcodeproj -scheme DzzReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

No corpus is needed to build. On a fresh install the shelf is empty until books are downloaded (书架 → cloud button).

## Tests

```sh
cd DzzReader/DzzCore && swift test                      # core, fast
DZZ_CORPUS=/path/to/dzz swift test --filter CorpusSmoke # index every file, report 卷数 mismatches
DZZ_TARBALL=/path/to/dzz.tar.gz swift test --filter TarGz # unpack the real GitHub archive
cd .. && xcodebuild test -project DzzReader.xcodeproj -scheme DzzReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

`DownloadUITests` needs network access (it downloads the dzz archive if the shelf lacks it) and `TEST_RUNNER_DZZ_TOCLESS=/path/to/sample.tar.gz`, an archive without toc.txt holding `念佛.txt` and `sub/心经.txt` (e.g. `COPYFILE_DISABLE=1 tar czf sample.tar.gz mybooks`).

`ImportUITests` expects a `dzz-import-sample.txt` in the simulator's *On My iPhone* storage; see the test file.

## Where things live at runtime

- Catalog, reading progress and bookmarks: SwiftData store in the app's Application Support.
- Downloaded books: `Application Support/Books/` (excluded from backup), source `bundled` in the store. A download unpacks the archive's `.txt` files (hidden entries skipped; a single wrapping folder removed) into `Books.partial/`, catalogues them from there, then merges them into `Books/`: same-path files are overwritten, nothing is removed. If that archive has a `toc.txt`, its `NN/<经号><title>.txt` files get ids `T<经号>` and are grouped into its 部; otherwise every `.txt` gets id `F:<path>`, no 部, and shows in the unnamed group at the bottom of the shelf.
- Deleting: swipe a book (部 page, unnamed group, 导入的书) to delete it with its file, progress and bookmarks; swipe or long-press a 部 row to delete the whole 部; long-press a book for 删除整组. Group deletes ask first. On 诵经 the same works for 念诵集 and 导入的文本; deleted bundled texts are listed in the `chant.deletedBundled` default so launch doesn't re-add them (there is no undo in the UI).
- Imported books: `Documents/Imported/<uuid>.txt`, re-encoded as UTF-8. The 书架 picker accepts only plain text.
- Imported chanting texts: `Documents/ImportedChanting/<uuid>.json`, validated before copying. The 诵经 picker accepts only JSON; a file opened from another app goes to the shelf matching its type.
- Chanting texts always open at the start; no reading position is kept. 最近阅读 uses the last-opened time; the font size is the `chant.fontSize` default, and the reader's light/dark toggle is `chant.theme` (empty follows the 书架 appearance setting).
- Chanting auto-scroll highlights one character-with-pinyin block at a time (punctuation and notes are skipped) at `chant.autoSpeed` blocks per minute, and scrolls to keep the highlighted line mid-screen except near the ends. It pauses while the chrome shows; stopping clears the highlight. Stepping logic: `DzzReader/Chanting/ChantUnits.swift`.
- Appearance settings: `UserDefaults` keys prefixed `reader.`.

## Corpus notes the code depends on

- Chapter marks `第0章 ` mark 卷 headings (twice: opening and closing line), 品 sub-headings (once) and, in some files, ordinary paragraphs. The indexer treats marks over 30 characters (parentheticals removed) as body text, collapses closing 卷 lines, and turns 品 marks into jumpable sections.
- Chapters longer than 120,000 UTF-16 units are split into parts titled `…（1/3）`.
- Persisted offsets are source-text offsets; the rendered text only drops the mark prefixes.

## Reading modes

- Books up to 300,000 UTF-16 units (`LoadedBook.wholeBookLimit`, about 97% of the corpus) are rendered as one continuous document; chapters are just positions in it, and the chapter shown in the chrome is whichever one is at the top of the screen.
- Larger books are rendered a chapter at a time. Pulling past the bottom (or top) edge opens the next (or previous) chapter, with a hint once the pull is far enough; a previous-screen swipe on the first screen also goes back a chapter.
- Progress and bookmarks are stored as (chapter index, source offset in that chapter) in both modes.
