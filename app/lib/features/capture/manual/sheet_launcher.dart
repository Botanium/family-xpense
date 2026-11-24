import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/entry_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/capture/manual/add_manually_sheet.dart';
import 'package:xpense_app/features/capture/manual/manual_entry.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A transparent page that only presents a sheet: what is behind it stays
/// visible, and the page leaves the stack when the sheet closes.
Page<void> sheetLauncherPage(GoRouterState state, Widget launcher) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (_, _, _, child) => child,
      child: launcher,
    );

/// Presents Add manually, prefilled with [draft], then closes its page.
class AddManuallyLauncher extends StatefulWidget {
  /// Creates the launcher.
  const new({this.draft, this.quiet = false, super.key});

  /// The draft to prefill ("Change" on a slip).
  final EntryDraft? draft;

  /// Whether the opener shows the save itself (an Ask card), so the sheet
  /// shows no toast.
  final bool quiet;

  @override
  State<AddManuallyLauncher> createState() => _AddManuallyLauncherState();
}

class _AddManuallyLauncherState extends State<AddManuallyLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  /// A new entry saved from a slip's draft goes back to whoever opened
  /// the route ([FormSave]), so the Ask card counts it as its own save.
  Future<void> _open() async {
    if (!mounted) return;
    final outcome = await showAddManuallySheet(
      context,
      draft: widget.draft,
      quiet: widget.quiet,
    );
    if (!mounted) return;
    final saved = outcome?.saved;
    final draft = outcome?.draft;
    _close(
      context,
      saved == null || draft == null ? null : (saved: saved, draft: draft),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Presents the edit sheet for entry [txnId], prefilled from its stored
/// version, at [field]; then closes its page. An entry the member cannot
/// read closes the page at once.
class EditEntryLauncher extends ConsumerStatefulWidget {
  /// Creates the launcher.
  const new({required this.txnId, this.field, super.key});

  /// The entry.
  final String txnId;

  /// The `ManualField` name of the row tapped on entry detail.
  final String? field;

  @override
  ConsumerState<EditEntryLauncher> createState() => _EditEntryLauncherState();
}

class _EditEntryLauncherState extends ConsumerState<EditEntryLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  // Every await is followed by a mounted check before ref or context: the
  // route can be popped while a read is pending (Codex review, PR #39).
  Future<void> _open() async {
    if (!mounted) return;
    final record = await ref
        .read(entryReaderProvider)
        .watchEntry(widget.txnId)
        .first;
    if (!mounted) return;
    final viewer = ref.read(accountsRepositoryProvider).viewerUid;
    // The form formats a typed arriving amount in its account's currency.
    await ref.read(accountsProvider.future);
    if (!mounted) return;
    if (record == null || viewer == null || record.txn.deleted) {
      _close(context);
      return;
    }
    await showAddManuallySheet(
      context,
      draft: draftFromTransaction(record.txn, viewerUid: viewer),
      editTxnId: widget.txnId,
      arrivesMinor: record.txn.toAmountSource == ToAmountSource.entered
          ? record.txn.toAmountMinor
          : null,
      focus: ManualField.values
          .where((f) => f.name == widget.field)
          .firstOrNull,
    );
    if (mounted) _close(context);
  }

  @override
  Widget build(BuildContext context) {
    // Watched so the accounts stay live (Riverpod pauses a provider no
    // one watches) while [_open] waits for them.
    ref.watch(accountsProvider);
    return const SizedBox.shrink();
  }
}

void _close(BuildContext context, [FormSave? result]) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop(result);
  } else {
    // Opened cold from a link: nothing is under it.
    router.go(AppRoutes.home);
  }
}
