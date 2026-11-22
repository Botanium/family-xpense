// Debug-only gallery content. The strings below are sample data for looking
// at components, not product copy, so they do not go through the ARB file.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// One component shown in the gallery and rendered by the golden tests.
@immutable
class GalleryEntry {
  /// Creates an entry.
  const new({
    required this.section,
    required this.name,
    required this.builder,
    this.backdrop = false,
  });

  /// Gallery section.
  final String section;

  /// Component name; also the golden file name.
  final String name;

  /// Builds the sample.
  final WidgetBuilder builder;

  /// Whether to draw a busy backdrop behind it so glass is visible.
  final bool backdrop;
}

const _usd = 2;
const _iqd = 0;
const _wave = [
  0.15, 0.3, 0.5, 0.75, 0.4, 0.85, 0.55, 0.3, 0.7, 0.9, 0.45, 0.25, 0.6, //
  0.75, 0.4, 0.2, 0.55, 0.8, 0.6, 0.35, 0.25, 0.45, 0.3, 0.2, 0.15, 0.1,
];
const _miniWave = [
  0.3, 0.55, 0.85, 0.4, 1.0, 0.7, 1.0, 0.55, 0.85, 0.4, //
  0.7, 1.0, 0.55, 0.85, 1.0, 0.7, 0.4, 0.7, 0.4, 0.3,
];
const _spend = [
  18, 30, 12, 44, 22, 8, 26, 38, 14, 20, 52, 16, 24, 10, 34, 28, 12, 40, 18, //
  30, 62,
];
const _tabs = [
  XpTabItem(glyph: XpGlyph.home, label: 'Home'),
  XpTabItem(glyph: XpGlyph.activity, label: 'Activity'),
  XpTabItem(glyph: XpGlyph.goals, label: 'Goals'),
  XpTabItem(glyph: XpGlyph.accounts, label: 'Accounts'),
];
const _dockLabels = CaptureDockLabels(
  typeInstead: 'Type instead',
  talk: 'Talk',
  stop: 'Stop listening',
  scan: 'Scan a receipt',
  message: 'Message',
  hint: 'Spent, earned, lent…',
);

void _noop() {}

/// Every component in DESIGN_SYSTEM 8, in gallery order.
final List<GalleryEntry> galleryEntries = [
  // Tokens.
  GalleryEntry(
    section: 'Tokens',
    name: 'colours',
    builder: (context) => const _Swatches(),
  ),
  GalleryEntry(
    section: 'Tokens',
    name: 'type',
    builder: (context) => const _TypeRamp(),
  ),
  // Glass.
  for (final variant in GlassVariant.values)
    GalleryEntry(
      section: 'Glass',
      name: 'glass_variant_${variant.name}',
      backdrop: true,
      builder: (context) => _GlassSample(variant: variant),
    ),
  for (final tier in GlassTier.values)
    GalleryEntry(
      section: 'Glass tiers',
      name: 'tier_${tier.index}_${tier.name}',
      backdrop: true,
      builder: (context) => _TierSample(tier: tier),
    ),
  // Navigation.
  GalleryEntry(
    section: 'Navigation',
    name: 'top_bar',
    backdrop: true,
    builder: (context) => const XpTopBar(
      title: 'Ask',
      leading: GlassIconButton(
        glyph: XpGlyph.back,
        semanticLabel: 'Back to home',
        onPressed: _noop,
      ),
      trailing: ModeChip(mode: PrivacyModeKind.onDevice, label: 'On-device'),
    ),
  ),
  GalleryEntry(
    section: 'Navigation',
    name: 'tab_bar',
    backdrop: true,
    builder: (context) => const _TabBarSample(),
  ),
  GalleryEntry(
    section: 'Navigation',
    name: 'glass_buttons',
    backdrop: true,
    builder: (context) => const Wrap(
      spacing: XpSpace.s12,
      runSpacing: XpSpace.s12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GlassIconButton(
          glyph: XpGlyph.bell,
          semanticLabel: 'Notifications, 1 new',
          unread: true,
          onPressed: _noop,
        ),
        GlassIconButton(
          glyph: XpGlyph.close,
          semanticLabel: 'Close',
          onPressed: _noop,
        ),
        ModeChip(mode: PrivacyModeKind.smart, label: 'Smart'),
        ModeChip(mode: PrivacyModeKind.cloud, label: 'Cloud'),
        GlassPill(
          label: 'Read on device',
          glyph: XpGlyph.lock,
          mono: true,
          overMedia: true,
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Navigation',
    name: 'capture_dock_voice',
    backdrop: true,
    builder: (context) => const _DockSample(initial: CaptureMode.voice),
  ),
  GalleryEntry(
    section: 'Navigation',
    name: 'capture_dock_type',
    backdrop: true,
    builder: (context) => const _DockSample(initial: CaptureMode.type),
  ),
  // Content.
  GalleryEntry(
    section: 'Content',
    name: 'money_text',
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MoneyText(
          1000000,
          exponent: _iqd,
          currency: 'IQD',
          style: MoneyStyle.large,
          converted: '≈ USD 7.63',
        ),
        MoneyText(
          4650000,
          exponent: _iqd,
          currency: 'IQD',
          style: MoneyStyle.medium,
        ),
        MoneyText(320000, exponent: _usd, tone: MoneyTone.income),
        MoneyText(-4280, exponent: _usd),
        MoneyText(
          763,
          exponent: _usd,
          currency: 'USD',
          style: MoneyStyle.small,
          tone: MoneyTone.secondary,
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'hero_balance',
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroBalance(
          label: 'Household balance',
          minorUnits: 1248000,
          exponent: _usd,
          currencyMark: r'$',
          delta: '+1,240.00 this month',
          secondary: 'IQD 16.3M',
        ),
        SizedBox(height: XpSpace.s24),
        HeroBalance(
          label: 'Household balance (IQD)',
          minorUnits: 163450000,
          exponent: _iqd,
          currencyMark: 'IQD',
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'mini_bars',
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Daily spending', actionLabel: 'avg 210/day'),
        SizedBox(height: XpSpace.s8),
        MiniBars(
          values: _spend,
          summary: 'Daily spending for November 1 to 21; today is the highest',
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'ledger_rows',
    builder: (context) {
      final c = XpColors.of(context);
      return Column(
        children: [
          LedgerRow(label: 'Income', value: '5,650.00', dotColor: c.income),
          LedgerRow(label: 'Spent', value: '4,410.00', dotColor: c.ink),
          LedgerRow(label: 'Saved', value: '650.00', dotColor: c.saved),
          LedgerRow(label: 'Loans', value: '1,200.00', dotColor: c.loan),
        ],
      );
    },
  ),
  GalleryEntry(
    section: 'Content',
    name: 'list_section',
    builder: (context) => XpSection(
      label: 'Recent',
      actionLabel: 'See all',
      onAction: _noop,
      children: [
        const XpListRow(
          title: 'Costco',
          subtitle: 'Groceries · You',
          trailing: MoneyText(-4280, exponent: _usd),
          onTap: _noop,
        ),
        const XpListRow(
          title: 'Salary',
          subtitle: 'Income · You',
          trailing: MoneyText(320000, exponent: _usd, tone: MoneyTone.income),
        ),
        XpListRow(
          title: 'Dining out',
          subtitle: 'Food · Joint',
          leading: Dot(color: XpColors.of(context).category('cat5')),
          trailing: const MoneyText(-1000000, exponent: _iqd),
          showDivider: false,
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'disclosure',
    builder: (context) => const Column(
      children: [
        XpDisclosure(title: 'Privacy mode', value: 'Smart', onTap: _noop),
        XpDisclosure(title: 'Categories', onTap: _noop, showDivider: false),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'nudge_row',
    builder: (context) => const NudgeRow(
      message: 'Internet is usually paid by the 5th.',
      actionLabel: 'Add',
      onAction: _noop,
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'history_row',
    builder: (context) => const HistoryRow(
      title: 'Sam changed the amount',
      detail: '10,000 → 12,000',
      when: 'Today 13:20',
      restoreLabel: 'Restore',
      onRestore: _noop,
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'slip',
    builder: (context) => const Slip(
      children: [
        Text('A plain slip holds solid content.'),
        DashedRule(),
        MoneyText(
          4650000,
          exponent: _iqd,
          currency: 'IQD',
          style: MoneyStyle.medium,
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'entry_slip',
    builder: (context) => const _EntrySlipSample(),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'transcript_quote',
    builder: (context) => const TranscriptQuote(
      text: 'Spent ten thousand dinars on lunch with the kids',
      duration: '0:06',
      levels: _miniWave,
    ),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'waveform',
    builder: (context) => const Waveform(levels: _wave, spoken: 20),
  ),
  GalleryEntry(
    section: 'Content',
    name: 'avatar_pair',
    builder: (context) => const Align(
      alignment: AlignmentDirectional.centerStart,
      child: AvatarPair(first: 'Y', second: 'S', semanticLabel: 'You and Sam'),
    ),
  ),
  // Controls.
  GalleryEntry(
    section: 'Controls',
    name: 'buttons',
    builder: (context) => const Column(
      children: [
        XpButton.primary(label: 'Save →', onPressed: _noop),
        SizedBox(height: XpSpace.s8),
        XpButton.secondary(label: 'Retake', onPressed: _noop),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            XpButton.text(label: 'Invite later', onPressed: _noop),
            XpButton.destructive(label: 'Delete account', onPressed: _noop),
          ],
        ),
        XpButton.primary(label: 'Disabled', onPressed: null),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'choice_chips',
    builder: (context) => const _ChipsSample(),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'filter_bar',
    builder: (context) => const _FilterSample(),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'switch',
    builder: (context) => const _SwitchSample(),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'search_field',
    builder: (context) => const XpSearchField(hint: 'Search or ask'),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'text_field',
    builder: (context) => const Column(
      children: [
        XpTextField(label: 'Household name', hint: 'Our home'),
        SizedBox(height: XpSpace.s16),
        XpTextField(label: 'Email', error: 'Enter an email address'),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'amount_field',
    builder: (context) => const AmountField(
      label: 'Amount',
      currency: 'IQD',
      exponent: _iqd,
      onCurrencyPressed: _noop,
      currencyLabel: 'Currency, IQD. Change',
    ),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'menu',
    builder: (context) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: XpMenu(
        actions: const [
          XpAction(label: 'Edit', onPressed: _noop),
          XpAction(label: 'Duplicate', onPressed: _noop),
          XpAction(label: 'Delete', onPressed: _noop, destructive: true),
        ],
        builder: (context, open) => XpButton.secondary(
          label: 'Pull-down menu',
          glyph: XpGlyph.more,
          expand: false,
          onPressed: open,
        ),
      ),
    ),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'system_sheets',
    builder: (context) => Wrap(
      spacing: XpSpace.s8,
      children: [
        XpButton.text(
          label: 'Action sheet',
          onPressed: () => unawaited(
            showXpActionSheet(
              context: context,
              cancelLabel: 'Cancel',
              actions: [
                const XpAction(label: 'Duplicate', onPressed: _noop),
                const XpAction(
                  label: 'Delete',
                  onPressed: _noop,
                  destructive: true,
                ),
              ],
            ),
          ),
        ),
        XpButton.text(
          label: 'Date picker',
          onPressed: () => unawaited(
            showXpDatePickerSheet(
              context: context,
              initial: DateTime(2026, 11, 22),
              cancelLabel: 'Cancel',
              doneLabel: 'Done',
              title: 'Date',
            ),
          ),
        ),
        XpButton.text(
          label: 'Undo toast',
          onPressed: () => showUndoToast(
            context: context,
            message: 'Entry deleted',
            actionLabel: 'Undo',
            onAction: _noop,
          ),
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Controls',
    name: 'context_menu',
    builder: (context) => const XpContextMenu(
      actions: [
        XpAction(label: 'Edit', onPressed: _noop),
        XpAction(label: 'Duplicate', onPressed: _noop),
        XpAction(label: 'Delete', onPressed: _noop, destructive: true),
      ],
      child: XpListRow(
        title: 'Long-press me',
        subtitle: 'Context menu',
        trailing: MoneyText(-5810, exponent: _usd),
        showDivider: false,
      ),
    ),
  ),
  // Status.
  GalleryEntry(
    section: 'Status',
    name: 'progress',
    builder: (context) => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThinBar(value: 0.64, semanticLabel: 'November budget'),
        SizedBox(height: XpSpace.s16),
        StepBar(current: 2, semanticLabel: 'Step 2 of 4'),
        SizedBox(height: XpSpace.s16),
        Row(
          children: [
            ProgressRing(value: 0.42, semanticLabel: 'Holiday fund'),
            SizedBox(width: XpSpace.s16),
            XpSpinner(semanticLabel: 'Loading'),
          ],
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'goal_bar',
    builder: (context) => const GoalBar(
      label: 'Holiday fund',
      value: 0.42,
      pace: 'On track · 120/mo',
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'skeleton',
    builder: (context) => const Skeleton(semanticLabel: 'Loading entries'),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'badges',
    builder: (context) => Row(
      children: [
        const GuessedBadge(label: 'Guessed'),
        const SizedBox(width: XpSpace.s16),
        Dot.unread(context),
        const SizedBox(width: XpSpace.s16),
        Dot(color: XpColors.of(context).income),
        const SizedBox(width: XpSpace.s16),
        const CountBadge(count: 3, semanticLabel: '3 unread'),
        const SizedBox(width: XpSpace.s8),
        const CountBadge(count: 128),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'empty_state',
    builder: (context) => const EmptyState(
      message: 'No entries yet.',
      actionLabel: 'Add one',
      onAction: _noop,
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'offline_banner',
    builder: (context) => const OfflineBanner(
      message: 'Offline. Showing saved data.',
      actionLabel: 'Retry',
      onAction: _noop,
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'undo_toast',
    backdrop: true,
    builder: (context) => const UndoToast(
      message: 'Entry deleted',
      actionLabel: 'Undo',
      onAction: _noop,
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'rate_prompt',
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RatePrompt(
          question: "Today's dollar rate?",
          rate: '1,705',
          sameLabel: 'Same',
          changeLabel: 'Change',
          onSame: _noop,
          onChange: () => unawaited(_openRateSheet(context)),
        ),
        const SizedBox(height: XpSpace.s16),
        Slip(
          children: [
            RatePrompt(
              question: 'Rate for this entry?',
              rate: '1,705',
              sameLabel: 'Same',
              changeLabel: 'Change',
              placement: RatePromptPlacement.inline,
              onSame: _noop,
              onChange: () => unawaited(_openRateSheet(context)),
            ),
          ],
        ),
      ],
    ),
  ),
  GalleryEntry(
    section: 'Status',
    name: 'rate_change_sheet',
    backdrop: true,
    builder: (context) => GlassSheet(
      child: RateChangeSheet(
        title: "Today's dollar rate",
        initial: '1,705',
        unit: 'IQD per USD',
        saveLabel: 'Save',
        backspaceLabel: 'Delete',
        onSave: (_) {},
      ),
    ),
  ),
  // Sheets and overlays.
  GalleryEntry(
    section: 'Sheets',
    name: 'glass_sheet',
    backdrop: true,
    builder: (context) => const GlassSheet(
      header: SheetHeader(
        cancelLabel: 'Cancel',
        onCancel: _noop,
        title: 'Add manually',
        actionLabel: 'Save',
        onAction: _noop,
      ),
      child: AmountField(
        label: 'Amount',
        currency: 'USD',
        exponent: _usd,
        onCurrencyPressed: _noop,
      ),
    ),
  ),
  GalleryEntry(
    section: 'Sheets',
    name: 'receipt_sheet',
    builder: (context) => const _ReceiptSample(),
  ),
  GalleryEntry(
    section: 'Sheets',
    name: 'lock_overlay',
    builder: (context) => const SizedBox(
      height: XpSpace.listRow * 6,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(),
          LockOverlay(unlockLabel: 'Unlock with Face ID', onUnlock: _noop),
        ],
      ),
    ),
  ),
];

Future<void> _openRateSheet(BuildContext context) => showGlassSheet<void>(
  context: context,
  detent: SheetDetent.large,
  builder: (sheet) => RateChangeSheet(
    title: "Today's dollar rate",
    initial: '1,705',
    unit: 'IQD per USD',
    saveLabel: 'Save',
    backspaceLabel: 'Delete',
    onSave: (_) => Navigator.of(sheet).pop(),
  ),
);

/// A busy, high-contrast backdrop so glass blur and tint are visible.
class _Backdrop extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = XpColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _StripePainter(ink: c.ink, canvas: c.canvas, accent: c.accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const new({required this.ink, required this.canvas, required this.accent});

  final Color ink;
  final Color canvas;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = this.canvas);
    final paint = Paint()..color = ink;
    const stripe = XpSpace.s16;
    for (var x = -size.height; x < size.width; x += stripe * 2) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + stripe, size.height)
          ..lineTo(x + stripe + size.height, 0)
          ..lineTo(x + size.height, 0)
          ..close(),
        paint,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.7, size.height / 2),
      size.height / 3,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_StripePainter old) =>
      old.ink != ink || old.canvas != canvas || old.accent != accent;
}

/// Wraps [child] over the busy backdrop.
class GalleryBackdrop extends StatelessWidget {
  /// Puts [child] over a striped backdrop.
  const new({required this.child, super.key});

  /// The glass sample.
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: _Backdrop()),
      Padding(
        padding: const EdgeInsetsDirectional.all(XpSpace.s16),
        child: child,
      ),
    ],
  );
}

class _Swatches extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = XpColors.of(context);
    final type = XpType.of(context);
    final swatches = <(String, Color)>[
      ('canvas', c.canvas),
      ('surface', c.surface),
      ('sunken', c.surfaceSunken),
      ('ink', c.ink),
      ('ink 2', c.inkSecondary),
      ('ink 3', c.inkTertiary),
      ('hairline', c.hairline),
      ('accent', c.accent),
      ('income', c.income),
      ('saved', c.saved),
      ('loan', c.loan),
      ('danger', c.danger),
      for (var i = 0; i < c.categories.length; i++)
        ('cat${i + 1}', c.categories[i]),
    ];
    return Wrap(
      spacing: XpSpace.s8,
      runSpacing: XpSpace.s8,
      children: [
        for (final (name, color) in swatches)
          SizedBox(
            width: XpSpace.s40 + XpSpace.s32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: XpSpace.s32,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: XpRadius.slipAll,
                      border: Border.all(
                        color: c.hairline,
                        width: XpSpace.hairline(context),
                      ),
                    ),
                  ),
                ),
                Text(
                  name.toUpperCase(),
                  style: type.monoLabel.copyWith(color: c.inkSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TypeRamp extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final t = XpType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('12,480.00', style: t.figureHero),
        Text('IQD 10,000', style: t.figureLarge),
        Text('IQD 46,500', style: t.figureMedium),
        Text('5,650.00 · figureBody', style: t.figureBody),
        Text('≈ USD 7.63 · figureSmall', style: t.figureSmall),
        Text('NOV 2026 · OUR HOME', style: t.monoLabel),
        Text('ASK', style: t.screenTitle),
        Text('“Spent ten thousand dinars”', style: t.quote),
        Text('City Market · title', style: t.title),
        Text('Body text, Geist 400', style: t.body),
        Text('Row title, Geist 500', style: t.bodyStrong),
        Text('Which wallet did you pay from?', style: t.subhead),
        Text('Section label · caption', style: t.caption),
        Text('Groceries · You · meta', style: t.meta),
        Text('Button label', style: t.button),
        Text('Chip label', style: t.chip),
        Text('Tab label', style: t.tabLabelActive),
      ],
    );
  }
}

class _GlassSample extends StatelessWidget {
  const new({required this.variant});

  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final shape = switch (variant) {
      GlassVariant.accent => const CircleBorder(),
      GlassVariant.sheet => const RoundedSuperellipseBorder(
        borderRadius: XpRadius.sheetAll,
      ),
      GlassVariant.dock => const RoundedSuperellipseBorder(
        borderRadius: XpRadius.dockAll,
      ),
      _ => const StadiumBorder(),
    };
    final size = switch (variant) {
      GlassVariant.accent => const Size.square(XpSpace.askButton),
      GlassVariant.sheet => const Size(double.infinity, XpSpace.listRow * 2),
      GlassVariant.dock => const Size(
        double.infinity,
        XpSpace.listRow + XpSpace.s20,
      ),
      _ => const Size(double.infinity, XpSpace.tabBarHeight),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: GlassSurface(
          variant: variant,
          shape: shape,
          child: Center(
            child: variant == GlassVariant.accent
                ? const XpIcon(XpGlyph.sparkle, size: XpSpace.iconAsk)
                : Builder(
                    builder: (context) => Text(
                      variant.name.toUpperCase(),
                      style: type.monoLabel.copyWith(
                        color: GlassSurface.contentColorOf(context),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TierSample extends StatefulWidget {
  const new({required this.tier});

  final GlassTier tier;

  @override
  State<_TierSample> createState() => _TierSampleState();
}

class _TierSampleState extends State<_TierSample> {
  late final GlassController _controller = GlassController(
    deviceTier: widget.tier,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassScope(
    controller: _controller,
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: XpSpace.tabBarHeight,
            child: GlassSurface(
              variant: GlassVariant.control,
              child: Center(
                child: Text(
                  'TIER ${widget.tier.index} · '
                  '${widget.tier.name.toUpperCase()}',
                  style: XpType.of(context).monoLabel,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: XpSpace.s8),
        const SizedBox.square(
          dimension: XpSpace.askButton,
          child: GlassSurface(
            variant: GlassVariant.accent,
            shape: CircleBorder(),
            child: Center(
              child: XpIcon(XpGlyph.sparkle, size: XpSpace.iconAsk),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TabBarSample extends StatefulWidget {
  const new();

  @override
  State<_TabBarSample> createState() => _TabBarSampleState();
}

class _TabBarSampleState extends State<_TabBarSample> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => XpTabBarWithAsk(
    tabBar: XpTabBar(
      items: _tabs,
      selectedIndex: _index,
      onSelected: (i) => setState(() => _index = i),
    ),
    askButton: const AskButton(
      semanticLabel: 'Ask: talk, type or scan',
      onPressed: _noop,
    ),
  );
}

class _DockSample extends StatefulWidget {
  const new({required this.initial});

  final CaptureMode initial;

  @override
  State<_DockSample> createState() => _DockSampleState();
}

class _DockSampleState extends State<_DockSample> {
  late CaptureMode _mode = widget.initial;
  bool _recording = true;

  @override
  Widget build(BuildContext context) => CaptureDock(
    mode: _mode,
    labels: _dockLabels,
    recording: _recording,
    levels: _recording ? _wave : const [],
    spoken: 20,
    onModeChanged: (mode) => setState(() => _mode = mode),
    onRecord: () => setState(() => _recording = !_recording),
    onScan: _noop,
  );
}

class _EntrySlipSample extends StatefulWidget {
  const new();

  @override
  State<_EntrySlipSample> createState() => _EntrySlipSampleState();
}

class _EntrySlipSampleState extends State<_EntrySlipSample> {
  String? _wallet;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return EntrySlip(
      header: 'Expense · Dining out',
      confidence: '94%',
      guessedLabel: 'Guessed',
      semanticLabel:
          'Expense, dining out, 10,000 Iraqi dinars, today, guessed category',
      amount: const MoneyText(
        10000,
        exponent: _iqd,
        currency: 'IQD',
        style: MoneyStyle.large,
        converted: '≈ USD 7.63',
      ),
      fields: [
        const SlipField(label: 'Who', value: 'You + kids'),
        const SlipField(label: 'When', value: 'Today 13:20'),
        SlipField(
          label: 'From',
          value: _wallet ?? '—',
          guessed: _wallet == null,
        ),
      ],
      question: _wallet == null
          ? 'Which wallet did you pay from?'
          : 'Got it. Save it?',
      choices: ChoiceChips<String>(
        options: const [
          ChoiceOption(value: 'Cash · IQD', label: 'Cash (IQD)'),
          ChoiceOption(value: 'Joint Visa', label: 'Joint Visa'),
          ChoiceOption(value: 'Sam paid', label: 'Sam paid'),
        ],
        selected: _wallet,
        onSelected: (v) => setState(() {
          _wallet = v;
          _saved = false;
        }),
      ),
      action: _wallet == null
          ? null
          : const XpButton.primary(label: 'Save →', onPressed: _noop),
      footer: _saved
          ? Row(
              children: [
                XpIcon(
                  XpGlyph.check,
                  size: XpSpace.iconPill,
                  color: colors.income,
                ),
                const SizedBox(width: XpSpace.s6),
                Expanded(
                  child: Text(
                    'SAVED · DINING 85,000 / 120,000',
                    style: type.figureSmall.copyWith(color: colors.income),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _ChipsSample extends StatefulWidget {
  const new();

  @override
  State<_ChipsSample> createState() => _ChipsSampleState();
}

class _ChipsSampleState extends State<_ChipsSample> {
  String? _value = 'IQD';

  @override
  Widget build(BuildContext context) => ChoiceChips<String>(
    options: const [
      ChoiceOption(value: 'USD', label: 'USD'),
      ChoiceOption(value: 'IQD', label: 'IQD'),
      ChoiceOption(value: 'Both', label: 'Both currencies'),
    ],
    selected: _value,
    onSelected: (v) => setState(() => _value = v),
  );
}

class _FilterSample extends StatefulWidget {
  const new();

  @override
  State<_FilterSample> createState() => _FilterSampleState();
}

class _FilterSampleState extends State<_FilterSample> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => XpFilterBar(
    labels: const ['All', 'Mine', 'Partner', 'Joint', 'Loans and debts'],
    selectedIndex: _index,
    onSelected: (i) => setState(() => _index = i),
  );
}

class _SwitchSample extends StatefulWidget {
  const new();

  @override
  State<_SwitchSample> createState() => _SwitchSampleState();
}

class _SwitchSampleState extends State<_SwitchSample> {
  bool _a = true;
  bool _b = false;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('Split by category', style: type.subhead)),
            XpSwitch(
              value: _a,
              semanticLabel: 'Split by category',
              onChanged: (v) => setState(() => _a = v),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text('Share this account', style: type.subhead)),
            XpSwitch(
              value: _b,
              semanticLabel: 'Share this account',
              onChanged: (v) => setState(() => _b = v),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptSample extends StatefulWidget {
  const new();

  @override
  State<_ReceiptSample> createState() => _ReceiptSampleState();
}

class _ReceiptSampleState extends State<_ReceiptSample> {
  bool _split = true;

  @override
  Widget build(BuildContext context) {
    final c = XpColors.of(context);
    final groups = _split
        ? const [
            ReceiptGroup(
              name: 'Groceries',
              items: '3 items',
              minorUnits: 27500,
            ),
            ReceiptGroup(name: 'Household', items: '1 item', minorUnits: 4000),
            ReceiptGroup(
              name: 'Kids & school',
              items: '1 item',
              minorUnits: 15000,
            ),
          ]
        : const [
            ReceiptGroup(
              name: 'Groceries',
              items: '5 items',
              minorUnits: 46500,
            ),
          ];
    return ColoredBox(
      color: c.scanBackdrop,
      child: Column(
        children: [
          Stack(
            children: [
              SizedBox(
                height: XpSpace.listRow * 4,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: XpSpace.s40 + XpSpace.s32,
                    vertical: XpSpace.s32,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.all(XpSpace.s16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.receiptPaper,
                            borderRadius: XpRadius.paperAll,
                            boxShadow: XpElevation.paper,
                          ),
                        ),
                      ),
                      const ScanFrame(),
                    ],
                  ),
                ),
              ),
              const CameraScrim(),
              const Padding(
                padding: EdgeInsetsDirectional.all(XpSpace.s16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassIconButton(
                      glyph: XpGlyph.close,
                      semanticLabel: 'Close',
                      overMedia: true,
                      onPressed: _noop,
                    ),
                    GlassPill(
                      label: 'Read on device',
                      glyph: XpGlyph.lock,
                      mono: true,
                      overMedia: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(XpSpace.sheetMargin),
            child: GlassSheet(
              overMedia: true,
              child: ReceiptSheet(
                merchant: 'City Market',
                meta: 'Today 18:05 · Cash',
                totalMinor: 46500,
                currency: 'IQD',
                exponent: _iqd,
                converted: '≈ USD 35.50',
                splitLabel: 'Split by category',
                split: _split,
                onSplitChanged: (v) => setState(() => _split = v),
                groups: groups,
                retakeLabel: 'Retake',
                onRetake: _noop,
                saveLabel: _split ? 'Save 3 entries →' : 'Save 1 entry →',
                onSave: _noop,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
