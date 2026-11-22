import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/conversation_views.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `Notice(text, kind, actionLabel?, action?)` (A2UI_CATALOG 3.4).
final ComponentImplementation noticeComponent = ComponentImplementation(
  name: 'Notice',
  schema: componentSchema('Notice', [
    Prop.string('text', required: true),
    Prop.oneOf('kind', const [
      'offline',
      'limit',
      'privacy',
      'error',
    ], required: true),
    Prop.string('actionLabel'),
    Prop.action('action'),
  ]),
  builder: (context, node, props, buildChild) => NoticeView(
    text: props.string('text') ?? '',
    topic:
        NoticeTopic.values.asNameMap()[props.string('kind')] ??
        NoticeTopic.error,
    actionLabel: props.action('action') == null
        ? null
        : props.string('actionLabel'),
    onAction: actionHandler(XpenseScope.of(context), node, props, 'action'),
  ),
);
