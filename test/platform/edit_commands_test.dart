import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/edit_commands.dart';

void main() {
  const channel = MethodChannel('mdviewer/edit');

  // The native side answers true when it handled the command (the WebView
  // is the first responder) and false otherwise.
  void mockNative(WidgetTester tester, {required bool handled, List<String>? log}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      log?.add(call.method);
      return handled;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  }

  Future<TextEditingController> pumpField(WidgetTester tester) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(key: const Key('field'), controller: controller, autofocus: true)),
    ));
    await tester.pump();
    return controller;
  }

  testWidgets('select all goes to the focused Flutter text field when the WebView is not focused', (tester) async {
    final log = <String>[];
    mockNative(tester, handled: false, log: log);
    final controller = await pumpField(tester);
    controller.selection = const TextSelection.collapsed(offset: 0);

    await const EditCommands().selectAll();
    await tester.pump();

    expect(log, ['selectAll']);
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 11));
  });

  testWidgets('copy goes to the focused Flutter text field when the WebView is not focused', (tester) async {
    mockNative(tester, handled: false);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final controller = await pumpField(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

    await const EditCommands().copy();
    await tester.pump();

    expect(copied, 'hello');
  });

  testWidgets('when the WebView handled the command, Flutter does nothing', (tester) async {
    mockNative(tester, handled: true);
    final controller = await pumpField(tester);
    controller.selection = const TextSelection.collapsed(offset: 0);

    await const EditCommands().selectAll();
    await tester.pump();

    expect(controller.selection, const TextSelection.collapsed(offset: 0));
  });

  testWidgets('without a native side the Flutter field still gets the command', (tester) async {
    // A null reply is how an unimplemented channel answers (MissingPluginException).
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final controller = await pumpField(tester);
    controller.selection = const TextSelection.collapsed(offset: 0);

    await const EditCommands().selectAll();
    await tester.pump();

    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 11));
  });
}
