import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Copy and Select All from the macOS Edit menu.
///
/// `PlatformMenuBar` replaces the whole native menu, so the standard Edit
/// items (which send `copy:`/`selectAll:` to the first responder) are gone and
/// must be re-created. The native side is asked first: it performs the
/// command when the WebView is the first responder and answers true. Asking
/// the native side first matters because Flutter's own focus does not change
/// when the user clicks into the WebView (a platform view), so a stale
/// Flutter focus must not win. Otherwise the command goes to the focused
/// Flutter text field (find bar, folder search), if any.
class EditCommands {
  const EditCommands({this.channel = const MethodChannel('mdviewer/edit')});

  final MethodChannel channel;

  Future<void> copy() => _run('copy', CopySelectionTextIntent.copy);

  Future<void> selectAll() => _run('selectAll', const SelectAllTextIntent(SelectionChangedCause.keyboard));

  Future<void> _run(String method, Intent intent) async {
    if (await _native(method)) return;
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    if (context.widget is! EditableText && context.findAncestorWidgetOfExactType<EditableText>() == null) return;
    Actions.maybeInvoke(context, intent);
  }

  Future<bool> _native(String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
