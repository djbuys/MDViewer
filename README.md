# MDViewer

A free, open-source, **read-only** Markdown viewer for macOS, Windows, iOS and Android. Linux support is planned (see below).

MDViewer never modifies your documents. The only file it ever writes for you is a PDF you export with **Save as PDF** (macOS and Windows), and only to the location you choose.

- GitHub-flavoured Markdown: tables, task lists, footnotes, strikethrough, autolinks
- Syntax-highlighted code, KaTeX maths (`$…$`, `$$…$$`, ```` ```math ````) and Mermaid diagrams
- Open a single file or a whole folder: file tree, table of contents, relative links between files, back/forward
- Find in page, search across a folder, print, save as PDF (macOS, Windows), share (iOS, Android)
- Live reload when the file changes on disk (desktop)
- Light, dark or system theme; adjustable text size
- Works fully offline; untrusted HTML in documents is sanitized

## Install

Download the latest build from [Releases](../../releases).

| Platform | File | Notes |
|---|---|---|
| macOS | `MDViewer-macos.dmg` | Unsigned: the first time, right-click the app → Open. |
| Windows | `MDViewer-windows-x64.zip` | Needs the [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (preinstalled on Windows 11). |
| Android | `MDViewer-android.apk` | Allow installing from your browser/files app. |
| iOS | — | Build from source with Xcode (no free distribution channel). |

**Linux** is not part of v1. The document view needs WPE WebKit 2.0 on Linux, which Ubuntu no longer packages (it is available on Debian 13+); a build that works across distributions (for example a Flatpak that bundles WPE WebKit) is planned. The Linux runner code stays in the repository.

## Build from source

Requirements: Flutter 3.47+, and for the renderer only, Node 22+.

```bash
flutter pub get
flutter run -d macos   # or windows, ios, android
```

The document renderer is a small web bundle in `renderer/`, prebuilt into `assets/renderer/`. After changing anything in `renderer/`:

```bash
cd renderer && npm ci && npm test && npm run build
```

## Tests

```bash
flutter test                                   # unit and widget tests
flutter test integration_test -d macos         # end-to-end in a real WebView
cd renderer && npm test                        # renderer tests
```

## Design

See [docs/superpowers/specs/2026-09-27-mdviewer-design.md](docs/superpowers/specs/2026-09-27-mdviewer-design.md).

Security: the WebView may only show the bundled renderer page (the exact URL it first loaded), and only that page's main frame can reach the app; documents are sanitized, every link is routed through the app, symbolic links cannot reach files outside the opened folder, and links to executables are never launched.

## Licence

MIT — see [LICENSE](LICENSE).
