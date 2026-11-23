import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

// The frame and text pieces of onboarding screens 2 to 5 (WP-11). They live
// in core/ui because those screens belong to different features
// (onboarding, household, accounts) and features may not import each
// other (WP-12 moved them here unchanged).

/// Number of steps in the onboarding step bar: account, household,
/// accounts, try it (DESIGN_SYSTEM 9, screens 2 to 5).
const int onboardingStepCount = 4;

/// The frame of an onboarding screen, placed as on the reference artboards
/// (docs/design/index.md): the top bar 8 pt under the safe area, the first
/// content line 16 pt under the bar, a 24 pt margin, and [bottom] pinned
/// [XpSpace.bottomControlOffset] above the bottom edge while there is room.
/// At large text sizes everything scrolls together instead of overlapping.
class OnboardingFrame extends StatelessWidget {
  /// Creates the frame.
  const new({
    required this.content,
    this.topBar,
    this.banner,
    this.bottom,
    super.key,
  });

  /// The scrolling content.
  final Widget content;

  /// The top bar, if the screen has one.
  final Widget? topBar;

  /// A banner under the top bar, such as the offline banner.
  final Widget? banner;

  /// Content kept at the bottom of the screen: buttons, notes.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final offset = XpSpace.bottomControlOffset(context);
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: XpSpace.s8),
            ?topBar,
            ?banner,
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsetsDirectional.only(
                      start: XpSpace.screenMargin,
                      end: XpSpace.screenMargin,
                      top: topBar == null ? 0 : XpSpace.s16,
                    ),
                    sliver: SliverToBoxAdapter(child: content),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: XpSpace.screenMargin,
                        end: XpSpace.screenMargin,
                        top: bottom == null ? 0 : XpSpace.s24,
                        bottom: offset,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.bottomCenter,
                        child: bottom,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An onboarding headline: `quote`, the largest sans style (there is no
/// display style; docs/design/index.md).
class OnboardingHeading extends StatelessWidget {
  /// Creates a headline.
  const new(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: XpType.of(context).quote),
  );
}

/// The paragraph under an onboarding headline, in secondary ink.
class OnboardingParagraph extends StatelessWidget {
  /// Creates a paragraph.
  const new(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: XpType.of(context).body
        .copyWith(color: XpColors.of(context).inkSecondary),
  );
}

/// A short status line that VoiceOver reads when it appears: an inline
/// error in `danger`, or a neutral note in secondary ink.
class OnboardingMessage extends StatelessWidget {
  /// Creates an error line.
  const new error(this.text, {super.key}) : isError = true;

  /// Creates a neutral note.
  const new note(this.text, {super.key}) : isError = false;

  /// The words.
  final String text;

  /// Whether this is an error.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        text,
        style: XpType.of(context).caption
            .copyWith(color: isError ? colors.danger : colors.inkSecondary),
      ),
    );
  }
}
