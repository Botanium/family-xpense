import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/features/accounts/account_labels.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What the add form found wrong, field by field. Empty when the draft is
/// good.
@immutable
final class AccountFormCheck {
  /// Creates a check.
  const new({
    this.draft,
    this.nameTooLong = false,
    this.amountInvalid = false,
    this.rateInvalid = false,
  });

  /// The draft, when every field reads.
  final AccountDraft? draft;

  /// The name is longer than [maxAccountNameLength].
  final bool nameTooLong;

  /// The amount is not a number in the currency's decimals.
  final bool amountInvalid;

  /// The rate is needed and does not read.
  final bool rateInvalid;
}

/// Reads the add form. Pure, so it is tested without widgets.
///
/// An empty name becomes [defaultName] (the kind's name); an empty amount
/// is zero. A credit card's amount is what is owed, so it is stored
/// negative (DATA_MODEL 2.4). The rate is read only when [needsRate].
AccountFormCheck checkAccountForm({
  required String name,
  required String defaultName,
  required AccountKind kind,
  required Currency currency,
  required AccountScope scope,
  required bool shared,
  required String amountText,
  required String rateText,
  required bool needsRate,
}) {
  final trimmed = name.trim();
  final nameTooLong = trimmed.runes.length > maxAccountNameLength;
  final amountBlank = amountText.trim().isEmpty;
  final amount = amountBlank
      ? 0
      : MoneyFormat.parseMinor(amountText, exponent: currency.exponent);
  FxRate? rate;
  var rateInvalid = false;
  if (needsRate && amount != null && amount != 0) {
    final cleaned = rateText.replaceAll(',', '').trim();
    rate = FxRate.forPair(FxPair.usdIqd, cleaned).valueOrNull;
    rateInvalid = rate == null;
  }
  if (nameTooLong || amount == null || rateInvalid) {
    return AccountFormCheck(
      nameTooLong: nameTooLong,
      amountInvalid: amount == null,
      rateInvalid: rateInvalid,
    );
  }
  return AccountFormCheck(
    draft: AccountDraft(
      name: trimmed.isEmpty ? defaultName : trimmed,
      kind: kind,
      currency: currency,
      scope: scope,
      sharedWithPartner: scope == AccountScope.personal && shared,
      openingBalanceMinor: kind == AccountKind.credit ? -amount : amount,
      openingRate: rate,
    ),
  );
}

/// The kinds the add form offers, in chip order (artboard 04).
const List<AccountKind> formKinds = [
  AccountKind.cash,
  AccountKind.bank,
  AccountKind.credit,
  AccountKind.savings,
  AccountKind.other,
];

/// The add and edit form for an account (screens 4 and 10).
///
/// Adding: kind chips, name, whose (just me or joint), sharing for a
/// personal account once there is a partner, and today's balance with the
/// currency toggle; the rate field appears when the balance needs
/// converting and the household has no rate yet. Editing: name and kind
/// only; currency and whose are fixed once an account exists.
class AccountForm extends ConsumerStatefulWidget {
  /// The add form. [onAdded] gets the new account's id.
  const new add({
    this.onAdded,
    this.inline = false,
    this.initialCurrency,
    super.key,
  }) : account = null,
       onSaved = null;

  /// The edit form for [account].
  const new edit({required Account this.account, this.onSaved, super.key})
    : onAdded = null,
      inline = false,
      initialCurrency = null;

  /// The account being edited; null when adding.
  final Account? account;

  /// Called after a successful add.
  final ValueChanged<String>? onAdded;

  /// Called after a successful edit.
  final VoidCallback? onSaved;

  /// Whether the form sits in a page (screen 4) rather than a sheet: it
  /// then clears itself after each add.
  final bool inline;

  /// The currency the amount starts in; the household's base by default.
  final Currency? initialCurrency;

  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  late AccountKind _kind;
  Currency? _currency;
  AccountScope _scope = AccountScope.personal;
  bool _shared = false;
  bool _saving = false;
  AccountFormCheck _check = const AccountFormCheck();
  AccountsFailure? _failure;

  bool get _adding => widget.account == null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _kind = account?.kind ?? AccountKind.cash;
    if (account != null) _name.text = account.name;
    _currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _rate.dispose();
    super.dispose();
  }

  Currency _currencyOr(Currency base) => _currency ?? base;

  bool _needsRate(Currency base, FxRate? latest) =>
      _currencyOr(base) != base && latest == null && _amount.text.isNotEmpty;

  void _edited() => setState(() {
    _check = const AccountFormCheck();
    _failure = null;
  });

  Future<void> _submit(Currency base, FxRate? latest) async {
    final l10n = context.l10n;
    final repository = ref.read(accountsRepositoryProvider);
    final account = widget.account;
    if (account != null) {
      final check = checkAccountForm(
        name: _name.text,
        defaultName: l10n.accountKindName(_kind),
        kind: _kind,
        currency: account.currency,
        scope: account.scope,
        shared: false,
        amountText: '',
        rateText: '',
        needsRate: false,
      );
      final draft = check.draft;
      if (draft == null) return setState(() => _check = check);
      setState(() => _saving = true);
      final result = await repository.edit(
        account.id,
        name: draft.name,
        kind: draft.kind,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failure = result.failureOrNull;
      });
      if (result.isOk) widget.onSaved?.call();
      return;
    }

    final check = checkAccountForm(
      name: _name.text,
      defaultName: l10n.accountKindName(_kind),
      kind: _kind,
      currency: _currencyOr(base),
      scope: _scope,
      shared: _shared,
      amountText: _amount.text,
      rateText: _rate.text,
      needsRate: _needsRate(base, latest),
    );
    final draft = check.draft;
    if (draft == null) return setState(() => _check = check);
    setState(() => _saving = true);
    final result = await repository.create(draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failure = result.failureOrNull;
    });
    final id = result.valueOrNull;
    if (id == null) return;
    if (widget.inline) {
      _name.clear();
      _amount.clear();
      _rate.clear();
      setState(() {
        _shared = false;
        _check = const AccountFormCheck();
      });
    }
    widget.onAdded?.call(id);
  }

  String? _failureMessage(AccountsFailure? failure) {
    final l10n = context.l10n;
    return switch (failure) {
      null || AccountsRateNeeded() => null,
      AccountsNotAllowed() => l10n.accountsErrorNotAllowed,
      AccountNotFound() => l10n.accountsErrorNotFound,
      AccountsUnknown() => l10n.accountsErrorUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final base = ref.watch(baseCurrencyProvider) ?? Currency.usd;
    final latest = ref.watch(latestRateProvider).value;
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
    final partner = members.where((m) => m.uid != viewer).firstOrNull;
    final currency = _currencyOr(base);
    final needsRate =
        _needsRate(base, latest) || _failure is AccountsRateNeeded;
    final failure = _failureMessage(_failure);
    final account = widget.account;
    final kindChip = l10n.accountKindChip(_kind);
    final amountLabel = _kind == AccountKind.credit
        ? l10n.accountsOwedLabel(kindChip)
        : l10n.accountsOpeningLabel(kindChip);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChips<AccountKind>(
          options: [
            for (final kind in formKinds)
              ChoiceOption(value: kind, label: l10n.accountKindChip(kind)),
          ],
          selected: _kind,
          onSelected: _saving
              ? null
              : (kind) {
                  _kind = kind;
                  _edited();
                },
        ),
        const SizedBox(height: XpSpace.s16),
        XpTextField(
          label: l10n.accountsNameLabel,
          controller: _name,
          hint: account == null ? l10n.accountKindName(_kind) : null,
          enabled: !_saving,
          error: _check.nameTooLong ? l10n.accountsNameError : null,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _edited(),
        ),
        if (_adding) ...[
          const SizedBox(height: XpSpace.s16),
          SectionLabel(l10n.accountsWhoseLabel),
          const SizedBox(height: XpSpace.s8),
          ChoiceChips<AccountScope>(
            options: [
              ChoiceOption(
                value: AccountScope.personal,
                label: l10n.accountsWhoseMine,
              ),
              ChoiceOption(
                value: AccountScope.joint,
                label: l10n.accountsWhoseJoint,
              ),
            ],
            selected: _scope,
            onSelected: _saving
                ? null
                : (scope) {
                    _scope = scope;
                    _edited();
                  },
          ),
          if (_scope == AccountScope.personal && partner != null) ...[
            const SizedBox(height: XpSpace.s8),
            _SwitchRow(
              title: partner.displayName.isEmpty
                  ? l10n.accountsShareNow
                  : l10n.accountsShareWith(partner.displayName),
              value: _shared,
              onChanged: _saving
                  ? null
                  : (value) {
                      _shared = value;
                      _edited();
                    },
            ),
          ],
          const SizedBox(height: XpSpace.s24),
          _Caption(amountLabel),
          AmountField(
            label: amountLabel,
            currency: currency.code,
            exponent: currency.exponent,
            controller: _amount,
            currencyLabel: '${l10n.accountsCurrencyLabel}, ${currency.code}',
            onChanged: (_) => _edited(),
            onCurrencyPressed: _saving
                ? null
                : () {
                    _currency = currency == Currency.usd
                        ? Currency.iqd
                        : Currency.usd;
                    _amount.clear();
                    _edited();
                  },
          ),
          if (_check.amountInvalid) ...[
            const SizedBox(height: XpSpace.s4),
            _Caption('', error: l10n.accountsAmountError),
          ],
          if (needsRate) ...[
            const SizedBox(height: XpSpace.s16),
            XpTextField(
              label: l10n.accountsRateLabel,
              controller: _rate,
              hint: l10n.accountsRateHint,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !_saving,
              error: _check.rateInvalid ? l10n.accountsRateError : null,
              onChanged: (_) => _edited(),
            ),
          ],
        ] else ...[
          const SizedBox(height: XpSpace.s16),
          _Caption(l10n.accountsCurrencyFixed),
        ],
        if (failure != null) ...[
          const SizedBox(height: XpSpace.s12),
          _Caption(failure, error: failure),
        ],
        const SizedBox(height: XpSpace.s16),
        if (widget.inline)
          XpButton.secondary(
            label: _saving ? l10n.accountsSaving : l10n.accountsAddAction,
            glyph: XpGlyph.plus,
            onPressed: _saving ? null : () => unawaited(_submit(base, latest)),
          )
        else
          XpButton.primary(
            label: _saving
                ? l10n.accountsSaving
                : _adding
                ? l10n.accountsAddAction
                : l10n.accountsSave,
            onPressed: _saving ? null : () => unawaited(_submit(base, latest)),
          ),
      ],
    );
  }
}

/// A caption line, or an error line in its place.
class _Caption extends StatelessWidget {
  const new(this.text, {this.error});

  final String text;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final shown = error ?? text;
    return Semantics(
      liveRegion: error != null,
      child: Text(
        shown,
        style: type.meta.copyWith(
          color: error != null ? colors.danger : colors.inkSecondary,
        ),
      ),
    );
  }
}

/// A switch with its title, for "Share with Sam".
class _SwitchRow extends StatelessWidget {
  const new({required this.title, required this.value, this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: type.body)),
        const SizedBox(width: XpSpace.s12),
        XpSwitch(value: value, onChanged: onChanged, semanticLabel: title),
      ],
    );
  }
}

/// Opens the add sheet (screen 10's plus button), above the tab bar.
Future<void> showAddAccountSheet(BuildContext context) => _showAccountSheet(
  context,
  title: context.l10n.accountsNewTitle,
  form: (close) => AccountForm.add(onAdded: (_) => close()),
);

/// Opens the edit sheet for [account], above the tab bar.
Future<void> showEditAccountSheet(BuildContext context, Account account) =>
    _showAccountSheet(
      context,
      title: context.l10n.accountsEditTitle,
      form: (close) => AccountForm.edit(account: account, onSaved: close),
    );

Future<void> _showAccountSheet(
  BuildContext context, {
  required String title,
  required Widget Function(VoidCallback close) form,
}) {
  // The root navigator, so the sheet covers the floating tab bar.
  final root = Navigator.of(context, rootNavigator: true);
  return showGlassSheet<void>(
    context: root.context,
    detent: SheetDetent.large,
    header: SheetHeader(
      cancelLabel: context.l10n.accountsCancel,
      onCancel: root.pop,
      title: title,
    ),
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(XpSpace.s16),
      child: form(root.pop),
    ),
  );
}
