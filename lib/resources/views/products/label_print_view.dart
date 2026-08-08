import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSPageScaffold, MSButton, ButtonIntent;

import '../../../ui/components/callout/callout.dart';
import '../../../ui/components/filter_chip/filter_chip.dart';
import '../../../ui/components/label_card/label_card.dart';
import '../../../ui/components/label_item_row/label_item_row.dart';
import '../../../ui/components/label_preview/label_preview.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import 'label_fixtures.dart';

/// Printing barcode labels for a batch of products.
///
/// **One screen, not a wizard, and the doc's own history is the argument.**
/// `labeling-and-printing.md` describes three steps and calls out what it is reacting to:
/// "the MVP's eight-state modal machine with no back button". Criterion 4 then asks for
/// three steps where every step has a back path. A single screen with three sections
/// satisfies that criterion in its strongest form rather than its literal one: there is no
/// sequential gate at all, so every decision is reachable at every moment and a back path
/// is not something to implement and get wrong. Every other capture surface in this app is
/// already shaped this way.
///
/// ### The preview is the feature
///
/// Criterion 7 is "preview matches print output" and criterion 1 asks a person to measure a
/// printed sheet with a ruler, which means the preview has to be dimensionally honest or it
/// is decoration. `LabelPreview` renders the sheet at true proportions with its empty cells
/// visible, because the unused part of a page is what a user is choosing between when they
/// pick a template. `LabelCard` renders one label at a size a person can read, because the
/// sheet cannot: at sheet scale, 9pt type is six pixels.
///
/// ### Quantity means two different things
///
/// D45. A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve
/// copies of one design and the count is free. A serial-tracked product's labels are all
/// different, one per unit, so its count is the number of selected serials and a stepper
/// there would be offering to edit how many units exist.
@immutable
class LabelPrintView extends StatelessWidget {
  static const IconData _printIcon = Icons.print_outlined;
  static const IconData _pdfIcon = Icons.download_outlined;

  /// The chosen sheet template, by index into [sheetTemplates].
  ///
  /// Two variants rather than a stateful picker, because what has to be reviewable is the
  /// arithmetic at both ends of the catalog: a large label that wastes most of a page, and
  /// a small one where a field stops fitting.
  final int templateIndex;

  /// Creates the [LabelPrintView] on the default 8-up sheet.
  const LabelPrintView({super.key}) : templateIndex = 0;

  /// Creates the view on the smallest sheet in the catalog, where a field overruns.
  const LabelPrintView.tight({super.key}) : templateIndex = 3;

  /// The chosen template.
  SheetTemplate get _template => sheetTemplates[templateIndex];

  /// The field that will not fit, or null when everything does.
  ///
  /// **Named rather than truncated**, because the doc requires it and because truncation in
  /// a preview reads as a design choice while the same truncation on 200 printed labels
  /// reads as a defect. At 38×21 mm the name and the code fit and the location does not.
  String? get _overflowField => _template.labelHeightMm < 30 ? Lang.get('screens.labels.field_location') : null;

  @override
  Widget build(BuildContext context) {
    return MSPageScaffold(
      title: Lang.get('screens.labels.title'),
      subtitle: Lang.get('screens.labels.subtitle', {'labels': pendingLabels, 'sheets': sheetsFor(_template)}),
      children: [
        WDiv(
          className: 'flex flex-col lg:flex-row items-start gap-4',
          children: [_buildPreview(), _buildControls()],
        ),
      ],
    );
  }

  /// The sheet, which moves to the left column on a wide window.
  ///
  /// `lg:order-first` rather than a reordered children list: the reading order on a phone
  /// is decide-then-check, and on a desktop the artifact sits beside the controls that
  /// change it so a template switch is visible without scrolling.
  Widget _buildPreview() {
    return WDiv(
      className: 'w-full lg:flex-1 lg:order-first',
      child: SectionCard(
        label: Lang.get('screens.labels.preview_group'),
        count: _template.label,
        children: [
          LabelPreview(
            template: _template,
            filled: lastSheetFill(_template),
            barcode: '8690504004073',
            // The last sheet is the one drawn, because it is the one with the waste on it.
            caption: sheetsFor(_template) == 1
                ? Lang.get('screens.labels.preview_one_sheet', {'used': lastSheetFill(_template), 'total': _template.perSheet})
                : Lang.get('screens.labels.preview_sheets', {
                    'sheets': sheetsFor(_template),
                    'used': lastSheetFill(_template),
                  }),
          ),
        ],
      ),
    );
  }

  /// What to print, how it is laid out, and the two ways out.
  Widget _buildControls() {
    return WDiv(
      className: 'flex flex-col gap-4 w-full lg:flex-1',
      children: [_buildItems(), _buildLayout(), _buildActions()],
    );
  }

  /// The batch. Printed lines stay, because criterion 5 makes it resumable.
  Widget _buildItems() {
    return SectionCard(
      label: Lang.get('screens.labels.what_group'),
      count: Lang.get('screens.labels.label_count', {'count': pendingLabels}),
      children: [
        for (final LabelItemFixture item in labelBatch)
          LabelItemRow(
            name: item.name,
            code: item.code,
            count: item.count,
            mode: item.mode,
            isPrinted: item.isPrinted,
            onDecrement: item.mode == LabelCountMode.free ? () {} : null,
            onIncrement: item.mode == LabelCountMode.free ? () {} : null,
          ),
        if (labelBatch.any((i) => i.isPrinted))
          WText(
            '${labelBatch.where((i) => i.isPrinted).length} satır basıldı, '
            'yeniden basılmaz',
            className: 'text-xs text-fg-muted',
          ),
      ],
    );
  }

  /// Sheet, fields, and the proof of what they produce.
  Widget _buildLayout() {
    return SectionCard(
      label: Lang.get('screens.labels.layout_group'),
      children: [
        for (final SheetTemplate template in sheetTemplates)
          _templateRow(template, template == _template),
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 pt-1',
          children: [
            for (final String field in labelFieldOptions)
              FilterChip(
                label: field,
                // The name and the code are what makes a label a label; the other two are
                // the tenant's choice. A default that switched everything on would put a
                // team name on a 21 mm sticker and call it a fit problem.
                applied: field == Lang.get('screens.labels.field_name') || field == Lang.get('screens.labels.field_barcode') || field == Lang.get('screens.labels.field_location'),
                onTap: () {},
              ),
          ],
        ),
        WDiv(
          // `items-start`, never `items-stretch`. A Row inside a scrolling Column has no
          // height of its own, and stretch asks its children to match a height that does
          // not exist yet; the result is a RenderBox-was-not-laid-out assertion with
          // nothing in it that names the Row.
          className: 'flex flex-row items-start gap-3 pt-2',
          children: [
            WDiv(
              // The width tracks the label so the two variants read as different sizes.
              // It is NOT the label's aspect ratio, and that is deliberate: the sheet is
              // the dimensional proof and this is the content proof, which is why they are
              // two views rather than one zoomable one. The fit verdict comes from the
              // overflow line, computed, rather than from a user eyeballing a wrap.
              className: _template.labelHeightMm < 30 ? 'w-40 axis-min' : 'w-56 axis-min',
              child: LabelCard(
                name: 'Pınar Süt Tam Yağlı 1 lt',
                meta: 'Mutfak › Buzdolabı',
                code: '8690504004073',
                overflowField: _overflowField,
                size: _template.labelHeightMm < 30 ? LabelCardSize.sm : LabelCardSize.md,
              ),
            ),
            WText(
              Lang.get('screens.labels.sample_label'),
              className: 'text-xs text-fg-muted flex-auto min-w-0',
            ),
          ],
        ),
        if (_overflowField != null)
          Callout(
            intent: CalloutIntent.danger,
            title: Lang.get('screens.labels.overflow', {'field': _overflowField}),
            message:
                'Etiket ${_template.labelWidthMm}×${_template.labelHeightMm} mm. '
                'Alan kısaltılmaz, ya kapatılır ya daha büyük bir yerleşim seçilir.',
          ),
      ],
    );
  }

  /// One sheet option. Every option carries a fill so the group reads as a set of choices.
  Widget _templateRow(SheetTemplate template, bool isSelected) {
    return OptionRow(
      label: template.label,
      isSelected: isSelected,
      semanticLabel: Lang.get('screens.labels.pick_layout', {'label': template.label}),
      onTap: () {},
      // Pages and waste together. Pages alone would show 24-up and 65-up as "1 sayfa"
      // each and hide that one prints 3 blanks and the other 44, which is the whole
      // difference between them for this batch.
      trailing: WText(
        Lang.get('screens.labels.layout_meta', {'sheets': sheetsFor(template), 'wasted': wastedCells(template)}),
        className: 'font-mono text-xs text-fg-muted',
      ),
    );
  }

  /// Print, or take the file away.
  ///
  /// The PDF path is not a fallback bolted on: a user with no printer at hand still gets
  /// something, and on web it is frequently the whole flow.
  Widget _buildActions() {
    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        WText(
          Lang.get('screens.labels.submit_note', {'labels': pendingLabels, 'sheets': sheetsFor(_template)}),
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              WIcon(_printIcon, className: 'size-4'),
              WText(Lang.get('screens.labels.submit')),
            ],
          ),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: const WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              WIcon(_pdfIcon, className: 'size-4'),
              WText('PDF indir'),
            ],
          ),
        ),
      ],
    );
  }
}
