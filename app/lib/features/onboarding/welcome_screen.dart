import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Welcome (DESIGN_SYSTEM 9, screen 1; PRD ON-1): the value before an
/// account. One sample exchange, a quote and the slip it became, then
/// "Get started" and the invite path.
class WelcomeScreen extends StatelessWidget {
  /// Creates Welcome; [inviteCode] comes from an `xpense://join` link.
  const new({this.inviteCode, super.key});

  /// An invite code to carry to the join screen after signing in.
  final String? inviteCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingFrame(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AppMark(),
          const SizedBox(height: XpSpace.s32),
          TranscriptQuote(
            text: l10n.onboardingWelcomeQuote,
            duration: l10n.onboardingWelcomeQuoteDuration,
            levels: _sampleLevels,
          ),
          const SizedBox(height: XpSpace.s16),
          const _SampleSlip(),
          const SizedBox(height: XpSpace.s32),
          OnboardingHeading(l10n.onboardingWelcomeHeadline),
          const SizedBox(height: XpSpace.s8),
          OnboardingParagraph(l10n.onboardingWelcomeBody),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          XpButton.primary(
            label: l10n.onboardingWelcomeStart,
            onPressed: () => context.go(
              OnboardingRoutes.createAccountWith(code: inviteCode),
            ),
          ),
          const SizedBox(height: XpSpace.s8),
          XpButton.text(
            label: l10n.onboardingWelcomeInvite,
            onPressed: () => context.go(
              OnboardingRoutes.createAccountWith(
                invite: true,
                code: inviteCode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sample clip's waveform on the Welcome artboard.
const List<double> _sampleLevels = [
  4 / 14,
  8 / 14,
  12 / 14,
  6 / 14,
  1,
  10 / 14,
  1,
  8 / 14,
  12 / 14,
  6 / 14,
  10 / 14,
  8 / 14,
];

/// USD 60.00 in cents, and the same at the sample market rate of 1,705
/// dinars per dollar (DECISIONS D-16): IQD 102,300.
const int _sampleUsdMinor = 6000;
const int _sampleIqdMinor = 102300;

/// The round app mark and the product name.
class _AppMark extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: XpSpace.topButton,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.primaryFill,
                shape: const CircleBorder(),
              ),
              child: Center(
                child: XpIcon(
                  XpGlyph.sparkle,
                  size: XpSpace.iconTop,
                  color: colors.onPrimaryFill,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: XpSpace.s12),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              context.l10n.onboardingAppName,
              style: XpType.of(context).title,
            ),
          ),
        ),
      ],
    );
  }
}

/// The slip the sample message became.
class _SampleSlip extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final converted = MoneyFormat.figure(
      _sampleIqdMinor,
      exponent: Currency.iqd.exponent,
      currency: Currency.iqd.code,
    ).withCurrency;
    return EntrySlip(
      header: l10n.onboardingWelcomeSlipHeader,
      confidence: l10n.onboardingWelcomeSlipConfidence,
      amount: MoneyText(
        _sampleUsdMinor,
        exponent: Currency.usd.exponent,
        currency: Currency.usd.code,
        style: MoneyStyle.large,
        converted: l10n.onboardingWelcomeConverted(converted),
      ),
      fields: [
        SlipField(
          label: l10n.onboardingWelcomeSlipWho,
          value: l10n.onboardingWelcomeSlipWhoValue,
        ),
        SlipField(
          label: l10n.onboardingWelcomeSlipWhen,
          value: l10n.onboardingWelcomeSlipWhenValue,
        ),
        SlipField(
          label: l10n.onboardingWelcomeSlipFrom,
          value: l10n.onboardingWelcomeSlipFromValue,
        ),
      ],
      semanticLabel: l10n.onboardingWelcomeSlipSpoken,
    );
  }
}
