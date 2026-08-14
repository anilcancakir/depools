import 'package:magic/magic.dart';

import '../models/scan_entry.dart';
import '../models/scan_source.dart';

/// The batch a scanning session accumulates, and the cascade call behind each row.
///
/// Follows `ProductController`'s shape: a [MagicController] resolved through [Magic.findOrPut],
/// [MagicStateMixin] carrying the states, and every request through the [Http] facade so the base
/// URL, the Sanctum bearer and the telescope interceptor come for free.
///
/// ### The queue is the screen, so a resolve failure must not blank it
///
/// The other controllers set an error state when a request fails, which blanks the list they own.
/// That is right for a list whose only content came from the request. Here the list is a batch the
/// user built with their own hands, one carton at a time, and losing it because the twelfth lookup
/// timed out would throw away their work over a row. So a failed resolve becomes an `unmatched` row
/// and the batch survives: `unmatched` already means "this needs you", which is exactly true.
///
/// ### A repeat scan is a second unit, not a duplicate
///
/// Scanning the same carton twice means two cartons, which is the whole reason a receiving bench
/// scans at all. The row's count increments and the row moves to the front, because a row that
/// incremented out of sight gives no feedback for a scan that worked (D40).
class ScanController extends MagicController with MagicStateMixin<List<ScanEntry>> {
  /// The shared instance, keyed by type.
  static ScanController get instance => Magic.findOrPut(ScanController.new);

  /// The batch, most recently scanned first.
  final List<ScanEntry> _entries = <ScanEntry>[];

  /// Increments once per read, so a row's place is decided by when it was SCANNED.
  int _sequence = 0;

  /// Which batch is being built. Bumped by [clear].
  ///
  /// **A lookup started before a clear must not land after it.** The user emptying the queue is
  /// saying the batch is done or abandoned; a stage-3 answer arriving half a second later would drop
  /// a row nobody scanned into the fresh batch. Found by mutation-testing `clear`, which stayed
  /// green because no test had a resolve in flight when it ran.
  int _generation = 0;

  /// The batch as the view reads it.
  List<ScanEntry> get entries => List<ScanEntry>.unmodifiable(_entries);

  /// Whether anything has been scanned yet.
  bool get hasScans => _entries.isNotEmpty;

  /// How many rows still need the user before the batch can be written.
  ///
  /// **Not `!isSettled`, because a pending row is neither.** That reading counted every lookup still
  /// in flight as a barcode that could not be matched, so the line above the button accused the
  /// cascade of failing at a question it had not finished answering.
  int get unmatchedCount => _entries.where((ScanEntry e) => e.needsUser).length;

  /// How many units the batch holds, across every row.
  int get totalUnits => _entries.fold(0, (int sum, ScanEntry e) => sum + e.count);

  /// Reads one barcode into the batch.
  ///
  /// **The repeat check happens BEFORE the request, not after it.** A second read of a carton
  /// already in the batch needs no lookup: the answer is on screen. Asking again would spend a
  /// round trip, and on the stage-3 path a real HTTP call to somebody else's server, to be told
  /// what we already know.
  Future<void> scan(String rawCode, {String? symbology}) async {
    final String code = rawCode.trim();

    if (code.isEmpty) {
      return;
    }

    final int existing = _entries.indexWhere(
      (ScanEntry e) => e.barcode == code && e.symbology == symbology,
    );

    // The read's place in the queue is decided HERE, before the lookup, because a lookup's
    // duration is not a fact about when the user scanned.
    final int sequence = ++_sequence;

    if (existing >= 0) {
      _entries[existing] = _entries[existing].incremented(sequence: sequence);
      _sort();
      _publish();

      return;
    }

    // **The row goes in before the question goes out**, so a read is on screen in the same frame the
    // user scanned it rather than whenever the slowest stage of the cascade answers.
    //
    // This also DELETED a mechanism. The class used to bank repeat reads in a side map, for the
    // reason its own comment gave: "the row does not exist during its own lookup, so there is
    // nothing to increment". Now it does exist, so the plain repeat branch above catches a second
    // read and the map has nothing left to do. Two scans of one code cannot both miss the branch,
    // because everything up to the first `await` here runs in one turn of the event loop.
    _entries.add(
      ScanEntry(
        barcode: code,
        symbology: symbology,
        count: 1,
        sequence: sequence,
        pending: true,
      ),
    );
    _sort();
    _publish();

    final int generation = _generation;

    // `finally` rather than a catch, so nothing is swallowed: a throw from the network layer must
    // still take the row out of its pending state, or it sits there as a question that will never be
    // answered and cannot be committed either.
    try {
      final ScanEntry resolved = await _resolve(code, symbology, sequence);

      // The batch this read belongs to is gone.
      if (generation != _generation) {
        return;
      }

      _replacePending(code, symbology, resolved);
    } finally {
      if (generation == _generation) {
        _settleAbandoned(code, symbology);
      }
    }
  }

  /// Puts the cascade's answer onto the row that was holding the place for it.
  ///
  /// **A row that is no longer pending is left alone, and that is not defensive coding.** The user can
  /// open the card and answer it while the lookup is still out, and when the answer then lands it
  /// would overwrite what they typed with what a catalogue guessed. The person holding the carton
  /// outranks the cascade.
  ///
  /// The count and the queue position come from the ROW rather than from the answer, because both are
  /// facts about scanning that accumulated while the question was out.
  void _replacePending(String code, String? symbology, ScanEntry resolved) {
    final int at = _indexOf(code, symbology);

    if (at < 0) {
      return;
    }

    final ScanEntry row = _entries[at];

    if (!row.pending) {
      return;
    }

    _entries[at] = resolved.copyWith(count: row.count, sequence: row.sequence);
    _sort();
    _publish();
  }

  /// Turns a row whose lookup never came back into one the user can finish.
  ///
  /// Only reachable when [_resolve] threw, since a failed response already resolves to an unmatched
  /// row. `unmatched` is the honest landing place either way: the batch survives, and the row says it
  /// needs somebody, which is exactly true.
  void _settleAbandoned(String code, String? symbology) {
    final int at = _indexOf(code, symbology);

    if (at < 0 || !_entries[at].pending) {
      return;
    }

    _entries[at] = _entries[at].copyWith(pending: false, source: ScanSource.unmatched);
    _publish();
  }

  /// Where a code sits in the batch, or -1.
  int _indexOf(String code, String? symbology) => _entries.indexWhere(
    (ScanEntry e) => e.barcode == code && e.symbology == symbology,
  );

  /// Newest scan first, by sequence.
  ///
  /// **Sorted rather than inserted at the front, because arrival order is not scan order.** A local
  /// hit answers in about five milliseconds and an OFF lookup in five hundred, so inserting on
  /// arrival put the older scan above the newer one and the user watched a row jump to the top for a
  /// carton two cartons ago.
  ///
  /// Not done, and named so it does not read as an oversight: the row still APPEARS only when its
  /// answer lands, so a stage-3 read shows nothing for half a second. Fixing that means a pending
  /// state on `ScanRow`, which is component work with its own preview and visual review rather than
  /// a line here.
  void _sort() {
    _entries.sort((ScanEntry a, ScanEntry b) => b.sequence.compareTo(a.sequence));
  }

  /// Where the batch will land, and how it was chosen.
  ///
  /// Null until [loadDestination] has answered, and null AFTER it when this tenant has never
  /// received anything: a first delivery is the ordinary case, so the screen asks for a location
  /// rather than showing an error.
  String? _destinationId;

  String? get destinationId => _destinationId;

  /// The recent destinations, newest first, for the picker's top section.
  List<String> _recentDestinationIds = const <String>[];

  List<String> get recentDestinationIds => _recentDestinationIds;

  /// Whether a commit is in flight, so the button cannot be pressed twice.
  ///
  /// **Read, unlike the flag this class carried before.** That one existed for a spinner nobody
  /// built and was deleted in review; this one guards a write, and a second press would append the
  /// whole batch to the ledger again.
  bool _committing = false;

  bool get isCommitting => _committing;

  /// Asks where the last delivery was put away.
  ///
  /// Habit rather than category affinity, which is the departure the screen's own docblock records:
  /// a mixed batch cannot ask "where does this category go", and where the last delivery landed is a
  /// fact about how the business works.
  Future<void> loadDestination() async {
    final dynamic response = await Http.get('/stock/recent-receiving-locations');

    if (!response.successful) {
      return;
    }

    final dynamic data = response['data'];

    if (data is! Map) return;

    final dynamic ids = data['location_ids'];

    if (ids is! List) return;

    _recentDestinationIds = <String>[
      for (final dynamic id in ids)
        if (id is String) id,
    ];
    // **The first recent IS the default, rather than a second answer that could disagree with it.**
    // Only when nothing is chosen yet: re-loading must not move a destination the user picked.
    _destinationId ??= _recentDestinationIds.isEmpty ? null : _recentDestinationIds.first;
    notifyListeners();
  }

  /// Chooses where the batch will land.
  void chooseDestination(String locationId) {
    _destinationId = locationId;
    notifyListeners();
  }

  /// Writes every settled row into the destination, or returns the server's refusal.
  ///
  /// **One request for the whole batch**, because the endpoint is one request: a dropped connection
  /// halfway down a pile of boxes would otherwise leave some stock written and no way for the user
  /// to tell which without re-counting the pile they just put away.
  ///
  /// Unmatched rows are left behind rather than sent. They have no product and no name, so there is
  /// nothing to create; the count above the button already says how many are waiting, and the batch
  /// survives the commit so the user can finish them.
  Future<String?> commit() async {
    if (_committing) {
      return null;
    }

    final String? destination = _destinationId;

    if (destination == null) {
      return Lang.get('screens.scan.choose_destination');
    }

    final List<ScanEntry> settled = _entries.where((ScanEntry e) => e.isSettled).toList();

    if (settled.isEmpty) {
      return Lang.get('screens.scan.nothing_to_write');
    }

    // **What was posted, keyed and counted, because the batch keeps moving while the request is out.**
    // Sweeping `isSettled` on the way back removed whatever happened to be settled by THEN, which is
    // not the same set: a row still being looked up when the button was pressed becomes settled when
    // its answer lands mid-request, and left with the others it would be deleted without ever having
    // been written. The count is here for the narrower half of the same problem, a repeat read landing
    // during the request, where the row was written N times and now says N+1.
    final Map<String, int> posted = <String, int>{
      for (final ScanEntry entry in settled) entry.key: entry.count,
    };

    _committing = true;
    notifyListeners();

    try {
      final dynamic response = await Http.post(
        '/stock/receive-batch',
        data: <String, dynamic>{
          'location_id': destination,
          'lines': settled.map(_lineOf).toList(),
        },
      );

      if (!response.successful) {
        // The server's own sentence, because it names the reason: a barcode already in use, a
        // serial-tracked product, a location that vanished. Replacing it with a generic line throws
        // away the only useful part of a refusal.
        final dynamic message = response['message'];

        return message is String && message.isNotEmpty
            ? message
            : Lang.get('screens.scan.write_failed');
      }

      // **Only what was written leaves the batch, and only as much of it as was written.** An
      // unmatched row still needs the user, and clearing everything would silently discard the work
      // of finding it. A row scanned again while the request was out keeps the difference, so the
      // carton that arrived too late to be in this batch is still in the next one.
      _entries.removeWhere((ScanEntry e) => (posted[e.key] ?? 0) >= e.count);

      for (int i = 0; i < _entries.length; i++) {
        final int sent = posted[_entries[i].key] ?? 0;

        if (sent > 0) {
          _entries[i] = _entries[i].copyWith(count: _entries[i].count - sent);
        }
      }

      _publish();

      return null;
    } finally {
      _committing = false;
      notifyListeners();
    }
  }

  /// One batch line: an id when the tenant owns the product, the card to create when they do not.
  ///
  /// A catalogue hit has no `productId`, which is not a gap in the answer: it means the cascade
  /// said what the thing IS and this tenant has never held one. `barcode-and-catalog.md` says such a
  /// row is written as it stands, so the line carries what the endpoint needs to create it.
  Map<String, dynamic> _lineOf(ScanEntry entry) {
    if (entry.productId != null) {
      return <String, dynamic>{
        'product_id': entry.productId,
        'quantity': entry.count,
      };
    }

    return <String, dynamic>{
      'name': entry.productName,
      'quantity': entry.count,
      'barcode': entry.barcode,
      if (entry.symbology != null) 'symbology': entry.symbology,
      if (entry.brand != null) 'brand': entry.brand,
      // Only when the row's unit was actually chosen. Sending the model's default would make a
      // catalogue row claim a unit the catalogue never carried, and `base_unit` is the one field
      // D54 says stops being freely editable the moment a movement exists.
      if (entry.brand != null || entry.unit != ScanEntry.defaultUnit) 'base_unit': entry.unit,
      'contribute': entry.contribute,
    };
  }

  /// Replaces a row with what the draft sheet returned.
  ///
  /// Keyed on `(barcode, symbology)` rather than on an index, because the queue re-sorts while the
  /// sheet is open: a scan landing behind it moves every row, and an index captured before would
  /// write the draft onto somebody else's carton.
  void fill(
    String barcode, {
    String? symbology,
    required String name,
    required String unit,
    String? brand,
    bool contribute = true,
  }) {
    final int at = _entries.indexWhere(
      (ScanEntry e) => e.barcode == barcode && e.symbology == symbology,
    );

    if (at < 0) return;

    _entries[at] = _entries[at].filled(
      name: name,
      unit: unit,
      brand: brand,
      contribute: contribute,
    );
    _publish();
  }

  /// Records that the user has seen this row's card, without changing what it says.
  ///
  /// **The cancel path, and it has to record something or the sheet reopens per carton.** Somebody who
  /// looks at a catalogue find and closes it has answered the question that was asked: the row keeps
  /// whatever the cascade said and will be written as it stands. Asking again on the next read of the
  /// same box would be the modal-per-scan the feature document rejects.
  void markAsked(String barcode, {String? symbology}) {
    final int at = _indexOf(barcode, symbology);

    if (at < 0 || _entries[at].asked) {
      return;
    }

    _entries[at] = _entries[at].copyWith(asked: true);
    _publish();
  }

  /// Removes a row from the batch.
  void remove(String barcode, {String? symbology}) {
    _entries.removeWhere(
      (ScanEntry e) => e.barcode == barcode && e.symbology == symbology,
    );
    _publish();
  }

  /// Empties the batch, after it has been written or abandoned.
  void clear() {
    _entries.clear();
    // A lookup already in flight belongs to the batch that is going away, so its answer is dropped
    // rather than appended to the fresh batch. This also covers the pending ROW it was holding: the
    // row went with `_entries`, and the generation check is what stops the late answer from landing
    // on a same-code row somebody scans into the next batch.
    _generation++;
    _publish();
  }

  /// Asks the cascade what a code is.
  ///
  /// A 404 is stage 6 and an ordinary answer, so it produces an `unmatched` row rather than an
  /// error. A 422 means the code cannot be identified at all, which for a scanner read means a
  /// non-GTIN label arrived with no symbology; that is also a row the user has to finish, so it
  /// lands in the same place rather than as a message about a field they never filled in.
  Future<ScanEntry> _resolve(String code, String? symbology, int sequence) async {
    final ScanEntry unmatched = ScanEntry(
      barcode: code,
      symbology: symbology,
      count: 1,
      sequence: sequence,
      source: ScanSource.unmatched,
    );

    // The query goes in the path, as every other controller here builds it: `Http.get` takes one
    // string, and a second way of passing parameters would be a second convention.
    final String query = <String>[
      'code=${Uri.encodeQueryComponent(code)}',
      if (symbology != null && symbology.isNotEmpty)
        'symbology=${Uri.encodeQueryComponent(symbology)}',
    ].join('&');

    final dynamic response = await Http.get('/barcode/resolve?$query');

    if (!response.successful) {
      return unmatched;
    }

    final dynamic data = response['data'];

    if (data is! Map) {
      return unmatched;
    }

    final dynamic name = data['name'];

    // A candidate with no name cannot be shown as resolved, and rendering an empty row as settled
    // would commit a nameless product to stock.
    if (name is! String || name.trim().isEmpty) {
      return unmatched;
    }

    final dynamic productId = data['product_id'];
    final dynamic brand = data['brand'];
    final dynamic unitHint = data['unit_hint'];

    return ScanEntry(
      barcode: code,
      symbology: symbology,
      count: 1,
      sequence: sequence,
      productName: name,
      source: ScanEntry.sourceOf(data['source'] as String?),
      productId: productId is String ? productId : null,
      // **Carried, and it was being dropped.** `ProductCandidate` has sent a brand since the endpoint
      // was written, and the confirm card renders a Brand field, so a find whose brand the catalogue
      // knew presented as one that had none: the user either retypes what we already had or the
      // product is created without it. Found by driving the screen, not by reading it.
      brand: brand is String && brand.trim().isNotEmpty ? brand : null,
      // **Only where a source actually suggested one**, which in practice is stage 1: the shared
      // catalogue deliberately holds no unit column, because what a product is COUNTED in is the
      // tenant's decision and a shop counting cartons and a cafe counting litres are both right about
      // the same milk. Dropping it made a row for the tenant's OWN product print the model's default
      // instead of the unit that product is actually kept in.
      unit: unitHint is String && unitHint.trim().isNotEmpty
          ? unitHint
          : ScanEntry.defaultUnit,
    );
  }

  void _publish() {
    if (_entries.isEmpty) {
      // The empty state is the one every session starts in, so it is a state rather than an
      // absence: the view renders a live viewfinder and an invitation, not a spinner.
      setEmpty();

      return;
    }

    setSuccess(entries);
  }
}
