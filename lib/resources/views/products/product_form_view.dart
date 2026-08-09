import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show ButtonIntent, MSButton, MSInput, MSSwitch;

import '../../../ui/components/choice_chip/choice_chip.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';

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

  /// The units offered as chips, in the order a Turkish small business meets them.
  ///
  /// Chips rather than a dropdown because there are five common answers and a dropdown hides all
  /// of them behind a tap. The field stays free-form underneath: an unusual unit is typed.
  static const List<String> _units = <String>['adet', 'kg', 'lt', 'paket', 'kutu'];

  String _name = '';
  String _unit = 'adet';
  bool _tracksExpiry = false;

  bool get _isValid => _name.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Lang.get('screens.product_form.title'),
      subtitle: Lang.get('screens.product_form.subtitle'),
      backLabel: Lang.get('screens.product_form.back'),
      backFallback: '/urunler',
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
              onChanged: (String next) => setState(() => _name = next),
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-1.5',
          children: [
            WText(
              Lang.get('screens.product_form.unit'),
              className: 'text-sm font-medium text-fg',
            ),
            WDiv(
              className: 'flex flex-row wrap items-center gap-2',
              children: [
                for (final String unit in _units)
                  ChoiceChip(
                    label: unit,
                    isSuggested: unit == _unit,
                    semanticLabel: unit == _unit
                        ? Lang.get('screens.product_form.unit_current', {'unit': unit})
                        : Lang.get('screens.product_form.unit_pick', {'unit': unit}),
                    onTap: () => setState(() => _unit = unit),
                  ),
              ],
            ),
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
            WDiv(
              className: 'shrink-0',
              child: MSSwitch(
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
                onChanged: (String _) {},
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
        for (final (String key, String hint) in <(String, String)>[
          ('brand', 'brand_placeholder'),
          ('sku', 'sku_placeholder'),
          ('category', 'category_placeholder'),
          ('description', 'description_placeholder'),
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
                onChanged: (String _) {},
              ),
            ],
          ),
      ],
    );
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
          onPressed: _isValid ? () {} : null,
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
          onPressed: _isValid ? () {} : null,
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
