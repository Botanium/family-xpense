import 'dart:convert';

import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixture_inputs.dart';

EntryDraft _draft(String id) =>
    EntryDraft(id: id, intent: 'expense', amountMinor: 100, currency: 'USD');

void main() {
  group('captureSurface', () {
    test('matches the A2UI_CATALOG 8 example (with the loc_ prefix)', () {
      // The doc's expected output, verbatim except for the surface id, which
      // the WP-S1 rule gives a `loc_` prefix.
      const expected = '''
[{
  "version": "1.0",
  "createSurface": {
    "surfaceId": "loc_cap_k3m9",
    "catalogId": "https://familyxpense.app/a2ui/catalogs/xpense/v1/catalog.json",
    "components": [
      {"id": "root", "component": "Column", "children": ["heard", "list"]},
      {"id": "heard", "component": "Transcript",
       "text": "Spent ten thousand dinars on lunch with the kids", "seconds": 6},
      {"id": "list", "component": "EntryList", "drafts": {"@path": "/drafts"}, "status": "review"}
    ],
    "dataModel": {
      "drafts": [{
        "id": "d1", "intent": "expense", "amountMinor": 10000, "currency": "IQD",
        "categoryId": "dining", "who": "me", "occurredOn": "2026-11-22", "occurredTime": "13:20",
        "title": "Lunch with the kids",
        "fx": {"pair": "USD/IQD", "pairRate": "1705", "source": "market", "asOf": "2026-11-22", "baseAmountMinor": 587},
        "confidence": {"intent": 0.97, "category": 0.94, "account": 0.31},
        "missing": ["accountId"], "origin": "decisions"
      }]
    }
  }
}]''';
      final built = localFixtures['capture_missing_account']!();
      expect(jsonDecode(jsonEncode(built)), jsonDecode(expected));
    });

    test('puts the intent question before the list and binds its path', () {
      final built = localFixtures['capture_intent_question']!();
      final components =
          (built.single['createSurface']! as Map)['components']! as List;
      expect(components.first, {
        'id': 'root',
        'component': 'Column',
        'children': ['ask', 'list'],
      });
      final ask = components[1] as Map;
      expect(ask['component'], 'ChoicePrompt');
      expect(ask['value'], {'@path': '/drafts/0/intent'});
      expect(ask.containsKey('action'), isFalse, reason: 'a pick stays local');
    });

    test('copies drafts, so later edits do not change the message', () {
      final draft = _draft('d1');
      final built = captureSurface(surfaceId: 'loc_a', drafts: [draft]);
      draft.amountMinor = 999;
      final model = (built.single['createSurface']! as Map)['dataModel'] as Map;
      expect(((model['drafts'] as List).single as Map)['amountMinor'], 100);
    });

    test('rejects ids without the loc_ prefix or with hyphens', () {
      expect(
        () => captureSurface(surfaceId: 'cap_1', drafts: [_draft('d1')]),
        throwsArgumentError,
      );
      expect(
        () => captureSurface(surfaceId: 'loc_cap-1', drafts: [_draft('d1')]),
        throwsArgumentError,
      );
    });

    test('rejects no drafts, more than 20, or duplicate ids', () {
      expect(
        () => captureSurface(surfaceId: 'loc_a', drafts: const []),
        throwsArgumentError,
      );
      expect(
        () => captureSurface(
          surfaceId: 'loc_a',
          drafts: [for (var i = 0; i < 21; i++) _draft('d$i')],
        ),
        throwsArgumentError,
      );
      expect(
        () => captureSurface(
          surfaceId: 'loc_a',
          drafts: [_draft('d1'), _draft('d1')],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a question with fewer than 2 or more than 5 options', () {
      expect(
        () => captureSurface(
          surfaceId: 'loc_a',
          drafts: [_draft('d1')],
          ask: ChoicePromptData.intent(
            question: 'Which?',
            options: const [ChoiceOptionData(label: 'A', value: 'a')],
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('other builders', () {
    test('a local action carries the xp.local. prefix', () {
      expect(
        const LocalAction('openLoan', context: {'loanId': 'loan_7'}).toJson(),
        {
          'event': {
            'name': 'xp.local.openLoan',
            'context': {'loanId': 'loan_7'},
          },
        },
      );
      expect(const LocalAction('retakeReceipt').toJson(), {
        'event': {'name': 'xp.local.retakeReceipt'},
      });
    });

    test('noticeSurface roots the notice', () {
      final built = noticeSurface(
        surfaceId: 'loc_n',
        text: 'Offline.',
        kind: NoticeKind.offline,
      );
      expect((built.single['createSurface']! as Map)['components'], [
        {
          'id': 'root',
          'component': 'Notice',
          'text': 'Offline.',
          'kind': 'offline',
        },
      ]);
    });

    test('receiptSurface binds receipt, drafts and the split switch', () {
      final built = localFixtures['receipt_split']!();
      final create = built.single['createSurface']! as Map;
      final root = (create['components']! as List).single as Map;
      expect(root['receipt'], {'@path': SurfacePaths.receipt});
      expect(root['drafts'], {'@path': SurfacePaths.drafts});
      expect(root['split'], {'@path': SurfacePaths.split});
      expect((create['dataModel']! as Map)['ui'], {'split': true});
    });
  });
}
