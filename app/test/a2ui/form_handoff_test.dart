// "Fix it in the form" from an Ask card (Codex review, PR #46): a save in
// the form is the card's own save, so the card never offers to save the
// same draft again.
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/widgets/draft_saving.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'a2ui_harness.dart';

/// The fixed form save of [raw]: the member gave it an amount and a
/// category in the form.
FormSaved _formSave(Map<String, Object?> raw) => FormSaved(
  groupId: 'grp_form',
  txnIds: const ['t_form'],
  draft: EntryDraft(
    id: raw['id']! as String,
    intent: 'expense',
    amountMinor: 10000,
    currency: 'IQD',
    accountId: 'acc_cash',
    categoryId: 'gifts',
    who: 'me',
    occurredOn: '2026-11-22',
    title: 'Gift',
  ),
);

/// `agent_needs_review`: d1 cannot be read, d2 is a good taxi; [only]
/// keeps just d1.
List<Map<String, Object?>> _messages({bool only = false}) {
  final messages = fixture('agent_needs_review');
  if (only) {
    final create = messages.last['createSurface']! as Map<String, Object?>;
    ((create['dataModel']! as Map)['drafts']! as List).removeLast();
  }
  return messages;
}

bool _enabled(WidgetTester tester, String label) =>
    tester
        .widget<XpPressable>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(XpPressable),
              )
              .first,
        )
        .onPressed !=
    null;

void main() {
  testWidgets('the last draft saved in the form leaves the card saved, '
      'with Undo, and tells the agent', (tester) async {
    final fake = FakeXpenseActions()..manualFormResult = _formSave;
    final (:host, :actions, :sent) = hostWith(
      _messages(only: true),
      actions: fake,
    );
    await pumpThread(tester, host);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('NEEDS REVIEW'), findsNothing);
    expect(find.textContaining('SAVED · GIFTS'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(host.debugDataModel('cap_bad', SurfacePaths.status), 'saved');
    final [saved] = host.takeSavedActions();
    expect(saved.context['draftIds'], ['d1']);
    expect(saved.context['txnIds'], ['t_form']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(actions.methods, ['openManualForm', 'undoSave']);
    expect(actions.calls.last.argument, 'grp_form');
    // The card offers the Undo, so the form's toast had none.
    expect(fake.formUndo, isNull);
  });

  // Codex review, PR #46: a draft that does not read opens the form empty,
  // and the form names its save "manual"; the agent hears the card's id.
  testWidgets('a form save of a draft that did not read keeps its id', (
    tester,
  ) async {
    final fake = FakeXpenseActions()
      ..manualFormResult = (raw) => _formSave({...raw, 'id': 'manual'});
    final (:host, :actions, :sent) = hostWith(
      _messages(only: true),
      actions: fake,
    );
    await pumpThread(tester, host);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final [saved] = host.takeSavedActions();
    expect(saved.context['draftIds'], ['d1']);
    final [draft] = host.debugDataModel('cap_bad', '/drafts')! as List;
    expect((draft as Map)['id'], 'd1');
  });

  // Codex review, PR #46: the form's own Undo toast, for a draft that left
  // others on the card, goes back through the card.
  testWidgets('the form toast Undo puts a draft that left others back and '
      'stops telling the agent it was saved', (tester) async {
    final fake = FakeXpenseActions()..manualFormResult = _formSave;
    final (:host, :actions, :sent) = hostWith(_messages(), actions: fake);
    await pumpThread(tester, host);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('NEEDS REVIEW'), findsNothing);
    expect(host.debugDataModel('cap_bad', formSavedPath), 1);

    await fake.formUndo!('grp_form');
    await tester.pumpAndSettle();
    expect(actions.methods, ['openManualForm', 'undoSave']);
    expect(actions.calls.last.argument, 'grp_form');
    // d1 is back where it was, unsaved, and the agent hears of no save.
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
    expect(_enabled(tester, 'Save both'), isFalse);
    final drafts = host.debugDataModel('cap_bad', '/drafts')! as List;
    expect([for (final d in drafts) (d as Map)['id']], ['d1', 'd2']);
    expect(host.debugDataModel('cap_bad', formSavedPath), isNull);
    expect(host.takeSavedActions(), isEmpty);
  });

  testWidgets('a failed toast Undo leaves the draft off the card', (
    tester,
  ) async {
    final fake = FakeXpenseActions()
      ..manualFormResult = _formSave
      ..undoError = StateError('offline');
    final (:host, :actions, :sent) = hostWith(_messages(), actions: fake);
    await pumpThread(tester, host);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await fake.formUndo!('grp_form');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('NEEDS REVIEW'), findsNothing);
    final [saved] = host.takeSavedActions();
    expect(saved.context['draftIds'], ['d1']);
  });

  testWidgets('one of two drafts saved in the form leaves the card; Save '
      'saves only the other', (tester) async {
    final fake = FakeXpenseActions()..manualFormResult = _formSave;
    final (:host, :actions, :sent) = hostWith(_messages(), actions: fake);
    await pumpThread(tester, host);
    expect(_enabled(tester, 'Save both'), isFalse);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('NEEDS REVIEW'), findsNothing);
    expect(find.textContaining('TRANSPORT'), findsOneWidget);
    expect(_enabled(tester, 'Save'), isTrue);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final drafts = actions.calls.last.argument! as List<EntryDraft>;
    expect(drafts.map((d) => d.id), ['d2']);
  });

  testWidgets('closing the form unsaved changes nothing', (tester) async {
    final (:host, :actions, :sent) = hostWith(_messages(only: true));
    await pumpThread(tester, host);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('NEEDS REVIEW'), findsOneWidget);
    expect(host.debugDataModel('cap_bad', SurfacePaths.status), isNot('saved'));
    expect(host.takeSavedActions(), isEmpty);
  });
}
