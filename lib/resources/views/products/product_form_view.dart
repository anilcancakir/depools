import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show ButtonIntent, MSBottomSheet, MSButton, MSCombobox, MSInput, MSSwitch;

import '../../../app/controllers/product_form_controller.dart';
import '../../../app/models/scan_entry.dart' show ScanEntry;
import '../../../app/support/merge_unit_codes.dart';
import '../../../app/support/unit_label.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';
import 'unit_draft_sheet.dart';

/// Creating a product by hand, which until now was impossible.
///
/// ### Why this screen was missing and why that mattered
///
/// `iterations.md` lists manual entry as the first v1 capture path and `inventory-core.md`
/// describes exactly this form, but the only product-creation surface that existed was
/// `ProductDraftView`, the AI draft that arrives from a scan or a photograph. So a product with no
/// barcode, or one the user simply wants to type in, could not be added at all. Both "Ürün ekle"
/// buttons in the app were `onPressed: () {}`.
///
/// ### The 60-second criterion decides the shape
///
/// `inventory-core.md`'s first acceptance criterion is a new tenant recording their first product
/// AND its stock in under 60 seconds, from an empty state, without documentation. That rules out a
/// long form and it rules out the tap-a-field-open-a-sheet pattern the draft screen uses: that
/// pattern is right when values ARRIVE and need checking, and wrong when the user is typing from
/// nothing.
///
/// So: two required fields visible (name, base unit), expiry as one switch, and everything else
/// folded away. A user who wants to fill in a SKU can; a user who does not never sees it.
///
/// The primary action is `Kaydet ve stok gir` rather than `Kaydet`, because the criterion counts
/// the stock too. Saving alone stays available as the quiet option for someone building a catalog
/// before they receive anything.
///
/// ### What is deliberately NOT asked
///
/// `tracking_mode` (lot versus serial). D30 keeps it off the creation form entirely: a user adding
/// a drill does not yet know they will want serial numbers, and asking costs every user a decision
/// to serve a few. It is flipped later from the product's own screen.
///
/// `par_level` and `reorder_point` are also absent. `forecasting.md` asks for a target level at the
/// moment it becomes useful (when the product first appears on a shortage surface with no target),
/// which is when the user has a reason to answer.
@immutable
class ProductFormView extends StatefulWidget {
  /// Creates the [ProductFormView] for a new product.
  const ProductFormView({super.key});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> {
  static const IconData _saveIcon = Icons.arrow_forward;

  static const IconData _addUnitIcon = Icons.add;

  /// The vocabulary, from `GET /units`.
  ///
  /// **Chips rather than a dropdown**, because a dropdown hides every answer behind a tap and the
  /// common ones are short. What changed is where the list comes from: it used to be five hardcoded
  /// Turkish words (`adet`, `kg`, `lt`, `paket`, `kutu`) with a comment claiming a free-text field
  /// underneath, which there never was. Those five were not codes the server recognised, so this
  /// screen was offering a vocabulary of its own.
  ///
  /// Starts as the countable unit alone so the chip row is never empty while the request is out.
  List<String> _units = const <String>[ScanEntry.defaultUnit];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _brand = TextEditingController();
  final TextEditingController _sku = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _shelfLife = TextEditingController();

  String _unit = ScanEntry.defaultUnit;
  bool _tracksExpiry = false;

  /// Whether a save is in flight, so a second press cannot create a second product.
  bool _saving = false;

  /// Both halves of the double validation `flutter-app.md` asks for: the button below refuses an
  /// empty name before the request goes out, and [ProductFormController] mirrors the server's own
  /// rules before sending it and maps back whatever the server still refuses. The four render sites
  /// below read `hasError`/`getError` off the shared instance rather than a map this view keeps
  /// itself, so a field's error is whichever half caught it.
  ProductFormController get _form => ProductFormController.instance;

  bool get _isValid => _name.text.trim().isNotEmpty && !_saving;

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnits());
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _sku.dispose();
    _description.dispose();
    _shelfLife.dispose();
    super.dispose();
  }

  /// Loads the units this tenant may pick.
  ///
  /// A failure leaves the countable unit as the only option, which is the honest degradation: every
  /// product can be counted in pieces.
  ///
  /// **The answer is MERGED rather than assigned, and overwriting was a real race.** This request is
  /// started in `initState`, and a user can register a unit of their own before it lands: the late
  /// response would then replace the list, drop the code they just created, and leave the combobox
  /// holding a `value` that is no longer among its `options`. Server order leads, because that is the
  /// order the picker is meant to read in, and anything the screen knows about and the server did not
  /// mention follows it.
  Future<void> _loadUnits() async {
    final dynamic response = await Http.get('/units');

    if (!mounted || !response.successful) return;

    final dynamic rows = response['data'];

    if (rows is! List) return;

    final List<String> codes = <String>[
      for (final dynamic row in rows)
        if (row is Map && row['code'] is String) row['code'] as String,
    ];

    if (codes.isEmpty) return;

    setState(() {
      _units = mergeUnitCodes(fromServer: codes, known: _units, selected: _unit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.product_form.title'),
      subtitle: Lang.get('screens.product_form.subtitle'),
      backLabel: Lang.get('screens.product_form.back'),
      backFallback: '/products',
      footer: _buildFooter(),
      children: [
        _buildIdentity(),
        _buildExpiry(),
        _buildOptional(),
      ],
    );
  }

  /// The two fields that are actually required.
  Widget _buildIdentity() {
    return SectionCard(
      label: Lang.get('screens.product_form.identity_group'),
      children: [
        WDiv(
          className: 'flex flex-col gap-1.5',
          children: [
            WText(
              Lang.get('screens.product_form.name'),
              className: 'text-sm font-medium text-fg',
            ),
            MSInput(
              className: 'bg-surface-container',
              placeholder: Lang.get('screens.product_form.name_placeholder'),
              controller: _name,
              // The button's own enabled state reads this, so the rebuild is the point rather than the
              // stored value: a controller holds the text either way.
              onChanged: (String _) => setState(() => _form.clearFieldError('name')),
            ),
            if (_form.hasError('name'))
              WText(_form.getError('name')!, className: 'text-xs text-expired'),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1.5',
          children: [
            WText(
              Lang.get('screens.product_form.unit'),
              className: 'text-sm font-medium text-fg',
            ),
            // **A searchable combobox rather than a row of chips**, and that was a correction:
            // nineteen seeded codes already wrapped to two rows, and a tenant may add their own on top,
            // so the list has no known length. Chips are right for a handful of answers and wrong for a
            // set that grows; the combobox stays one line however long the vocabulary gets.
            //
            // The CODE picks and the WORD shows: the option reads `piece` or `adet` while `C62` travels
            // to the server. Rec 20 codes are unreadable by design, so an option labelled with one would
            // be an option nobody can choose.
            MSCombobox<String>(
              value: _unit,
              options: <SelectOption<String>>[
                for (final String unit in _units)
                  SelectOption<String>(value: unit, label: unitLabel(unit)),
              ],
              searchPlaceholder: Lang.get('screens.product_form.unit_search'),
              onChange: (String? next) {
                // Clears its own complaint, the same way the name field does: a refusal about the unit
                // stops being true the moment a different one is chosen.
                if (next != null) {
                  setState(() {
                    _unit = next;
                    _form.clearFieldError('base_unit');
                  });
                }
              },
            ),
            // The one deliberate way out of a closed vocabulary. Nineteen codes cover a lot and not
            // everything, and `units.team_id` exists precisely so a tenant who counts in something the
            // standard does not name can say so once instead of typing it per product.
            WAnchor(
              onTap: () => unawaited(_addUnit()),
              semanticLabel: Lang.get('screens.product_form.unit_add_label'),
              child: WDiv(
                className: 'flex flex-row items-center gap-1 px-3 py-2 rounded-md '
                    'bg-surface-container border border-color-border',
                children: [
                  const WIcon(_addUnitIcon, className: 'size-4 text-fg-muted'),
                  WText(
                    Lang.get('screens.product_form.unit_add'),
                    className: 'text-sm text-fg-muted',
                  ),
                ],
              ),
            ),
            if (_form.hasError('base_unit'))
              WText(_form.getError('base_unit')!, className: 'text-xs text-expired'),
            // Said once, under the chips: stock is stored in this unit and a package unit is a
            // conversion to it, which is the distinction `inventory-core.md` spends a section on.
            WText(
              Lang.get('screens.product_form.unit_note'),
              className: 'text-xs text-fg-muted',
            ),
          ],
        ),
      ],
    );
  }

  /// One switch, and the shelf life only once it can matter.
  ///
  /// The shelf-life field appears only when expiry is tracked, because a number of days is
  /// meaningless for a product with no date and an always-visible disabled field is noise.
  Widget _buildExpiry() {
    return SectionCard(
      label: Lang.get('screens.product_form.expiry_group'),
      children: [
        WDiv(
          className: 'flex flex-row items-start justify-between gap-3 w-full',
          children: [
            WDiv(
              className: 'flex flex-col gap-1 flex-1 min-w-0',
              children: [
                WText(
                  Lang.get('screens.product_form.tracks_expiry'),
                  className: 'text-sm font-semibold text-fg',
                ),
                WText(
                  Lang.get('screens.product_form.tracks_expiry_note'),
                  className: 'text-xs text-fg-muted',
                ),
              ],
            ),
            // **A hairline, because the fill cannot carry the boundary in both appearances.**
            // Measured in light mode on a white card: the off track is #E7E6EC and the thumb is
            // white, so the control's own edge sits at about 1.2:1 against the card and the whole
            // switch nearly disappears. Dark mode hides this completely, which is why it survived
            // three screens. WCAG 1.4.11 asks 3:1 for a UI component's boundary.
            //
            // `border-color-control`, not `border-color-border`: the card hairline is deliberately
            // low contrast and clears nothing, and DESIGN.md records why that is right for a card
            // edge. A control edge is a different job, so it got its own token
            // (`lib/config/depools_control_tokens.dart`), measured at 3.13:1 on a card.
            WDiv(
              className: 'shrink-0',
              child: MSSwitch(
                className: 'border border-color-control',
                value: _tracksExpiry,
                semanticLabel: Lang.get('screens.product_form.tracks_expiry'),
                onChanged: (bool next) => setState(() => _tracksExpiry = next),
              ),
            ),
          ],
        ),
        if (_tracksExpiry)
          WDiv(
            className: 'flex flex-col gap-1.5',
            children: [
              WText(
                Lang.get('screens.product_form.shelf_life'),
                className: 'text-sm font-medium text-fg',
              ),
              MSInput(
                className: 'bg-surface-container',
                placeholder: Lang.get('screens.product_form.shelf_life_placeholder'),
                type: InputType.number,
                controller: _shelfLife,
                onChanged: (String _) =>
                    setState(() => _form.clearFieldError('default_shelf_life_days')),
              ),
              if (_form.hasError('default_shelf_life_days'))
                WText(
                  _form.getError('default_shelf_life_days')!,
                  className: 'text-xs text-expired',
                ),
              WText(
                Lang.get('screens.product_form.shelf_life_note'),
                className: 'text-xs text-fg-muted',
              ),
            ],
          ),
      ],
    );
  }

  /// Everything a user can ignore, folded away.
  ///
  /// Collapsed by default for the same reason the placement dial is (D70): a field nobody needs on
  /// the common path should not tax the common path. Open, it is four ordinary inputs.
  Widget _buildOptional() {
    return SectionCard(
      label: Lang.get('screens.product_form.optional_group'),
      // The count names the CONTENTS rather than the state, because `SectionCard` owns its own
      // expansion and a closed section that does not say what is inside is a section nobody opens.
      count: Lang.get('screens.product_form.optional_closed'),
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // **Three of the four are wired and `category` is not, which is a fact rather than an
        // oversight.** The API takes a `product_category_id` into the SHARED taxonomy, and that table
        // holds zero rows: its Google seed is documented in the migration and lives nowhere, so there is
        // no id for a typed word to become. A free-text category would either be dropped silently or
        // invent a per-tenant vocabulary, which is the exact mistake this whole change is undoing.
        for (final (String key, String hint, TextEditingController? controller)
            in <(String, String, TextEditingController?)>[
          ('brand', 'brand_placeholder', _brand),
          ('sku', 'sku_placeholder', _sku),
          ('category', 'category_placeholder', null),
          ('description', 'description_placeholder', _description),
        ])
          WDiv(
            className: 'flex flex-col gap-1.5',
            children: [
              WText(
                Lang.get('screens.product_form.$key'),
                className: 'text-sm font-medium text-fg',
              ),
              MSInput(
                className: 'bg-surface-container',
                placeholder: Lang.get('screens.product_form.$hint'),
                controller: controller,
                // The one field with no controller cannot be saved, so it cannot be typed into either:
                // an input that accepts text and discards it is worse than one that does not accept it.
                // `enabled`, which is what `MSInput` calls it.
                enabled: controller != null,
                onChanged: (String _) => setState(() => _form.clearFieldError(key)),
              ),
              if (_form.hasError(key))
                WText(_form.getError(key)!, className: 'text-xs text-expired'),
            ],
          ),
      ],
    );
  }

  /// Registers a unit of this tenant's own and selects it.
  ///
  /// The code is folded to upper case by the server, so `koli` and `Koli` are one unit rather than two;
  /// the sheet does not pretend otherwise and shows what came back.
  Future<void> _addUnit() async {
    final UnitDraft? draft = await MSBottomSheet.show<UnitDraft>(
      context,
      title: Lang.get('screens.product_form.unit_add_title'),
      body: const UnitDraftSheet(),
    );

    if (draft == null || !mounted) return;

    final dynamic response = await Http.post('/units', data: <String, dynamic>{
      'code': draft.code,
      'name': draft.name,
    });

    if (!mounted) return;

    if (!response.successful) {
      // `firstError` over `response['message']`: this is the unit sheet's whole write path, and
      // the sheet has already popped by the time this answers, so there is no field slot left to
      // put a refusal under. A collision on `code` (this tenant already has it, or it shadows a
      // standard one) is a field-named 422 from `StoreUnitRequest`, and `firstError` reads that
      // field's own sentence before falling back to the envelope's `message`.
      MagicFeedback.error(
        Lang.get('screens.product_form.unit_add_title'),
        response.firstError ?? Lang.get('screens.product_form.unit_add_failed'),
      );

      return;
    }

    final dynamic code = response['data'] is Map ? response['data']['code'] : null;

    if (code is! String) return;

    setState(() {
      _units = <String>[..._units, code];
      _unit = code;
      _form.clearFieldError('base_unit');
    });
  }

  /// Creates the product, then either opens it or goes back to the list.
  ///
  /// **Both buttons save.** The primary one is `save and enter stock` because
  /// `inventory-core.md`'s first criterion counts the stock too, so it lands on the product's own
  /// screen, which is where stock is entered. The quiet one returns to the list, for somebody building
  /// a catalogue before they receive anything.
  Future<void> _save({required bool thenStock}) async {
    if (_saving) return;

    setState(() => _saving = true);

    final ({bool ok, String? id}) result = await _form.save(
      name: _name.text.trim(),
      baseUnit: _unit,
      tracksExpiry: _tracksExpiry,
      defaultShelfLifeDays: _tracksExpiry && int.tryParse(_shelfLife.text.trim()) != null
          ? int.parse(_shelfLife.text.trim())
          : null,
      brand: _brand.text.trim().isNotEmpty ? _brand.text.trim() : null,
      sku: _sku.text.trim().isNotEmpty ? _sku.text.trim() : null,
      description: _description.text.trim().isNotEmpty ? _description.text.trim() : null,
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _saving = false);

      // A message as well as the field marks, because a refusal with no field (a rate limit, a 500)
      // would otherwise mark nothing and look like the button doing nothing. `_form.saveError` is
      // null exactly when the refusal named at least one field, which the render sites above show.
      if (_form.saveError != null) {
        MagicFeedback.error(Lang.get('screens.product_form.title'), _form.saveError!);
      }

      return;
    }

    setState(() => _saving = false);

    MagicFeedback.success(
      Lang.get('screens.product_form.title'),
      Lang.get('screens.product_form.saved', {'name': _name.text.trim()}),
    );

    if (thenStock && result.id != null) {
      MagicRoute.to('/products/${result.id}');

      return;
    }

    MagicRoute.to('/products');
  }

  /// Save and go straight to stock, or just save.
  ///
  /// Pinned (D70), because the form grows when expiry is tracked and when the optional section is
  /// opened, and the action a screen exists for cannot sit below content that varies in height.
  Widget _buildFooter() {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        // **The intent carries the disabled state, because the disabled STYLING does not.**
        // `MSButton` takes `disabled` separately from a null callback and honours it for taps,
        // but a primary button rendered disabled still looks like a filled blue primary button:
        // measured on this screen, the empty form's `Kaydet ve stok gir` was indistinguishable
        // from the valid one. A control that looks tappable and is not is the anti-pattern the
        // design rules already name, so the fill goes away until the form can actually be saved
        // and returns the moment it can, which is also the clearest possible signal of what
        // changed.
        MSButton(
          onPressed: _isValid ? () => unawaited(_save(thenStock: true)) : null,
          disabled: !_isValid,
          intent: _isValid ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              WText(Lang.get('screens.product_form.save_and_stock')),
              const WIcon(_saveIcon, className: 'size-4'),
            ],
          ),
        ),
        MSButton(
          onPressed: _isValid ? () => unawaited(_save(thenStock: false)) : null,
          disabled: !_isValid,
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WText(Lang.get('screens.product_form.save_only')),
        ),
      ],
    );
  }
}
