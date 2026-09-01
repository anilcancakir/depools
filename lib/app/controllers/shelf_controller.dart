import 'dart:async';

import 'package:magic/magic.dart';

import '../../ui/components/receipt_line_row/receipt_line_row.dart' show LineResolution;
import '../models/shelf_read.dart';
import '../support/mapped_or_null.dart';

/// A photographed shelf, from the shutter to the stock it becomes.
///
/// ### The photograph is held here rather than passed through the route
///
/// `/shelf-photo` takes no parameters and an `XFile` is not a path segment, so the capture hands the
/// file to this singleton and then navigates. `ReceiptController` and `ProductDraftController` both
/// do the same for the same reason.
///
/// ### Three calls, because the design needs the row before the read
///
/// `ai-enrichment.md` requires a failed read to leave "a resumable record rather than an orphaned
/// file", and D60 keeps the photograph on screen through the whole review. The upload creates the
/// row, so both are true before a model is asked anything; the read is separately callable, which is
/// what makes a retake a retry rather than a second upload.
class ShelfController extends MagicController with MagicStateMixin<ShelfRead> {
  /// The shared instance, keyed by type.
  static ShelfController get instance => Magic.findOrPut(ShelfController.new);

  XFile? _photo;

  bool _uploading = false;

  bool _reading = false;

  bool _committing = false;

  String? _error;

  /// Which capture the in-flight work belongs to.
  ///
  /// Incremented by every [begin] and compared before every publish. Backing out and shooting
  /// again is ordinary, and without this the first photograph's answer lands on the second
  /// photograph's screen: boxes drawn over a picture they do not describe.
  int _capture = 0;

  /// The photograph being read, kept so the screen can draw the boxes over it.
  ///
  /// **The server never sends the picture back.** Its copy is on a private disk with no route
  /// serving it, deliberately, so the only picture the boxes can sit on is the local file the user
  /// just took. That is also why the screen cannot be resumed on another device yet.
  XFile? get photo => _photo;

  /// Whether the upload is in flight, which is the state before there is anything to draw.
  bool get uploading => _uploading;

  /// Whether the read is in flight, which draws the skeleton rows.
  bool get reading => _reading;

  /// Whether a commit is in flight.
  bool get committing => _committing;

  /// Why the last call failed, or null.
  String? get error => _error;

  /// The read as it stands, or null before [begin].
  ShelfRead? get read => rxState;

  /// Start a new capture from this photograph.
  ///
  /// Publishes nothing yet: there is no read id until the upload answers, and the screen draws its
  /// uploading state off [uploading] rather than off an empty read. Inventing a placeholder id would
  /// give the commit something to address that the server has never heard of.
  void begin(XFile photo) {
    _capture++;
    _photo = photo;
    _uploading = true;
    _reading = false;
    _committing = false;
    _error = null;

    setLoading();
  }

  /// Upload the photograph, then read it.
  ///
  /// One method rather than two, because there is nothing a caller would ever do between them: the
  /// upload exists to give the read a row to write into. They stay two REQUESTS, which is what makes
  /// a retake a retry.
  Future<void> uploadAndRead() async {
    if (!await _upload()) return;

    await reread();
  }

  /// Ask the server to read the photograph again.
  ///
  /// Separate from [uploadAndRead] so a failed read can be retried without re-uploading, which is
  /// what `ai-enrichment.md`'s "the photo is kept and no credit was spent" promises the user.
  Future<void> reread() async {
    final ShelfRead? current = rxState;
    final int capture = _capture;

    if (current == null) return;

    _reading = true;
    _error = null;
    refreshUI();

    final dynamic response = await Http.post('/shelf-reads/${Uri.encodeComponent(current.id)}/read');

    if (capture != _capture) return;

    _reading = false;

    // 409 is the server refusing to re-read a shelf it has already written stock from, because the
    // movements point at the candidates a re-read would delete. It answers with the read as it
    // stands, so the screen catches up instead of arguing.
    if (!response.successful && response.statusCode != 409) {
      _error = _sentence(response, Lang.get('screens.shelf_photo.read_failed'));
      refreshUI();

      return;
    }

    _publish(response, 'a shelf read payload');
  }

  /// Apply the user's decision to one region, locally.
  ///
  /// Nothing reaches the server until [commit]: D60's accept count is the settled count, and the
  /// user is allowed to change their mind about a region before they submit the shelf.
  void decide(ShelfCandidate candidate) {
    final ShelfRead? current = rxState;

    if (current == null) return;

    setSuccess(current.withCandidate(candidate));
  }

  /// Write the settled candidates into [locationId].
  ///
  /// Returns null on success, or the sentence to show. The location is a commit-time choice rather
  /// than a capture-time one, because a shelf IS one location and the user picks it once for the
  /// whole batch, which is exactly the shape `stock/receive-batch` has.
  Future<String?> commit({required String locationId}) async {
    final ShelfRead? current = rxState;

    if (current == null || _committing) return null;

    _committing = true;
    _error = null;
    refreshUI();

    final dynamic response = await Http.post(
      '/shelf-reads/${Uri.encodeComponent(current.id)}/commit',
      data: <String, dynamic>{
        'location_id': locationId,
        'accepted': <String, dynamic>{
          for (final ShelfCandidate c in current.candidates)
            if (c.isSettled && c.productId != null)
              '${c.region}': <String, dynamic>{
                'product_id': c.productId,
                // One when the model could not count, because the user accepted a region they can
                // see and a null would refuse at the server's `gt:0`. The sheet offers the number.
                'quantity': c.quantity ?? 1,
              },
        },
        'rejected': <int>[
          for (final ShelfCandidate c in current.candidates)
            if (c.resolution == LineResolution.rejected) c.region,
        ],
      },
    );

    _committing = false;

    if (!response.successful) {
      _error = _sentence(response, Lang.get('errors.unexpected'));
      refreshUI();

      return _error;
    }

    _publish(response, 'a committed shelf read payload');

    return null;
  }

  /// Create a product for a region nothing could name, and return its id.
  ///
  /// **The client creates it, which is a decision the backend records rather than hides.**
  /// `ShelfCommitter` takes product ids only, the same as `ReceiptCommitter`, so a new product is
  /// one request before the commit. On a shelf of five new products that is five requests a batch
  /// endpoint would have folded into one, and `stock/receive-batch` is where to look if that ever
  /// becomes the thing worth fixing.
  Future<String?> createProduct({required String name, String? unit}) async {
    // The unit is omitted rather than sent as null: the server's `Product::creating` resolves the
    // team's own default when the caller names nothing, and an explicit null reaches a mutator that
    // looks the code up and throws on a miss.
    final Map<String, dynamic> payload = <String, dynamic>{'name': name};

    if (unit != null) payload['base_unit'] = unit;

    final dynamic response = await Http.post('/products', data: payload);

    if (!response.successful) {
      _error = _sentence(response, Lang.get('errors.unexpected'));
      refreshUI();

      return null;
    }

    final Object? data = response['data'];

    return data is Map<dynamic, dynamic> ? data['id'] as String? : null;
  }

  /// Drop the held photograph, so a walked-away capture does not outlive its screen.
  void reset() {
    _photo = null;
    _uploading = false;
    _reading = false;
    _committing = false;
    _error = null;

    refreshUI();
  }

  /// Stores the photograph and publishes the row it created.
  Future<bool> _upload() async {
    final XFile? photo = _photo;
    final int capture = _capture;

    if (photo == null) return false;

    final dynamic response = await Http.upload(
      '/shelf-reads',
      data: const <String, dynamic>{},
      files: <String, dynamic>{'photo': photo},
    );

    if (capture != _capture) return false;

    _uploading = false;

    if (!response.successful) {
      _error = _sentence(response, Lang.get('screens.shelf_photo.upload_failed'));
      setError(_error!);

      return false;
    }

    return _publish(response, 'a shelf read payload');
  }

  /// Reads a `ShelfRead` out of a response and publishes it.
  bool _publish(dynamic response, String describing) {
    final Object? data = response['data'];

    final ShelfRead? read = data is Map<dynamic, dynamic>
        ? mappedOrNull(
            () => ShelfRead.fromApi(Map<String, dynamic>.from(data)),
            describing: describing,
          )
        : null;

    if (read == null) {
      _error = Lang.get('screens.shelf_photo.read_failed');
      refreshUI();

      return false;
    }

    setSuccess(read);

    return true;
  }

  /// The refusal to show, from the response BODY rather than from `MagicResponse.message`.
  ///
  /// Laravel puts a validation refusal in the JSON body's `message`; the driver fills
  /// `MagicResponse.message` from the HTTP status line. Reading the wrong one turned "This picture
  /// holds too many pixels to process." into "Unprocessable Content" on the product-photo path
  /// before its own test caught it.
  String _sentence(dynamic response, String fallback) {
    final dynamic message = response['message'];

    return message is String && message.isNotEmpty ? message : fallback;
  }
}
