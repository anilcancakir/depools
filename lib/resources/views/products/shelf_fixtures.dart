import '../../../app/models/shelf_read.dart';
import '../../../ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;

/// One shelf, six regions, in the state a user reviews.
///
/// **The class moved to `lib/app/models/shelf_read.dart` when the screen was wired**, because
/// `flutter-app.md` says to replace a fixture rather than shadow it: two types for one thing diverge
/// the moment the API changes. What is left here is the DATA, which is what a preview needs.
///
/// Two of its fields went with the move. `formatted` and `meta` were already-presented strings, and
/// a live screen has to compute those: the view formats the quantity and derives the meta line from
/// the resolution, the same way `ReceiptReviewView` does for a receipt line.
///
/// **Mixed on purpose, including a failure the model will really make.** Region 6 is a price label
/// the recogniser took for a product; rejecting it is not an edge case, it is Tuesday. Region 3 is a
/// bottle it could not name at all, which `ai-enrichment.md` requires be presented rather than
/// invented.
///
/// The regions are ordered left to right, top to bottom, so the numbers on the photograph read the
/// way a person scans a shelf. That ordering is only a convenience: D60 makes the NUMBER the link
/// between a row and a box, precisely because rows get filtered and reordered while boxes stay where
/// the shelf put them.
const List<ShelfCandidate> shelfCandidates = <ShelfCandidate>[
  ShelfCandidate(
    id: 'c1',
    region: 1,
    left: 0.06,
    top: 0.12,
    width: 0.20,
    height: 0.46,
    productName: 'Pınar Süt Tam Yağlı 1 lt',
    productId: 'p1',
    quantity: 2,
  ),
  ShelfCandidate(
    id: 'c2',
    region: 2,
    left: 0.30,
    top: 0.16,
    width: 0.16,
    height: 0.38,
    productName: 'Sütaş Ayran 250 ml',
    productId: 'p2',
    resolution: LineResolution.created,
    quantity: 4,
  ),
  ShelfCandidate(
    id: 'c3',
    region: 3,
    left: 0.50,
    top: 0.10,
    width: 0.14,
    height: 0.50,
    resolution: LineResolution.unresolved,
    quantity: 1,
  ),
  ShelfCandidate(
    id: 'c4',
    region: 4,
    left: 0.68,
    top: 0.18,
    width: 0.24,
    height: 0.34,
    productName: 'Yoğurt 2 kg',
    productId: 'p4',
    quantity: 1,
  ),
  ShelfCandidate(
    id: 'c5',
    region: 5,
    left: 0.10,
    top: 0.64,
    width: 0.18,
    height: 0.28,
    productName: 'Tariş Zeytinyağı 5 lt',
    productId: 'p5',
    resolution: LineResolution.created,
    quantity: 1,
  ),
  // The model read a shelf label as a product. Rejecting it is routine, so the state has to exist
  // and the row has to stay visible: a candidate that vanished on rejection would be one the user
  // could not un-reject.
  ShelfCandidate(
    id: 'c6',
    region: 6,
    left: 0.34,
    top: 0.70,
    width: 0.22,
    height: 0.16,
    productName: 'Fiyat etiketi',
    resolution: LineResolution.rejected,
    quantity: 1,
  ),
];

/// The read a preview renders, with every region already in place.
const ShelfRead shelfRead = ShelfRead(id: 'shelf-1', candidates: shelfCandidates);

/// Candidates that will be written as they stand.
List<ShelfCandidate> get settledCandidates => shelfRead.settled;

/// Candidates nothing could name.
List<ShelfCandidate> get unresolvedCandidates => shelfRead.unresolved;
