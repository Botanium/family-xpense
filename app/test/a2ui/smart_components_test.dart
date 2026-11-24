// EntryList, ChoicePrompt and ReceiptSummary flows (A2UI_CATALOG 3.2,
// story S3.3): save, undo, pick and validation, against the fake actions.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'a2ui_harness.dart';

/// The fixtures are dated 2026-11-22.
DateTime _now = DateTime(2026, 11, 22, 14);

/// Runs [body] as a widget test on a clock the test moves.
void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      _now = DateTime(2026, 11, 22, 14);
      await withClock(Clock(() => _now), () => body(tester));
    });

Object? _model(XpenseSurfaceHost host, String surfaceId, String path) =>
    host.debugDataModel(surfaceId, path);

/// Whether the pressable labelled [label] is enabled.
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
  group('EntryList: save', () {
    _test('Save both writes the drafts once and shows them saved', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();

      expect(actions.methods, ['saveDrafts']);
      final drafts = actions.calls.single.argument! as List<EntryDraft>;
      expect(drafts.map((d) => d.id), ['d1', 'd2']);
      expect(find.text('Saved 2 entries.'), findsOneWidget);
      expect(find.textContaining('SAVED · SALARY'), findsOneWidget);
      expect(find.textContaining('SAVED · RENT'), findsOneWidget);
      expect(find.text('Save both'), findsNothing);
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), 'saved');
      expect(
        (_model(host, 'cap_k3m9', SurfacePaths.saved)! as Map)['groupId'],
        'grp_1',
      );
      expect(sent, isEmpty, reason: 'a local save is not an agent turn');
    });

    _test('the saved line shows the budget standing when there is one', (
      tester,
    ) async {
      final fake = FakeXpenseActions()
        ..budgets = const {
          'rent': BudgetStanding(
            spentMinor: 140000,
            limitMinor: 150000,
            currency: 'USD',
          ),
        };
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_two_entries'),
        actions: fake,
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      expect(find.text('SAVED · RENT · 1,400.00 / 1,500.00'), findsOneWidget);
    });

    _test('a failed save keeps the drafts and says so', (tester) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_two_entries'),
        actions: FakeXpenseActions(
          saveResult: const SaveFailed(SaveFailure.unknown),
        ),
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save. Your entries are still here."),
        findsOneWidget,
      );
      expect(find.text('Save both'), findsOneWidget);
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), isNull);
    });

    _test('while saving, the button is busy and a second tap does nothing', (
      tester,
    ) async {
      final fake = FakeXpenseActions()..saveGate = Completer<void>();
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_two_entries'),
        actions: fake,
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.text('Saving…'));
      fake.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(actions.methods, ['saveDrafts']);
    });

    _test('a changed guess is learned on save', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      await tester.tap(find.text('JOINT'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pick_who_me')));
      await tester.pump();
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      final learned = actions.calls
          .where((c) => c.method == 'learn')
          .map((c) => c.argument! as DraftCorrection)
          .single;
      expect(learned.draftId, 'd2');
      expect(learned.field, 'who');
      expect(learned.guessed, 'joint');
      expect(learned.chosen, 'me');
      expect(learned.title, 'Rent');
    });
  });

  group('EntryList: undo', () {
    _test('Undo within ten seconds soft-deletes the group and reopens the '
        'drafts', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(actions.methods, ['saveDrafts', 'undoSave']);
      expect(actions.calls.last.argument, 'grp_1');
      expect(actions.saved, isEmpty);
      expect(find.text('Save both'), findsOneWidget);
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), 'review');
    });

    _test('Undo goes after ten seconds', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      _now = _now.add(XpMotion.toastLifetime);
      await tester.pump(XpMotion.toastLifetime);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Saved 2 entries.'), findsOneWidget);
    });

    _test('a failed undo keeps the entries saved and offers Undo again', (
      tester,
    ) async {
      final fake = FakeXpenseActions()..undoError = StateError('offline');
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_two_entries'),
        actions: fake,
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      // Reported to the error handler, never swallowed.
      expect(tester.takeException(), isA<StateError>());
      expect(
        find.text("Couldn't undo. The entries are still saved; try again."),
        findsOneWidget,
      );
      expect(find.text('Saved 2 entries.'), findsOneWidget);
      expect(find.text('Save both'), findsNothing);
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), 'saved');

      // Still offered after the usual ten seconds, until it works.
      _now = _now.add(XpMotion.toastLifetime);
      await tester.pump(XpMotion.toastLifetime);
      fake.undoError = null;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Save both'), findsOneWidget);
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), 'review');
      expect(actions.methods, ['saveDrafts', 'undoSave', 'undoSave']);
    });

    _test('a save that ends after the surface is gone is still recorded', (
      tester,
    ) async {
      final fake = FakeXpenseActions()..saveGate = Completer<void>();
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_two_entries'),
        actions: fake,
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pump();
      // The member leaves before the write returns.
      await tester.pumpWidget(const SizedBox.shrink());
      fake.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(_model(host, 'cap_k3m9', SurfacePaths.status), 'saved');
      // Coming back shows it saved; Save is not offered twice.
      await pumpThread(tester, host);
      expect(find.text('Saved 2 entries.'), findsOneWidget);
      expect(find.text('Save both'), findsNothing);
      expect(actions.methods, ['saveDrafts']);
    });

    _test('the saved state survives a rebuild of the surface', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      // Drop the widgets and render the same surface again.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpThread(tester, host);
      expect(find.text('Saved 2 entries.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('EntryList: pick', () {
    _test('the first missing field is asked; a pick fills it and enables '
        'Save', (tester) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('local_capture_missing_account'),
      );
      await pumpThread(tester, host);
      expect(find.text('Which account?'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isFalse);
      // Only accounts in the draft's currency (IQD) are offered.
      expect(
        find.byKey(const ValueKey('pick_accountId_acc_chk')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('pick_accountId_acc_cash')));
      await tester.pump();
      expect(find.text('Which account?'), findsNothing);
      expect(find.text('CASH'), findsOneWidget);
      expect(_model(host, 'loc_cap_k3m9', '/drafts/0/accountId'), 'acc_cash');
      expect(_model(host, 'loc_cap_k3m9', '/drafts/0/missing'), isNull);
      expect(_enabled(tester, 'Save'), isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = actions.calls.single.argument! as List<EntryDraft>;
      expect(saved.single.accountId, 'acc_cash');
    });

    _test('tapping a field opens its picker and writes the answer back', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
      await pumpThread(tester, host);
      expect(find.text('GUESSED'), findsOneWidget);
      await tester.tap(find.text('JOINT'));
      await tester.pump();
      expect(find.text('Whose is it?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick_who_partner')));
      await tester.pump();
      expect(_model(host, 'cap_k3m9', '/drafts/1/who'), 'partner');
      expect(find.text('SAM'), findsOneWidget);
      // Answered: no longer a guess.
      expect(find.text('GUESSED'), findsNothing);
      expect(_model(host, 'cap_k3m9', '/drafts/1/guessed'), isNull);
    });

    _test('ChoicePrompt writes the intent; the EntryList redraws without an '
        'agent turn', (tester) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_intent_question'),
      );
      await pumpThread(tester, host);
      expect(find.text('LENT'), findsOneWidget);
      expect(find.text('Answer the question above to save.'), findsOneWidget);
      await tester.tap(find.text('No, gift or payment'));
      await tester.pump();
      expect(_model(host, 'cap_p7x2', '/drafts/0/intent'), 'expense');
      expect(_model(host, 'cap_p7x2', '/drafts/0/missing'), isEmpty);
      // An expense needs a category, so that is asked next.
      expect(find.text('Which category?'), findsOneWidget);
      expect(sent, isEmpty);
    });

    _test('picking the provisional intent answers it too', (tester) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_intent_question'),
      );
      await pumpThread(tester, host);
      await tester.tap(find.text("Yes, it's a loan"));
      await tester.pump();
      expect(_model(host, 'cap_p7x2', '/drafts/0/intent'), 'loan_given');
      expect(_model(host, 'cap_p7x2', '/drafts/0/missing'), isEmpty);
      expect(_enabled(tester, 'Save'), isTrue);
    });

    // PR #30 review: the agent asks for the account of "groceries 45",
    // whose dollars were only a guess; the dinar wallet is offered.
    _test('picking an account in another currency settles a guessed '
        'currency', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'cap_g45',
            'catalogId': xpenseCatalogId,
            'sendDataModel': false,
            'components': [
              {
                'id': 'root',
                'component': 'Column',
                'children': ['ask', 'list'],
              },
              {
                'id': 'ask',
                'component': 'ChoicePrompt',
                'question': 'Which account?',
                'options': [
                  {'label': 'Checking', 'value': 'acc_chk'},
                  {'label': 'Cash', 'value': 'acc_cash'},
                ],
                'value': {'@path': '/drafts/0/accountId'},
              },
              {
                'id': 'list',
                'component': 'EntryList',
                'drafts': {'@path': '/drafts'},
              },
            ],
            'dataModel': {
              'drafts': [
                {
                  'id': 'd1',
                  'intent': 'expense',
                  'amountMinor': 4500,
                  'currency': 'USD',
                  'accountId': 'acc_chk',
                  'categoryId': 'groceries',
                  'occurredOn': '2026-11-22',
                  'missing': ['accountId'],
                  'guessed': ['accountId', 'currency'],
                  // Worked out for USD 45; stale once the currency moves.
                  'duplicate': {'txnId': 't_usd_45', 'probability': 0.9},
                },
              ],
            },
          },
        },
      ]);
      await pumpThread(tester, host);
      await tester.tap(find.text('Cash').first);
      await tester.pump();
      expect(_model(host, 'cap_g45', '/drafts/0/accountId'), 'acc_cash');
      expect(_model(host, 'cap_g45', '/drafts/0/currency'), 'IQD');
      expect(_model(host, 'cap_g45', '/drafts/0/amountMinor'), 45);
      expect(_model(host, 'cap_g45', '/drafts/0/duplicate'), isNull);
      expect(_model(host, 'cap_g45', '/drafts/0/missing'), isEmpty);
      // Still guessed: a later pick of another account moves it again.
      expect(_model(host, 'cap_g45', '/drafts/0/guessed'), ['currency']);
      expect(_enabled(tester, 'Save'), isTrue);
      expect(sent, isEmpty);
    });

    // PR #30 review: person options carry ids; the pick links the person.
    _test('picking a person links the id and shows the name', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'cap_lend',
            'catalogId': xpenseCatalogId,
            'sendDataModel': false,
            'components': [
              {
                'id': 'root',
                'component': 'Column',
                'children': ['ask', 'list'],
              },
              {
                'id': 'ask',
                'component': 'ChoicePrompt',
                'question': 'Who did you lend it to?',
                'options': [
                  {'label': 'Alex', 'value': 'p_alex'},
                  {'label': 'Someone else', 'value': 'p_other'},
                ],
                'value': {'@path': '/drafts/0/personName'},
              },
              {
                'id': 'list',
                'component': 'EntryList',
                'drafts': {'@path': '/drafts'},
              },
            ],
            'dataModel': {
              'drafts': [
                {
                  'id': 'd1',
                  'intent': 'loan_given',
                  'amountMinor': 5000,
                  'currency': 'USD',
                  'accountId': 'acc_chk',
                  'occurredOn': '2026-11-22',
                  'missing': ['personName'],
                },
              ],
            },
          },
        },
      ]);
      await pumpThread(tester, host);
      await tester.tap(find.text('Alex').first);
      await tester.pump();
      expect(_model(host, 'cap_lend', '/drafts/0/personId'), 'p_alex');
      expect(_model(host, 'cap_lend', '/drafts/0/personName'), 'Alex');
      expect(_model(host, 'cap_lend', '/drafts/0/missing'), isEmpty);
      expect(_enabled(tester, 'Save'), isTrue);
    });

    // PR #30 review: a typed "Other…" answer is not a category id.
    _test('an id field takes no free-text answer', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'cap_cat',
            'catalogId': xpenseCatalogId,
            'sendDataModel': false,
            'components': [
              {
                'id': 'root',
                'component': 'Column',
                'children': ['ask', 'intent'],
              },
              {
                'id': 'ask',
                'component': 'ChoicePrompt',
                'question': 'Which category?',
                'options': [
                  {'label': 'Groceries', 'value': 'groceries'},
                  {'label': 'Dining out', 'value': 'dining'},
                ],
                'value': {'@path': '/drafts/0/categoryId'},
                'allowOther': true,
              },
              {
                'id': 'intent',
                'component': 'ChoicePrompt',
                'question': 'What kind?',
                'options': [
                  {'label': 'Expense', 'value': 'expense'},
                  {'label': 'Income', 'value': 'income'},
                ],
                'value': {'@path': '/drafts/0/intent'},
                'allowOther': true,
              },
            ],
            'dataModel': {
              'drafts': [
                {
                  'id': 'd1',
                  'intent': 'expense',
                  'amountMinor': 4500,
                  'currency': 'USD',
                  'accountId': 'acc_chk',
                  'occurredOn': '2026-11-22',
                  'missing': ['categoryId'],
                },
              ],
            },
          },
        },
      ]);
      await pumpThread(tester, host);
      // Only the intent question keeps its "Other…" answer.
      expect(find.byKey(const ValueKey('choice_other')), findsOneWidget);
    });

    _test("today's rate is asked inline and saved for the household", (
      tester,
    ) async {
      final fake = FakeXpenseActions(
        household: const XpenseHousehold(
          baseCurrency: 'USD',
          accounts: [
            HouseholdAccount(id: 'acc_cash', name: 'Cash', currency: 'IQD'),
          ],
          categories: [HouseholdCategory(id: 'dining', name: 'Dining out')],
          latestRate: '1705',
        ),
      );
      final (:host, :actions, :sent) = hostWith(
        fixture('local_capture_missing_account'),
        actions: fake,
      );
      await pumpThread(tester, host);
      expect(find.textContaining("Today's dollar rate?"), findsOneWidget);
      await tester.tap(find.text('Use it'));
      await tester.pumpAndSettle();
      expect(actions.calls.single, (method: 'setDailyRate', argument: '1705'));
      expect(find.textContaining("Today's dollar rate?"), findsNothing);
    });
  });

  group('EntryList: validation', () {
    _test('a malformed draft needs review, opens the form, and blocks Save', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_needs_review'));
      await pumpThread(tester, host);
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
      expect(find.text('TAXI'), findsNothing);
      expect(_enabled(tester, 'Save both'), isFalse);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(actions.calls.single.method, 'openManualForm');
      expect((actions.calls.single.argument! as Map)['intent'], 'gift');
    });

    _test('an account the household does not have blocks Save', (tester) async {
      final messages = fixture('agent_two_entries');
      final create = messages.last['createSurface']! as Map<String, Object?>;
      final drafts = (create['dataModel']! as Map)['drafts']! as List;
      (drafts.first as Map)['accountId'] = 'acc_gone';
      final (:host, :actions, :sent) = hostWith(messages);
      await pumpThread(tester, host);
      expect(
        find.text("That account isn't in your household."),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Save both'), isFalse);
    });

    _test('a category of the wrong kind blocks Save and is asked again', (
      tester,
    ) async {
      final messages = fixture('agent_two_entries');
      final create = messages.last['createSurface']! as Map<String, Object?>;
      final drafts = (create['dataModel']! as Map)['drafts']! as List;
      // Income filed under an expense category (cleanups, item 2).
      (drafts.first as Map)['categoryId'] = 'rent';
      final (:host, :actions, :sent) = hostWith(messages);
      await pumpThread(tester, host);
      expect(
        find.text("This category doesn't fit this entry."),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Save both'), isFalse);
      // The picker offers income categories only, as the server does.
      expect(
        find.byKey(const ValueKey('pick_categoryId_salary')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pick_categoryId_rent')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pick_categoryId_salary')));
      await tester.pump();
      expect(_model(host, 'cap_k3m9', '/drafts/0/categoryId'), 'salary');
      expect(find.text("This category doesn't fit this entry."), findsNothing);
      expect(_enabled(tester, 'Save both'), isTrue);
    });

    _test("a currency that is not the account's blocks Save", (tester) async {
      final messages = fixture('agent_two_entries');
      final create = messages.last['createSurface']! as Map<String, Object?>;
      final drafts = (create['dataModel']! as Map)['drafts']! as List;
      (drafts.first as Map)['accountId'] = 'acc_cash';
      final (:host, :actions, :sent) = hostWith(messages);
      await pumpThread(tester, host);
      expect(find.text('This account is in IQD.'), findsOneWidget);
      expect(_enabled(tester, 'Save both'), isFalse);
    });

    _test('a possible duplicate blocks Save until "Save anyway"', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_capture_hints'));
      await pumpThread(tester, host);
      expect(_enabled(tester, 'Save'), isFalse);
      await tester.tap(find.text('View'));
      expect(actions.calls.single, (
        method: 'openTransaction',
        argument: 't_88',
      ));
      await tester.tap(find.text('Save anyway'));
      await tester.pump();
      expect(_enabled(tester, 'Save'), isTrue);
    });

    _test('unbound drafts are read-only', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'literal',
            'catalogId': xpenseCatalogId,
            'components': [
              {
                'id': 'root',
                'component': 'EntryList',
                'drafts': [
                  {
                    'id': 'd1',
                    'intent': 'expense',
                    'amountMinor': 500,
                    'currency': 'USD',
                    'occurredOn': '2026-11-22',
                  },
                ],
              },
            ],
          },
        },
      ]);
      await pumpThread(tester, host);
      // Account and category are missing, but nothing can be picked.
      expect(find.text('Which account?'), findsNothing);
      expect(_enabled(tester, 'Save'), isFalse);
    });
  });

  group('after a save', () {
    _test('the recurring offer creates a recurring template', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_capture_hints'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Save anyway'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Repeat Internet every month, on day 5?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Make it repeat'));
      await tester.pumpAndSettle();
      expect(actions.calls.last, (
        method: 'setRecurring',
        argument: ('d1', RecurringMode.monthly),
      ));
      expect(find.text('Make it repeat'), findsNothing);
    });
  });

  group('ReceiptSummary', () {
    _test('the switch regroups the drafts; groups always add up', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_receipt_split'));
      await pumpThread(tester, host);
      expect(find.text('Save 3 entries'), findsOneWidget);
      await tester.tap(find.byType(XpSwitch));
      await tester.pump();
      expect(_model(host, 'loc_rcpt_fm', SurfacePaths.split), false);
      final one = _model(host, 'loc_rcpt_fm', SurfacePaths.drafts)! as List;
      expect(one.single, containsPair('amountMinor', 60500));
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.byType(XpSwitch));
      await tester.pump();
      final three = _model(host, 'loc_rcpt_fm', SurfacePaths.drafts)! as List;
      expect(
        three.fold<int>(0, (s, d) => s + ((d as Map)['amountMinor']! as int)),
        60500,
      );
      await tester.tap(find.text('Save 3 entries'));
      await tester.pumpAndSettle();
      expect((actions.calls.single.argument! as List).length, 3);
      expect(find.text('Saved 3 entries.'), findsOneWidget);
    });

    _test('splitting keeps the converted total and divides it', (tester) async {
      final messages = fixture('local_receipt_split');
      final create = messages.single['createSurface']! as Map<String, Object?>;
      final model = create['dataModel']! as Map<String, Object?>;
      // One unsplit entry, converted at 1705: IQD 60,500 ≈ USD 35.48.
      model['drafts'] = [
        {
          ...((model['drafts']! as List).first as Map),
          'id': 'r',
          'amountMinor': 60500,
          'fx': {
            'pair': 'USD/IQD',
            'pairRate': '1705',
            'baseAmountMinor': 3548,
          },
        },
      ];
      model['ui'] = {'split': false};
      final (:host, :actions, :sent) = hostWith(messages);
      await pumpThread(tester, host);
      expect(find.text('≈ USD 35.48'), findsOneWidget);
      await tester.tap(find.byType(XpSwitch));
      await tester.pump();
      expect(find.text('≈ USD 35.48'), findsOneWidget);
      final split = _model(host, 'loc_rcpt_fm', SurfacePaths.drafts)! as List;
      expect(
        [for (final d in split) ((d as Map)['fx']! as Map)['baseAmountMinor']],
        [2078, 256, 1214],
      );
    });

    _test('Retake reopens the camera', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_receipt_split'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Retake'));
      expect(actions.methods, ['retakeReceipt']);
    });
  });
}
