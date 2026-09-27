import 'package:flutter/foundation.dart';

import '../workspace/workspace.dart';

@immutable
sealed class LinkTarget {
  const LinkTarget();
}

class InDocumentAnchor extends LinkTarget {
  const InDocumentAnchor(this.fragment);
  final String fragment;

  @override
  bool operator ==(Object other) => other is InDocumentAnchor && other.fragment == fragment;
  @override
  int get hashCode => fragment.hashCode;
  @override
  String toString() => 'InDocumentAnchor($fragment)';
}

class WorkspaceDocument extends LinkTarget {
  const WorkspaceDocument(this.path, this.fragment);
  final String path;
  final String? fragment;

  @override
  bool operator ==(Object other) => other is WorkspaceDocument && other.path == path && other.fragment == fragment;
  @override
  int get hashCode => Object.hash(path, fragment);
  @override
  String toString() => 'WorkspaceDocument($path, $fragment)';
}

class ExternalLink extends LinkTarget {
  const ExternalLink(this.uri);
  final Uri uri;

  @override
  bool operator ==(Object other) => other is ExternalLink && other.uri == uri;
  @override
  int get hashCode => uri.hashCode;
  @override
  String toString() => 'ExternalLink($uri)';
}

class WorkspaceFile extends LinkTarget {
  const WorkspaceFile(this.path);
  final String path;

  @override
  bool operator ==(Object other) => other is WorkspaceFile && other.path == path;
  @override
  int get hashCode => path.hashCode;
  @override
  String toString() => 'WorkspaceFile($path)';
}

class UnsupportedLink extends LinkTarget {
  const UnsupportedLink(this.href);
  final String href;

  @override
  bool operator ==(Object other) => other is UnsupportedLink && other.href == href;
  @override
  int get hashCode => href.hashCode;
  @override
  String toString() => 'UnsupportedLink($href)';
}

final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
const Set<String> _externalSchemes = {'http', 'https', 'mailto'};

class LinkRouter {
  const LinkRouter(this.workspace);

  final Workspace workspace;

  LinkTarget classify(String href, {required String currentFile}) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return UnsupportedLink(href);
    if (trimmed.startsWith('#')) return InDocumentAnchor(_decode(trimmed.substring(1)));

    final scheme = _scheme.firstMatch(trimmed)?.group(1)?.toLowerCase();
    if (scheme != null) {
      return _externalSchemes.contains(scheme) ? ExternalLink(Uri.parse(trimmed)) : UnsupportedLink(href);
    }

    final hashAt = trimmed.indexOf('#');
    final fragment = hashAt == -1 ? null : _decode(trimmed.substring(hashAt + 1));
    var pathPart = hashAt == -1 ? trimmed : trimmed.substring(0, hashAt);
    final queryAt = pathPart.indexOf('?');
    if (queryAt != -1) pathPart = pathPart.substring(0, queryAt);
    if (pathPart.isEmpty) return fragment == null ? UnsupportedLink(href) : InDocumentAnchor(fragment);

    final resolved = workspace.resolve(currentFile, pathPart);
    if (resolved == null) return UnsupportedLink(href);
    if (isMarkdownPath(resolved, workspace.source.pathContext)) {
      return WorkspaceDocument(resolved, (fragment == null || fragment.isEmpty) ? null : fragment);
    }
    return WorkspaceFile(resolved);
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }
}
