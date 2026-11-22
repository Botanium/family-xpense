/// One member's view of a household, cached for 60 seconds.
///
/// The `householdContext` middleware reads it on every model call of the
/// tool loop and the tools read it on every call, so without a cache one
/// capture turn would read the same documents a dozen times
/// (AI_PIPELINE 8: "cached 60 s").
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What the agent knows about the household for one member.
@immutable
final class HouseholdSnapshot {
  /// Creates a snapshot.
  const new({
    required this.profile,
    required this.uid,
    required this.members,
    required this.accounts,
    required this.categories,
    required this.people,
  });

  /// The household.
  final HouseholdProfile profile;

  /// The calling member.
  final String uid;

  /// Every member.
  final List<HouseholdMember> members;

  /// Accounts visible to [uid], archived ones included (labels of past
  /// entries). Balances and new entries use [activeAccounts].
  final List<HouseholdAccount> accounts;

  /// The accounts a new entry may use, and that balances list.
  List<HouseholdAccount> get activeAccounts => [
    for (final a in accounts)
      if (!a.archived) a,
  ];

  /// Every category, archived ones included: past entries keep their
  /// category, so totals, budgets and labels must still find it. New
  /// entries choose from [activeCategories].
  final List<HouseholdCategory> categories;

  /// The categories a new entry may use (archived ones left out).
  List<HouseholdCategory> get activeCategories => [
    for (final c in categories)
      if (!c.archived) c,
  ];

  /// People visible to [uid].
  final List<HouseholdPerson> people;

  /// The base currency.
  String get baseCurrency => profile.baseCurrency;

  /// The other member, if any.
  HouseholdMember? get partner {
    for (final m in members) {
      if (m.uid != uid) return m;
    }
    return null;
  }

  /// The calling member.
  HouseholdMember? get me {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  /// The account with [id], archived or not, or null (labels).
  HouseholdAccount? account(String? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The active account with [id], or null (new entries).
  HouseholdAccount? activeAccount(String? id) {
    final a = account(id);
    return a == null || a.archived ? null : a;
  }

  /// The category with [idOrSlug] as its id or slug, archived or not, or
  /// null (read side: totals and labels).
  HouseholdCategory? category(String? idOrSlug) => _find(categories, idOrSlug);

  /// The active category with [idOrSlug], or null (new entries).
  HouseholdCategory? activeCategory(String? idOrSlug) =>
      _find(activeCategories, idOrSlug);

  static HouseholdCategory? _find(
    List<HouseholdCategory> list,
    String? idOrSlug,
  ) {
    if (idOrSlug == null) return null;
    for (final c in list) {
      if (c.id == idOrSlug) return c;
    }
    for (final c in list) {
      if (c.slug == idOrSlug) return c;
    }
    return null;
  }

  /// The person with [id], or null.
  HouseholdPerson? person(String? id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The ids the phone would check drafts against.
  HouseholdRefs get refs => HouseholdRefs(
    accountCurrencies: {for (final a in activeAccounts) a.id: a.currency},
    categoryIds: {for (final c in activeCategories) c.id},
    personIds: {for (final p in people) p.id},
  );

  /// The fast parser's view of the household.
  List<ParserAccount> get parserAccounts => [
    for (final a in activeAccounts)
      if (Currency.tryParse(a.currency) case final currency?)
        ParserAccount(id: a.id, name: a.name, currency: currency, kind: a.kind),
  ];

  /// The fast parser's view of the people.
  List<ParserPerson> get parserPeople => [
    for (final p in people)
      ParserPerson(id: p.id, name: p.name, aliases: p.aliases),
  ];

  /// The fast parser's view of the categories.
  List<ParserCategory> get parserCategories => [
    for (final c in activeCategories)
      ParserCategory(id: c.id, names: {'en': c.name}, kind: c.kind),
  ];
}

/// Loads [HouseholdSnapshot]s through a [HouseholdReader] and keeps each for
/// [ttl].
final class HouseholdSnapshots {
  /// Creates the cache.
  new(this.reader, {Clock? clock, this.ttl = const Duration(seconds: 60)})
    : _clock = clock ?? const Clock();

  /// The data source.
  final HouseholdReader reader;

  /// How long a snapshot is reused.
  final Duration ttl;

  final Clock _clock;
  final _entries =
      <String, ({DateTime at, Future<HouseholdSnapshot?> value})>{};

  /// The snapshot of [hid] as seen by [uid], or null when the household
  /// does not exist. Throws [HouseholdUnavailable] when it cannot be read.
  Future<HouseholdSnapshot?> get(String hid, String uid) {
    final key = '$hid/$uid';
    final now = _clock.now();
    final hit = _entries[key];
    if (hit != null && now.difference(hit.at) < ttl) return hit.value;
    final value = _load(hid, uid);
    _entries[key] = (at: now, value: value);
    // A failed load is not cached.
    value.ignore();
    unawaited(
      value.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_entries[key]?.value, value)) _entries.remove(key);
        },
      ),
    );
    if (_entries.length > 500) _entries.remove(_entries.keys.first);
    return value;
  }

  /// Drops every cached snapshot (tests).
  void clear() => _entries.clear();

  Future<HouseholdSnapshot?> _load(String hid, String uid) async {
    final profile = await reader.profile(hid);
    if (profile == null) return null;
    // Future.wait rethrows the first error itself (a HouseholdUnavailable),
    // unlike a record's `.wait`.
    final results = await Future.wait<Object>([
      reader.members(hid),
      reader.accounts(hid, uid: uid),
      reader.categories(hid),
      reader.people(hid, uid: uid),
    ]);
    final members = results[0] as List<HouseholdMember>;
    final accounts = results[1] as List<HouseholdAccount>;
    final categories = results[2] as List<HouseholdCategory>;
    final people = results[3] as List<HouseholdPerson>;
    return HouseholdSnapshot(
      profile: profile,
      uid: uid,
      members: members,
      accounts: [...accounts]..sort((a, b) => a.order.compareTo(b.order)),
      categories: categories,
      people: people,
    );
  }
}
