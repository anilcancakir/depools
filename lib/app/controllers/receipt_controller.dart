import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../models/receipt.dart';
import '../support/mapped_or_null.dart';

/// What an upload attempt turned into.
///
/// **Not a plain `Future<String?>`**, the shape every other write in this app returns, because a
/// duplicate is not a failure the way a 422 is: `receipt-ingestion.md` wants the caller able to offer
/// "open the receipt you already have" rather than only a refusal. A `(String?, Receipt?)` record
/// could carry the same two values, but a caller destructuring it has no name to lean on for which
/// half is which; this reads `outcome.isDuplicate` instead of guessing at a record's second slot. A
/// caller that only checks [message] (the existing app-wide contract) still behaves correctly: it
/// reports this app's own duplicate sentence and never has to know [duplicate] exists.
@immutable
class ReceiptUploadOutcome {
  /// The sentence to show on a refusal, or null on success.
  ///
  /// The server's own on a 422, which carries per-field errors. On a 409 it is this app's, because
  /// that response is `{'data': ...}` and nothing else: the receipt IS the answer there, so there is
  /// no sentence to send and [duplicate] carries the meaning instead.
  final String? message;

  /// The receipt this upload turned out to be, set only on a 409. Null everywhere else, including
  /// success, where there is nothing to open a second time.
  final Receipt? duplicate;

  const ReceiptUploadOutcome({this.message, this.duplicate});

  /// The upload landed and created a new receipt.
  const ReceiptUploadOutcome.ok() : this();

  /// The upload was refused for a reason other than a duplicate (422, a network failure).
  const ReceiptUploadOutcome.failed(String message) : this(message: message);

  /// The upload was the same file the tenant already has on file.
  const ReceiptUploadOutcome.duplicateOf(String message, Receipt receipt)
    : this(message: message, duplicate: receipt);

  /// Whether the upload actually created a new receipt.
  bool get succeeded => message == null;

  /// Whether the refusal was a duplicate rather than an outright failure.
  bool get isDuplicate => duplicate != null;
}

/// What the user decided about one line they are keeping.
///
/// **The product and the quantity travel together because both are editable.** The cascade proposes
/// a product and the paper proposes a quantity, and per-line confirmation means the user can change
/// either before anything reaches the ledger. A commit that sent only the ids would silently discard
/// a correction the user had just made.
///
/// Lives beside [ReceiptUploadOutcome] rather than in `models/receipt.dart` for the same reason that
/// one does: it describes a REQUEST this controller makes, not a row the server sent back.
@immutable
class ReceiptLineDecision {
  /// The product this line is being counted as.
  final String productId;

  /// How many, in the product's own unit, as the user left it.
  final num quantity;

  const ReceiptLineDecision({required this.productId, required this.quantity});
}

/// Captured purchase documents, from `api/v1/receipts`.
///
/// ### This slice stores a photograph and lists it, and reads nothing off it
///
/// Every receipt this controller holds has zero lines, because there is no AI extraction wired up
/// yet. That is the normal, correct state: the same list and detail state this holds is what slice 2
/// starts filling, so the shape is built once rather than reworked when extraction lands.
class ReceiptController extends MagicController with MagicStateMixin<List<Receipt>> {
  /// The shared instance, keyed by type.
  static ReceiptController get instance => Magic.findOrPut(ReceiptController.new);

  Receipt? _detail;

  /// The id [open] last asked for, so a slower response for an abandoned id cannot overwrite a
  /// faster one for the id the user is actually looking at now.
  String? _detailId;

  bool _detailLoading = false;

  bool _extracting = false;

  String? _detailError;

  /// The tenant's receipts, newest first, or empty while the first fetch is in flight.
  List<Receipt> get receipts => rxState ?? const <Receipt>[];

  /// The receipt [open] most recently landed, or null before the first successful fetch.
  Receipt? get detail => _detail;

  /// Whether a detail fetch is in flight.
  bool get detailLoading => _detailLoading;

  /// Whether a model is reading a photograph right now.
  ///
  /// Separate from [detailLoading] because they mean different things to the screen: one is a fetch
  /// that replaces what is shown, the other spends a credit and takes seconds, so it earns a label
  /// rather than a spinner over the whole card.
  bool get extracting => _extracting;

  /// The server's sentence for the last failed detail fetch, or null.
  String? get detailError => _detailError;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetches the tenant's receipts.
  Future<void> load() async {
    setLoading();

    final dynamic response = await Http.get('/receipts');

    if (!response.successful) {
      setError(response.message ?? Lang.get('errors.unexpected'));

      return;
    }

    final List<Receipt>? receipts = mappedOrNull<List<Receipt>?>(
      () {
        final Object? data = response['data'];

        if (data is! List) return null;

        final List<Receipt> found = <Receipt>[];

        for (final Object? row in data) {
          // **`Map<dynamic, dynamic>` and then convert**, which is what every other reader in this
          // app does. The narrower `Map<String, dynamic>` test happens to match what this HTTP layer
          // decodes today, and `product_detail_controller.dart:312-321` carries the scar: the day it
          // decodes one level less precisely, the narrow test rejects every row. Failing loudly
          // rather than skipping the row, because a list quietly one receipt short is worse than an
          // error on a screen whose whole job is to be complete.
          if (row is! Map<dynamic, dynamic>) return null;

          found.add(Receipt.fromApi(Map<String, dynamic>.from(row)));
        }

        return found;
      },
      describing: 'the receipt list',
    );

    if (receipts == null) {
      setError(Lang.get('errors.unexpected'));

      return;
    }

    setSuccess(receipts);
  }

  /// Fetches one receipt with its lines, into [detail].
  ///
  /// Not part of [MagicStateMixin]'s state, deliberately: that mixin tracks one typed value, and the
  /// list already claims it. A held detail alongside a held list is the same split
  /// `ProductDetailController` keeps from `ProductController`, for the same reason: a fetch racing a
  /// list refresh must not overwrite fields the other one does not carry.
  Future<void> open(String id) async {
    _detailId = id;
    _detailLoading = true;
    _detailError = null;
    refreshUI();

    final dynamic response = await Http.get('/receipts/${Uri.encodeComponent(id)}');

    // The latest request wins. A slower response for an id the user has since navigated away from
    // must not clobber the receipt actually on screen.
    if (_detailId != id) return;

    if (!response.successful) {
      _detailLoading = false;
      _detailError = response.message ?? Lang.get('errors.unexpected');
      refreshUI();

      return;
    }

    final Object? data = response['data'];

    final Receipt? receipt = data is Map<dynamic, dynamic>
        ? mappedOrNull(
            () => Receipt.fromApi(Map<String, dynamic>.from(data)),
            describing: 'a receipt detail payload',
          )
        : null;

    _detailLoading = false;

    if (receipt == null) {
      _detailError = Lang.get('errors.unexpected');
    } else {
      _detail = receipt;
    }

    refreshUI();
  }

  /// Reads a stored photograph into lines, and holds the result in [detail].
  ///
  /// Returns null on success, or the sentence to show. The server answers 200 with no lines when the
  /// tenant is out of AI credits, which is deliberate on both sides: `receipt-ingestion.md` requires
  /// the manual path to stay open, so extraction stopping is not the feature failing. That case
  /// reaches the screen as a receipt with nothing on it rather than as an error, and the screen says
  /// so with its own empty state.
  ///
  /// A 409 means somebody already read this receipt, which is a stale screen rather than a failure:
  /// the fresh copy is in the body, so it is taken and shown.
  Future<String?> extract(String id) async {
    _extracting = true;
    refreshUI();

    final dynamic response = await Http.post('/receipts/${Uri.encodeComponent(id)}/extract');

    _extracting = false;

    // 409 carries the receipt as it already stands, so the screen catches up instead of arguing.
    if (!response.successful && response.statusCode != 409) {
      refreshUI();

      final dynamic message = response['message'];

      return message is String && message.isNotEmpty
          ? message
          : Lang.get('screens.receipt.extract_failed');
    }

    final Receipt? receipt = _readReceipt(response, 'an extracted receipt payload');

    if (receipt == null) {
      refreshUI();

      return Lang.get('errors.unexpected');
    }

    _detail = receipt;
    _detailId = receipt.id;
    refreshUI();

    // The list row carries a line COUNT, so a receipt that just gained lines is stale in the list
    // until this lands. Not awaited by the caller's error path: the read succeeded either way.
    await load();

    return null;
  }

  /// Writes the confirmed lines into stock.
  ///
  /// [accepted] is keyed by line id and carries the product and quantity as the user left them;
  /// [rejected] are the lines they threw away. Anything in neither stays untouched and unresolved,
  /// which is what makes a half-worked receipt resumable rather than a restart.
  ///
  /// [batchKey] is the idempotency key. The server splits it per line, so a retry after a dropped
  /// connection writes each line once rather than twice.
  Future<String?> commit(
    String id, {
    required String locationId,
    required Map<String, ReceiptLineDecision> accepted,
    List<String> rejected = const <String>[],
    String? batchKey,
  }) async {
    final dynamic response = await Http.post(
      '/receipts/${Uri.encodeComponent(id)}/commit',
      data: <String, dynamic>{
        'location_id': locationId,
        'idempotency_key': ?batchKey,
        'lines': <Map<String, dynamic>>[
          for (final MapEntry<String, ReceiptLineDecision> entry in accepted.entries)
            <String, dynamic>{
              'id': entry.key,
              'product_id': entry.value.productId,
              'quantity': entry.value.quantity,
            },
        ],
        if (rejected.isNotEmpty) 'rejections': rejected,
      },
    );

    if (!response.successful) {
      final dynamic message = response['message'];

      return message is String && message.isNotEmpty
          ? message
          : Lang.get('screens.receipt.commit_failed');
    }

    final Receipt? receipt = _readReceipt(response, 'a committed receipt payload');

    if (receipt != null) {
      _detail = receipt;
      _detailId = receipt.id;
    }

    refreshUI();

    await load();

    return null;
  }

  /// The receipt in a `{'data': ...}` body, or null when it cannot be read.
  ///
  /// Shared by the two writes above and shaped like [open]'s reader for the reason that one gives:
  /// `Map<dynamic, dynamic>` and then convert, because the narrower test happens to match what this
  /// HTTP layer decodes today and breaks the day it decodes one level less precisely.
  Receipt? _readReceipt(dynamic response, String describing) {
    final Object? data = response['data'];

    return data is Map<dynamic, dynamic>
        ? mappedOrNull(
            () => Receipt.fromApi(Map<String, dynamic>.from(data)),
            describing: describing,
          )
        : null;
  }

  /// Photographs a receipt, then reloads the list on success.
  ///
  /// See [ReceiptUploadOutcome] for why a 409 is answered rather than treated as a failure: the
  /// server catches the duplicate-file constraint and sends back the receipt that already exists, and
  /// the caller can offer to open it instead of losing the tenant's tap to a bare error.
  ///
  /// That 409 body is `{'data': ...}` with no `message`, so the sentence below is always this app's
  /// own. Read as a fallback it would look like a defence against a server that forgot to explain
  /// itself; it is the normal path, and the receipt is what the response actually says.
  Future<ReceiptUploadOutcome> upload(XFile file) async {
    final response = await Http.upload(
      '/receipts',
      data: const <String, dynamic>{},
      files: <String, dynamic>{'image': file},
    );

    if (response.statusCode == 409) {
      final Object? data = response['data'];

      final Receipt? existing = data is Map<dynamic, dynamic>
          ? mappedOrNull(
              () => Receipt.fromApi(Map<String, dynamic>.from(data)),
              describing: 'a duplicate receipt payload',
            )
          : null;

      // No `response['message']` read: that body is `{'data': ...}` and nothing else, so preferring a
      // server sentence would be a branch this app's own comment says is unreachable.
      final String sentence = Lang.get('screens.receipt.duplicate');

      // `existing == null` only if the server sent a 409 with an unreadable receipt, which reads as
      // an outright failure rather than a duplicate the caller has nothing to open.
      return existing == null
          ? ReceiptUploadOutcome.failed(sentence)
          : ReceiptUploadOutcome.duplicateOf(sentence, existing);
    }

    if (!response.successful) {
      final dynamic message = response['message'];

      return ReceiptUploadOutcome.failed(
        message is String && message.isNotEmpty ? message : Lang.get('screens.receipt.upload_failed'),
      );
    }

    await load();

    return const ReceiptUploadOutcome.ok();
  }
}
