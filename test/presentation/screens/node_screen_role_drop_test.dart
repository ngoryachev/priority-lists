import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';

import 'node_screen_roles_test.dart'
    show app, cardTitles, node, seeded, treeOf, twoRoles, usePhoneSize;

/// While a node is being moved by tap, the role chips are drop targets too:
/// tapping one puts the node into that role instead of switching to it.

ChoiceChip chipFor(WidgetTester tester, String title) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, title));

void main() {
  testWidgets('tapping a role chip in move mode drops the node into the role', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['a work task']);

    await tester.tap(find.byTooltip('Move into another node').first);
    await tester.pumpAndSettle();

    // The other role lights up as a target; the node's own role does not,
    // and the "+" chip steps aside.
    expect(chipFor(tester, 'home').onSelected, isNotNull);
    expect(chipFor(tester, 'work').onSelected, isNull);
    expect(find.widgetWithText(ActionChip, '+'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.pumpAndSettle();

    final tree = treeOf(tester).tree;
    expect(tree.nodeById('a work task')!.parentId, 'home');
    // A drop, not a switch: "work" is still the active (red) role.
    expect(tree.nodeById('work')!.priority, Priority.critical);
    expect(tree.nodeById('home')!.priority, Priority.high);
    // Move mode is over and the bar is back to normal.
    expect(cardTitles(tester), isEmpty);
    expect(find.widgetWithText(ActionChip, '+'), findsOneWidget);
    expect(chipFor(tester, 'work').selected, isTrue);
  });

  testWidgets('from deeper down the node\'s own role is a target as well', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('work', priority: Priority.critical),
          node('home', priority: Priority.high, position: 1),
          node('project', parent: 'work'),
          node('step', parent: 'project'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('project'));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['step']);

    await tester.tap(find.byTooltip('Move into another node').first);
    await tester.pumpAndSettle();
    expect(chipFor(tester, 'work').onSelected, isNotNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'work'));
    await tester.pumpAndSettle();

    expect(treeOf(tester).tree.nodeById('step')!.parentId, 'work');
  });
}
