// WP-S1 spike (throwaway). A SessionStore that keeps agent sessions under
// households/{hid}/agentSessions by holding one FirestoreSessionStore per
// household. FirestoreSessionStore takes one fixed collection path, so the
// household cannot come from the per-tenant prefix (which may not contain
// '/'); it has to choose the store instance.
// ignore_for_file: experimental_member_use
import 'package:genkit/experimental.dart';
import 'package:genkit_google_cloud/firestore_session_store.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

class HouseholdSessionStore implements SessionStore {
  HouseholdSessionStore(this.db);

  final Firestore db;
  final _stores = <String, FirestoreSessionStore>{};

  FirestoreSessionStore _forContext(Map<String, dynamic>? context) {
    final hid = context?['hid'];
    if (hid is! String || hid.isEmpty || hid.contains('/')) {
      throw StateError('HouseholdSessionStore: missing or invalid hid');
    }
    return _stores.putIfAbsent(
      hid,
      () => FirestoreSessionStore(
        db: db,
        collection: 'households/$hid/agentSessions',
        // The member still scopes the documents inside the household.
        snapshotPathPrefix: (ctx) => '${ctx?['uid']}',
      ),
    );
  }

  @override
  Future<SessionSnapshot?> getSnapshot({
    String? snapshotId,
    String? sessionId,
    Map<String, dynamic>? context,
  }) => _forContext(
    context,
  ).getSnapshot(snapshotId: snapshotId, sessionId: sessionId, context: context);

  @override
  Future<String?> saveSnapshot(
    String? snapshotId,
    SnapshotMutator mutator, {
    Map<String, dynamic>? context,
  }) =>
      _forContext(context).saveSnapshot(snapshotId, mutator, context: context);
}
