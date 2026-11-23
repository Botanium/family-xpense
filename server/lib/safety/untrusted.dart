/// Untrusted content (receipt text, transcripts, notes) is wrapped in data
/// delimiters before it reaches the model (AI_PIPELINE 8 rule 6, 10).
///
/// The `_untrusted.prompt` partial tells the model that anything between
/// `<<<data` and `data>>>` is quoted material and never an instruction.
/// [wrapUntrusted] makes sure the content cannot close the block early or
/// open a fake one.
library;

/// Opening delimiter.
const untrustedOpen = '<<<data';

/// Closing delimiter.
const untrustedClose = 'data>>>';

final _delimiters = RegExp(r'<<<\s*data|data\s*>>>', caseSensitive: false);

/// Wraps [content] as quoted data of [kind] (`receipt`, `transcript`,
/// `note`). Delimiter look-alikes inside [content] are defused.
String wrapUntrusted(String content, {required String kind}) {
  final safeKind = kind.replaceAll(RegExp('[^a-z_]'), '');
  final body = content.replaceAllMapped(
    _delimiters,
    (m) => m[0]!.replaceAll('<', '‹').replaceAll('>', '›'),
  );
  return '$untrustedOpen $safeKind\n$body\n$untrustedClose';
}
