import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  late Map<String, dynamic> json;

  setUpAll(() async {
    json = await readCatalogJson();
  });

  test('loads the shared xpense_shared catalog', () async {
    final file = await locateCatalogFile(environment: const {});
    expect(file.path, endsWith('xpense_catalog.json'));
    expect((json['components'] as Map).keys, xpenseComponentNames);
  });

  test('the agent view drops only what the agent never uses', () {
    final catalog = agentCatalog(json);
    expect(catalog.id, xpenseCatalogId);
    expect(
      catalog.components.keys.toSet(),
      {...xpenseComponentNames}.difference(agentOmittedComponents),
    );
    expect(catalog.functions.keys, ['required']);
  });

  test('property order is unchanged (the positional contract)', () {
    final full = json['components'] as Map;
    final trimmed = trimCatalogForAgent(json)['components'] as Map;
    for (final name in trimmed.keys) {
      expect(
        ((trimmed[name] as Map)['properties'] as Map?)?.keys.toList(),
        ((full[name] as Map)['properties'] as Map?)?.keys.toList(),
        reason: '$name',
      );
    }
  });

  test('the agent view is shorter than the full catalog', () {
    final full = renderCatalogInstructions(agentCatalog(json, trim: false));
    final trimmed = renderCatalogInstructions(agentCatalog(json));
    expect(trimmed.length, lessThan(full.length * 0.9));
    expect(trimmed, isNot(contains('DateTimeInput(')));
    expect(trimmed, isNot(contains('pluralize(')));
    expect(trimmed, contains('EntryList('));
  });

  test('registers under "xpense" and compiles the documented blocks', () async {
    final ai = Genkit(plugins: [A2uiPlugin()]);
    final catalog = registerXpenseCatalog(ai, json);
    expect(
      ai.registry.lookupValue<A2uiCatalog>(a2uiCatalogValueType, 'xpense'),
      same(catalog),
    );
  });
}
