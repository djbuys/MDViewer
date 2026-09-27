import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';

class FakeRendererController implements RendererController {
  FakeRendererController({
    RendererStatus initialStatus = RendererStatus.ready,
    this.printable = true,
    this.savePdfSupported = true,
  })
      : statusNotifier = ValueNotifier(initialStatus);

  final ValueNotifier<RendererStatus> statusNotifier;
  bool printable;
  bool savePdfSupported;

  /// What [savePdf] answers.
  bool savePdfResult = true;
  final List<String> savedPdfPaths = [];

  /// The render options in effect when [savePdf] / [print] ran.
  final List<RenderOptions?> optionsAtSave = [];
  final List<RenderOptions?> optionsAtPrint = [];

  /// Emit [rendered] (asynchronously) after every [render], like the real
  /// renderer does once a render has finished.
  bool emitRenderedOnRender = false;
  String? reason;
  final List<String> calls = [];
  String? lastMarkdown;
  RenderOptions? lastOptions;
  int renderCount = 0;
  double scrollY = 0;
  ResourceResolver? resolver;

  final _headings = StreamController<List<Heading>>.broadcast(sync: true);
  final _links = StreamController<String>.broadcast(sync: true);
  final _finds = StreamController<FindResult>.broadcast(sync: true);
  final _rendered = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);

  void emitHeadings(List<Heading> headings) => _headings.add(headings);
  void emitLink(String href) => _links.add(href);
  void emitFind(FindResult result) => _finds.add(result);
  void emitRendered() => _rendered.add(null);
  void emitError(String message) => _errors.add(message);

  @override
  ValueListenable<RendererStatus> get status => statusNotifier;
  @override
  String? get unavailableReason => reason;
  @override
  Stream<List<Heading>> get headings => _headings.stream;
  @override
  Stream<String> get linkClicks => _links.stream;
  @override
  Stream<FindResult> get findResults => _finds.stream;
  @override
  Stream<void> get rendered => _rendered.stream;
  @override
  Stream<String> get renderErrors => _errors.stream;
  @override
  set resourceResolver(ResourceResolver? value) => resolver = value;
  @override
  bool get canPrint => printable;
  @override
  bool get canSavePdf => savePdfSupported;

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand(key: ValueKey('fake-renderer'));

  @override
  Future<void> render(String markdown, RenderOptions options) async {
    calls.add('render');
    renderCount++;
    lastMarkdown = markdown;
    lastOptions = options;
    if (emitRenderedOnRender) scheduleMicrotask(emitRendered);
  }

  @override
  Future<void> scrollToHeading(String id) async => calls.add('scrollToHeading:$id');
  @override
  Future<double> scrollPosition() async => scrollY;
  @override
  Future<void> find(String query) async => calls.add('find:$query');
  @override
  Future<void> findNext() async => calls.add('findNext');
  @override
  Future<void> findPrevious() async => calls.add('findPrevious');
  @override
  Future<void> clearFind() async => calls.add('clearFind');
  @override
  Future<void> print() async {
    calls.add('print');
    optionsAtPrint.add(lastOptions);
  }

  @override
  Future<bool> savePdf(String path) async {
    calls.add('savePdf');
    optionsAtSave.add(lastOptions);
    savedPdfPaths.add(path);
    return savePdfResult;
  }

  @override
  void dispose() {
    _headings.close();
    _links.close();
    _finds.close();
    _rendered.close();
    _errors.close();
  }
}
