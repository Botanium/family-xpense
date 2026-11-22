/// Names shared by the local surface builder and the phone's surface host
/// (A2UI_CATALOG 5 and 6, ARCHITECTURE 7).
library;

/// Every surface the phone builds has an id starting with this prefix, so an
/// agent surface can never replace one by accident (WP-S1 Q4).
const String localSurfacePrefix = 'loc_';

/// Actions whose name starts with this prefix are handled on the phone and
/// never become agent turns.
const String localActionPrefix = 'xp.local.';

/// The name an agent's dummy action carries (the `a2ui()` contract tells the
/// model to supply `Event("click")` for required actions). The phone drops
/// it (A2UI_CATALOG 3.2, optional actions).
const String dummyActionName = 'click';

/// Surface and component ids: identifiers with underscores, never hyphens
/// (A2UI_CATALOG 2 rule 7).
final RegExp surfaceIdPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Whether [surfaceId] names a surface the phone built.
bool isLocalSurfaceId(String surfaceId) =>
    surfaceId.startsWith(localSurfacePrefix);

/// Whether an action named [name] is handled on the phone.
bool isLocalActionName(String name) => name.startsWith(localActionPrefix);

/// Data-model paths of a surface (A2UI_CATALOG 6).
abstract final class SurfacePaths {
  /// The drafts an `EntryList` or `ReceiptSummary` edits.
  static const String drafts = '/drafts';

  /// The receipt a `ReceiptSummary` shows.
  static const String receipt = '/receipt';

  /// The "Split by category" switch.
  static const String split = '/ui/split';

  /// The phone's own save state: `review` or `saved`. The agent's `status`
  /// prop is set once; after a save the phone keeps its state here.
  static const String status = '/ui/status';

  /// What a save produced: `{groupId, txnIds, savedAt}`.
  static const String saved = '/ui/saved';
}

/// Actions the local builder puts on `Button`, `Nudge` and `Notice`, without
/// the [localActionPrefix]. Each maps to one `XpenseActions` call on the
/// phone (A2UI_CATALOG 5.1).
abstract final class LocalActionNames {
  /// Opens the manual entry form, prefilled from the context's `draft`.
  static const String openManualForm = 'openManualForm';

  /// Opens a saved transaction (`txnId`).
  static const String openTransaction = 'openTransaction';

  /// Opens a loan (`loanId`).
  static const String openLoan = 'openLoan';

  /// Opens a goal (`goalId`).
  static const String openGoal = 'openGoal';

  /// Starts a capture with the context's `message`.
  static const String sendText = 'sendText';

  /// Reopens the camera.
  static const String retakeReceipt = 'retakeReceipt';

  /// Retries a queued capture (`captureId`).
  static const String retryQueued = 'retryQueued';

  /// Every name above.
  static const List<String> all = [
    openManualForm,
    openTransaction,
    openLoan,
    openGoal,
    sendText,
    retakeReceipt,
    retryQueued,
  ];
}
