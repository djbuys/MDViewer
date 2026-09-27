import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../renderer/renderer_controller.dart';

class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.renderer, required this.onClose, this.initialQuery = ''});

  final RendererController renderer;
  final VoidCallback onClose;
  final String initialQuery;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialQuery);
  final FocusNode _focus = FocusNode();
  late final StreamSubscription<FindResult> _results;
  FindResult _result = FindResult.none;

  @override
  void initState() {
    super.initState();
    _results = widget.renderer.findResults.listen((result) => setState(() => _result = result));
    if (widget.initialQuery.isNotEmpty) unawaited(widget.renderer.find(widget.initialQuery));
  }

  @override
  void dispose() {
    unawaited(_results.cancel());
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    if (query.isEmpty) {
      setState(() => _result = FindResult.none);
      unawaited(widget.renderer.clearFind());
    } else {
      unawaited(widget.renderer.find(query));
    }
  }

  void _next() => unawaited(widget.renderer.findNext());
  void _previous() => unawaited(widget.renderer.findPrevious());

  void _close() {
    unawaited(widget.renderer.clearFind());
    widget.onClose();
  }

  String get _label {
    if (_controller.text.isEmpty) return '';
    if (_result.total == 0) return 'No matches';
    return '${_result.current} of ${_result.total}';
  }

  @override
  Widget build(BuildContext context) {
    final hasMatches = _result.total > 0;
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _close,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): _previous,
          },
          child: Row(
            children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('find-field'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Find in document',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: _onChanged,
                  onSubmitted: (_) {
                    _next();
                    _focus.requestFocus();
                  },
                ),
              ),
              Text(_label, key: const Key('find-count')),
              IconButton(
                key: const Key('find-prev'),
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: hasMatches ? _previous : null,
              ),
              IconButton(
                key: const Key('find-next'),
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: hasMatches ? _next : null,
              ),
              IconButton(
                key: const Key('find-close'),
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
