import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/choice_prompt_view.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_shared/xpense_shared.dart';

final RegExp _draftField = RegExp(r'^/drafts/(\d+)/(\w+)$');

/// `ChoicePrompt(question, options, value, allowOther?, action?)`
/// (A2UI_CATALOG 3.2). A pick writes `value` locally. When `value` is a
/// draft field (`/drafts/N/field`), the field also leaves that draft's
/// `missing` and `guessed`: the member answered it. The action fires only
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
      allowOther: props.boolean('allowOther') ?? false,
      onPick: binding == null
          ? null
          : (value) {
              binding.set(value);
              final match = _draftField.firstMatch(binding.path);
              final model = dataModelOf(node);
              if (match != null && model != null) {
                final draft = '/drafts/${match[1]}';
                for (final list in ['missing', 'guessed']) {
                  final values = model.get('$draft/$list');
                  if (values is List && values.contains(match[2])) {
                    model.set('$draft/$list', [
                      for (final v in values)
                        if (v != match[2]) v,
                    ]);
                  }
                }
              }
              if (fires) fire(action);
            },
    );
  },
);
