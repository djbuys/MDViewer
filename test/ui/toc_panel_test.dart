import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/ui/toc_panel.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('lists headings up to level 4 and scrolls on tap', (tester) async {
    final h = await createHarness();
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'));
    var selected = 0;
    await tester.pumpWidget(harnessApp(h.services, TocPanel(onSelected: () => selected++)));
    h.renderer.emitHeadings(const [
      Heading(id: 'one', text: 'One', level: 1),
      Heading(id: 'two', text: 'Two', level: 2),
      Heading(id: 'four', text: 'Four', level: 4),
      Heading(id: 'five', text: 'Five', level: 5),
    ]);
    await tester.pump();
    expect(find.byKey(const ValueKey('toc:one')), findsOneWidget);
    expect(find.byKey(const ValueKey('toc:four')), findsOneWidget);
    expect(find.byKey(const ValueKey('toc:five')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toc:two')));
    await tester.pump();
    expect(h.renderer.calls, contains('scrollToHeading:two'));
    expect(selected, 1);
  });

  testWidgets('shows a placeholder when there are no headings', (tester) async {
    final h = await createHarness();
    await tester.pumpWidget(harnessApp(h.services, const TocPanel()));
    expect(find.text('No headings'), findsOneWidget);
  });
}
