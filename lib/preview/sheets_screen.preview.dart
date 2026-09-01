import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../app/models/shelf_read.dart';
import '../resources/views/products/field_editor_sheet.dart';
import '../resources/views/products/product_fixtures.dart';
import '../resources/views/products/shelf_candidate_sheet.dart';
import '../resources/views/products/shelf_fixtures.dart';
import '../resources/views/products/stock_in_sheet.dart';
import '../resources/views/products/stock_move_sheet.dart';
import '../resources/views/products/stock_out_sheet.dart';
import '../resources/views/products/unit_definition_sheet.dart';
import 'sheet_preview_frame.dart';

/// Every bottom sheet in the app, in one catalog entry.
///
/// ### Why they are together rather than one entry each
///
/// A sheet is small, and the thing a reviewer actually wants to check across them is CONSISTENCY:
/// whether stock-in and stock-out ask for the same things in the same order, whether the unit
/// sheet's equation reads like the rest of the app. Six separate entries put that comparison a
/// navigation away; one entry puts it in a single screenshot.
///
/// It is also the one place in the catalog where grouping beats the one-per-file rule, and the
/// rule it bends (`.claude/rules/design.md`: one preview class per `.preview.dart`) is still kept:
/// this is one class in one file.
///
/// The filter sheet is deliberately absent. It takes a `countMatches` callback that runs against
/// the real filter model, so previewing it means duplicating the stock list's filtering logic here
/// to serve a sheet whose own screen already renders it.
@immutable
class SheetsScreenPreview extends StatelessWidget {
  /// Creates the [SheetsScreenPreview].
  const SheetsScreenPreview({super.key});

  /// The product the movement sheets act on.
  ProductListItem get _product => productFixtures.first;

  /// A shelf region the recogniser matched to a product already in stock.
  ShelfCandidate get _matched => shelfCandidates.first;

  /// A shelf region nothing could name, which is the shape that grows a name field.
  ShelfCandidate get _unnamed => shelfRead.unresolved.first;

  /// A few of the seeded codes, standing in for the tenant list `ShelfPhotoView` fetches.
  ///
  /// The screen reads `GET /units`, so a preview cannot have the real set; what matters here is that
  /// the combobox renders WORDS from CODES, which three of them show as well as nineteen.
  List<String> get _unitCodes => const <String>['C62', 'KGM', 'LTR'];

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 w-full',
      children: [
        SheetPreviewFrame(
          title: Lang.get('screens.stock_in.title'),
          description: _product.name,
          child: StockInSheet(product: _product),
        ),
        SheetPreviewFrame(
          title: Lang.get('screens.stock_out.title'),
          description: _product.name,
          child: StockOutSheet(product: _product),
        ),
        SheetPreviewFrame(
          title: Lang.get('screens.stock_move.title'),
          description: _product.name,
          child: StockMoveSheet(product: _product),
        ),
        SheetPreviewFrame(
          title: Lang.get('screens.unit_definition.title', {'unit': 'koli'}),
          description: Lang.get('screens.unit_definition.description'),
          child: const UnitDefinitionSheet(unit: 'koli', baseUnit: 'adet', quantity: 2),
        ),
        // The three shapes the field editor takes, because which one it picks is the decision
        // `ai-enrichment.md` spends a section on and they are indistinguishable from a call site.
        SheetPreviewFrame(
          title: Lang.get('screens.product_form.brand'),
          child: FieldEditorSheet(
            label: Lang.get('screens.product_form.brand'),
            value: 'Pınar',
            quickAnswers: const <String>['Pınar', 'Sütaş', 'İçim'],
          ),
        ),
        SheetPreviewFrame(
          title: Lang.get('screens.product_form.shelf_life'),
          child: FieldEditorSheet(
            label: Lang.get('screens.product_form.shelf_life'),
            value: '7',
            unit: 'gün',
            kind: FieldEditorKind.number,
          ),
        ),
        // **Both shapes the shelf sheet takes, because the difference is invisible from a call
        // site.** A matched region already has a product, so it asks how many; a region nothing
        // could name has to be named before it can be counted, so the same sheet grows a name field
        // and a unit row. `ai-enrichment.md` requires the unnameable one to be PRESENTED rather than
        // invented, and this is where that presentation is reviewable.
        SheetPreviewFrame(
          title: Lang.get('screens.shelf_candidate.title', {'region': _matched.region}),
          description: _matched.productName,
          child: ShelfCandidateSheet(candidate: _matched, unitCodes: _unitCodes),
        ),
        SheetPreviewFrame(
          title: Lang.get('screens.shelf_candidate.title', {'region': _unnamed.region}),
          description: Lang.get('screens.shelf_candidate.unnamed'),
          child: ShelfCandidateSheet(candidate: _unnamed, unitCodes: _unitCodes),
        ),
      ],
    );
  }
}
