# MDViewer

A free, open-source, **read-only** Markdown viewer for macOS, Windows, Linux, iOS and Android.

- GitHub-flavoured Markdown: tables, task lists, footnotes, strikethrough, autolinks
- Syntax-highlighted code, KaTeX maths (`$…$`, `$$…$$`, ```` ```math ````) and Mermaid diagrams
- Open a single file or a whole folder: file tree, table of contents, relative links between files, back/forward
- Find in page, search across a folder, print / save as PDF
- Live reload when the file changes on disk (desktop)
- Light, dark or system theme; adjustable text size
- Works fully offline; untrusted HTML in documents is sanitized

## Install

Download the latest build from [Releases](../../releases).

| Platform | File | Notes |
|---|---|---|
| macOS | `MDViewer-macos.dmg` | Unsigned: the first time, right-click the app → Open. |
| Windows | `MDViewer-windows-x64.zip` | Needs the [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (preinstalled on Windows 11). |
| Linux | `MDViewer-linux-x64.tar.gz` | Needs GTK 3 and WPE WebKit, e.g. `sudo apt install libgtk-3-0 libwpewebkit-1.1-0 libwpebackend-fdo-1.0-1` on Ubuntu 24.04. |
| Android | `MDViewer-android.apk` | Allow installing from your browser/files app. |
| iOS | — | Build from source with Xcode (no free distribution channel). |

## Build from source

Requirements: Flutter 3.47+, and for the renderer only, Node 22+.

```bash
flutter pub get
flutter run -d macos   # or windows, linux, ios, android
```

Linux builds need `scripts/install-linux-deps.sh` first.

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
