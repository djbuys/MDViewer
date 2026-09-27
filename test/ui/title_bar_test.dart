import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/window_controls.dart';
import 'package:mdviewer/ui/app_actions.dart';
import 'package:mdviewer/ui/title_bar.dart';

void main() {
  const channel = MethodChannel('mdviewer/window');

  Future<List<String>> pumpBar(WidgetTester tester, {required TargetPlatform platform, VoidCallback? onTheme}) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: MdTitleBar(
          title: 'README.md',
          platform: platform,
          actions: [
            AppAction(
              id: 'theme',
              label: 'Theme',
              icon: Icons.brightness_auto,
              onSelected: onTheme ?? () {},
              group: ActionGroup.view,
              priority: ActionPriority.appearance,
            ),
          ],
        ),
      ),
    ));
    return calls;
  }

  testWidgets('macOS: dragging the empty title area moves the window', (tester) async {
    final calls = await pumpBar(tester, platform: TargetPlatform.macOS);
    await tester.drag(find.byKey(const Key('title-bar-title')), const Offset(40, 10));
    await tester.pumpAndSettle();
    expect(calls, ['startDrag']);

    calls.clear();
    await tester.dragFrom(const Offset(20, 26), const Offset(30, 0)); // traffic-light inset
    await tester.pumpAndSettle();
    expect(calls, ['startDrag']);
  });

  testWidgets('macOS: double-clicking the empty title area zooms', (tester) async {
    final calls = await pumpBar(tester, platform: TargetPlatform.macOS);
    final title = find.byKey(const Key('title-bar-title'));
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(calls, ['toggleZoom']);
  });

  testWidgets('macOS: buttons stay buttons (no drag, no zoom)', (tester) async {
    var themes = 0;
    final calls = await pumpBar(tester, platform: TargetPlatform.macOS, onTheme: () => themes++);
    await tester.tap(find.byKey(const Key('action-theme')));
    await tester.pumpAndSettle();
    expect(themes, 1);
    expect(calls, isEmpty);
    expect(tester.getSize(find.byType(MdTitleBar)).height, macTitleBarHeight);
  });

  testWidgets('other platforms use a standard app bar', (tester) async {
    final calls = await pumpBar(tester, platform: TargetPlatform.windows);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.getSize(find.byType(MdTitleBar)).height, kToolbarHeight);
    await tester.drag(find.text('README.md'), const Offset(40, 10));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  test('dividers are only counted for groups that stay visible', () {
    AppAction action(String id, ActionGroup group, int priority) =>
        AppAction(id: id, label: id, icon: Icons.circle, onSelected: () {}, group: group, priority: priority);
    final actions = [
      action('back', ActionGroup.navigation, ActionPriority.history),
      action('forward', ActionGroup.navigation, ActionPriority.history),
      action('find', ActionGroup.search, ActionPriority.pinned),
      action('theme', ActionGroup.view, ActionPriority.appearance),
      action('print', ActionGroup.output, ActionPriority.output),
    ];
    // more + find + back + forward + theme, and two dividers
    // (navigation | search | view); the output group is not shown.
    final split = splitTitleBarActions(actions, available: 5 * 40 + 2 * 10, extent: 40, dividerWidth: 10);
    expect(split.bar.map((a) => a.id), ['back', 'forward', 'find', 'theme']);
    expect(split.overflow.map((a) => a.id), ['print']);
    // One pixel less and the view group no longer fits with its divider.
    final tighter = splitTitleBarActions(actions, available: 5 * 40 + 2 * 10 - 1, extent: 40, dividerWidth: 10);
    expect(tighter.bar.map((a) => a.id), ['back', 'forward', 'find']);
  });

  testWidgets('macOS: no traffic-light inset while the window is in full screen', (tester) async {
    final controls = WindowControls();
    addTearDown(controls.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'isFullScreen' ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await controls.listen();
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: MdTitleBar(title: 'README.md', platform: TargetPlatform.macOS, actions: const [], windowControls: controls),
      ),
    ));
    double titleLeft() => tester.getTopLeft(find.byKey(const Key('title-bar-title'))).dx;
    expect(titleLeft(), greaterThanOrEqualTo(macTrafficLightInset));

    Future<void> nativeSays(bool fullScreen) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('fullScreenChanged', fullScreen)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await nativeSays(true);
    expect(controls.fullScreen.value, isTrue);
    expect(titleLeft(), lessThan(macTrafficLightInset));
    await nativeSays(false);
    expect(titleLeft(), greaterThanOrEqualTo(macTrafficLightInset));
  });
}
