import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';

class FakeRendererController implements RendererController {
  FakeRendererController({RendererStatus initialStatus = RendererStatus.ready, this.printable = true})
      : statusNotifier = ValueNotifier(initialStatus);

  final ValueNotifier<RendererStatus> statusNotifier;
  bool printable;
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
  Widget buildView(BuildContext context) => const SizedBox.expand(key: ValueKey('fake-renderer'));

  @override
  Future<void> render(String markdown, RenderOptions options) async {
    calls.add('render');
    renderCount++;
    lastMarkdown = markdown;
    lastOptions = options;
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
  Future<void> print() async => calls.add('print');

  @override
  void dispose() {
    _headings.close();
    _links.close();
    _finds.close();
    _rendered.close();
    _errors.close();
  }
}
