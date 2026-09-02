import 'dart:async';

import 'package:magic/magic.dart';

import '../models/print_batch.dart';
import '../support/mapped_or_null.dart';

/// The print batch a label sheet is built from, and the sheet the server renders of it.
///
/// ### Opening the screen resumes rather than restarts
///
/// A batch exists because items are added over time: a delivery is labelled at the end of an
/// afternoon, not one sticker at a time. So arriving from a product's menu adds that product to the
/// batch already open, and only starts a new one when there is none. The screen shows the whole batch,
/// so a user who meant otherwise sees the extra line and can drop it, which is why
/// `DELETE .../lines/{position}` had to exist before this default was reasonable.
///
/// ### The preview is a URL, not bytes, and the client's own limits decided that
///
/// D18's reversal renders the sheet on the backend precisely so the preview and the print are one
/// artefact. Fetching it as bytes is not available: magic's `Http` facade has no binary response mode
/// (`get`, `post`, `put`, `delete`, `upload`, none carrying a response type), and `Image.network`
/// issues a plain GET that cannot hold a bearer token. So the endpoints answer with a signed
/// short-lived URL, which is the shape `MediaUrl` already established for product photographs.
class LabelBatchController extends MagicController with MagicStateMixin<PrintBatch> {
  /// The shared instance, keyed by type.
  static LabelBatchController get instance => Magic.findOrPut(LabelBatchController.new);

  /// The product to add on the next [open], handed over by the screen that navigated here.
  ///
  /// `/labels` takes no parameters, so the caller hands the id to this singleton and then navigates,
  /// which is what `ShelfController` and `ProductDraftController` both do for the same reason.
  String? _pendingProductId;

  String? _previewUrl;

  bool _rendering = false;

  bool _working = false;

  String? _error;

  /// Which render the current URL belongs to, so a slow one cannot land on a newer batch.
  int _generation = 0;

  /// The batch, or null before [open].
  PrintBatch? get batch => rxState;

  /// A signed URL for the server's rendered sheet, or null when there is nothing to show.
  String? get previewUrl => _previewUrl;

  /// Whether the sheet is being rendered.
  bool get rendering => _rendering;

  /// Whether a write is in flight.
  bool get working => _working;

  /// Why the last call failed, or null.
  String? get error => _error;

  /// Names the product to add when the screen opens.
  void addOnOpen(String productId) {
    _pendingProductId = productId;
  }

  /// Resumes the open batch, or starts one, and renders it.
  ///
  /// [template] is only consulted when a batch has to be created: an existing one keeps its own, which
  /// is the point of it being saved.
  Future<void> open({String template = 'a4_24_up_70x37'}) async {
    setLoading();

    final ({PrintBatch? batch, bool failed}) resumed = await _resume();

    // **A failed list is not an empty one, and treating them alike split the user's work.** A 500, a
    // timeout or an offline moment used to fall straight through to `_create`, so the afternoon's
    // labels went into a fresh batch while the real unfinished one still owed stickers, and nothing on
    // screen said a second batch existed.
    if (resumed.failed) {
      setError(_error ?? Lang.get('errors.unexpected'));

      return;
    }

    if (resumed.batch != null) {
      setSuccess(resumed.batch!);
    } else {
      final PrintBatch? created = await _create(template);

      if (created == null) return;

      setSuccess(created);
    }

    final String? productId = _pendingProductId;
    _pendingProductId = null;

    if (productId != null) {
      await addProduct(productId);

      return;
    }

    unawaited(render());
  }

  /// Adds a product to the batch.
  Future<void> addProduct(String productId, {int copies = 1}) async {
    await _write(() => Http.post('/labels/batches/$_id/lines', data: <String, dynamic>{
      'items': <Map<String, dynamic>>[
        {'product_id': productId, 'copies': copies},
      ],
    }));
  }

  /// Changes how many copies one line prints.
  ///
  /// A PUT rather than a PATCH, because magic's `Http` facade has no `patch`. The route follows the
  /// client rather than the other way round: an endpoint the app cannot call is not an endpoint.
  Future<void> setCopies(int position, int copies) async {
    if (copies < 1) return;

    await _write(() => Http.put(
      '/labels/batches/$_id/lines/$position',
      data: <String, dynamic>{'copies': copies},
    ));
  }

  /// Drops a line.
  Future<void> removeLine(int position) async {
    await _write(() => Http.delete('/labels/batches/$_id/lines/$position'));
  }

  /// Switches a label field on or off.
  ///
  /// **These chips used to be inert and the screen said so in a comment**, because nothing consumed a
  /// field selection: the preview drew a fill diagram rather than a label's contents. The server's
  /// template consumes it now and the preview IS the server's output, so a toggle changes the picture.
  /// The comment recorded a design question; the backend answered it.
  Future<void> toggleField(String field) async {
    final PrintBatch? current = rxState;

    if (current == null) return;

    final List<String> fields = current.shows(field)
        ? current.fields.where((String f) => f != field).toList()
        : <String>[...current.fields, field];

    // A label is not a label with nothing on it, and an empty selection renders a sheet of blank
    // stickers at full cost. The server refuses it too; refusing here keeps the chip from flickering.
    if (fields.isEmpty) return;

    await _write(() => Http.put('/labels/batches/$_id', data: <String, dynamic>{'fields': fields}));
  }

  /// Chooses a sheet template.
  Future<void> setTemplate(String template) async {
    final PrintBatch? current = rxState;

    if (current == null || current.template == template) return;

    await _write(() => Http.put('/labels/batches/$_id', data: <String, dynamic>{'template': template}));
  }

  /// Asks the server for the sheet it would print.
  Future<void> render() async {
    final PrintBatch? current = rxState;
    final int generation = ++_generation;

    if (current == null || current.id.isEmpty) return;

    // Nothing left to print is neither a failure nor a picture; the screen says so instead.
    if (!current.isUnfinished) {
      _previewUrl = null;
      _rendering = false;
      refreshUI();

      return;
    }

    _rendering = true;
    refreshUI();

    final dynamic response = await Http.post('/labels/batches/${current.id}/preview');

    if (generation != _generation) return;

    _rendering = false;

    if (!response.successful) {
      _previewUrl = null;
      _error = _sentence(response, Lang.get('screens.labels.render_failed'));
      refreshUI();

      return;
    }

    final Object? data = response['data'];

    _previewUrl = data is Map<dynamic, dynamic> ? data['url'] as String? : null;

    refreshUI();
  }

  /// The signed URL of the printable sheet, or null with [error] set.
  ///
  /// Not held in state: it is handed straight to whatever opens it, and a stale print URL on screen
  /// would be a button that prints an older sheet.
  Future<String?> pdfUrl() async {
    final PrintBatch? current = rxState;

    if (current == null || current.id.isEmpty) return null;

    // Respects `_working` rather than only setting it: writing the flag without reading it cleared it
    // out from under an in-flight `_write` and let a second one start concurrently.
    if (_working) {
      _error = Lang.get('screens.labels.busy');
      refreshUI();

      return null;
    }

    _working = true;
    _error = null;
    refreshUI();

    final dynamic response = await Http.post('/labels/batches/${current.id}/pdf');

    _working = false;

    if (!response.successful) {
      _error = _sentence(response, Lang.get('screens.labels.render_failed'));
      refreshUI();

      return null;
    }

    refreshUI();

    final Object? data = response['data'];

    return data is Map<dynamic, dynamic> ? data['url'] as String? : null;
  }

  /// Records that the pending lines came off a printer.
  ///
  /// Every pending line, because this screen prints the whole sheet. A partial reprint names positions,
  /// and that belongs to a batch list rather than here.
  Future<String?> settle() async {
    final PrintBatch? current = rxState;

    if (current == null) return null;

    final bool ok = await _write(() => Http.post('/labels/batches/${current.id}/settle'));

    return ok ? null : _error;
  }

  /// Forgets the batch, so a walked-away screen does not outlive itself.
  ///
  /// Called from the view's `dispose`. It was written and never wired, which made the docblock a claim
  /// about behaviour that did not exist: the shelf slice's review found the same shape one screen over,
  /// where leaving and returning drew an already-written sheet with a live accept button.
  void reset() {
    _pendingProductId = null;
    _previewUrl = null;
    _rendering = false;
    _working = false;
    _error = null;

    setEmpty();
  }

  String get _id => Uri.encodeComponent(rxState?.id ?? '');

  /// The batch to carry on filling, and whether the question could be answered at all.
  ///
  /// Two facts rather than one nullable, because the caller has to act differently on each: no batch
  /// means create one, a failed request means say so and stop.
  Future<({PrintBatch? batch, bool failed})> _resume() async {
    final dynamic response = await Http.get('/labels/batches');

    if (!response.successful) {
      _error = _sentence(response, Lang.get('errors.unexpected'));

      return (batch: null, failed: true);
    }

    final Object? rows = response['data'];

    if (rows is! List) return (batch: null, failed: true);

    for (final Object? row in rows) {
      if (row is! Map) continue;

      final PrintBatch? batch = mappedOrNull(
        () => PrintBatch.fromApi(Map<String, dynamic>.from(row)),
        describing: 'a print batch payload',
      );

      // The server orders unfinished first, so the first one that has not been finished is the one to
      // carry on. Checked here anyway rather than trusted, because a list's order is not a contract.
      //
      // `isResumable`, not `isUnfinished`: an empty batch has no unprinted lines and was therefore
      // skipped forever while never being deleted.
      if (batch != null && batch.isResumable) return (batch: batch, failed: false);
    }

    return (batch: null, failed: false);
  }

  Future<PrintBatch?> _create(String template) async {
    final dynamic response = await Http.post('/labels/batches', data: <String, dynamic>{
      'template': template,
    });

    if (!response.successful) {
      _error = _sentence(response, Lang.get('errors.unexpected'));
      setError(_error!);

      return null;
    }

    return _parse(response);
  }

  /// Runs a write, publishes what it answers with, and re-renders.
  Future<bool> _write(Future<dynamic> Function() call) async {
    // **A refusal has to say so, and this branch was the one that did not.** `settle()` returns
    // `ok ? null : _error`, and `_error` is null after any successful write, so a write refused because
    // another was in flight came back as `null` and the screen said "Marked as printed" while nothing
    // had been settled.
    if (_working) {
      _error = Lang.get('screens.labels.busy');
      refreshUI();

      return false;
    }

    _working = true;
    _error = null;
    refreshUI();

    final dynamic response = await call();

    _working = false;

    if (!response.successful) {
      _error = _sentence(response, Lang.get('errors.unexpected'));
      refreshUI();

      return false;
    }

    final PrintBatch? batch = _parse(response);

    if (batch == null) {
      _error = Lang.get('errors.unexpected');
      refreshUI();

      return false;
    }

    setSuccess(batch);

    unawaited(_renderSoon());

    return true;
  }

  /// Renders after a pause, so a run of writes produces one sheet rather than one per write.
  ///
  /// **Twelve taps on a copies stepper is twelve distinct signatures**, and each one used to spawn a
  /// Chrome with a 60-second timeout, keep a PNG forever, and count against `throttle:30,1` until the
  /// user met "Too Many Attempts". The debounce is on the CLIENT because the server cannot tell a
  /// deliberate template switch from the middle of a stepper run.
  Future<void> _renderSoon() async {
    final int generation = ++_generation;

    await Future<void>.delayed(const Duration(milliseconds: 600));

    // A later write already scheduled its own render, so this one is about a batch that has moved on.
    if (generation != _generation) return;

    await render();
  }

  PrintBatch? _parse(dynamic response) {
    final Object? data = response['data'];

    return data is Map<dynamic, dynamic>
        ? mappedOrNull(
            () => PrintBatch.fromApi(Map<String, dynamic>.from(data)),
            describing: 'a print batch payload',
          )
        : null;
  }

  /// The refusal to show, from the response BODY rather than from `MagicResponse.message`.
  ///
  /// Laravel puts a validation refusal in the JSON body's `message`; the driver fills
  /// `MagicResponse.message` from the HTTP status line. Reading the wrong one turned "too many pixels"
  /// into "Unprocessable Content" on the product-photo path before its own test caught it.
  String _sentence(dynamic response, String fallback) {
    final dynamic message = response['message'];

    return message is String && message.isNotEmpty ? message : fallback;
  }
}
