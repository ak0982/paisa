/// On-demand lookup of the original bank SMS behind a stored transaction.
///
/// Bodies are deliberately **not** persisted with the transaction — the scan
/// keeps only the parsed result. The coin reverse fetches the message from the
/// inbox by `Transaction.smsId` when the user asks for it, so a deleted SMS or
/// a revoked permission is a normal, expected outcome rather than an error.
library;

/// Why the reverse of the coin has (or has not) an SMS to show.
enum OriginalSmsStatus {
  /// The inbox row was found and [OriginalSmsLookup.sms] is populated.
  loaded,

  /// The transaction carries no `smsId` (manual / legacy row).
  noSmsId,

  /// The id is known but the message is gone from the inbox.
  notFound,

  /// SMS permission is not granted, so the inbox cannot be read.
  noPermission,

  /// Inbox access is Android-only.
  unsupportedPlatform,

  /// The inbox row was found but carries no text (empty / whitespace body),
  /// so there is nothing to strike onto the reverse.
  emptyBody,

  /// The read itself failed — channel error, unexpected payload shape, or any
  /// other throw on the way to the inbox.
  lookupFailed,
}

/// One inbox message: sender, full body and receive time.
class OriginalSms {
  const OriginalSms({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
}

/// Result of an [OriginalSmsLoader] call.
class OriginalSmsLookup {
  const OriginalSmsLookup._(this.status, this.sms);

  const OriginalSmsLookup.loaded(OriginalSms message)
      : this._(OriginalSmsStatus.loaded, message);

  const OriginalSmsLookup.miss(OriginalSmsStatus status)
      : this._(status, null);

  final OriginalSmsStatus status;
  final OriginalSms? sms;

  bool get hasBody => sms != null && sms!.body.trim().isNotEmpty;

  /// Status to draw the reverse from. A [OriginalSmsStatus.loaded] row whose
  /// body is blank has no text to show, so it reads as
  /// [OriginalSmsStatus.emptyBody] instead of falling through to blank copy.
  OriginalSmsStatus get displayStatus =>
      status == OriginalSmsStatus.loaded && !hasBody
          ? OriginalSmsStatus.emptyBody
          : status;
}

/// Fetches the inbox message for a transaction's `smsId`.
typedef OriginalSmsLoader = Future<OriginalSmsLookup> Function(String smsId);

/// Reverse-side copy for every non-loaded state, so the coin never shows a
/// blank field or a raw platform error.
({String title, String body}) originalSmsEmptyCopy(OriginalSmsStatus status) {
  return switch (status) {
    OriginalSmsStatus.loaded => (title: '', body: ''),
    OriginalSmsStatus.noSmsId => (
        title: 'Minted by you',
        body: 'This move was added manually — there is no bank alert on the '
            'reverse of the coin.',
      ),
    OriginalSmsStatus.notFound => (
        title: 'Alert no longer in the inbox',
        body: 'The original message was deleted from this phone. Paisa keeps '
            'only the parsed transaction — never the text.',
      ),
    OriginalSmsStatus.noPermission => (
        title: 'SMS access is off',
        body: 'Grant SMS permission to read the original bank alert here.',
      ),
    OriginalSmsStatus.unsupportedPlatform => (
        title: 'Inbox unavailable',
        body: 'Original bank alerts can only be read on Android.',
      ),
    OriginalSmsStatus.emptyBody => (
        title: 'Alert has no text',
        body: 'The linked message is still in the inbox but carries no body, '
            'so there is nothing to strike here.',
      ),
    OriginalSmsStatus.lookupFailed => (
        title: 'Could not read the inbox',
        body: 'Something went wrong fetching the original alert. Close the '
            'coin and open it again.',
      ),
  };
}
