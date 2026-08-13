/// Decides when a code in front of the camera is a NEW presentation rather than the same one.
///
/// **A timer cannot answer this and that is what shipped first.** `mobile_scanner`'s
/// `detectionTimeoutMs` suppresses a repeat for a fixed period, so a label held steady in front of
/// the lens produces one read per period: Anılcan scanned one carton and the row said two. On a
/// screen whose camera never closes, "held for three seconds" is the ORDINARY case, so any timer
/// long enough to stop it is also long enough to swallow a real second carton.
///
/// So this counts EDGES. A code is a new presentation when it was absent from the frame for long
/// enough beforehand; while it stays in view it is the same carton however long it is held. That is
/// the distinction the user actually makes with their hands, and it is the one a timer erases.
///
/// [reentryGap] exists because decoding is not continuous: a hand moving over the label, a glare, a
/// focus hunt all drop the code out of a frame or two. Without a grace period that flicker reads as
/// the label leaving and returning, which is the same double-count arriving by the other road.
class ScanPresence {
  ScanPresence({this.reentryGap = const Duration(milliseconds: 800)});

  /// How long a code has to be out of frame before it counts again.
  ///
  /// 800ms sits between the two things it has to separate, both measured in hand rather than in
  /// software: a decode dropout is a few frames, and swapping one carton for the next takes over a
  /// second. Shorter and a glare double-counts; much longer and a genuine second carton is lost.
  final Duration reentryGap;

  /// When each code was last seen in a frame.
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  /// Whether this read should count, recording the sighting either way.
  ///
  /// Called for every capture the camera produces, including the ones that change nothing: the
  /// sighting has to be recorded even when it does not count, or a code held in view would look
  /// absent as soon as its own gap elapsed.
  bool shouldCount(String code, DateTime now) {
    final DateTime? seen = _lastSeen[code];

    _lastSeen[code] = now;

    if (seen == null) {
      return true;
    }

    return now.difference(seen) >= reentryGap;
  }

  /// Forgets codes not seen for longer than the gap, so a long session does not accumulate every
  /// label it ever saw.
  ///
  /// **Longer than the gap, and it used to be ten times it while this comment claimed the gap.** The
  /// two are behaviourally identical: once a code has been absent for the gap, keeping its entry
  /// answers "count it" and dropping it answers "count it", because an unseen code counts. So the
  /// 10x bought nothing and cost the reader a discrepancy to reconcile.
  void prune(DateTime now) {
    _lastSeen.removeWhere(
      (String _, DateTime seen) => now.difference(seen) > reentryGap,
    );
  }

  /// How many codes are being tracked, for the pruning test to be able to see anything at all.
  int get trackedCount => _lastSeen.length;
}
