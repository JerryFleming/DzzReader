# DzzReader（大藏经）

A personal iOS reader for the 大正藏 plain-text corpus in `../dzz`. Every text ships inside the app bundle; more `.txt` books can be imported at runtime from the Files app or the share sheet.

Design: `docs/superpowers/specs/2026-11-15-dzz-reader-ios-design.md`.

## Layout

- `DzzCore/` — Swift package with all Foundation-only logic: toc parsing, chapter indexing (卷 + 品 sections, oversized-卷 splitting), chapter rendering with a source/rendered offset map, text decoding, progress maths. Test with `swift test` on macOS.
- `DzzReader/` — the SwiftUI app: SwiftData models, catalog loader, shelf, reader (TextKit 2 `UITextView`), bookmarks, appearance, import, and the 分享 tab (`Share/`: the vertical quote card ported from `../lecture/index.html`).
- `DzzReaderTests/` — Swift Testing unit tests for the app layer (run on the simulator).
- `DzzReaderUITests/` — XCUITest flows that drive the real app: shelf, reader, chapter list, slider, appearance, bookmarks, relaunch, import.
- `Scripts/copy-books.sh` — build phase that rsyncs `../dzz/toc.txt` and `../dzz/NN/*.txt` into the bundle's `Books/` folder (nothing else from `../dzz` is copied).

## Build

```sh
brew install xcodegen          # once
cd DzzReader
xcodegen generate              # regenerates DzzReader.xcodeproj from project.yml
open DzzReader.xcodeproj       # or:
xcodebuild -project DzzReader.xcodeproj -scheme DzzReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

The corpus must be present at `../dzz` relative to this folder. The first build copies ~350 MB of text into the app; later builds skip it unless `toc.txt` changes.

## Tests

```sh
cd DzzReader/DzzCore && swift test                      # core, fast
DZZ_CORPUS=/path/to/dzz swift test --filter CorpusSmoke # index every file, report 卷数 mismatches
cd .. && xcodebuild test -project DzzReader.xcodeproj -scheme DzzReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

`ImportUITests` expects a `dzz-import-sample.txt` in the simulator's *On My iPhone* storage; see the test file.

## Where things live at runtime

- Catalog, reading progress and bookmarks: SwiftData store in the app's Application Support.
- Imported books: `Documents/Imported/<uuid>.txt`, re-encoded as UTF-8.
- Appearance settings: `UserDefaults` keys prefixed `reader.`.

## Corpus notes the code depends on

- Chapter marks `第0章 ` mark 卷 headings (twice: opening and closing line), 品 sub-headings (once) and, in some files, ordinary paragraphs. The indexer treats marks over 30 characters (parentheticals removed) as body text, collapses closing 卷 lines, and turns 品 marks into jumpable sections.
- Chapters longer than 120,000 UTF-16 units are split into parts titled `…（1/3）`.
- Persisted offsets are source-text offsets; the rendered text only drops the mark prefixes.

## Reading modes

- Books up to 300,000 UTF-16 units (`LoadedBook.wholeBookLimit`, about 97% of the corpus) are rendered as one continuous document; chapters are just positions in it, and the chapter shown in the chrome is whichever one is at the top of the screen.
- Larger books are rendered a chapter at a time. Pulling past the bottom (or top) edge opens the next (or previous) chapter, with a hint once the pull is far enough; a previous-screen swipe on the first screen also goes back a chapter.
- Progress and bookmarks are stored as (chapter index, source offset in that chapter) in both modes.
