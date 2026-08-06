import 'package:flutter/foundation.dart';

import '../../../ui/components/movement_row/movement_row.dart';

/// Whether an entry can be reversed, and if not, why not.
enum UndoState {
  /// The compensating movement is valid right now, so undo is offered.
  available,

  /// A later correction already reversed this entry.
  reversed,

  /// This entry IS the correction that reversed another one. Undoing an undo is a
  /// third movement nobody asked for; the user re-records instead.
  correction,

  /// The compensating movement would break an invariant. The row states the blocking
  /// fact instead of offering a button that fails.
  blocked,
}

/// One entry in the activity feed.
///
/// **The product leads and the reason moves into the meta**, which is the opposite of the
/// same row on a product's own history page. The rule behind both is one rule: the primary
/// line carries whatever distinguishes this row from its neighbours. On a product page every
/// row shares the product, so the reason distinguishes them; in a feed across every product,
/// twelve rows reading "Satın alma" distinguish nothing.
///
/// It is also what stopped the meta truncating. With the product, the location, the source
/// AND an undo button on one line, the source fell off the end, and the source is exactly
/// what criterion 4 requires a feed entry to carry.
@immutable
class ActivityFixture {
  /// The product name, which leads the row here.
  final String product;

  /// The already-localised reason label, which moves into the meta line.
  final String reason;

  /// The raw signed delta.
  final num deltaAmount;

  /// The already-signed, already-formatted delta.
  final String delta;

  /// The unit.
  final String unit;

  /// Reason, location and source, already composed.
  final String meta;

  /// Which way it pushed stock.
  final MovementDirection direction;

  /// Whether it can be reversed.
  final UndoState undo;

  /// The already-localised blocking fact or reversal pointer.
  final String? note;

  /// Whether the write happened without asking, under full automation.
  final bool isAutomatic;

  /// Creates an [ActivityFixture].
  const ActivityFixture({
    required this.product,
    required this.reason,
    required this.deltaAmount,
    required this.delta,
    required this.meta,
    required this.direction,
    this.unit = 'adet',
    this.undo = UndoState.available,
    this.note,
    this.isAutomatic = false,
  });
}

/// One day's entries, newest day first.
@immutable
class ActivityDay {
  /// The already-localised day label.
  final String label;

  /// The entries, newest first.
  final List<ActivityFixture> entries;

  /// Creates an [ActivityDay].
  const ActivityDay({required this.label, required this.entries});
}

/// Two days of writes across every product, which is what the panel is for.
///
/// **The reversal pair is deliberately visible as two rows.** The correction sits above
/// the entry it reversed (newest first) and the original stays in place, struck through.
/// That is D51: the ledger is append-only, both movements exist, and `forecasting.md`
/// asks for balances that reconcile against the visible history by hand. A feed that
/// collapsed the pair would hide half its own arithmetic.
///
/// **Two entries are automatic.** Those are the panel's reason to exist: under full
/// automation the assistant writes without asking, and this is the one place a user can
/// see what happened while they were not looking.
///
/// One entry is blocked, because an undo is not always possible and the interesting
/// design question is what the row says when it is not.
const List<ActivityDay> activityDays = <ActivityDay>[
  ActivityDay(
    label: 'Bugün',
    entries: <ActivityFixture>[
      // The correction, above the entry it reverses. Its own undo is not offered:
      // undoing an undo is a third movement nobody asked for.
      ActivityFixture(
        product: 'Ayçiçek Yağı 5 lt',
        reason: 'Geri alma',
        deltaAmount: -2,
        delta: '-2',
        meta: 'Geri alma · Kiler › Raf 2 · elle',
        direction: MovementDirection.correction,
        undo: UndoState.correction,
        note: 'Aşağıdaki satın alma kaydını geri alır',
      ),
      ActivityFixture(
        product: 'Ayçiçek Yağı 5 lt',
        reason: 'Satın alma',
        deltaAmount: 2,
        delta: '+2',
        meta: 'Satın alma · Kiler › Raf 2 · fiş',
        direction: MovementDirection.inbound,
        undo: UndoState.reversed,
        note: 'Geri alındı',
      ),
      ActivityFixture(
        product: 'Pınar Süt Tam Yağlı 1 lt',
        reason: 'Satın alma',
        deltaAmount: 1,
        delta: '+1',
        meta: 'Satın alma · Mutfak › Buzdolabı · asistan',
        direction: MovementDirection.inbound,
        isAutomatic: true,
      ),
      // Undo is impossible, and the row says the fact that makes it impossible rather
      // than showing a control that would fail.
      ActivityFixture(
        product: 'Bulgur',
        reason: 'Satın alma',
        deltaAmount: 3,
        delta: '+3',
        unit: 'kg',
        meta: 'Satın alma · Kiler › Çekmece 2 · barkod',
        direction: MovementDirection.inbound,
        undo: UndoState.blocked,
        note: 'Geri alınamaz · bu partiden 0,8 kg kaldı',
      ),
    ],
  ),
  ActivityDay(
    label: 'Dün',
    entries: <ActivityFixture>[
      ActivityFixture(
        product: 'Yoğurt 2 kg',
        reason: 'Tüketim',
        deltaAmount: -1,
        delta: '-1',
        meta: 'Tüketim · Mutfak › Buzdolabı · asistan',
        direction: MovementDirection.outbound,
        isAutomatic: true,
      ),
      ActivityFixture(
        product: 'Kıyma',
        reason: 'Fire',
        deltaAmount: -0.4,
        delta: '-0,4',
        unit: 'kg',
        meta: 'Fire · Mutfak › Derin dondurucu · elle',
        direction: MovementDirection.waste,
      ),
      ActivityFixture(
        product: 'USB-C Kablo 2 m',
        reason: 'Sayım düzeltmesi',
        deltaAmount: 1,
        delta: '+1',
        meta: 'Sayım düzeltmesi · Depo › Raf A · elle',
        direction: MovementDirection.correction,
      ),
    ],
  ),
];

/// Every entry, flattened.
List<ActivityFixture> get activityEntries =>
    activityDays.expand((d) => d.entries).toList(growable: false);

/// The writes that happened without being asked for. The panel's reason to exist.
int get automaticWrites => activityEntries.where((e) => e.isAutomatic).length;
