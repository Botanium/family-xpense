/// Closed sets of string values used by the schemas.
///
/// They are `const` lists so that `@StringField(enumValues: ...)` can use
/// them directly, which keeps the JSON Schemas and Dart code in step.
library;

/// Whose spending or income an entry is (`EntryDraft.who`).
const List<String> whoValues = ['me', 'partner', 'joint'];

/// Which step produced a draft (`EntryDraft.origin`).
const List<String> draftOriginValues = [
  'parser',
  'rule',
  'on_device',
  'decisions',
  'agent',
];

/// The household's label for a rate (`fx.source`, DATA_MODEL 1, D-16).
///
/// `official` and `market` label the daily rate; `manual` marks a rate typed
/// for a single transaction.
const List<String> fxSourceValues = ['official', 'market', 'manual'];

/// The repeat unit of a recurring guess (`recurring.cadence.unit`).
const List<String> cadenceUnitValues = ['month', 'week'];

/// What a fast-parse hint points at (`ParseHint.kind`).
const List<String> parseHintKindValues = [
  'account',
  'person',
  'category',
  'who',
];

/// The fields a learned rule can set (`RuleHit.field`, DATA_MODEL 2.12).
const List<String> ruleFieldValues = [
  'categoryId',
  'accountId',
  'who',
  'intent',
];

/// Required fields the fast parser could not settle
/// (`ComplexitySignals.unresolved`, AI_PIPELINE 2).
const List<String> unresolvedFieldValues = ['category', 'account', 'intent'];

/// The attachment of a captured message (AI_PIPELINE 2).
const List<String> attachmentValues = ['none', 'audio', 'image'];

/// The Decisions question keys a phone may ask for (AI_PIPELINE 7).
/// `to_account` and `person` were added after WP-S4.
const List<String> decideQuestionKeys = [
  'intent',
  'category',
  'account',
  'to_account',
  'who',
  'person',
  'multi_entry',
  'repayable',
  'needs_followup',
  'is_recurring',
  'duplicate',
];
