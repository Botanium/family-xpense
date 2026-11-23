/// Registers the Xpense catalog for the `a2ui(catalog: 'xpense')`
/// middleware (A2UI_CATALOG 1).
///
/// The source of truth is `xpense_catalog.json` in `xpense_shared`, the same
/// file the phone renders from. The server registers a trimmed view of it:
/// the phone's catalog is a superset, so anything the agent writes still
/// renders, while the instructions `a2ui()` injects into every model call
/// get shorter. What is cut, and why it is safe:
///
/// - `DateTimeInput`: the agent never asks for a date with a picker; dates
///   live in the drafts and are edited on the slip.
/// - `List`: rows of data are rendered by `BreakdownList`,
///   `TransactionList` and `EntryList`, which the phone lays out itself;
///   `Column` covers static layout.
/// - Every function except `required`: money is formatted by `MoneyText`,
///   counts and dates come from tools as finished figures, and the only
///   client check the agent needs is `required` on a free-text answer.
///
/// Measured in WP-32 (AI_PIPELINE 12): see `tool/instruction_tokens.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Components of the shared catalog the agent may not render.
const agentOmittedComponents = {'DateTimeInput', 'List'};

/// Functions of the shared catalog the agent may call.
const agentFunctions = {'required'};

/// Where the catalog JSON is looked for, in order: `XPENSE_CATALOG_FILE`,
/// `catalog/xpense_catalog.json` under the working directory (the container
/// image copies it there), then the `xpense_shared` package.
Future<File> locateCatalogFile({Map<String, String>? environment}) async {
  final env = environment ?? Platform.environment;
  final candidates = <File>[
    if (env['XPENSE_CATALOG_FILE'] case final path? when path.isNotEmpty)
      File(path),
    File('catalog/xpense_catalog.json'),
  ];
  final resolved = await Isolate.resolvePackageUri(
    Uri.parse(xpenseCatalogPackageUri),
  );
  if (resolved != null) candidates.add(File.fromUri(resolved));
  for (final file in candidates) {
    if (file.existsSync()) return file;
  }
  throw StateError(
    'xpense_catalog.json not found (looked in '
    '${candidates.map((f) => f.path).join(', ')})',
  );
}

/// Reads the shared catalog JSON.
Future<Map<String, dynamic>> readCatalogJson({File? file}) async {
  final f = file ?? await locateCatalogFile();
  return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
}

/// The agent's view of the catalog: the shared JSON minus
/// [agentOmittedComponents] and every function not in [agentFunctions].
/// Property order is untouched (it is the positional contract).
Map<String, dynamic> trimCatalogForAgent(Map<String, dynamic> json) {
  final components = (json['components'] as Map).cast<String, dynamic>();
  final functions = json['functions'];
  return {
    ...json,
    'components': {
      for (final MapEntry(:key, :value) in components.entries)
        if (!agentOmittedComponents.contains(key)) key: value,
    },
    if (functions is Map)
      'functions': {
        for (final MapEntry(:key, :value) in functions.entries)
          if (agentFunctions.contains(key)) key: value,
      },
  };
}

/// Builds the catalog the agent uses. [trim] false keeps the full shared
/// catalog (for measuring).
A2uiCatalog agentCatalog(Map<String, dynamic> json, {bool trim = true}) =>
    A2uiCatalog.fromJson(trim ? trimCatalogForAgent(json) : json);

/// Registers the agent view of [json] on [ai] under `xpense`, before any
/// turn. Synchronous, so the agent can be built while the server is
/// assembled; [json] is read beforehand with [readCatalogJson].
///
/// Does what `loadCatalog` does for an inline catalog: rendering the
/// instructions once validates the document (an invalid catalog throws
/// here, at startup, not on the first turn).
A2uiCatalog registerXpenseCatalog(Genkit ai, Map<String, dynamic> json) {
  final catalog = agentCatalog(json);
  renderCatalogInstructions(catalog);
  ai.registry.registerValue(
    a2uiCatalogValueType,
    xpenseCatalogLookupId,
    catalog,
  );
  return catalog;
}
