import 'package:magic/magic.dart';

/// The manual product form's save, from `ProductFormView`.
///
/// ### Why this exists rather than reusing `ProductDraftController`
///
/// Both post to `/products`, but they are different callers of the same endpoint rather than one
/// screen with two entry points. `ProductDraftController` owns the AI draft card (`rxState` is the
/// draft, `save()` reads it and restores it on a refused write); this screen has no card and no
/// draft to restore, only a form the caller fills in and submits once. Giving the form controller
/// its own rule set rather than sharing `ProductDraftController`'s is the house rule waiting for a
/// third caller before extracting anything shared: two is not it.
///
/// ### No `MagicStateMixin`
///
/// Every other controller in `lib/app/controllers/` caches something the view reads back
/// (`LocationController.nodes`, `ProductDraftController.draft`). This one caches nothing: the form's
/// values live in the view's own `TextEditingController`s, and a save either succeeds (the view
/// navigates away) or fails (the view stays on the same fields with the errors this controller now
/// holds). So `handleApiError`'s `if (this is MagicStateMixin)` branch never fires here, and that is
/// deliberate rather than an oversight: there is no cached state a blank `rxState` could clobber, and
/// none to restore afterwards either.
class ProductFormController extends MagicController with ValidatesRequests {
  /// The shared instance, keyed by type.
  static ProductFormController get instance => Magic.findOrPut(ProductFormController.new);

  /// [save]'s rule set, mirroring `StoreProductRequest::rules()` by hand.
  ///
  /// Only the fields `ProductFormView._save` actually sends. `tracks_expiry` carries no rule: magic
  /// ships no `boolean` rule and the field is always a real `bool` from a switch, never a string that
  /// could fail to parse as one. `sku`'s `Rule::unique` is an [AsyncRule] and only runs under
  /// `validateAsync()`, which [ValidatesRequests.validate] does not call, so it is left off rather
  /// than approximated (same call `ProductDraftController._saveRules` already made). `base_unit`'s
  /// `UnitExists` has no magic equivalent either, so only its `max:16` column bound is mirrored.
  static final Map<String, List<Rule>> _createRules = <String, List<Rule>>{
    'name': <Rule>[Required(), Max(255)],
    'brand': <Rule>[Max(255)],
    'sku': <Rule>[Max(64)],
    'description': <Rule>[Max(2000)],
    'base_unit': <Rule>[Max(16)],
    'default_shelf_life_days': <Rule>[Min(1), Max(3650)],
  };

  /// The refusal to show as a toast, or null.
  ///
  /// Set only when the last [save] failed with NO field named: a rate limit or a 500. The view's own
  /// `_save` used to compute this inline as `_errors.isEmpty` and show `_messageOf(response)`; the
  /// same no-field fallback now lives here so the view can read it after the call rather than
  /// recomputing it, and `validationErrors` (via [hasErrors]) already carries the per-field half.
  String? get saveError => _saveError;

  String? _saveError;

  /// Validates, then posts to `/products`.
  ///
  /// Returns `(ok: true, id: ...)` on success, where `id` is the server's id when it sent one (a
  /// missing id is a real answer the caller decides how to treat, not a failure). Returns
  /// `(ok: false, id: null)` on either a client-side refusal (per-field errors only, [saveError]
  /// stays null) or a server refusal (per-field errors via [hasError]/[getError] when the server
  /// named a field, [saveError] when it named none).
  Future<({bool ok, String? id})> save({
    required String name,
    required String baseUnit,
    required bool tracksExpiry,
    int? defaultShelfLifeDays,
    String? brand,
    String? sku,
    String? description,
  }) async {
    _saveError = null;

    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name,
      'base_unit': baseUnit,
      'tracks_expiry': tracksExpiry,
      'default_shelf_life_days': ?defaultShelfLifeDays,
      'brand': ?brand,
      'sku': ?sku,
      'description': ?description,
    };

    try {
      validate(payload, _createRules);
    } on ValidationException {
      // validationErrors is already populated and refreshUI() already fired, so the view already
      // shows the refusal once it reads hasError()/getError(); nothing else has to happen here.
      return (ok: false, id: null);
    }

    final dynamic response = await Http.post('/products', data: payload);

    if (!response.successful) {
      // No cached state to blank and restore here, unlike LocationController.create and
      // ProductDraftController.save: see this class's own docblock on why MagicStateMixin is absent.
      handleApiError(response, fallback: Lang.get('screens.product_form.save_failed'));

      // A message only when the server named no field: the same no-field fallback the view's own
      // `_save` always carried, so a rate limit or a 500 still tells the user something happened.
      if (validationErrors.isEmpty) {
        _saveError = response.errorMessage as String? ?? Lang.get('screens.product_form.save_failed');
      }

      return (ok: false, id: null);
    }

    final dynamic id = response['data'] is Map ? response['data']['id'] : null;

    return (ok: true, id: id is String ? id : null);
  }
}
