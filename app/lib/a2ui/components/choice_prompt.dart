import 'dart:convert';

import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/choice_prompt_view.dart';
import 'package:xpense_app/a2ui/widgets/draft_fields.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_shared/xpense_shared.dart';

final RegExp _draftField = RegExp(r'^/drafts/(\d+)/(\w+)$');

/// Draft keys a pick may change besides the bound field: the answered
/// field leaves `missing` and `guessed`; an account settles a guessed
/// currency and its amount; a person's id sets `personId` and the name.
/// Draft fields that hold an id: a typed "Other…" answer would be a name
/// the household does not know, so they take only the offered options (the
/// slip's own picker lists every choice).
const Set<String> _idFields = {
  'accountId',
  'toAccountId',
  'categoryId',
  'personName',
};

const List<String> _derived = [
  'missing',
  'guessed',
  'currency',
  'amountMinor',
  'personId',
  'personName',
];

/// `ChoicePrompt(question, options, value, allowOther?, action?)`
/// (A2UI_CATALOG 3.2). A pick writes `value` locally. When `value` is a
/// draft field (`/drafts/N/field`), the field also leaves that draft's
/// `missing` and `guessed`: the member answered it; an account also settles
/// a guessed currency (`withField`). The action fires only
/// when the agent asked for one, never for a dummy `click`, and not while a
/// turn is streaming.
final ComponentImplementation choicePromptComponent = ComponentImplementation(
  name: 'ChoicePrompt',
  schema: componentSchema('ChoicePrompt', [
    Prop.string('question', required: true),
    Prop.items(
      'options',
      const ['label', 'value', 'hint'],
      itemRequired: const ['label', 'value'],
      minItems: 2,
      maxItems: 5,
      required: true,
    ),
    Prop.string('value', required: true),
    Prop.flag('allowOther'),
    Prop.action('action'),
  ]),
  builder: (context, node, props, buildChild) {
    final scope = XpenseScope.of(context);
    final binding = props.writable('value');
    final action = props.action('action');
    final name = actionNameOf(node, 'action');
    final fires =
        action != null &&
        name != dummyActionName &&
        !(scope.busy && reachesAgent(name));
    // A provisional value still listed in the draft's `missing` is a guess
    // being asked about, not an answer: show nothing picked.
    final asked = binding == null ? null : _draftField.firstMatch(binding.path);
    final missing = asked == null
        ? null
        : dataModelOf(node)?.get('/drafts/${asked[1]}/missing');
    final unanswered = missing is List && missing.contains(asked?[2]);
    return ChoicePromptView(
      question: props.string('question') ?? '',
      answers: [
        for (final o in props.list('options'))
          if (o case {'label': final String label, 'value': final String value})
            PromptAnswer(
              label: label,
              value: value,
              hint: switch (o) {
                {'hint': final String hint} => hint,
                _ => null,
              },
            ),
      ],
      selected: unanswered ? null : props.string('value'),
      allowOther:
          (props.boolean('allowOther') ?? false) &&
          !_idFields.contains(asked?[2]),
      onPick: binding == null
          ? null
          : (value) {
              binding.set(value);
              final match = _draftField.firstMatch(binding.path);
              final model = dataModelOf(node);
              final before = match == null
                  ? null
                  : model?.get('/drafts/${match[1]}');
              if (match != null && model != null && before is Map) {
                // The same edit as a pick on the slip (withField): the
                // field leaves `missing` and `guessed`, and an account
                // settles a guessed currency and its amount.
                final draft = '/drafts/${match[1]}';
                final old = Map<String, Object?>.from(before);
                final next = withField(
                  old,
                  match[2]!,
                  value,
                  household: scope.actions.household,
                );
                for (final key in _derived) {
                  if (jsonEncode(old[key]) == jsonEncode(next[key])) continue;
                  final isList = key == 'missing' || key == 'guessed';
                  model.set(
                    '$draft/$key',
                    next[key] ?? (isList ? <Object?>[] : null),
                  );
                }
              }
              if (fires) fire(action);
            },
    );
  },
);
