import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

@immutable
class Heading {
  const Heading({required this.id, required this.text, required this.level});

  factory Heading.fromJson(Map<dynamic, dynamic> json) => Heading(
        id: json['id'] as String,
        text: json['text'] as String,
        level: (json['level'] as num).toInt(),
      );

  final String id;
  final String text;
  final int level;

  @override
  bool operator ==(Object other) => other is Heading && other.id == id && other.text == text && other.level == level;
  @override
  int get hashCode => Object.hash(id, text, level);
  @override
  String toString() => 'Heading($level, $id, $text)';
}

@immutable
class FindResult {
  const FindResult({required this.total, required this.current});

  factory FindResult.fromJson(Map<dynamic, dynamic> json) =>
      FindResult(total: (json['total'] as num).toInt(), current: (json['current'] as num).toInt());

  static const none = FindResult(total: 0, current: 0);

  final int total;

  /// 1-based index of the highlighted match; 0 when there are no matches.
  final int current;

  @override
  bool operator ==(Object other) => other is FindResult && other.total == total && other.current == current;
  @override
  int get hashCode => Object.hash(total, current);
  @override
  String toString() => 'FindResult($current/$total)';
}

@immutable
class RenderOptions {
  const RenderOptions({
    required this.dark,
    required this.fontScale,
    required this.heavyFeatures,
    this.restoreScrollY,
  });

  final bool dark;
  final double fontScale;

  /// Syntax highlighting, maths and diagrams. Disabled for large files.
  final bool heavyFeatures;
  final double? restoreScrollY;

  Map<String, Object?> toJson() => {
        'theme': dark ? 'dark' : 'light',
        'fontScale': fontScale,
        'heavyFeatures': heavyFeatures,
        if (restoreScrollY != null) 'restoreScrollY': restoreScrollY,
      };
}

enum RendererStatus { loading, ready, unavailable }

/// Resolves a relative resource reference to a `data:` URI, or null.
typedef ResourceResolver = Future<String?> Function(String path);

/// Renders Markdown for display. The production implementation hosts the
/// bundled JS renderer in a WebView; tests use a fake.
abstract interface class RendererController {
  ValueListenable<RendererStatus> get status;

  /// Human-readable explanation when [status] is unavailable.
  String? get unavailableReason;

  Stream<List<Heading>> get headings;
  Stream<String> get linkClicks;
  Stream<FindResult> get findResults;

  /// Fires after a render finished, including images and diagrams.
  Stream<void> get rendered;
  Stream<String> get renderErrors;

  set resourceResolver(ResourceResolver? resolver);

  bool get canPrint;

  Widget buildView(BuildContext context);

  Future<void> render(String markdown, RenderOptions options);
  Future<void> scrollToHeading(String id);
  Future<double> scrollPosition();
  Future<void> find(String query);
  Future<void> findNext();
  Future<void> findPrevious();
  Future<void> clearFind();
  Future<void> print();
  void dispose();
}
