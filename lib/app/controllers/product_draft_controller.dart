import 'dart:async';

import 'package:magic/magic.dart';

import '../models/product_draft.dart';
import '../models/scan_entry.dart';
import '../support/mapped_or_null.dart';
import '../support/merge_unit_codes.dart';

/// The draft card a photograph becomes, from the shutter to the saved product.
///
/// ### The photograph is held here rather than passed through the route
///
/// `/draft` takes no parameters and an `XFile` is not a path segment, so the capture hands the file
/// to this singleton and then navigates. That is the shape `ReceiptController` already uses for the
/// same reason, and it keeps the router from learning about a file it cannot express.
///
/// ### The screen is drawn before the read finishes, on purpose
///
/// `ai-enrichment.md`'s second acceptance criterion is that the user sees a draft card within a
/// second, before the model responds. So [begin] publishes an empty draft synchronously and [read]
/// fills it in afterwards; a controller that only published on completion would make that criterion
/// unreachable however fast the model was.
class ProductDraftController extends MagicController
    with MagicStateMixin<ProductDraft>, ValidatesRequests {
  /// The shared instance, keyed by type.
  static ProductDraftController get instance =>
      Magic.findOrPut(ProductDraftController.new);

  /// [save]'s rule set, mirroring `StoreProductRequest::rules()` by hand.
  ///
  /// Only the fields [ProductDraft.toCreatePayload] actually sends: `sku`'s `Rule::unique` is an
  /// [AsyncRule] and only runs under `validateAsync()`, which [ValidatesRequests.validate] does not
  /// call, so it is left off rather than approximated. `base_unit`'s `UnitExists`,
  /// `product_category_id`'s uuid-plus-closure check and `image_phash`'s `size:32|regex:...` all have
  /// no magic equivalent either.
  static final Map<String, List<Rule>> _saveRules = <String, List<Rule>>{
    'name': <Rule>[Required(), Max(255)],
    'brand': <Rule>[Max(255)],
    'description': <Rule>[Max(2000)],
    'sku': <Rule>[Max(64)],
    'base_unit': <Rule>[Max(16)],
    'default_shelf_life_days': <Rule>[Min(1), Max(3650)],
  };

  XFile? _photo;

  bool _reading = false;

  bool _saving = false;

  String? _error;

  /// Which capture the in-flight read belongs to.
  ///
  /// **Incremented by every [begin], compared before every publish.** Backing out of a draft and
  /// shooting again is an ordinary thing to do, and without this the first photograph's answer
  /// lands on the second photograph's card: the user sees a product they are not holding, with a
  /// hash that belongs to a different picture.
  int _capture = 0;

  /// The unit codes this tenant may pick, server order first.
  ///
  /// Starts as the countable unit alone so the editor is never empty while the request is out, and
  /// merged rather than assigned when the answer lands, the same way `ProductFormView` does it: a
  /// tenant unit the screen already knew about must not be dropped by a late response.
  List<String> _units = const <String>[ScanEntry.defaultUnit];

  /// The unit vocabulary the unit editor offers.
  ///
  /// Fetched rather than hardcoded because `units.team_id` exists precisely so a tenant can count in
  /// something the seeded list does not name, and a draft that offered only the shared codes would
  /// be the one screen where their own unit was unreachable.
  List<String> get units => _units;

  /// The photograph this draft is being read from, or null before one is chosen.
  ///
  /// Kept after the read so the save can upload it to the product's gallery: the read discards its
  /// own copy, and the picture the user just took is the obvious first picture of the product.
  XFile? get photo => _photo;

  /// Whether the read is still in flight, which is what draws the skeleton fields.
  bool get reading => _reading;

  /// Whether a save is in flight.
  bool get saving => _saving;

  /// Why the last read or save failed, or null.
  String? get error => _error;

  /// The draft as it stands, or null before [begin].
  ProductDraft? get draft => rxState;

  /// Start a new draft from this photograph.
  ///
  /// Publishes immediately with nothing in it, so the screen can be on-screen before the request is
  /// even sent. The hash is empty until the server answers, which is also the honest state: nothing
  /// has been hashed yet.
  void begin(XFile photo) {
    _capture++;
    _photo = photo;
    _reading = true;
    _error = null;
    _saving = false;

    setSuccess(const ProductDraft(imagePhash: ''));

    // Not awaited: the vocabulary is needed when the user opens the unit editor, which is several
    // seconds away at the earliest, and blocking the first frame on it would cost the one second
    // criterion 2 allows for the whole card.
    unawaited(_loadUnits());
  }

  /// Ask the server what is in the photograph, and fill the draft with whatever it says.
  ///
  /// Never throws and never leaves the draft null: a read that fails still leaves a card the user
  /// can type into, which is what keeps manual creation working with no credits (criterion 5).
  Future<void> read() async {
    final XFile? photo = _photo;
    final int capture = _capture;

    if (photo == null) return;

    final dynamic response = await Http.upload(
      '/products/recognise',
      data: const <String, dynamic>{},
      files: <String, dynamic>{'photo': photo},
    );

    // The latest capture wins. A slower answer for a photograph the user has already replaced must
    // not overwrite the card they are looking at.
    if (capture != _capture) return;

    _reading = false;

    if (!response.successful) {
      _error = _sentence(response, Lang.get('screens.product_draft.read_failed'));
      refreshUI();

      return;
    }

    final Object? data = response['data'];

    final ProductDraft? read = data is Map<dynamic, dynamic>
        ? mappedOrNull(
            () => ProductDraft.fromApi(Map<String, dynamic>.from(data)),
            describing: 'a product recognition payload',
          )
        : null;

    if (read == null) {
      _error = Lang.get('screens.product_draft.read_failed');
      refreshUI();

      return;
    }

    setSuccess(read);
  }

  /// Load the unit vocabulary, leaving the countable default alone on a failure.
  ///
  /// Degrading to one option is honest rather than broken: every product can be counted in pieces,
  /// and the field is optional anyway because `Product::creating` resolves the team's own default
  /// when the client names nothing.
  Future<void> _loadUnits() async {
    final dynamic response = await Http.get('/units');

    if (!response.successful) return;

    final dynamic rows = response['data'];

    if (rows is! List) return;

    final List<String> codes = <String>[
      for (final dynamic row in rows)
        if (row is Map && row['code'] is String) row['code'] as String,
    ];

    if (codes.isEmpty) return;

    _units = mergeUnitCodes(
      fromServer: codes,
      known: _units,
      selected: rxState?.unit ?? ScanEntry.defaultUnit,
    );

    refreshUI();
  }

  /// Replace one field and clear its "we guessed this" mark (D53).
  void edit(String field, String? value) {
    final ProductDraft? current = rxState;

    if (current == null) return;

    setSuccess(current.withField(field, value));
  }

  /// Create the product, and give it the photograph it was read from.
  ///
  /// Returns the new product's id on success, or null when it failed, in which case [error] carries
  /// the sentence to show. The gallery upload is deliberately NOT part of that verdict: the product
  /// exists either way, and failing the save over a picture would throw away the card the user just
  /// confirmed.
  Future<String?> save() async {
    final ProductDraft? current = rxState;

    // **`_saving` guards the request as well as the button.** The button recedes while a save is in
    // flight, but a double tap can land two taps before the first frame that shows it, and two
    // products is not a state a compensating action can tidy.
    if (current == null || (current.name ?? '').isEmpty || _saving) return null;

    final Map<String, dynamic> payload = current.toCreatePayload();

    try {
      validate(payload, _saveRules);
    } on ValidationException {
      // validationErrors is already populated and refreshUI() already fired; the card reads
      // hasError()/getError() once it is wired (step 8/9), so nothing else has to happen here.
      return null;
    }

    _saving = true;
    _error = null;
    refreshUI();

    final dynamic response = await Http.post(
      '/products',
      data: payload,
    );

    _saving = false;

    if (!response.successful) {
      // handleApiError nulls rxState via MagicStateMixin.setError/setEmpty for ANY failure, which
      // would drop the draft the user is still looking at. Restore it right after: only the field
      // errors (read via hasError()/getError()) are new state from a refused save, not the card
      // itself, per this method's own docblock ("Returns null... in which case error carries the
      // sentence").
      handleApiError(response, fallback: Lang.get('errors.unexpected'));
      setSuccess(current);
      _error = _sentence(response, Lang.get('errors.unexpected'));
      refreshUI();

      return null;
    }

    final Object? data = response['data'];
    final String? id = data is Map<dynamic, dynamic>
        ? data['id'] as String?
        : null;

    if (id != null) {
      await _attachPhoto(id);
    }

    refreshUI();

    return id;
  }

  /// Drop the held photograph and the flags around it.
  ///
  /// It does NOT clear the draft, because [begin] replaces it wholesale and a null state would give
  /// the screen a fourth thing to draw for the length of one frame. What this is actually for is the
  /// file handle: holding a photograph the user has walked away from is the one thing that outlives
  /// the screen.
  void reset() {
    _photo = null;
    _reading = false;
    _saving = false;
    _error = null;

    refreshUI();
  }

  /// The refusal to show, from the response BODY rather than from `MagicResponse.message`.
  ///
  /// **The two are not the same field and reading the wrong one was a real defect here**, caught by
  /// the controller's own test before it reached a screen. Laravel puts a validation refusal in the
  /// JSON body's `message`; the driver fills `MagicResponse.message` from the HTTP status line, so
  /// "This picture holds too many pixels to process." arrived as "Unprocessable Content". Every
  /// other write in this app reads the body for the same reason.
  String _sentence(dynamic response, String fallback) {
    final dynamic message = response['message'];

    return message is String && message.isNotEmpty ? message : fallback;
  }

  /// Put the photograph in the new product's gallery.
  ///
  /// Its own step rather than part of the create, because the create endpoint takes JSON and this is
  /// multipart: one request carrying both would mean a second shape for a route every other caller
  /// already sends JSON to. The picture is also the one part of this the user can redo later from
  /// the product screen, which is what makes a silent failure here acceptable where one on the card
  /// would not be.
  Future<void> _attachPhoto(String productId) async {
    final XFile? photo = _photo;

    if (photo == null) return;

    await Http.upload(
      '/products/${Uri.encodeComponent(productId)}/images',
      data: const <String, dynamic>{},
      files: <String, dynamic>{'image': photo},
    );
  }
}
