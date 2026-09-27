# MDViewer — Design Spec

**Date:** 2026-09-27
**Status:** Approved design, pending implementation plan

## 1. Goal

A free, open-source, **read-only** Markdown viewer that runs on macOS, Windows, Linux, iOS and Android from one Flutter codebase. Double-click (or "Open in…") a `.md` file and read it rendered with GitHub-level fidelity, including Mermaid diagrams and LaTeX maths. Open a folder to browse and search a set of Markdown files.

### Non-goals (v1)

- Editing or saving files of any kind.
- Web build target.
- App store distribution (Mac App Store, Play Store, App Store, Microsoft Store).
- Signed/notarized macOS binaries, iOS binary distribution.
- Plugins, custom CSS themes, sync, cloud storage integrations.

## 2. Requirements

### 2.1 Opening content

- Open a single file via: file picker, recent list, desktop CLI argument, desktop drag-and-drop, OS file association / "Open with" (macOS open-file event, Windows/Linux argv, iOS "Open in…", Android `ACTION_VIEW` intent).
- Open a folder via folder picker or recent list; desktop drag-and-drop of a folder.
- Recognized extensions: `.md`, `.markdown`, `.mdown`, `.mkd`.
- Recents: last 10 files/folders, persisted. On iOS/macOS persisted with security-scoped bookmarks; on Android with persisted SAF URI permissions.

### 2.2 Rendering

- CommonMark + GFM: tables, strikethrough, autolinks, task lists (rendered as disabled checkboxes), footnotes.
- Raw HTML in Markdown is allowed but sanitized (see §5).
- Fenced code blocks syntax-highlighted (highlight.js, common languages bundled).
- Maths: `$inline$`, `$$block$$`, and ` ```math ` fences, rendered with KaTeX.
- Diagrams: ` ```mermaid ` fences rendered with Mermaid.
- Headings get GitHub-style slug IDs (so `#anchor` links written for GitHub work).
- YAML front matter (leading `---` block) is stripped and not rendered.
- Images: relative paths resolved against the document's directory; remote `https:` images loaded directly.
- Light, dark, and follow-system themes; styling based on github-markdown-css. Mermaid and highlight.js themes switch with it.
- Adjustable font scale (persisted).

### 2.3 Navigation

- Folder sidebar: tree showing directories and recognized Markdown files; hidden (dot) directories and `node_modules` are excluded.
- TOC panel listing the current document's headings (H1–H4); tapping scrolls to the heading.
- Link routing:
  - relative link to a recognized Markdown file → open it in the app (fragment scrolls to heading);
  - `#fragment` → scroll within current document;
  - `http:`/`https:`/`mailto:` → system handler via `url_launcher`;
  - other relative file → desktop: open with OS default app; mobile: ignored with a snackbar.
- Back/forward history across in-app navigations.

### 2.4 Search

- Find-in-page: query field, match count, next/previous, Escape/close clears highlights. Case-insensitive plain-text match.
- Folder search (only when a folder is open): case-insensitive plain-text search over recognized files, run in a background isolate. Skips files > 5 MB. Caps at 1000 results. Results show file, line number, snippet. Selecting a result opens the file and runs find-in-page for the query.

### 2.5 Live reload

- Desktop: the open document is watched; changes (debounced 200 ms) re-render while preserving scroll position.
- Mobile: re-read and re-render on app resume if the file's modified time changed.

### 2.6 Export

- A Print action prints the rendered document via the platform print path; the OS dialog provides "Save as PDF".
- Per-platform support is verified during implementation; on any platform where printing does not work, the action is hidden.

### 2.7 Layout

- Wide (≥ 900 logical px): three panes — file sidebar (only if a folder is open) | document | TOC. Sidebar and TOC are collapsible.
- Narrow (< 900 px): document full width; file sidebar in the start drawer; TOC in the end drawer.
- App bar: open file, open folder, recents, back/forward, find, folder search (when folder open), theme toggle, print.
- Empty state (nothing open): open-file / open-folder buttons and recents list.

## 3. Architecture

Flutter owns all application chrome and file access. The document is rendered inside a WebView by a bundled, offline JavaScript renderer. The two halves communicate only through a small bridge.

```
┌──────────────────── Flutter app (Dart) ────────────────────┐
│  AppShell (responsive)                                     │
│   ├─ FileSidebar                                           │
│   ├─ DocumentPane ──► RendererView (WebView) ◄─┐           │
│   └─ TocPanel                                   │ JS bridge │
│  Workspace / FileSource   DocumentController ───┘           │
│  FolderSearch (isolate)   Settings & Recents               │
│  IncomingFiles                                             │
└────────────────────────────────────────────────────────────┘
          assets/renderer/  (index.html + renderer.bundle.js + css + fonts)
```

### 3.1 JS renderer (`renderer/` → `assets/renderer/`)

An npm project bundled with esbuild into `assets/renderer/`. The built output is committed so Flutter builds never need Node. No network access is required.

Libraries: markdown-it (+ task-lists, footnote, anchor/slug, texmath or equivalent KaTeX plugin), highlight.js, KaTeX, Mermaid, DOMPurify, github-markdown-css.

Dart → JS API (called via `evaluateJavascript`):

| Function | Purpose |
|---|---|
| `render(markdown, options)` | options: `{theme: 'light'|'dark', fontScale, heavyFeatures: bool}`; replaces document content |
| `setTheme(theme)` | switch theme without re-parsing |
| `scrollToHeading(id)` | smooth-scroll to heading ID |
| `getScrollPosition()` / `setScrollPosition(y)` | preserve scroll across reloads |
| `find(query)` / `findNext()` / `findPrev()` / `clearFind()` | find-in-page via text-node highlighting |
| `print()` | invoke print where done from JS |

JS → Dart events (via WebView JavaScript handlers):

| Event | Payload |
|---|---|
| `ready` | renderer loaded |
| `headingsChanged` | `[{id, text, level}]` |
| `linkClicked` | `{href}` |
| `resolveResource` | `{path}` → returns `data:` URI or `null` |
| `findResult` | `{total, current}` |
| `renderError` | `{message}` (unexpected renderer failure) |

Pure logic (Markdown → sanitized HTML, heading extraction, link classification, front-matter stripping) lives in modules with no DOM dependency so it can be tested in Node.

### 3.2 Dart components (`lib/`)

| Unit | Responsibility | Depends on |
|---|---|---|
| `workspace/file_source.dart` | Interface: `list(dir)`, `readText(path)`, `readBytes(path)`, `stat(path)`, `watch(path)` | — |
| `workspace/io_file_source.dart` | `dart:io` implementation (desktop, iOS) | — |
| `workspace/saf_file_source.dart` | Android SAF implementation over a Kotlin method channel (`openDocumentTree`, `listChildren`, `readBytes`, `stat`, persisted permissions) | platform channel |
| `workspace/workspace.dart` | Single-file or folder root; relative path resolution, containment checks, tree building | `FileSource` |
| `document/text_decoding.dart` | UTF-8 decode with BOM handling and lossy fallback | — |
| `document/link_router.dart` | Classifies an href into in-app doc / anchor / external / other-file | `Workspace` |
| `document/document_controller.dart` | Current doc, load state, history, reload, routing link events | `Workspace`, `FileSource`, `LinkRouter` |
| `renderer/renderer_controller.dart` | Interface mirroring the JS API + event streams | — |
| `renderer/webview_renderer.dart` | `flutter_inappwebview` implementation; intercepts all navigation; serves `resolveResource` | `FileSource` |
| `renderer/plain_text_fallback.dart` | Selectable monospace view used when the WebView is unavailable | — |
| `search/folder_search.dart` | Isolate-based full-text search | `FileSource` |
| `search/find_bar.dart` | Find-in-page UI | `RendererController` |
| `platform/incoming_files.dart` | Stream of opened paths/URIs from argv, drag-drop, macOS/iOS/Android open events | platform channels, `desktop_drop` |
| `settings/settings.dart`, `settings/recents.dart` | Theme, font scale, recents (with bookmarks/persisted URIs) | `shared_preferences`, platform channels |
| `ui/*` | `AppShell`, `FileSidebar`, `TocPanel`, `DocumentPane`, `ErrorView`, empty state | controllers above |

State management: `ChangeNotifier` controllers exposed through a single `InheritedWidget` app scope, consumed with `ListenableBuilder`. No state-management library.

Native code (kept minimal, one method channel per platform):
- macOS: forward `application(_:open:)` open-file events; security-scoped bookmarks for recents.
- iOS: `LSSupportsOpeningDocumentsInPlace`, document types for Markdown UTIs, incoming URL forwarding, security-scoped bookmarks.
- Android: intent filters for `ACTION_VIEW` on `text/markdown`, `text/x-markdown` and the recognized extensions; SAF channel for §3.2.
- Windows/Linux: file associations are set up by the user/packager; the app reads `argv`.

### 3.3 Dependency decisions

- `flutter_inappwebview`: use the version line that endorses `flutter_inappwebview_linux` (6.2.0 beta line) so Linux gets an inline WPE WebKit view. If that line proves unstable on the other four platforms, pin 6.1.5 and Linux uses the plain-text fallback (§5) until the Linux implementation stabilizes.
- `flutter_markdown` is discontinued and is not used.
- Other packages: `file_picker`, `url_launcher`, `shared_preferences`, `desktop_drop`, `path`, `watcher`.

## 4. Data flow

**Open document:** `IncomingFiles`/picker → `Workspace` set → `DocumentController.open(path)` → `FileSource.readText` → `decode` → `renderer.render(text, options)` → renderer parses, sanitizes, highlights, typesets maths, renders Mermaid asynchronously → emits `headingsChanged` (→ `TocPanel`) → for each relative `<img>`, calls `resolveResource(path)` → Dart resolves against the document directory via `Workspace`, reads bytes, returns `data:` URI.

**Link click:** WebView navigation is always cancelled → renderer emits `linkClicked` → `LinkRouter.classify` → `DocumentController` opens doc / scrolls / launches externally.

**Live reload:** `FileSource.watch` event (debounced 200 ms) → save scroll position → re-read → `render` → restore scroll position.

**Folder search:** query → isolate walks workspace files → streamed results → select → `open(path)` → `find(query)`.

## 5. Security and error handling

### Security

- All markdown-it output passes through DOMPurify before insertion: no `<script>`, no inline event handlers, no `javascript:`/`vbscript:` URLs, no `<iframe>`/`<object>`/`<embed>`.
- `index.html` sets a CSP: scripts only from the bundle (`'self'`), styles from `'self'` plus inline styles needed by KaTeX/Mermaid, images from `data:` and `https:`, fonts from `'self'`, `frame-src 'none'`, `connect-src 'none'`.
- The WebView never navigates away from the renderer page; every navigation is intercepted and routed through `LinkRouter`.
- `resolveResource` only serves files inside the workspace root (folder mode) or the document's directory tree (single-file mode) — path traversal outside is refused and returns `null`.

### Error handling

| Situation | Behaviour |
|---|---|
| File missing or unreadable | `ErrorView` in document pane: path, reason, Retry |
| Open file deleted during live reload | Keep last render; banner "File no longer exists" |
| Invalid UTF-8 | Lossy decode (replacement characters); never crash |
| Mermaid syntax error | Error message inside that diagram block; rest of document renders |
| KaTeX error | Raw TeX shown in error colour in place of formula |
| Relative image missing/refused | Broken-image placeholder showing alt text |
| WebView unavailable (e.g. no WebView2 runtime on Windows, no WPE libs on Linux, unsupported plugin version) | `PlainTextFallback` with banner explaining what to install |
| File > 5 MB | Rendered with `heavyFeatures: false` (no highlighting, Mermaid or KaTeX; blocks shown as code) |
| File > 50 MB | `PlainTextFallback` with banner "File too large to render" |
| Renderer `renderError` | `ErrorView` with message and a "Show as plain text" action |

## 6. Testing

- **Renderer (Node, `node --test`):** Markdown → sanitized HTML (tables, task lists, footnotes, maths and mermaid block detection), heading slug extraction incl. duplicates, link classification, front-matter stripping, XSS cases (`<script>`, `onerror=`, `javascript:` hrefs, `<iframe>`).
- **Dart unit tests** (in-memory `FileSource` fake): `Workspace` resolution and containment, `LinkRouter` classification, `DocumentController` history/reload/error states, `FolderSearch` (limits, exclusions), `text_decoding`, `Settings`/`Recents` persistence.
- **Widget tests** (`FakeRendererController`): `AppShell` at 1280 px and 390 px widths, TOC tap → `scrollToHeading`, link events → routing, `ErrorView`, plain-text fallback, empty state.
- **Integration test** (`integration_test`, macOS): real WebView opens `test_fixtures/sample_folder/`; asserts headings received, a Mermaid SVG exists, a relative image resolves to a `data:` URI, a relative link navigates to the second file.

## 7. Build, CI and release

- Repository: `github.com/djbuys/MDViewer` (to be created), MIT licence.
- App name `MDViewer`, bundle/application ID `io.github.djbuys.mdviewer`.
- `ci.yml` on push/PR: `flutter analyze`, `flutter test`, renderer `npm ci && npm test`, check that committed `assets/renderer/` matches a fresh build, macOS integration test.
- `release.yml` on `v*` tag: build macOS (`.dmg`, unsigned), Windows (zip), Linux (`tar.gz`), Android (APK, signed with a release keystore stored in GitHub secrets); attach to a GitHub Release.
- Known distribution limitations, documented in README: macOS first launch requires right-click → Open (unsigned); iOS must be built from source (no free distribution channel without an Apple Developer account).

## 8. Project layout

```
MDViewer/
├─ lib/
│  ├─ main.dart, app.dart
│  ├─ workspace/  document/  renderer/  search/  platform/  settings/  ui/
├─ renderer/            package.json, build.mjs, src/*.js, test/*.test.js
├─ assets/renderer/     built output (committed)
├─ test/  integration_test/  test_fixtures/
├─ macos/ windows/ linux/ ios/ android/
├─ .github/workflows/   ci.yml, release.yml
├─ LICENSE, README.md
```

## 9. Risks

| Risk | Mitigation |
|---|---|
| Linux WebView plugin is beta (`flutter_inappwebview_linux` 0.1.0-beta.1) | Plain-text fallback; option to pin stable 6.1.5 and defer Linux rendering |
| Printing unsupported on some WebView platforms | Verify per platform; hide action where unsupported |
| Android SAF complexity | Isolated behind `FileSource`; minimal Kotlin channel with its own tests on emulator |
| Mermaid bundle size (~3 MB) | Acceptable for desktop/mobile app size; loaded once per WebView |
| Windows/Linux builds cannot be produced on this Mac | Built and smoke-tested in GitHub Actions |
