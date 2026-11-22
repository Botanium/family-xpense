import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/conversation_views.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `Nudge(text, kind, actionLabel?, action?)` (A2UI_CATALOG 3.4). The
/// action is optional; a dummy `click` is dropped by the router.
final ComponentImplementation nudgeComponent = ComponentImplementation(
  name: 'Nudge',
  schema: componentSchema('Nudge', [
    Prop.string('text', required: true),
    Prop.oneOf('kind', const [
      'bill',
      'budget',
      'loan',
      'rate',
      'report',
      'info',
    ], required: true),
    Prop.string('actionLabel'),
    Prop.action('action'),
  ]),
  builder: (context, node, props, buildChild) => NudgeView(
    text: props.string('text') ?? '',
    topic:
        NudgeTopic.values.asNameMap()[props.string('kind')] ?? NudgeTopic.info,
    actionLabel: props.action('action') == null
        ? null
        : props.string('actionLabel'),
    onAction: actionHandler(XpenseScope.of(context), node, props, 'action'),
  ),
);
