// The Firestore and server adapter behind `HouseholdRepository`
// (DATA_MODEL 2.2, 2.3, 2.15; ARCHITECTURE 4.2). Only the composition root
// names this file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/auth_repository_firebase.dart'
    show parseEmulatorHost;
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Returns an App Check token for the server, or null when there is none.
typedef AppCheckTokenSource = Future<String?> Function();

/// [HouseholdRepository] over Firestore, Firebase Auth and the server's
/// `/v1/household/*` routes.
///
/// Membership follows `users/{uid}.householdId` and then
/// `households/{hid}`; the household counts only when its `memberIds` lists
/// the person, as in the rules.
final class FirebaseHouseholdRepository implements HouseholdRepository {
  /// Creates the adapter and starts following the signed-in person.
  ///
  /// `serverUrl` is the server's base address (`--dart-define=
  /// XPENSE_SERVER_URL`). Without one, or with one that is not an absolute
  /// http or https address, invites and joins fail as
  /// [HouseholdServiceUnavailable].
  new({
    required this._auth,
    required this._firestore,
    required this._appCheckToken,
    Uri? serverUrl,
    Clock? clock,
    Random? random,
  }) : _serverUrl = serverUrl != null && _isServerUrl(serverUrl)
           ? serverUrl
           : null,
       _clock = clock ?? const Clock(),
       _random = random ?? Random.secure() {
    _authSubscription = _auth.authStateChanges().listen(_onUser);
  }

  /// Wraps [FirebaseFirestore.instance], pointed at the Firestore emulator
  /// when [emulator] is `host:port`. Call after `Firebase.initializeApp()`.
  factory connect({
    required AppCheckTokenSource appCheckToken,
    Uri? serverUrl,
    String? emulator,
  }) {
    final firestore = FirebaseFirestore.instance;
    final target = parseEmulatorHost(emulator);
    if (target != null) {
      firestore.useFirestoreEmulator(target.host, target.port);
    }
    return FirebaseHouseholdRepository(
      auth: FirebaseAuth.instance,
      firestore: firestore,
      appCheckToken: appCheckToken,
      serverUrl: serverUrl,
    );
  }

  /// How long [create] waits for Firestore to confirm the batch before
  /// treating it as queued offline.
  static const Duration writeAckTimeout = Duration(seconds: 8);

  /// How long a server call may take.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// Default household time zone (DATA_MODEL 2.2).
  static const String defaultTimeZone = 'Asia/Baghdad';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AppCheckTokenSource _appCheckToken;
  final Uri? _serverUrl;
  final Clock _clock;
  final Random _random;

  // Cancelled in [dispose] and whenever the person or household changes.
  late final StreamSubscription<User?> _authSubscription;
  // ignore: cancel_subscriptions, cancelled in _stopUser (taken first).
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _householdSubscription;
  String? _uid;
  String? _watchedHid;
  String? _displayName;

  /// Whether the latest users/{uid} snapshot came from the server with no
  /// local writes waiting.
  bool _userSettled = false;

  /// Refusals of the household listener since its last snapshot.
  int _deniedRetries = 0;

  Membership _membership = const MembershipUnknown();
  final StreamController<Membership> _changes =
      StreamController<Membership>.broadcast();

  @override
  Membership get current => _membership;

  @override
  Stream<Membership> watchMembership() async* {
    yield _membership;
    yield* _changes.stream;
  }

  /// Stops following the signed-in person.
  Future<void> dispose() async {
    await _authSubscription.cancel();
    await _stopUser();
    await _changes.close();
  }

  // ------------------------------------------------------------ membership

  void _onUser(User? user) {
    final uid = user?.uid;
    if (uid == _uid) return;
    unawaited(_stopUser());
    _uid = uid;
    _set(const MembershipUnknown());
    if (uid == null) return;
    // Metadata changes too: the snapshot that says the founding batch
    // reached the server restarts a household listener the server refused
    // while the batch was still on its way.
    _userSubscription = _firestore
        .doc('users/$uid')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) => _onUserDocument(uid, snapshot),
          onError: (Object error, StackTrace stack) =>
              _onListenError(error, stack, 'users'),
        );
  }

  // Takes both subscriptions before the first await, so a listener started
  // right after this call is never the one cancelled.
  Future<void> _stopUser() {
    final user = _userSubscription;
    final household = _householdSubscription;
    _userSubscription = null;
    _householdSubscription = null;
    _watchedHid = null;
    _userSettled = false;
    return Future.wait<void>([?user?.cancel(), ?household?.cancel()]);
  }

  void _onUserDocument(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (uid != _uid) return;
    final metadata = snapshot.metadata;
    _userSettled = !metadata.isFromCache && !metadata.hasPendingWrites;
    final data = snapshot.data();
    final name = data?['displayName'];
    _displayName = name is String && name.isNotEmpty ? name : null;
    final hid = data?['householdId'];
    if (hid is! String || hid.isEmpty) {
      // A cached "nothing" may be stale (the server may have just added
      // the person); only the server's answer means no household.
      if (snapshot.metadata.isFromCache) return;
      _watchHousehold(uid, null);
      _set(const NoHousehold());
      return;
    }
    if (hid == _watchedHid) {
      if (_householdSubscription != null) {
        _refreshDisplayName();
        return;
      }
      // Refused before: try again only once the server has this pointer,
      // or a refusal would just repeat.
      if (!_userSettled) return;
    }
    _watchHousehold(uid, hid);
  }

  void _watchHousehold(String uid, String? hid) {
    unawaited(_householdSubscription?.cancel());
    _householdSubscription = null;
    if (hid != _watchedHid) _deniedRetries = 0;
    _watchedHid = hid;
    if (hid == null) return;
    _householdSubscription = _firestore
        .doc('households/$hid')
        .snapshots()
        .listen(
          (snapshot) => _onHousehold(uid, hid, snapshot),
          onError: (Object error, StackTrace stack) {
            // The rules refused the read. Either the household is still on
            // its way to the server (the founding batch shows locally
            // first), or the pointer is stale and the person is not a
            // member. The listener is dead; the users/{uid} snapshot that
            // confirms the batch restarts it. Only a refusal after the
            // server has confirmed the pointer means no household.
            _householdSubscription = null;
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              if (uid != _uid || hid != _watchedHid || !_userSettled) return;
              // The refusal may still be from before the batch landed: one
              // more try, then believe it.
              if (_deniedRetries++ == 0) {
                _watchHousehold(uid, hid);
              } else {
                _set(const NoHousehold());
              }
              return;
            }
            _onListenError(error, stack, 'households');
          },
        );
  }

  void _onHousehold(
    String uid,
    String hid,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (uid != _uid || hid != _watchedHid) return;
    // Only the server's answer proves the listener is allowed.
    if (!snapshot.metadata.isFromCache) _deniedRetries = 0;
    final data = snapshot.data();
    if (data == null) {
      if (snapshot.metadata.isFromCache) return;
      _set(const NoHousehold());
      return;
    }
    final memberIds = switch (data['memberIds']) {
      final List<Object?> ids => ids.whereType<String>().toList(),
      _ => const <String>[],
    };
    final currency = Currency.tryParse('${data['baseCurrency']}');
    final name = data['name'];
    if (!memberIds.contains(uid) || currency == null) {
      _set(const NoHousehold());
      return;
    }
    _set(
      InHousehold(
        HouseholdSummary(
          id: hid,
          name: name is String ? name : '',
          baseCurrency: currency,
          memberCount: memberIds.length,
          myDisplayName: _displayName,
        ),
      ),
    );
  }

  void _refreshDisplayName() {
    final membership = _membership;
    if (membership is! InHousehold) return;
    final h = membership.household;
    if (h.myDisplayName == _displayName) return;
    _set(
      InHousehold(
        HouseholdSummary(
          id: h.id,
          name: h.name,
          baseCurrency: h.baseCurrency,
          memberCount: h.memberCount,
          myDisplayName: _displayName,
        ),
      ),
    );
  }

  void _set(Membership membership) {
    if (membership == _membership) return;
    _membership = membership;
    if (!_changes.isClosed) _changes.add(membership);
  }

  void _onListenError(Object error, StackTrace stack, String what) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'household_repository',
          context: ErrorDescription('while listening to $what'),
        ),
      );

  // ---------------------------------------------------------------- create

  @override
  Future<Result<String, HouseholdFailure>> create({
    required String name,
    required String displayName,
    required Currency baseCurrency,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Err(HouseholdNotAllowed());
    final hid = uuidV7(_clock.now(), _random);
    final household = _firestore.collection('households').doc(hid);
    final now = FieldValue.serverTimestamp();
    final stamps = <String, Object?>{
      'createdAt': now,
      'createdBy': uid,
      'updatedAt': now,
      'updatedBy': uid,
      'schemaVersion': 1,
    };
    // One batch, checked by the rules as a whole (`isFoundingBatch`): the
    // household, its owner and the default categories, plus the pointer on
    // the person's own profile.
    final batch = _firestore.batch()
      ..set(household, {
        'name': name,
        'baseCurrency': baseCurrency.code,
        'timeZone': defaultTimeZone,
        'memberIds': [uid],
        'rateKind': 'market',
        'rateAskedOn': null,
        'cloudInsights': true,
        'weekStart': 'sat',
        'moneySchema': moneySchemaVersion,
        ...stamps,
      })
      ..set(household.collection('members').doc(uid), {
        'displayName': displayName,
        'initial': initialOf(displayName),
        'role': 'owner',
        'privacyMode': 'smart',
        'notificationPrefs': <String, Object?>{},
        'joinedAt': now,
        ...stamps,
      });
    for (final (index, category) in defaultCategories.indexed) {
      // System categories use their stable slug as the id, so seeding is
      // idempotent and the id reads well in rules and logs.
      batch.set(household.collection('categories').doc(category.slug), {
        'slug': category.slug,
        'names': category.names,
        'kind': category.kind.wire,
        'parentId': category.parentSlug,
        'colorKey': null,
        'iconKey': null,
        'order': index,
        'system': true,
        'archived': false,
        ...stamps,
      });
    }
    batch.set(_firestore.doc('users/$uid'), {
      'householdId': hid,
      'displayName': displayName,
      'locale': 'en',
    }, SetOptions(merge: true));

    final commit = batch.commit();
    try {
      await commit.timeout(writeAckTimeout);
    } on TimeoutException {
      // Offline: the batch waits on the phone and the household already
      // shows from the cache. A later refusal rolls it back there, and the
      // router sends the person to household setup again.
      unawaited(
        commit.then<void>(
          (_) {},
          onError: (Object e, StackTrace s) =>
              _onListenError(e, s, 'the household batch'),
        ),
      );
    } on FirebaseException catch (error, stack) {
      return Err(_firestoreFailure(error, stack));
    }
    return Ok(hid);
  }

  // --------------------------------------------------------- invite, join

  @override
  Future<Result<HouseholdInvite, HouseholdFailure>> createInvite() async {
    final result = await _post('household/invite', const {});
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final body) => switch (body) {
        {
          'code': final String code,
          'link': final String link,
          'expiresAt': final String expiresAt,
        }
            when DateTime.tryParse(expiresAt) != null =>
          Ok(
            HouseholdInvite(
              code: code,
              link: link,
              expiresAt: DateTime.parse(expiresAt),
            ),
          ),
        _ => const Err(HouseholdUnknown('bad_invite_response')),
      },
    };
  }

  @override
  Future<Result<JoinedHousehold, HouseholdFailure>> join({
    required String code,
    required String displayName,
  }) async {
    final result = await _post('household/join', {
      'code': code,
      'displayName': displayName,
    });
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final body) => switch (body) {
        {'householdId': final String id, 'householdName': final String name} =>
          Ok(JoinedHousehold(id: id, name: name)),
        _ => const Err(HouseholdUnknown('bad_join_response')),
      },
    };
  }

  /// Calls `POST /v1/<path>` with the ID token and App Check token, and
  /// returns the flow's `result`. An `invalid_id_token` refusal is retried
  /// once with a fresh token (server README, "Request contract").
  Future<Result<Map<String, Object?>, HouseholdFailure>> _post(
    String path,
    Map<String, String> data, {
    bool freshToken = false,
  }) async {
    final base = _serverUrl;
    if (base == null) return const Err(HouseholdServiceUnavailable());
    final user = _auth.currentUser;
    if (user == null) return const Err(HouseholdNotAllowed());

    final String? idToken;
    final String? appCheck;
    try {
      idToken = await user.getIdToken(freshToken);
      appCheck = await _appCheckToken();
    } on FirebaseException catch (error, stack) {
      return Err(_tokenFailure(error, stack));
    }
    if (idToken == null || appCheck == null || appCheck.isEmpty) {
      return const Err(HouseholdNotAllowed());
    }

    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final request = await client.postUrl(base.resolve('v1/$path'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
        ..set('x-firebase-appcheck', appCheck);
      request.write(jsonEncode({'data': data}));
      final response = await request.close().timeout(requestTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      final body = jsonDecode(text);
      if (response.statusCode == HttpStatus.ok) {
        return switch (body) {
          {'result': final Map<String, Object?> result} => Ok(result),
          _ => const Err(HouseholdUnknown('bad_response')),
        };
      }
      final message = switch (body) {
        {'message': final String message} => message,
        _ => 'http_${response.statusCode}',
      };
      if (message == 'invalid_id_token' && !freshToken) {
        return await _post(path, data, freshToken: true);
      }
      return Err(householdFailureFromServerCode(message));
    } on SocketException {
      return const Err(HouseholdOffline());
    } on TimeoutException {
      return const Err(HouseholdOffline());
    } on HandshakeException {
      return const Err(HouseholdOffline());
    } on HttpException {
      return const Err(HouseholdOffline());
    } on FormatException catch (error, stack) {
      _report(error, stack, 'reading the server answer');
      return const Err(HouseholdUnknown('bad_response'));
    } finally {
      client.close(force: true);
    }
  }

  static HouseholdFailure _firestoreFailure(
    FirebaseException error,
    StackTrace stack,
  ) => switch (error.code) {
    'unavailable' => const HouseholdOffline(),
    'permission-denied' || 'unauthenticated' => () {
      // The founding batch broke a rule: a bug, never the person's fault.
      _report(error, stack, 'writing the household');
      return const HouseholdNotAllowed();
    }(),
    _ => () {
      _report(error, stack, 'writing the household');
      return HouseholdUnknown(error.code);
    }(),
  };

  static HouseholdFailure _tokenFailure(
    FirebaseException error,
    StackTrace stack,
  ) {
    if (error.code == 'network-request-failed') return const HouseholdOffline();
    _report(error, stack, 'getting tokens for the server');
    return const HouseholdNotAllowed();
  }

  static void _report(Object error, StackTrace stack, String what) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'household_repository',
          context: ErrorDescription('while $what'),
        ),
      );
}

/// The server address in [raw] (an `XPENSE_SERVER_URL` define), or null when
/// it is unset, relative, or not http or https. `Uri.tryParse('')` gives an
/// empty, relative URI rather than null, which `HttpClient` refuses with an
/// error instead of a failure the screen can show (PR #29 review).
Uri? usableServerUrl(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  return uri != null && _isServerUrl(uri) ? uri : null;
}

bool _isServerUrl(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;

/// The first character of [name], upper-cased: the avatar letter.
String initialOf(String name) =>
    name.isEmpty ? '' : String.fromCharCode(name.runes.first).toUpperCase();

/// A UUID version 7 (RFC 9562): 48 bits of Unix milliseconds from [now],
/// then random bits from [random]. Client-generated ids sort by time and
/// make offline creates idempotent (DATA_MODEL 2).
String uuidV7(DateTime now, Random random) {
  final ms = now.millisecondsSinceEpoch;
  final bytes = [
    for (var i = 5; i >= 0; i--) (ms >> (8 * i)) & 0xff,
    for (var i = 0; i < 10; i++) random.nextInt(256),
  ];
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
