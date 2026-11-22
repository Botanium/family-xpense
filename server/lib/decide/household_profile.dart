/// What `/decide` reads about a household to build its question set: the
/// categories, the accounts and people the speaker may see, the members,
/// and recent entries with a given amount (duplicate candidates).
///
/// [HouseholdSource] is the read interface. The Firestore implementation is
/// `lib/admin/firestore_household_source.dart` (only `lib/admin/` may import
/// the Firestore client); tests use an in-memory source.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A household member (`households/{hid}/members/{uid}`).
@immutable
final class ProfileMember {
  /// Creates a member.
  const new({required this.uid, required this.name});

  /// The member's uid.
  final String uid;

  /// Display name.
  final String name;
}

/// An account the speaker may see (`accounts/{accountId}`).
@immutable
final class ProfileAccount {
  /// Creates an account.
  const new({
    required this.id,
    required this.name,
    required this.currency,
    required this.kind,
    required this.joint,
    this.ownerUid,
  });

  /// Document id; the option key.
  final String id;

  /// Display name, such as "Cash wallet".
  final String name;

  /// ISO code.
  final String currency;

  /// `cash`, `bank`, `credit`, `savings` or `other`.
  final String kind;

  /// Whether the account is joint.
  final bool joint;

  /// The owner of a personal account.
  final String? ownerUid;
}

/// A counterparty the speaker may see (`people/{personId}`).
@immutable
final class ProfilePerson {
  /// Creates a person.
  const new({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.memberUid,
  });

  /// Document id; the option key.
  final String id;

  /// Display name.
  final String name;

  /// Other names the person is called by.
  final List<String> aliases;

  /// Set when the person is a household member.
  final String? memberUid;
}

/// A household category (`categories/{categoryId}`).
@immutable
final class ProfileCategory {
  /// Creates a category.
  const new({
    required this.id,
    required this.slug,
    required this.name,
    required this.kind,
    this.parentId,
  });

  /// Document id; the option key.
  final String id;

  /// Stable slug; for seeded categories it names the examples.
  final String slug;

  /// Display name in the request language.
  final String name;

  /// Expense or income.
  final CategoryKind kind;

  /// The group's document id, for a sub-category.
  final String? parentId;

  /// Whether this is a top-level group.
  bool get isGroup => parentId == null;
}

/// Everything about one household that the question set needs, already
/// limited to what the speaker may see.
@immutable
final class HouseholdProfile {
  /// Creates a profile.
  const new({
    required this.baseCurrency,
    required this.members,
    required this.accounts,
    required this.people,
    required this.categories,
  });

  /// The household base currency.
  final String baseCurrency;

  /// The members (at most two).
  final List<ProfileMember> members;

  /// Accounts visible to the speaker, not archived, in list order.
  final List<ProfileAccount> accounts;

  /// People visible to the speaker.
  final List<ProfilePerson> people;

  /// Categories, not archived, in list order.
  final List<ProfileCategory> categories;

  /// The member with [uid], or null.
  ProfileMember? member(String uid) {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  /// The account with [id], or null.
  ProfileAccount? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// A saved entry with the same amount as the message (DATA_MODEL 2.5).
@immutable
final class RecentEntry {
  /// Creates an entry.
  const new({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.occurredOn,
    required this.accountId,
    this.title,
    this.deleted = false,
  });

  /// Transaction id.
  final String id;

  /// Amount in minor units.
  final int amountMinor;

  /// ISO code.
  final String currency;

  /// Household-local date, `YYYY-MM-DD`.
  final String occurredOn;

  /// The account money left or entered.
  final String accountId;

  /// Merchant or short label.
  final String? title;

  /// Whether the entry is soft-deleted.
  final bool deleted;
}

/// Reads a household for `/decide`.
abstract interface class HouseholdSource {
  /// The profile of household [hid] as member [uid] may see it. Throws
  /// `GatewayUnavailable` when Firestore cannot be read.
  Future<HouseholdProfile> profile({required String hid, required String uid});

  /// Entries of [hid] visible to [uid] with [amountMinor], dated from
  /// [fromDay] to [toDay] inclusive (`YYYY-MM-DD`). Uses the duplicate-check
  /// index (`visibleTo`, `amountMinor`, `occurredOn`, DATA_MODEL 6).
  Future<List<RecentEntry>> entriesWithAmount({
    required String hid,
    required String uid,
    required int amountMinor,
    required String fromDay,
    required String toDay,
  });
}
