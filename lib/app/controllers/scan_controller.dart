import 'package:magic/magic.dart';

import '../../ui/components/scan_row/scan_row.dart';
import '../models/scan_entry.dart';

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

  /// The batch as the view reads it.
  List<ScanEntry> get entries => List<ScanEntry>.unmodifiable(_entries);

  /// Whether anything has been scanned yet.
  bool get hasScans => _entries.isNotEmpty;

  /// How many rows still need the user before the batch can be written.
  int get unmatchedCount => _entries.where((ScanEntry e) => !e.isSettled).length;

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

    // **No in-flight flag, and the review was right that the one here was broken.** It could be
    // cleared by whichever resolve finished first while another was still running, and a throw
    // would have left it stuck on. What made it harmless is worse than the bug: nothing read it.
    // So it is gone rather than fixed, which is also what removes the defect.
    final ScanEntry entry = await _resolve(code, symbology, sequence);

    _entries.add(entry);
    _sort();
    _publish();
  }

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

    return ScanEntry(
      barcode: code,
      symbology: symbology,
      count: 1,
      sequence: sequence,
      productName: name,
      source: ScanEntry.sourceOf(data['source'] as String?),
      productId: productId is String ? productId : null,
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
