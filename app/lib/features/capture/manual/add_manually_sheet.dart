import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/capture/manual/category_chips.dart';
import 'package:xpense_app/features/capture/manual/manual_entry.dart';
import 'package:xpense_app/features/capture/manual/manual_labels.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What a closed sheet did.
@immutable
final class ManualSheetOutcome {
  /// Creates the outcome.
  const new({required this.ack, this.saved});

  /// Whether the write reached the server.
  final WriteAck ack;

  /// The new entry, when the sheet added one (null for an edit).
  final SavedEntries? saved;
}

/// Opens Add manually (DESIGN_SYSTEM screen 9) above the tab bar.
///
/// [draft] prefills it ("Change" on a slip). With [editTxnId] the sheet
/// edits that saved entry instead, prefilled from [draft], and [focus]
/// names the row the member tapped on entry detail.
///
/// After a new entry is saved a toast offers Undo; after an offline save
/// it says the entry is on this phone.
Future<ManualSheetOutcome?> showAddManuallySheet(
  BuildContext context, {
  EntryDraft? draft,
  String? editTxnId,
  ManualField? focus,
}) {
  // The root navigator, so the sheet covers the floating tab bar.
  final root = Navigator.of(context, rootNavigator: true);
  final l10n = context.l10n;
  final form = GlobalKey<AddManuallyFormState>();
  final editing = editTxnId != null;
  return _showFormSheet(
    context: root.context,
    header: SheetHeader(
      cancelLabel: l10n.captureManualCancel,
      onCancel: () => form.currentState?.cancel(),
      title: editing ? l10n.captureManualEditTitle : l10n.captureManualTitle,
      actionLabel: l10n.captureManualSave,
      onAction: () => unawaited(form.currentState?.save()),
    ),
    builder: (_) => AddManuallyForm(
      key: form,
      initial: draft,
      editTxnId: editTxnId,
      focus: focus,
    ),
  );
}

/// [showGlassSheet] at the large detent, without drag-to-dismiss.
///
/// The bottom sheet's drag closes its route with `Navigator.pop`, which a
/// [PopScope] cannot stop, so a half-filled form could be lost to a swipe.
/// Cancel and a tap on the dimmed screen both go through
/// [AddManuallyFormState.cancel] instead (Codex review, PR #39). Same look
/// as `showGlassSheet`; that helper has no `enableDrag` yet (design system
/// follow-up).
Future<ManualSheetOutcome?> _showFormSheet({
  required BuildContext context,
  required SheetHeader header,
  required WidgetBuilder builder,
}) {
  final colors = XpColors.of(context);
  final motion = XpMotion.of(context);
  return showModalBottomSheet<ManualSheetOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: colors.canvas.withValues(alpha: 0),
    elevation: 0,
    barrierColor: colors.ink.withValues(alpha: XpOpacity.barrier),
    sheetAnimationStyle: AnimationStyle(
      duration: motion.slow,
      reverseDuration: motion.base,
      curve: XpMotion.slowCurve,
    ),
    builder: (context) => Padding(
      padding: EdgeInsetsDirectional.only(
        start: XpSpace.sheetMargin,
        end: XpSpace.sheetMargin,
        bottom: XpSpace.sheetMargin + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        child: GlassSheet(
          header: header,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

/// The Add manually form: type bar, amount, the type's fields, account,
/// date and note, and the bottom Save button. It saves through the write
/// path and closes its route with a [ManualSheetOutcome].
class AddManuallyForm extends ConsumerStatefulWidget {
  /// Creates the form, prefilled from [initial]; with [editTxnId] it edits
  /// that entry.
  const new({this.initial, this.editTxnId, this.focus, super.key});

  /// The prefilled draft.
  final EntryDraft? initial;

  /// The saved entry being edited.
  final String? editTxnId;

  /// The field to bring into view first.
  final ManualField? focus;

  @override
  ConsumerState<AddManuallyForm> createState() => AddManuallyFormState();
}

/// State of [AddManuallyForm]; the sheet header calls [save] and [cancel].
class AddManuallyFormState extends ConsumerState<AddManuallyForm> {
  final _amount = TextEditingController();
  final _toAmount = TextEditingController();
  final _note = TextEditingController();
  final _person = TextEditingController();
  final _rate = TextEditingController();
  final Map<ManualField, GlobalKey> _anchors = {
    for (final f in ManualField.values) f: GlobalKey(debugLabel: f.name),
  };

  late ManualEntryValues _values;
  late ManualEntryValues _start;
  Map<ManualField, ManualIssue> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.editTxnId != null;

  /// Whether anything was changed since the sheet opened.
  bool get dirty => _values != _start;

  @override
  void initState() {
    super.initState();
    final today = manualDay(ref.read(clockProvider).now());
    final initial = widget.initial;
    _values = initial == null
        ? ManualEntryValues(kind: ManualKind.expense, occurredOn: today)
        : ManualEntryValues.fromDraft(initial, today: today);
    _start = _values;
    _amount.text = _values.amountText;
    _note.text = _values.note;
    _person.text = _values.personName;
    _rate.text = _values.rateText;
    final focus = widget.focus;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(focus));
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _note.dispose();
    _person.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _reveal(ManualField field) {
    if (!mounted) return;
    final target = _anchors[field]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: XpMotion.of(context).base,
        alignment: 0.2,
      );
    }
  }

  void _edit(ManualEntryValues next, {List<ManualField> clears = const []}) {
    setState(() {
      _values = next;
      if (clears.isNotEmpty) {
        _errors = {
          for (final e in _errors.entries)
            if (!clears.contains(e.key)) e.key: e.value,
        };
      }
    });
  }

  List<Account> _accounts() =>
      _offered(ref.read(accountsProvider).value ?? const <Account>[]);

  /// The accounts the form offers and checks against: the live ones, plus
  /// any archived one the entry already uses (its source or a transfer's
  /// destination, as saved or as chosen now), so an old entry stays
  /// editable after its account was archived (Codex review, PR #39).
  List<Account> _offered(List<Account> all) {
    final used = {
      ?widget.initial?.accountId,
      ?widget.initial?.toAccountId,
      ?_values.accountId,
      ?_values.toAccountId,
    };
    return all.where((a) => !a.archived || used.contains(a.id)).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Currency _base() => switch (ref.read(membershipProvider).value) {
    InHousehold(:final household) => household.baseCurrency,
    _ => Currency.usd,
  };

  /// The values with the defaults filled in, so what the sheet shows is
  /// what it saves: the account (one in the base currency first) and, for
  /// expense and income, whose it is ([defaultWho], the write path's
  /// rule).
  ManualEntryValues _resolved(List<Account> accounts) {
    var values = _values;
    if (values.accountId == null && accounts.isNotEmpty) {
      final base = _base();
      final first =
          accounts.where((a) => a.currency == base).firstOrNull ??
          accounts.first;
      values = values.copyWith(accountId: first.id);
    }
    final account = accounts.where((a) => a.id == values.accountId).firstOrNull;
    if (values.who == null && values.categoryKind != null && account != null) {
      values = values.copyWith(
        who: defaultWho(
          joint: account.scope == AccountScope.joint,
          ownerUid: account.ownerUid,
          viewerUid: ref.read(accountsRepositoryProvider).viewerUid,
        ),
      );
    }
    return values;
  }

  /// Closes without saving; asks first when something was changed.
  void cancel() {
    final navigator = Navigator.of(context);
    if (!dirty || _saving) {
      if (!_saving) navigator.pop();
      return;
    }
    final l10n = context.l10n;
    unawaited(
      showXpActionSheet(
        context: context,
        cancelLabel: l10n.captureManualKeepEditing,
        actions: [
          XpAction(
            label: l10n.captureManualDiscard,
            destructive: true,
            onPressed: navigator.pop,
          ),
        ],
      ),
    );
  }

  /// Checks the form and saves it through the write path.
  Future<void> save() async {
    if (_saving) return;
    final accounts = _accounts();
    final values = _resolved(accounts);
    final check = checkManualEntry(
      values,
      draftId: widget.initial?.id ?? 'manual',
      currencyOf: (id) =>
          accounts.where((a) => a.id == id).firstOrNull?.currency,
      base: _base(),
      initial: widget.initial,
    );
    final draft = check.draft;
    if (draft == null) {
      unawaited(XpHaptics.warning());
      setState(() => _errors = check.errors);
      _reveal(check.errors.keys.first);
      return;
    }
    setState(() {
      _values = values;
      _saving = true;
      _errors = const {};
    });
    final repository = ref.read(transactionsRepositoryProvider);
    final navigator = Navigator.of(context);
    final txnId = widget.editTxnId;
    final Result<ManualSheetOutcome, TransactionsFailure> result;
    if (txnId != null) {
      final edited = await repository.editEntry(
        txnId,
        draft,
        extras: check.extras,
      );
      result = edited.map((ack) => ManualSheetOutcome(ack: ack));
    } else {
      final saved = await repository.saveEntries(
        [draft],
        extras: {draft.id: check.extras},
      );
      result = saved.map((s) => ManualSheetOutcome(ack: s.ack, saved: s));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok(:final value):
        unawaited(XpHaptics.saved());
        _toast(value, repository);
        navigator.pop(value);
      case Err(:final failure):
        _show(failure);
    }
  }

  /// The toast after a save, shown in the overlay the sheet sits in, so it
  /// outlives the sheet: Undo after a new entry, a note after an offline
  /// edit.
  void _toast(ManualSheetOutcome outcome, TransactionsRepository repository) {
    final l10n = context.l10n;
    final saved = outcome.saved;
    final offline = outcome.ack == WriteAck.queued;
    if (saved != null) {
      showUndoToast(
        context: context,
        message: offline
            ? l10n.captureManualSavedOffline
            : l10n.captureManualSaved,
        actionLabel: l10n.captureManualUndo,
        onAction: () => unawaited(repository.undoSave(saved)),
      );
    } else if (offline) {
      showUndoToast(
        context: context,
        message: l10n.captureManualSavedOffline,
        actionLabel: l10n.captureManualOk,
        onAction: () {},
      );
    }
  }

  void _show(TransactionsFailure failure) {
    unawaited(XpHaptics.warning());
    final placed = placeFailure(failure);
    final field = placed.field;
    if (field != null) {
      setState(() {
        _errors = {field: placed.issue ?? ManualIssue.invalid};
        if (field == ManualField.rate) {
          _values = _values.copyWith(rateAsked: true);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(field));
      return;
    }
    final l10n = context.l10n;
    final retry =
        failure is TransactionConflict || failure is TransactionsUnknown;
    showUndoToast(
      context: context,
      message: l10n.manualFailure(placed.toast ?? failure),
      actionLabel: retry ? l10n.captureManualRetry : l10n.captureManualOk,
      onAction: retry ? () => unawaited(save()) : () {},
    );
  }

  Future<void> _pickAccount({required bool destination}) async {
    final l10n = context.l10n;
    final accounts = _accounts();
    final current = destination
        ? _values.toAccountId
        : _resolved(accounts).accountId;
    final picked = await showGlassSheet<String>(
      context: context,
      header: SheetHeader(
        cancelLabel: l10n.captureManualCancel,
        onCancel: () => Navigator.of(context).pop(),
        title: destination ? l10n.captureManualTo : l10n.captureManualAccount,
      ),
      builder: (sheet) => accounts.isEmpty
          ? Padding(
              padding: const EdgeInsetsDirectional.all(XpSpace.s16),
              child: EmptyState(message: l10n.captureManualNoAccounts),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: XpSpace.s8,
              ),
              children: [
                for (final (i, a) in accounts.indexed)
                  XpListRow(
                    title: a.name,
                    subtitle: a.currency.code,
                    showDivider: i < accounts.length - 1,
                    trailing: a.id == current
                        ? const XpIcon(XpGlyph.check, size: XpSpace.iconRow)
                        : null,
                    onTap: () => Navigator.of(sheet).pop(a.id),
                  ),
              ],
            ),
    );
    if (picked == null || !mounted) return;
    unawaited(XpHaptics.picked());
    if (destination) {
      _edit(
        _values.copyWith(toAccountId: picked, toAmountText: ''),
        clears: const [ManualField.toAccount, ManualField.toAmount],
      );
      _toAmount.clear();
      return;
    }
    final account = accounts.firstWhere((a) => a.id == picked);
    final fitted = _fitDecimals(_values.amountText, account.currency.exponent);
    if (fitted != _values.amountText) _amount.text = fitted;
    _edit(
      _values.copyWith(accountId: picked, amountText: fitted),
      clears: const [
        ManualField.account,
        ManualField.amount,
        ManualField.toAccount,
        ManualField.rate,
      ],
    );
  }

  /// [text] cut to [exponent] decimals, so the amount still reads after
  /// the account (and with it the currency) changes.
  static String _fitDecimals(String text, int exponent) {
    final dot = text.indexOf('.');
    if (dot < 0) return text;
    if (exponent == 0) return text.substring(0, dot);
    final end = dot + 1 + exponent;
    return text.length > end ? text.substring(0, end) : text;
  }

  Future<void> _pickDate() async {
    final l10n = context.l10n;
    final day =
        DateTime.tryParse(_values.occurredOn) ?? ref.read(clockProvider).now();
    final picked = await showXpDatePickerSheet(
      context: context,
      initial: day,
      cancelLabel: l10n.captureManualCancel,
      doneLabel: l10n.captureManualDone,
      title: l10n.captureManualDate,
    );
    if (picked == null || !mounted) return;
    _edit(
      _values.copyWith(occurredOn: manualDay(picked)),
      clears: const [ManualField.date, ManualField.rate],
    );
  }

  String _dayLabel(String day) {
    final l10n = context.l10n;
    final now = ref.read(clockProvider).now();
    if (day == manualDay(now)) return l10n.captureManualToday;
    if (day == manualDay(DateTime(now.year, now.month, now.day - 1))) {
      return l10n.captureManualYesterday;
    }
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return day;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return parsed.year == now.year
        ? DateFormat.MMMd(locale).format(parsed)
        : DateFormat.yMMMd(locale).format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final accounts = _offered(
      ref.watch(accountsProvider).value ?? const <Account>[],
    );
    ref.watch(membershipProvider);
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
    final partner = members.where((m) => m.uid != viewer).firstOrNull;
    final values = _resolved(accounts);
    Account? byId(String? id) =>
        id == null ? null : accounts.where((a) => a.id == id).firstOrNull;
    final account = byId(values.accountId);
    final toAccount = byId(values.toAccountId);
    final currency = account?.currency ?? _base();
    final kind = ManualKind.fromIntent(values.intent);
    final transfer =
        kind == ManualKind.transfer &&
        !(values.intent == CaptureIntent.savingsMove.wire &&
            widget.initial?.goalId != null);
    final crossCurrency =
        transfer &&
        toAccount != null &&
        account != null &&
        toAccount.currency != account.currency;
    final categoryKind = values.categoryKind;
    final effectiveWho = values.who;

    String? error(ManualField field, {String? code}) =>
        switch (_errors[field]) {
          null => null,
          final issue => l10n.manualError(field, issue, code ?? currency.code),
        };

    Widget anchor(ManualField field, Widget child) =>
        KeyedSubtree(key: _anchors[field], child: child);

    final accountLabel = switch (kind) {
      ManualKind.transfer => l10n.captureManualFrom,
      _ => l10n.captureManualAccount,
    };

    // A tap on the dimmed screen or a back gesture goes through [cancel],
    // like the Cancel button: it asks first when something changed, and
    // nothing closes the sheet while a save is in flight.
    return PopScope<ManualSheetOutcome>(
      canPop: !dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          XpSpace.s8,
          XpSpace.s12,
          XpSpace.s8,
          XpSpace.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (values.otherIntent == null) ...[
              XpFilterBar(
                labels: [
                  for (final k in ManualKind.values) l10n.manualKindTab(k),
                ],
                selectedIndex: values.kind.index,
                onSelected: _saving
                    ? (_) {}
                    : (i) => _edit(
                        _values.copyWith(kind: ManualKind.values[i]),
                        clears: ManualField.values,
                      ),
              ),
              const SizedBox(height: XpSpace.s24),
            ],
            anchor(
              ManualField.amount,
              AmountField(
                label: l10n.captureManualAmount,
                currency: currency.code,
                exponent: currency.exponent,
                controller: _amount,
                currencyLabel: l10n.captureManualCurrency(currency.code),
                onCurrencyPressed: _saving
                    ? null
                    : () => unawaited(_pickAccount(destination: false)),
                onChanged: (text) => _edit(
                  _values.copyWith(amountText: text),
                  clears: const [ManualField.amount],
                ),
              ),
            ),
            _FieldError(error(ManualField.amount)),
            if (_values.rateAsked) ...[
              const SizedBox(height: XpSpace.s16),
              anchor(
                ManualField.rate,
                XpTextField(
                  label: l10n.captureManualRate,
                  hint: l10n.captureManualRateHint,
                  controller: _rate,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  error: error(ManualField.rate),
                  onChanged: (text) => _edit(
                    _values.copyWith(rateText: text),
                    clears: const [ManualField.rate],
                  ),
                ),
              ),
            ],
            if (kind == ManualKind.loan) ...[
              const SizedBox(height: XpSpace.s20),
              ChoiceChips<LoanDirection>(
                options: [
                  for (final d in LoanDirection.values)
                    ChoiceOption(value: d, label: l10n.loanDirectionChip(d)),
                ],
                selected: values.loanDirection,
                onSelected: _saving
                    ? null
                    : (d) => _edit(_values.copyWith(loanDirection: d)),
              ),
              const SizedBox(height: XpSpace.s16),
              anchor(
                ManualField.person,
                XpTextField(
                  label: l10n.captureManualPerson,
                  hint: l10n.captureManualPersonHint,
                  controller: _person,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  error: error(ManualField.person),
                  onChanged: (text) => _edit(
                    _values.copyWith(personName: text),
                    clears: const [ManualField.person],
                  ),
                ),
              ),
            ],
            if (categoryKind != null) ...[
              const SizedBox(height: XpSpace.s20),
              anchor(
                ManualField.category,
                _Caption(l10n.captureManualCategory),
              ),
              const SizedBox(height: XpSpace.s8),
              CategoryChips(
                kind: categoryKind,
                selected: values.categoryId,
                onSelected: _saving
                    ? null
                    : (id) => _edit(
                        _values.copyWith(categoryId: id),
                        clears: const [ManualField.category],
                      ),
              ),
              _FieldError(error(ManualField.category)),
              const SizedBox(height: XpSpace.s16),
              anchor(ManualField.who, _Caption(l10n.captureManualWho)),
              const SizedBox(height: XpSpace.s8),
              ChoiceChips<String>(
                options: [
                  ChoiceOption(value: 'me', label: l10n.captureManualWhoYou),
                  if (partner != null)
                    ChoiceOption(
                      value: 'partner',
                      label: partner.displayName.isEmpty
                          ? l10n.captureManualWhoPartner
                          : partner.displayName,
                    ),
                  ChoiceOption(
                    value: 'joint',
                    label: l10n.captureManualWhoJoint,
                  ),
                ],
                selected: effectiveWho,
                onSelected: _saving
                    ? null
                    : (who) => _edit(
                        _values.copyWith(who: who),
                        clears: const [ManualField.who],
                      ),
              ),
              _FieldError(error(ManualField.who)),
            ],
            const SizedBox(height: XpSpace.s12),
            anchor(
              ManualField.account,
              XpDisclosure(
                title: accountLabel,
                value: account?.name ?? l10n.captureManualChoose,
                showDivider: false,
                onTap: _saving
                    ? null
                    : () => unawaited(_pickAccount(destination: false)),
              ),
            ),
            _FieldError(error(ManualField.account)),
            if (transfer) ...[
              anchor(
                ManualField.toAccount,
                XpDisclosure(
                  title: l10n.captureManualTo,
                  value: toAccount?.name ?? l10n.captureManualChoose,
                  showDivider: false,
                  onTap: _saving
                      ? null
                      : () => unawaited(_pickAccount(destination: true)),
                ),
              ),
              _FieldError(error(ManualField.toAccount)),
              if (crossCurrency) ...[
                const SizedBox(height: XpSpace.s8),
                _Caption(l10n.captureManualArrives),
                anchor(
                  ManualField.toAmount,
                  AmountField(
                    label: l10n.captureManualArrives,
                    currency: toAccount.currency.code,
                    exponent: toAccount.currency.exponent,
                    controller: _toAmount,
                    onChanged: (text) => _edit(
                      _values.copyWith(toAmountText: text),
                      clears: const [ManualField.toAmount],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
                  child: Text(
                    l10n.captureManualArrivesHint,
                    style: type.meta.copyWith(color: colors.inkSecondary),
                  ),
                ),
                _FieldError(
                  error(ManualField.toAmount, code: toAccount.currency.code),
                ),
              ],
            ],
            anchor(
              ManualField.date,
              XpDisclosure(
                title: l10n.captureManualDate,
                value: _dayLabel(values.occurredOn),
                showDivider: false,
                onTap: _saving ? null : () => unawaited(_pickDate()),
              ),
            ),
            _FieldError(error(ManualField.date)),
            const SizedBox(height: XpSpace.s8),
            anchor(
              ManualField.note,
              XpTextField(
                label: l10n.captureManualNote,
                hint: l10n.captureManualNoteHint,
                controller: _note,
                enabled: !_saving,
                error: error(ManualField.note),
                textInputAction: TextInputAction.done,
                onChanged: (text) => _edit(
                  _values.copyWith(note: text),
                  clears: const [ManualField.note],
                ),
              ),
            ),
            const SizedBox(height: XpSpace.s24),
            XpButton.primary(
              label: _saving
                  ? l10n.captureManualSaving
                  : l10n.manualSaveLabel(values.kind, editing: _editing),
              onPressed: _saving ? null : () => unawaited(save()),
            ),
          ],
        ),
      ),
    );
  }
}

/// A caption above a group of chips.
class _Caption extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return ExcludeSemantics(
      child: Text(
        text,
        style: type.caption.copyWith(color: colors.inkSecondary),
      ),
    );
  }
}

/// The error line next to a field, read out when it appears.
class _FieldError extends StatelessWidget {
  const new(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
      child: Semantics(
        liveRegion: true,
        child: Text(message, style: type.meta.copyWith(color: colors.danger)),
      ),
    );
  }
}
