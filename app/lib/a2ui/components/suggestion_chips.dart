import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/conversation_views.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `SuggestionChips(options)` (A2UI_CATALOG 3.4). A tap calls `sendText`,
/// which starts a new capture through the router.
final ComponentImplementation suggestionChipsComponent =
    ComponentImplementation(
      name: 'SuggestionChips',
      schema: componentSchema('SuggestionChips', [
        Prop.items(
          'options',
          const ['label', 'message'],
          itemRequired: const ['label', 'message'],
          minItems: 1,
          maxItems: 4,
          required: true,
        ),
      ]),
      builder: (context, node, props, buildChild) {
        final scope = XpenseScope.of(context);
        return SuggestionChipsView(
          options: [
            for (final o in props.list('options'))
              if (o case {
                'label': final String label,
                'message': final String message,
              })
                Suggestion(label: label, message: message),
          ],
          onPick: scope.busy ? null : scope.actions.sendText,
        );
      },
    );
