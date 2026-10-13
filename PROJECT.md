# Markeer: project notes

## Architecture

A native macOS document application. `MarkdownDocument` owns UTF-8 text and uses `NSDocument` for opening, saving and autosave. `EditorWindowController` combines a plain `NSTextView` source editor with an editable `WKWebView`.

The source text is rendered with vendored cmark-gfm. Rendered blocks retain their original Markdown. The formatted editor converts changed blocks back through Turndown and preserves untouched blocks and reference definitions. Revision identifiers prevent stale editor messages from replacing more recent source edits.

Saving updates relative image URLs without replacing the editor DOM. This preserves WebKit's undo history across the initial save and subsequent saves.

The numbered-list toolbar action uses `insertOrderedList` in the formatted editor. In source mode, it edits whole selected lines, handles UTF-16 text-selection offsets, replaces existing list markers, and leaves unselected lines alone.

## Build and packaging

- Target: Apple Silicon, macOS 13 or later.
- Build: `build.sh`; complete automated checks: `Tests/run.sh`.
- Build products: `dist/`; intermediate files and test dependencies: `.build/`.
- Runtime dependencies are bundled; the app does not need Node.js or Python.
- Sign app bundles in a temporary directory outside iCloud, then package them. Finder metadata in an iCloud folder can invalidate signing checks on the unpacked copy.
- Releases are locally ad-hoc signed. Apple Developer signing and notarization are not included.

## Verification

The automated suite covers rendering, document encodings, source-mode numbered-list edits, formatted text conversion, preservation of existing blocks, table and checkbox edits, relative images, safe code fences, and native bridge messages.

Native window checks cover source/formatted/split views, formatting, undo, tasks, table edits, save/reopen, undo after saving, and the numbered-list button in both editors. The macOS unified log is unavailable inside the command sandbox, so a complete app-log review is not claimed. The legacy optional headless WebKit checks are separate from the passing Swift and DOM suites.

## Current limitations

No math rendering, Jekyll front-matter processing, code syntax highlighting, Markdown auto-completion, or full rendering-preferences interface. Raw HTML is shown literally. Find operates in the source editor. Interface labels are currently Dutch.
