import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/badges.dart';
import 'package:xpense_app/core/ui/glass/glass_surface.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Round 44 pt glass button for the top of a screen: back, close, bell
/// (DESIGN_SYSTEM 5 and 8.1).
class GlassIconButton extends StatelessWidget {
  /// Creates a round glass button.
  const new({
    required this.glyph,
    required this.semanticLabel,
    required this.onPressed,
    this.unread = false,
    this.overMedia = false,
    super.key,
  });

  /// The icon.
  final XpGlyph glyph;

  /// Spoken label, such as "Back to home" or "Notifications, 1 new".
  final String semanticLabel;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Whether to show the orange unread dot.
  final bool unread;

  /// Whether the button sits over the camera preview.
  final bool overMedia;

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    excludeChildSemantics: true,
    child: SizedBox.square(
      dimension: XpSpace.topButton,
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassSurface(
              variant: overMedia ? GlassVariant.overMedia : GlassVariant.button,
              shape: const CircleBorder(),
              child: Center(child: XpIcon(glyph, size: XpSpace.iconTop)),
            ),
          ),
          if (unread)
            PositionedDirectional(
              top: XpSpace.s12,
              end: XpSpace.s12,
              child: Dot.unread(context),
            ),
        ],
      ),
    ),
  );
}

/// Glass pill, 32 high: optional icon and a short label (DESIGN_SYSTEM 5).
class GlassPill extends StatelessWidget {
  /// Creates a glass pill.
  const new({
    required this.label,
    this.glyph,
    this.color,
    this.mono = false,
    this.overMedia = false,
    this.onPressed,
    super.key,
  });

  /// Pill text.
  final String label;

  /// Optional leading icon.
  final XpGlyph? glyph;

  /// Text and icon colour; defaults to the recipe's content colour.
  final Color? color;

  /// Whether the label is a mono upper-case label (as "READ ON DEVICE").
  final bool mono;

  /// Whether the pill sits over the camera preview.
  final bool overMedia;

  /// Tap handler; null makes the pill a status display.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final pill = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: XpSpace.pillHeight),
      child: GlassSurface(
        variant: overMedia ? GlassVariant.overMedia : GlassVariant.button,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.pillPadding,
          vertical: XpSpace.s6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (glyph != null) ...[
              XpIcon(glyph!, size: XpSpace.iconPill, color: color),
              const SizedBox(width: XpSpace.s6),
            ],
            Flexible(
              child: Builder(
                builder: (context) {
                  final fg = color ?? GlassSurface.contentColorOf(context);
                  return Text(
                    mono ? label.toUpperCase() : label,
                    style: mono
                        ? type.monoLabel.copyWith(color: fg)
                        : type.meta.copyWith(
                            fontWeight: FontWeight.w500,
                            color: fg,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return onPressed == null
        ? Semantics(container: true, child: pill)
        : XpPressable(onPressed: onPressed, child: pill);
  }
}

/// Privacy modes shown by [ModeChip].
enum PrivacyModeKind {
  /// Nothing leaves the phone for AI processing.
  onDevice,

  /// Default mix of device and cloud.
  smart,

  /// Cloud first.
  cloud,
}

/// Glass pill with a lock icon and the privacy mode (DESIGN_SYSTEM 8.2).
/// On-device mode reads in income green; the lock and the word carry the
/// meaning, not the colour.
class ModeChip extends StatelessWidget {
  /// Creates a mode chip.
  const new({
    required this.mode,
    required this.label,
    this.onPressed,
    super.key,
  });

  /// Current mode.
  final PrivacyModeKind mode;

  /// Mode name, such as "On-device".
  final String label;

  /// Opens the mode picker.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return GlassPill(
      label: label,
      glyph: mode == PrivacyModeKind.onDevice ? XpGlyph.lock : null,
      color: mode == PrivacyModeKind.onDevice ? colors.income : null,
      onPressed: onPressed,
    );
  }
}

/// Navigation bar: glass back button leading, mono upper-case title,
/// optional glass pill trailing. No large titles (DESIGN_SYSTEM 8.1).
class XpTopBar extends StatelessWidget {
  /// Creates a top bar.
  const new({required this.title, this.leading, this.trailing, super.key});

  /// Screen title; upper-cased here.
  final String title;

  /// Leading control, usually a [GlassIconButton] with [XpGlyph.back].
  final Widget? leading;

  /// Trailing control, such as a [ModeChip].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: XpSpace.floatingMargin,
      ),
      child: SizedBox(
        height: XpSpace.minTarget,
        child: NavigationToolbar(
          leading: leading,
          middle: Semantics(
            header: true,
            child: Text(title.toUpperCase(), style: type.screenTitle),
          ),
          trailing: trailing,
          middleSpacing: XpSpace.s8,
        ),
      ),
    );
  }
}

/// One tab of [XpTabBar].
@immutable
class XpTabItem {
  /// Creates a tab item.
  const new({required this.glyph, required this.label});

  /// Icon.
  final XpGlyph glyph;

  /// Label under the icon.
  final String label;
}

/// The floating glass tab bar: four equal items in a pill (DESIGN_SYSTEM
/// 8.1). Tab labels stop scaling at 1.35×, matching iOS; each item keeps its
/// full semantics label.
class XpTabBar extends StatelessWidget {
  /// Creates a tab bar.
  const new({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  /// Tabs, in order.
  final List<XpTabItem> items;

  /// Index of the current tab.
  final int selectedIndex;

  /// Called with the tapped index.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final motion = XpMotion.of(context);
    return SizedBox(
      height: XpSpace.tabBarHeight,
      child: GlassSurface(
        variant: GlassVariant.control,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.tabBarInset,
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: XpFonts.tabLabelMaxScale,
          child: Row(
            children: [
              for (final (i, item) in items.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selectedIndex,
                    label: item.label,
                    excludeSemantics: true,
                    onTap: () => onSelected(i),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: AnimatedContainer(
                        duration: motion.fast,
                        curve: XpMotion.fastCurve,
                        height: XpSpace.tabItemWell,
                        decoration: ShapeDecoration(
                          color: i == selectedIndex
                              ? colors.tabActiveWell
                              : null,
                          shape: const StadiumBorder(),
                        ),
                        child: _TabContent(
                          item: item,
                          color: i == selectedIndex
                              ? colors.ink
                              : colors.tabInactive,
                          style: i == selectedIndex
                              ? type.tabLabelActive
                              : type.tabLabelInactive,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const new({required this.item, required this.color, required this.style});

  final XpTabItem item;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      XpIcon(item.glyph, size: XpSpace.iconTab, color: color),
      const SizedBox(height: XpSpace.s2),
      Text(
        item.label,
        style: style.copyWith(color: color),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    ],
  );
}

/// The round orange Ask button beside the tab bar (DESIGN_SYSTEM 8.1).
class AskButton extends StatelessWidget {
  /// Creates the Ask button.
  const new({required this.semanticLabel, required this.onPressed, super.key});

  /// Spoken label, such as "Ask: talk, type or scan".
  final String semanticLabel;

  /// Opens Ask.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    excludeChildSemantics: true,
    child: const SizedBox.square(
      dimension: XpSpace.askButton,
      child: GlassSurface(
        variant: GlassVariant.accent,
        shape: CircleBorder(),
        child: Center(child: XpIcon(XpGlyph.sparkle, size: XpSpace.iconAsk)),
      ),
    ),
  );
}

/// The tab bar and the Ask button side by side, as they float at the bottom
/// of the four tab screens. Wraps both in one glass group.
class XpTabBarWithAsk extends StatelessWidget {
  /// Creates the bottom controls.
  const new({required this.tabBar, required this.askButton, super.key});

  /// The tab bar.
  final XpTabBar tabBar;

  /// The Ask button.
  final AskButton askButton;

  @override
  Widget build(BuildContext context) => XpGlassGroup(
    child: Row(
      children: [
        Expanded(child: tabBar),
        const SizedBox(width: XpSpace.s8),
        askButton,
      ],
    ),
  );
}
