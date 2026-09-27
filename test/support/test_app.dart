import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mdviewer/app_services.dart';
import 'package:mdviewer/document/document_controller.dart';
import 'package:mdviewer/open_actions.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/platform/incoming_files.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:mdviewer/workspace/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_renderer.dart';
import 'fakes.dart';
import 'memory_file_source.dart';

class TestHarness {
  TestHarness({
    required this.services,
    required this.renderer,
    required this.access,
    required this.launcher,
    required this.source,
    required this.sharer,
  });

  final AppServices services;
  final FakeRendererController renderer;
  final FakeDocumentAccess access;
  final FakeLauncher launcher;
  final MemoryFileSource source;
  final FakeSharer sharer;

  /// Suggested names passed to the save-location picker.
  final List<String> saveSuggestions = [];

  /// What the save-location picker answers (null = cancelled).
  String? saveLocation;

  /// Files "written" through [AppServices.writeFile].
  final Map<String, Uint8List> writtenFiles = {};

  /// A folder workspace at /ws containing README.md, guide.md and docs/b.md.
  OpenRequest folderRequest() => OpenRequest(
        workspace: Workspace.folder(source: source, root: '/ws'),
        recent: const RecentEntry(kind: RecentKind.folder, location: '/ws', displayName: 'ws'),
      );
}

/// [resetPreferences] false keeps what an earlier harness saved (a relaunch).
Future<TestHarness> createHarness({IncomingFiles? incoming, bool resetPreferences = true}) async {
  if (resetPreferences) SharedPreferences.setMockInitialValues({});
  final source = MemoryFileSource()
    ..addText('/ws/README.md', '# Readme\n\nSee [guide](guide.md).')
    ..addText('/ws/guide.md', '# Guide')
    ..addText('/ws/docs/b.md', '# B');
  final renderer = FakeRendererController();
  final access = FakeDocumentAccess();
  final launcher = FakeLauncher();
  final settings = await Settings.load();
  final recents = await Recents.load();
  final document = DocumentController(renderer: renderer, launcher: launcher, reloadDebounce: Duration.zero);
  final actions = OpenActions(access: access, recents: recents, document: document);
  final sharer = FakeSharer();
  late final TestHarness harness;
  final services = AppServices(
    settings: settings,
    recents: recents,
    renderer: renderer,
    document: document,
    actions: actions,
    incoming: incoming,
    sharer: sharer,
    pickSaveLocation: (name) async {
      harness.saveSuggestions.add(name);
      return harness.saveLocation;
    },
    writeFile: (path, bytes) async => harness.writtenFiles[path] = bytes,
  );
  return harness = TestHarness(
    services: services,
    renderer: renderer,
    access: access,
    launcher: launcher,
    source: source,
    sharer: sharer,
  );
}

Widget harnessApp(AppServices services, Widget child) => AppScope(
      services: services,
      child: MaterialApp(home: Scaffold(body: child)),
    );
