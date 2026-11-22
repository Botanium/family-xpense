/// App strings (DESIGN_SYSTEM 10).
///
/// Every user-facing string comes from `lib/l10n/app_en.arb` through the
/// generated [AppLocalizations]. Read them with `context.l10n.someKey`.
/// Keys start with the feature that owns them; sentences stay whole and
/// amounts are placeholders, so a new language is a translation task.
library;

import 'package:flutter/widgets.dart';

import 'package:xpense_app/core/l10n/generated/app_localizations.dart';

export 'package:xpense_app/core/l10n/generated/app_localizations.dart';

/// Short access to the app strings.
extension XpL10n on BuildContext {
  /// The strings for the current locale.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
