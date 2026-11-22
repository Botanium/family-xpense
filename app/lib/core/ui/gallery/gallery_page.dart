// Debug-only gallery screen. Labels are developer-facing, not product copy.
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/gallery/gallery_entries.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Route path of the gallery. WP-10 registers it in debug builds only
/// (`if (kDebugMode)`), so it never ships.
const String galleryRoutePath = '/gallery';

/// Every Signal component on one scrolling page, with a glass tier
/// override, for review in the simulator (DESIGN_SYSTEM 8).
class GalleryPage extends StatefulWidget {
  /// Creates the gallery.
  const new({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  GlassTier? _forced;
  GlassController? _override;

  void _cycleTier() {
    setState(() {
      final next = _forced == null
          ? GlassTier.premium
          : _forced == GlassTier.solid
          ? null
          : GlassTier.values[_forced!.index - 1];
      _override?.dispose();
      _forced = next;
      _override = next == null ? null : GlassController(deviceTier: next);
    });
  }

  @override
  void dispose() {
    _override?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final tier = _forced ?? GlassScope.tierOf(context);
    final sections = <String, List<GalleryEntry>>{};
    for (final entry in galleryEntries) {
      sections.putIfAbsent(entry.section, () => []).add(entry);
    }
    Widget page = Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: XpTopBar(
                title: 'Gallery',
                trailing: GlassPill(
                  label: 'Tier ${tier.index} ${tier.name}',
                  mono: true,
                  onPressed: _cycleTier,
                ),
              ),
            ),
            for (final MapEntry(key: section, value: entries)
                in sections.entries) ...[
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  XpSpace.screenMargin,
                  XpSpace.s32,
                  XpSpace.screenMargin,
                  XpSpace.s8,
                ),
                sliver: SliverToBoxAdapter(
                  child: Text(section, style: type.title),
                ),
              ),
              for (final entry in entries)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: XpSpace.screenMargin,
                      vertical: XpSpace.s12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          entry.name.toUpperCase(),
                          style: type.monoLabel.copyWith(
                            color: colors.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: XpSpace.s8),
                        GalleryEntryView(entry: entry),
                      ],
                    ),
                  ),
                ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: XpSpace.contentBottomPadding(context)),
            ),
          ],
        ),
      ),
    );
    if (_override != null) {
      page = GlassScope(controller: _override!, child: page);
    }
    return page;
  }
}

/// Renders one [GalleryEntry], over the striped backdrop when it holds
/// glass. Shared by the gallery page and the golden tests.
class GalleryEntryView extends StatelessWidget {
  /// Creates the view.
  const new({required this.entry, super.key});

  /// The entry.
  final GalleryEntry entry;

  @override
  Widget build(BuildContext context) {
    final sample = Builder(builder: entry.builder);
    return entry.backdrop
        ? ClipRRect(
            borderRadius: XpRadius.slipAll,
            child: GalleryBackdrop(child: sample),
          )
        : sample;
  }
}
