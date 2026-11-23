/// `householdInvite` and `householdJoin`: the flows behind
/// `POST /v1/household/invite` and `POST /v1/household/join` (ARCHITECTURE
/// 4.2).
///
/// Inputs and outputs are flat string maps, like `ping`:
///
/// - invite: input `{}` (or null). Output `{code, link, expiresAt}`; `code`
///   is 10 characters without separators, `expiresAt` ISO 8601 UTC.
/// - join: input `{code, displayName}`. Output `{householdId,
///   householdName}`.
///
/// Refusals are `GenkitException`s whose message is a [HouseholdFailure]
/// code.
library;

import 'package:genkit/genkit.dart';
import 'package:logging/logging.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/member_directory.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/household/household_failure.dart';
import 'package:xpense_agent/household/household_service.dart';

final _log = Logger('xpense.household.flows');

/// A household flow: string map in, string map out.
typedef HouseholdFlow =
    Flow<Map<String, String>?, Map<String, String>, void, void>;

/// Defines `householdInvite` on [ai]. The caller is the verified member in
/// the context; the input carries nothing.
HouseholdFlow defineHouseholdInviteFlow(Genkit ai, HouseholdService service) =>
    ai.defineFlow(
      name: 'householdInvite',
      inputSchema: .nullable(.map(.string(), .string(maxLength: 200))),
      outputSchema: .map(.string(), .string()),
      fn: (input, ctx) async {
        final caller = XpenseContext.of(ctx.context);
        final invite = await _guard(
          () => service.createInvite(uid: caller.uid, hid: caller.hid),
        );
        return {
          'code': invite.code,
          'link': invite.link,
          'expiresAt': invite.expiresAt.toUtc().toIso8601String(),
        };
      },
    );

/// Defines `householdJoin` on [ai]. The caller is any signed-in user;
/// [members] forgets its cached refusal for them once they join.
///
/// [afterJoin] runs once the join is committed, with the household id: it
/// rewrites the history of the joint and shared accounts the join widened
/// (WP-13), so the partner's first look is complete. The widening itself
/// commits inside the join transaction (`HouseholdService` `onJoin`), and
/// every widened account fires `/events/account-visibility`, which Eventarc
/// retries until the history follows; so a failure here is logged and never
/// fails the join.
HouseholdFlow defineHouseholdJoinFlow(
  Genkit ai,
  HouseholdService service,
  MemberDirectory members, {
  Future<Object?> Function(String hid)? afterJoin,
}) => ai.defineFlow(
  name: 'householdJoin',
  inputSchema: .nullable(.map(.string(), .string(maxLength: 200))),
  outputSchema: .map(.string(), .string()),
  fn: (input, ctx) async {
    final caller = CallerContext.of(ctx.context);
    final code = input?['code'];
    final displayName = input?['displayName'];
    if (code == null || displayName == null) {
      throw HouseholdFailure.invalidInput.toException();
    }
    final joined = await _guard(
      () => service.join(uid: caller.uid, code: code, displayName: displayName),
    );
    members.invalidate(caller.uid);
    if (afterJoin != null) {
      try {
        await afterJoin(joined.hid);
      } on Exception catch (e, st) {
        _log.warning('after-join visibility failed', e, st);
      }
    }
    return {'householdId': joined.hid, 'householdName': joined.name};
  },
);

/// Maps the module's refusals and backend failures to the Genkit errors the
/// phone gets.
Future<T> _guard<T>(Future<T> Function() work) async {
  try {
    return await work();
  } on HouseholdRejection catch (e) {
    _log.info('refused: ${e.failure.code}');
    throw e.failure.toException();
  } on GatewayUnavailable catch (e) {
    _log.warning('backend unavailable (${e.operation})', e.cause);
    throw HouseholdFailure.unavailable.toException();
  }
}
