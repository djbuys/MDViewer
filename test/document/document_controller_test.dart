import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/document_controller.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/workspace/io_file_source.dart';
import 'package:mdviewer/workspace/workspace.dart';
import 'package:path/path.dart' as p;

import '../support/fake_renderer.dart';
import '../support/fakes.dart';
import '../support/memory_file_source.dart';

void main() {
  late MemoryFileSource source;
  late FakeRendererController renderer;
  late FakeLauncher launcher;
  late DocumentController controller;
  late Workspace workspace;

  setUp(() {
    source = MemoryFileSource()
      ..addText('/ws/README.md', '# Readme\n[b](docs/b.md)')
      ..addText('/ws/docs/b.md', '# B')
      ..addText('/ws/docs/pic.png', 'PNGDATA')
      ..addText('/ws/docs/notes.txt', 'text');
    renderer = FakeRendererController();
    launcher = FakeLauncher();
    controller = DocumentController(
      renderer: renderer,
      launcher: launcher,
      reloadDebounce: Duration.zero,
      largeFileBytes: 100,
      hugeFileBytes: 1000,
      maxImageBytes: 50,
    );
    workspace = Workspace.folder(source: source, root: '/ws');
  });

  tearDown(() => controller.dispose());

  test('starts empty', () {
    expect(controller.status, DocumentStatus.empty);
    expect(controller.currentPath, isNull);
    expect(controller.title, 'MDViewer');
  });

  test('opening a folder shows its README and renders it', () async {
    await controller.openWorkspace(workspace);
    expect(controller.status, DocumentStatus.ready);
    expect(controller.currentPath, '/ws/README.md');
    expect(controller.title, 'README.md');
    expect(renderer.lastMarkdown, '# Readme\n[b](docs/b.md)');
    expect(renderer.lastOptions!.heavyFeatures, isTrue);
    expect(renderer.lastOptions!.dark, isFalse);
  });

  test('opening a folder without a default document stays empty', () async {
    final bare = MemoryFileSource()..addText('/w/z.md', '# Z');
    await controller.openWorkspace(Workspace.folder(source: bare, root: '/w'));
    expect(controller.status, DocumentStatus.empty);
    expect(controller.workspace!.root, '/w');
    expect(renderer.renderCount, 0);
  });

  test('opening an explicit file in a workspace', () async {
    await controller.openWorkspace(workspace, file: '/ws/docs/b.md');
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(renderer.lastMarkdown, '# B');
  });

  test('a missing file produces an error state', () async {
    await controller.openWorkspace(workspace, file: '/ws/missing.md');
    expect(controller.status, DocumentStatus.error);
    expect(controller.errorMessage, contains('/ws/missing.md'));
    expect(renderer.renderCount, 0);
  });

  test('large files render without heavy features; huge files are not rendered', () async {
    source
      ..addBytes('/ws/large.md', Uint8List(101))
      ..addBytes('/ws/huge.md', Uint8List(1001));
    await controller.openWorkspace(workspace, file: '/ws/large.md');
    expect(renderer.lastOptions!.heavyFeatures, isFalse);
    expect(controller.heavyFeatures, isFalse);

    final before = renderer.renderCount;
    await controller.open('/ws/huge.md');
    expect(controller.tooLarge, isTrue);
    expect(controller.status, DocumentStatus.ready);
    expect(controller.text, isNotNull);
    expect(renderer.renderCount, before);
  });

  test('headings from the renderer are exposed and notify listeners', () async {
    await controller.openWorkspace(workspace);
    var notified = 0;
    controller.addListener(() => notified++);
    renderer.emitHeadings(const [Heading(id: 'readme', text: 'Readme', level: 1)]);
    expect(controller.headings.single.id, 'readme');
    expect(notified, 1);
  });

  test('relative markdown links navigate with back/forward history', () async {
    await controller.openWorkspace(workspace);
    renderer.emitLink('docs/b.md');
    await settle();
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(controller.canGoBack, isTrue);
    expect(controller.canGoForward, isFalse);

    await controller.goBack();
    expect(controller.currentPath, '/ws/README.md');
    expect(controller.canGoForward, isTrue);

    await controller.goForward();
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(controller.canGoForward, isFalse);
  });

  test('opening a new document clears forward history', () async {
    await controller.openWorkspace(workspace);
    await controller.open('/ws/docs/b.md');
    await controller.goBack();
    await controller.open('/ws/docs/b.md');
    expect(controller.canGoForward, isFalse);
  });

  test('link fragments scroll after the target document has rendered', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('docs/b.md#part');
    expect(renderer.calls, isNot(contains('scrollToHeading:part')));
    renderer.emitRendered();
    await settle();
    expect(renderer.calls, contains('scrollToHeading:part'));
  });

  test('anchor links and same-document links scroll without reloading', () async {
    await controller.openWorkspace(workspace);
    final renders = renderer.renderCount;
    await controller.handleLink('#intro');
    await controller.handleLink('README.md#usage');
    expect(renderer.calls, containsAll(['scrollToHeading:intro', 'scrollToHeading:usage']));
    expect(renderer.renderCount, renders);
    expect(controller.canGoBack, isFalse);
  });

  test('external links go to the launcher', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('https://example.com');
    expect(launcher.launched, [Uri.parse('https://example.com')]);
  });

  test('non-markdown workspace files open with the OS when supported', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('docs/notes.txt');
    expect(launcher.opened, ['/ws/docs/notes.txt']);
  });

  test('non-markdown files report a message when the OS cannot open them', () async {
    launcher.canOpenFiles = false;
    await controller.openWorkspace(workspace);
    final messages = <String>[];
    controller.messages.listen(messages.add);
    await controller.handleLink('docs/notes.txt');
    await settle();
    expect(launcher.opened, isEmpty);
    expect(messages.single, contains('notes.txt'));
  });

  test('links to executables are blocked instead of launched', () async {
    source
      ..addText('/ws/tools/setup.EXE', 'MZ')
      ..addText('/ws/tools/run.sh', '#!/bin/sh')
      ..addText('/ws/tools/Installer.AppImage', 'x')
      ..addText('/ws/tools/launch.command', 'x');
    await controller.openWorkspace(workspace);
    final messages = <String>[];
    controller.messages.listen(messages.add);
    await controller.handleLink('tools/setup.EXE');
    await controller.handleLink('tools/run.sh');
    await controller.handleLink('tools/Installer.AppImage');
    await controller.handleLink('tools/launch.command');
    await settle();
    expect(launcher.opened, isEmpty);
    expect(messages, [
      'Opening setup.EXE is blocked for safety',
      'Opening run.sh is blocked for safety',
      'Opening Installer.AppImage is blocked for safety',
      'Opening launch.command is blocked for safety',
    ]);
  });

  test('the executable denylist covers common launchable types', () {
    for (final ext in [
      '.exe', '.bat', '.cmd', '.com', '.msi', '.ps1', '.vbs', '.js', '.jse', '.wsf', '.scr', '.lnk', '.reg', //
      '.jar', '.app', '.command', '.sh', '.bash', '.zsh', '.csh', '.pkg', '.dmg', '.desktop', '.run', '.bin',
      '.appimage', '.deb', '.rpm', '.apk',
    ]) {
      expect(isBlockedExecutable('/x/file$ext'), isTrue, reason: ext);
      expect(isBlockedExecutable('/x/FILE${ext.toUpperCase()}'), isTrue, reason: ext);
    }
    expect(isBlockedExecutable('/x/notes.txt'), isFalse);
    expect(isBlockedExecutable('/x/report.pdf'), isFalse);
    expect(isBlockedExecutable('/x/Makefile'), isFalse);
  });

  test('the denylist also covers scripts, shortcuts and launcher files', () {
    for (final ext in [
      '.hta', '.cpl', '.msc', '.pif', '.scf', '.vbe', '.wsh', '.py', '.pyw', '.pl', '.rb', '.appref-ms', //
      '.application', '.jnlp', '.settingcontent-ms', '.url', '.website', '.tool', '.terminal', '.workflow',
      '.action', '.scpt', '.applescript', '.osx', '.inetloc', '.fileloc', '.webloc', '.desktop',
    ]) {
      expect(isBlockedExecutable('/x/file$ext'), isTrue, reason: ext);
      expect(isBlockedExecutable('/x/FILE${ext.toUpperCase()}'), isTrue, reason: ext);
    }
  });

  group('launch policy', () {
    test('on macOS/Linux, files without an extension are refused', () async {
      const posix = LaunchPolicy(posixChecks: true);
      expect(await posix.blocks('/x/Makefile'), isTrue);
      expect(await posix.blocks('/x/.profile'), isTrue);
      expect(await posix.blocks('/x/notes.txt'), isFalse);
      expect(await posix.blocks('/x/run.sh'), isTrue);
      const other = LaunchPolicy(posixChecks: false);
      expect(await other.blocks('/x/Makefile'), isFalse);
      expect(await other.blocks('/x/run.sh'), isTrue);
    });

    test('on macOS/Linux, files with any execute bit are refused', () async {
      final dir = await Directory.systemTemp.createTemp('mdv_exec');
      addTearDown(() => dir.delete(recursive: true));
      final plain = File(p.join(dir.path, 'notes.txt'))..writeAsStringSync('text');
      final script = File(p.join(dir.path, 'innocent.txt'))..writeAsStringSync('#!/bin/sh\necho hi');
      final groupOnly = File(p.join(dir.path, 'group.txt'))..writeAsStringSync('x');
      expect((await Process.run('chmod', ['u+x', script.path])).exitCode, 0);
      expect((await Process.run('chmod', ['g+x', groupOnly.path])).exitCode, 0);
      const posix = LaunchPolicy(posixChecks: true);
      expect(await posix.blocks(plain.path), isFalse);
      expect(await posix.blocks(script.path), isTrue);
      expect(await posix.blocks(groupOnly.path), isTrue);
    }, skip: Platform.isWindows);

    test('the host policy does the POSIX checks on macOS and Linux only', () {
      expect(LaunchPolicy.forHost().posixChecks, Platform.isMacOS || Platform.isLinux);
    });

    test('links to extensionless files are blocked with the POSIX policy', () async {
      final strict = DocumentController(
        renderer: renderer,
        launcher: launcher,
        reloadDebounce: Duration.zero,
        launchPolicy: const LaunchPolicy(posixChecks: true),
      );
      addTearDown(strict.dispose);
      source.addText('/ws/tools/install', '#!/bin/sh');
      await strict.openWorkspace(workspace);
      final messages = <String>[];
      strict.messages.listen(messages.add);
      await strict.handleLink('tools/install');
      await strict.handleLink('docs/notes.txt');
      await settle();
      expect(launcher.opened, ['/ws/docs/notes.txt']);
      expect(messages, ['Opening install is blocked for safety']);
    });
  });

  test('unsupported links report a message', () async {
    await controller.openWorkspace(workspace);
    final messages = <String>[];
    controller.messages.listen(messages.add);
    await controller.handleLink('javascript:alert(1)');
    await controller.handleLink('../../etc/passwd.md');
    await settle();
    expect(messages, hasLength(2));
  });

  test('resolves relative images to data URIs inside the workspace only', () async {
    await controller.openWorkspace(workspace, file: '/ws/docs/b.md');
    expect(renderer.resolver, isNotNull);
    expect(
      await controller.resolveResource('pic.png'),
      'data:image/png;base64,${base64Encode(utf8.encode('PNGDATA'))}',
    );
    expect(await controller.resolveResource('missing.png'), isNull);
    expect(await controller.resolveResource('notes.txt'), isNull);
    expect(await controller.resolveResource('../../outside.png'), isNull);
  });

  test('images larger than the cap are not resolved', () async {
    source
      ..addBytes('/ws/docs/big.png', Uint8List(51))
      ..addBytes('/ws/docs/ok.png', Uint8List(50));
    await controller.openWorkspace(workspace, file: '/ws/docs/b.md');
    source.reads.clear();
    expect(await controller.resolveResource('big.png'), isNull);
    expect(source.reads, isEmpty, reason: 'the size is checked before reading');
    expect(await controller.resolveResource('ok.png'), startsWith('data:image/png;base64,'));
  });

  test('the default image cap is 20 MB', () {
    final defaults = DocumentController(renderer: FakeRendererController(), launcher: FakeLauncher());
    addTearDown(defaults.dispose);
    expect(defaults.maxImageBytes, 20 * 1024 * 1024);
  });

  test('image mime types', () {
    expect(imageMimeType('a.PNG'), 'image/png');
    expect(imageMimeType('a.jpeg'), 'image/jpeg');
    expect(imageMimeType('a.svg'), 'image/svg+xml');
    expect(imageMimeType('a.txt'), isNull);
  });

  test('appearance changes re-render the current document preserving scroll', () async {
    await controller.openWorkspace(workspace);
    renderer.scrollY = 120;
    final renders = renderer.renderCount;
    controller.setAppearance(dark: true, fontScale: 1.2);
    await settle();
    expect(renderer.renderCount, renders + 1);
    expect(renderer.lastOptions!.dark, isTrue);
    expect(renderer.lastOptions!.fontScale, 1.2);
    expect(renderer.lastOptions!.restoreScrollY, 120);

    controller.setAppearance(dark: true, fontScale: 1.2);
    await settle();
    expect(renderer.renderCount, renders + 1);
  });

  test('appearance set before opening is used for the first render', () async {
    controller.setAppearance(dark: true, fontScale: 1.4);
    await controller.openWorkspace(workspace);
    expect(renderer.lastOptions!.dark, isTrue);
    expect(renderer.lastOptions!.fontScale, 1.4);
  });

  test('renderer errors become an error state that can fall back to plain text', () async {
    await controller.openWorkspace(workspace);
    renderer.emitError('boom');
    expect(controller.status, DocumentStatus.error);
    expect(controller.errorMessage, contains('boom'));
    controller.showAsPlainText();
    expect(controller.status, DocumentStatus.ready);
    expect(controller.showPlainText, isTrue);
    await controller.open('/ws/docs/b.md');
    expect(controller.showPlainText, isFalse);
  });

  group('with real files and symbolic links', () {
    late Directory temp;
    late String ws;
    late String outside;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('mdv_doc_links');
      ws = p.join(temp.path, 'ws');
      outside = p.join(temp.path, 'outside');
      await Directory(ws).create();
      await Directory(outside).create();
      File(p.join(outside, 'secret.md')).writeAsStringSync('# Secret');
      File(p.join(outside, 'secret.png')).writeAsStringSync('SECRETPNG');
      File(p.join(ws, 'README.md')).writeAsStringSync('# Readme');
      File(p.join(ws, 'inner.png')).writeAsStringSync('PNG');
      Link(p.join(ws, 'leak.md')).createSync(p.join(outside, 'secret.md'));
      Link(p.join(ws, 'leak.png')).createSync(p.join(outside, 'secret.png'));
      Link(p.join(ws, 'alias.md')).createSync(p.join(ws, 'README.md'));
      Link(p.join(ws, 'linked')).createSync(outside);
    });

    tearDown(() => temp.delete(recursive: true));

    test('images behind escaping symlinks are not resolved', () async {
      await controller.openWorkspace(Workspace.folder(source: IoFileSource(supportsWatch: false), root: ws));
      expect(controller.status, DocumentStatus.ready);
      expect(await controller.resolveResource('inner.png'), 'data:image/png;base64,${base64Encode(utf8.encode('PNG'))}');
      expect(await controller.resolveResource('leak.png'), isNull);
      expect(await controller.resolveResource('linked/secret.png'), isNull);
    });

    test('documents behind escaping symlinks are refused; internal links are fine', () async {
      await controller.openWorkspace(Workspace.folder(source: IoFileSource(supportsWatch: false), root: ws));
      await controller.handleLink('leak.md');
      expect(controller.status, DocumentStatus.error);
      expect(controller.errorMessage, contains('outside the opened folder'));
      expect(renderer.lastMarkdown, '# Readme');

      await controller.open(p.join(ws, 'linked', 'secret.md'));
      expect(controller.status, DocumentStatus.error);
      expect(renderer.lastMarkdown, '# Readme');

      await controller.open(p.join(ws, 'alias.md'));
      expect(controller.status, DocumentStatus.ready);
    });

    test('file links are not launched through escaping or executable symlinks', () async {
      File(p.join(outside, 'tool.sh')).writeAsStringSync('#!/bin/sh');
      File(p.join(outside, 'notes.txt')).writeAsStringSync('outside');
      File(p.join(ws, 'inside.txt')).writeAsStringSync('inside');
      File(p.join(ws, 'script.sh')).writeAsStringSync('#!/bin/sh');
      Link(p.join(ws, 'report.txt')).createSync(p.join(ws, 'script.sh'));
      Link(p.join(ws, 'other.txt')).createSync(p.join(outside, 'notes.txt'));
      await controller.openWorkspace(Workspace.folder(source: IoFileSource(supportsWatch: false), root: ws));
      final messages = <String>[];
      controller.messages.listen(messages.add);

      await controller.handleLink('report.txt');
      await controller.handleLink('other.txt');
      await controller.handleLink('inside.txt');
      await settle();
      expect(messages, ['Opening report.txt is blocked for safety', 'Opening other.txt is blocked for safety']);
      expect(launcher.opened, [p.join(ws, 'inside.txt')]);
    });

    test('a symlinked file the user opened explicitly still opens', () async {
      final file = p.join(ws, 'leak.md');
      await controller.openWorkspace(
        Workspace.singleFile(source: IoFileSource(supportsWatch: false), file: file),
        file: file,
      );
      expect(controller.status, DocumentStatus.ready);
      expect(renderer.lastMarkdown, '# Secret');
    });
  });
}
