import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSButton, ButtonIntent, MagicStarterConfirmDialog;

import '../../../app/controllers/label_batch_controller.dart';
import '../../../app/models/print_batch.dart';
import '../../../app/support/plural.dart';
import '../../../ui/components/callout/callout.dart';
import '../../../ui/components/filter_chip/filter_chip.dart';
import '../../../ui/components/label_card/label_card.dart';
import '../../../ui/components/label_item_row/label_item_row.dart';
import '../../../ui/components/label_preview/label_preview.dart';
import '../../../ui/components/option_row/option_row.dart';
import '../../../ui/components/section_card/section_card.dart';
import '../../../ui/layouts/app_page_scaffold.dart';

/// Printing barcode labels for a batch of products.
///
/// **One screen, not a wizard, and the doc's own history is the argument.**
/// `labeling-and-printing.md` describes three steps and calls out what it is reacting to:
/// "the MVP's eight-state modal machine with no back button". Criterion 4 then asks for
/// three steps where every step has a back path. A single screen with three sections
/// satisfies that criterion in its strongest form rather than its literal one: there is no
/// sequential gate at all, so every decision is reachable at every moment and a back path
/// is not something to implement and get wrong.
///
/// ### The preview is the feature, and it is now the server's own sheet
///
/// Criterion 7 is "preview matches print output" and criterion 1 asks a person to measure a
/// printed sheet with a ruler. `LabelPreview` used to draw a proportion box with a placeholder,
/// deliberately, because drawing an accurate page here would mean re-implementing the renderer
/// in order to preview it. With the endpoint in place it shows the PNG the backend rendered from
/// the same Blade template the PDF comes from, so the two are one artefact by construction.
///
/// `LabelCard` still renders one label at a size a person can read, because the sheet cannot: at
/// sheet scale, 9pt type is six pixels.
///
/// ### Quantity means two different things
///
/// D45. A lot-tracked product's label identifies the PRODUCT, so twelve stickers are twelve
/// copies of one design and the count is free. A serial-tracked product's labels are all
/// different, one per unit, so its count is the number of selected serials and a stepper
/// there would be offering to edit how many units exist.
class LabelPrintView extends StatefulWidget {
  static const IconData _printIcon = Icons.print_outlined;
  static const IconData _pdfIcon = Icons.download_outlined;
  static const IconData _removeIcon = Icons.close;

  /// A batch supplied by the caller, which is how the preview catalog stays offline.
  ///
  /// Null means "read [LabelBatchController]", which is what the route does. The state class only
  /// touches the controller when this is null, so a preview never issues a request.
  final PrintBatch? preview;

  /// The templates to offer. Fetched from the server on the route; supplied here for the catalog.
  final List<SheetTemplate>? previewTemplates;

  /// Creates the [LabelPrintView], reading from [LabelBatchController].
  const LabelPrintView({super.key}) : preview = null, previewTemplates = null;

  /// Creates the view over a supplied batch, for the catalog.
  const LabelPrintView.preview(
    PrintBatch this.preview,
    List<SheetTemplate> this.previewTemplates, {
    super.key,
  });

  @override
  State<LabelPrintView> createState() => _LabelPrintViewState();
}

class _LabelPrintViewState extends State<LabelPrintView> {
  LabelBatchController? _controller;

  /// The sheet catalogue.
  ///
  /// Fetched in the view rather than in the controller, which is what `BarcodeScanView` does with its
  /// own picker list and for the same reason: `SheetTemplate` is the PREVIEW component's input shape,
  /// so a controller building it would be the dependency pointing the wrong way.
  List<SheetTemplate> _templates = const <SheetTemplate>[];

  /// Why the catalogue could not be fetched, or null.
  ///
  /// Held here rather than in the controller because the request is this view's, and the screen cannot
  /// render without an answer: `_template` gates the whole build, so an empty catalogue and a slow one
  /// look identical without this.
  String? _templatesError;

  @override
  void initState() {
    super.initState();

    if (widget.preview != null) {
      _templates = widget.previewTemplates ?? const <SheetTemplate>[];

      return;
    }

    final LabelBatchController controller = LabelBatchController.instance
      ..addListener(_onControllerChanged);

    _controller = controller;

    unawaited(_loadTemplates());
    unawaited(controller.open());
  }

  @override
  void dispose() {
    final LabelBatchController? controller = _controller;

    controller?.removeListener(_onControllerChanged);

    // The batch is a type-keyed singleton, so without this a return visit draws whatever the last visit
    // held: `reset()` existed for exactly that and was never called. After the listener is dropped, so
    // the `refreshUI` inside it cannot reach a disposed `setState`.
    controller?.reset();

    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Loads the sheet catalogue and its geometry.
  Future<void> _loadTemplates() async {
    final dynamic response = await Http.get('/labels/templates');

    if (!mounted) return;

    // **A failure here is not cosmetic, and the shape copied from `BarcodeScanView` assumed it was.**
    // There the picker list is auxiliary and the screen works without it; here the catalogue carries
    // the geometry every section reads, so returning silently left the screen on "Loading the sheet
    // catalogue…" for good with a printable batch behind it.
    if (!response.successful) {
      final Object? message = response['message'];

      setState(() {
        _templatesError =
            message is String && message.isNotEmpty ? message : Lang.get('errors.unexpected');
      });

      return;
    }

    final Object? rows = response['data'];

    setState(() {
      _templatesError = null;
      _templates = <SheetTemplate>[
        if (rows is List)
          for (final Object? row in rows)
            if (row is Map) SheetTemplate.fromApi(Map<String, dynamic>.from(row)),
      ];
    });
  }

  PrintBatch? get _batch => widget.preview ?? _controller?.batch;

  /// The chosen template's geometry, or null before the catalogue lands.
  SheetTemplate? get _template {
    final String? key = _batch?.template;

    if (key == null) return null;

    for (final SheetTemplate template in _templates) {
      if (template.key == key) return template;
    }

    return _templates.isEmpty ? null : _templates.first;
  }

  /// How many stickers a print would produce now.
  int get _pending => _batch?.pendingStickerCount ?? 0;

  /// How many sheets those stickers need.
  int _sheetsFor(SheetTemplate template) =>
      _pending == 0 ? 0 : (_pending + template.perSheet - 1) ~/ template.perSheet;

  /// The cells printed blank across every sheet.
  int _wastedCells(SheetTemplate template) =>
      _sheetsFor(template) * template.perSheet - _pending;

  /// How many cells the last sheet uses.
  int _lastSheetFill(SheetTemplate template) {
    final int remainder = _pending % template.perSheet;

    return remainder == 0 ? template.perSheet : remainder;
  }

  /// The codes that will not fit the chosen label, at a scannable density.
  ///
  /// **Computed from the server's own ceiling rather than guessed from the label's height.** This used
  /// to be `labelHeightMm < 30`, which named a field by correlation; `max_code_length` is arithmetic
  /// the encoder owns: a Code 128 set B symbol is `11(n + 2) + 13` modules plus 20 of quiet zone, and
  /// GS1's absolute floor is a 0.250 mm module, so a 38 mm label holds seven characters.
  List<String> get _unscannable {
    final SheetTemplate? template = _template;
    final int? ceiling = template?.maxCodeLength;
    final PrintBatch? batch = _batch;

    if (ceiling == null || batch == null || !batch.shows('code')) return const <String>[];

    final List<String> over = <String>[];

    for (final String code in batch.codes) {
      if (code.length > ceiling && !over.contains(code)) over.add(code);
    }

    return over;
  }

  /// The failure that stops this screen rendering at all, or null.
  ///
  /// **Two channels, because two requests gate the render and only one of them is the controller's.**
  /// The batch arrives through `RxStatus`, and `setError` is `setState(null, ...)`: it nulls the state
  /// this whole build keys on, so a failed open left the screen on "Loading the sheet catalogue…"
  /// forever while the controller held a sentence nothing rendered. Reading the status is what makes
  /// the transition the controller already performs visible.
  String? get _blockingFailure {
    if (widget.preview != null) return null;

    final LabelBatchController? controller = _controller;

    if (controller != null && controller.isError) {
      return controller.rxStatus.message ?? Lang.get('errors.unexpected');
    }

    return _templatesError;
  }

  /// The header's second line: the wait, or what a print would produce.
  ///
  /// Null on a failure, because the card below says what happened and a header reading "Loading the
  /// sheet catalogue…" over it would contradict it.
  String? get _subtitle {
    if (_blockingFailure != null) return null;

    final SheetTemplate? template = _template;

    if (template == null) return Lang.get('screens.labels.subtitle_loading');

    return Lang.get('screens.labels.subtitle', {
      'labels': plural('screens.labels.label_count', _pending, {'count': _pending}),
      'sheets': plural('screens.labels.sheet_count', _sheetsFor(template), {
        'count': _sheetsFor(template),
      }),
    });
  }

  @override
  Widget build(BuildContext context) {
    final SheetTemplate? template = _template;
    final String? failure = _blockingFailure;

    return AppPageScaffold(
      title: Lang.get('screens.labels.title'),
      subtitle: _subtitle,
      // **Pinned rather than trailing (D70).** A batch is filled over an afternoon rather than one
      // sticker at a time, so the two ways out sat under a list whose length the user does not
      // control: the server caps it at 200 lines. Outside the app shell the scaffold falls back to a
      // trailing section, so both previews keep rendering it.
      footer: template == null ? null : _buildActions(template),
      children: [
        if (failure != null)
          _buildFailure(failure)
        else if (template == null)
          _buildLoading()
        else
          WDiv(
            className: 'flex flex-col lg:flex-row items-start gap-4',
            children: [_buildPreview(template), _buildControls(template)],
          ),
      ],
    );
  }

  /// A request that did not come back, in the card slot every screen here uses for one.
  Widget _buildFailure(String message) {
    return SectionCard(
      error: message,
      // Both requests, because either one failing leaves the screen unrenderable and nothing on it
      // tells the user which of the two it was.
      onRetry: () {
        setState(() => _templatesError = null);

        unawaited(_loadTemplates());
        unawaited(_controller?.open() ?? Future<void>.value());
      },
      children: const <Widget>[],
    );
  }

  Widget _buildLoading() {
    return SectionCard(
      label: Lang.get('screens.labels.preview_group'),
      children: [
        WText(
          Lang.get('screens.labels.subtitle_loading'),
          className: 'text-sm text-fg-muted',
        ),
      ],
    );
  }

  /// The sheet, which moves to the left column on a wide window.
  ///
  /// `lg:order-first` rather than a reordered children list: the reading order on a phone
  /// is decide-then-check, and on a desktop the artifact sits beside the controls that
  /// change it so a template switch is visible without scrolling.
  Widget _buildPreview(SheetTemplate template) {
    final int sheets = _sheetsFor(template);

    return WDiv(
      className: 'w-full lg:flex-1 lg:order-first',
      child: SectionCard(
        label: Lang.get('screens.labels.preview_group'),
        count: template.label,
        children: [
          LabelPreview(
            template: template,
            url: _controller?.previewUrl,
            isLoading: _controller?.rendering ?? false,
            caption: _pending == 0
                ? Lang.get('screens.labels.preview_nothing')
                : sheets == 1
                    ? Lang.get('screens.labels.preview_one_sheet', {
                        'used': _lastSheetFill(template),
                        'total': template.perSheet,
                      })
                    : Lang.get('screens.labels.preview_sheets', {
                        'sheets': plural('screens.labels.sheet_count', sheets, {'count': sheets}),
                        // **The fill is a count too, and it disagreed at the common case.** The value
                        // read ":used labels on the last", so 25 labels on the 24-up sheet rendered
                        // "2 sheets · 1 labels on the last": one left over is what `pending % perSheet`
                        // gives most of the time. It was added to `localization_test`'s debt list in
                        // the same commit that widened the guard to catch this exact shape.
                        'used': plural(
                          'screens.labels.label_count',
                          _lastSheetFill(template),
                          {'count': _lastSheetFill(template)},
                        ),
                      }),
          ),
        ],
      ),
    );
  }

  /// What to print and how it is laid out. The two ways out are pinned, so they are not here.
  Widget _buildControls(SheetTemplate template) {
    return WDiv(
      className: 'flex flex-col gap-4 w-full lg:flex-1',
      children: [
        _buildItems(),
        _buildLayout(template),
      ],
    );
  }

  /// The batch. Printed lines stay, because criterion 5 makes it resumable.
  Widget _buildItems() {
    final PrintBatch? batch = _batch;
    final List<PrintBatchLine> lines = batch?.lines ?? const <PrintBatchLine>[];

    return SectionCard(
      label: Lang.get('screens.labels.what_group'),
      count: plural('screens.labels.label_count', _pending, {'count': _pending}),
      children: [
        if (lines.isEmpty)
          WText(Lang.get('screens.labels.nothing_yet'), className: 'text-sm text-fg-muted'),
        for (final PrintBatchLine line in lines)
          WDiv(
            className: 'flex flex-row items-center gap-2',
            children: [
              WDiv(
                className: 'flex-1 min-w-0',
                child: LabelItemRow(
                  name: line.name,
                  code: line.serial ?? line.code,
                  count: line.count,
                  mode: line.mode,
                  isPrinted: line.isPrinted,
                  onDecrement: line.isAdjustable && line.count > 1
                      ? () => unawaited(_controller?.setCopies(line.position, line.count - 1) ?? Future<void>.value())
                      : null,
                  onIncrement: line.isAdjustable
                      ? () => unawaited(_controller?.setCopies(line.position, line.count + 1) ?? Future<void>.value())
                      : null,
                ),
              ),
              // **The way out of a batch a user did not mean to be in.** Opening this screen from a
              // product adds it to the batch already open, which is what a batch is for; without a
              // per-line removal that default is a trap. A printed line has no remove control at all,
              // because it is a record of paper that already went.
              //
              // **The box is INSIDE the anchor, and having it outside made the target the icon.**
              // `WAnchor` takes no `className`: it wraps its child in a translucent `GestureDetector`,
              // so the hit region is whatever the child measures. With the 32px box as its parent that
              // was a `size-4` icon, 16 logical px, against DESIGN.md's 44. `QuantityStepper` puts the
              // padded box inside for the same reason.
              WDiv(
                className: 'size-11 shrink-0 flex items-center justify-center',
                child: line.isPrinted
                    ? null
                    : WAnchor(
                        onTap: () => unawaited(
                          _controller?.removeLine(line.position) ?? Future<void>.value(),
                        ),
                        semanticLabel: Lang.get('screens.labels.remove_line', {'name': line.name}),
                        child: const WDiv(
                          className: 'size-11 flex items-center justify-center',
                          child: WIcon(LabelPrintView._removeIcon, className: 'size-4 text-fg-muted'),
                        ),
                      ),
              ),
            ],
          ),
        if (batch != null && batch.printed.isNotEmpty)
          WText(
            plural('screens.labels.already_printed', batch.printed.length, {
              'count': batch.printed.length,
            }),
            className: 'text-xs text-fg-muted',
          ),
      ],
    );
  }

  /// Sheet, fields, and the proof of what they produce.
  Widget _buildLayout(SheetTemplate chosen) {
    final PrintBatch? batch = _batch;
    final List<String> unscannable = _unscannable;

    return SectionCard(
      label: Lang.get('screens.labels.layout_group'),
      children: [
        for (final SheetTemplate template in _templates)
          _templateRow(template, template.key == chosen.key),
        WDiv(
          className: 'flex flex-row wrap items-center gap-2 pt-1',
          children: [
            // **These chips were inert and the screen said so.** The comment recorded that nothing
            // consumed a field selection, because the preview drew a fill diagram rather than a
            // label's contents, so wiring the toggle would have changed the chip and left the output
            // identical. The server's template consumes `fields` now and the preview IS its output,
            // so a toggle changes the picture. The recorded design question is answered.
            for (final MapEntry<String, String> field in _fields.entries)
              FilterChip(
                label: field.value,
                applied: batch?.shows(field.key) ?? false,
                // The default announcement is about a FILTER, and these chips filter nothing: they
                // choose what the sticker carries. A screen reader said "Apply the Team name filter"
                // until this line existed.
                //
                // **Two whole calls rather than one call with the key chosen inside it.**
                // `lang_keys_exist_test` matches a quoted literal straight after `Lang.get(`, so a
                // ternary in that position hid both keys from the only gate that can see a key nobody
                // translated. Seventy lines down `_fields` lectures about exactly this and I did it
                // here anyway.
                semanticLabel: (batch?.shows(field.key) ?? false)
                    ? Lang.get('screens.labels.field_off', {'field': field.value})
                    : Lang.get('screens.labels.field_on', {'field': field.value}),
                onTap: () => unawaited(
                  _controller?.toggleField(field.key) ?? Future<void>.value(),
                ),
              ),
          ],
        ),
        WDiv(
          // `items-start`, never `items-stretch`. A Row inside a scrolling Column has no
          // height of its own, and stretch asks its children to match a height that does
          // not exist yet.
          className: 'flex flex-row items-start gap-3 pt-2',
          children: [
            WDiv(
              // The width tracks the label so two templates read as different sizes. It is NOT the
              // label's aspect ratio: the sheet is the dimensional proof and this is the content
              // proof, which is why they are two views rather than one zoomable one.
              className: chosen.labelHeightMm < 30 ? 'w-40 axis-min' : 'w-56 axis-min',
              child: LabelCard(
                name: _sampleLine?.name ?? Lang.get('screens.labels.nothing_yet'),
                meta: null,
                // The code the server says will be printed. It used to fall back to a literal
                // `DPL00000000`, which the copy beside it calls "real content": the resource was not
                // sending the field at all, so every product line showed the same invented string.
                code: _sampleLine?.serial ?? _sampleLine?.code ?? '',
                overflowField: unscannable.isEmpty ? null : Lang.get('screens.labels.field_code'),
                size: chosen.labelHeightMm < 30 ? LabelCardSize.sm : LabelCardSize.md,
              ),
            ),
            WText(
              Lang.get('screens.labels.sample_label'),
              className: 'text-xs text-fg-muted flex-auto min-w-0',
            ),
          ],
        ),
        if (unscannable.isNotEmpty)
          Callout(
            intent: CalloutIntent.danger,
            title: Lang.get('screens.labels.overflow', {
              'field': Lang.get('screens.labels.field_code'),
            }),
            message: Lang.get('screens.labels.overflow_note', {
              'width': chosen.labelWidthMm,
              'height': chosen.labelHeightMm,
              'codes': unscannable.join(', '),
              // Inflected rather than interpolated raw. No template in the catalogue holds one
              // character, so ":max characters" never actually rendered wrong, but it joined the
              // debt list whose own contract is that nothing new joins it.
              'chars': plural(
                'screens.labels.char_count',
                chosen.maxCodeLength ?? 0,
                {'count': chosen.maxCodeLength ?? 0},
              ),
            }),
          ),
      ],
    );
  }

  /// The first pending line, which is what the sample label stands for.
  PrintBatchLine? get _sampleLine {
    for (final PrintBatchLine line in _batch?.lines ?? const <PrintBatchLine>[]) {
      if (!line.isPrinted) return line;
    }

    return null;
  }

  /// The fields a label may carry, keyed by the server's vocabulary and valued by our copy.
  ///
  /// **Written out rather than assembled into `Lang.get('...field_$key')`**, because an interpolated key
  /// is the one thing neither copy gate can see: `no_hardcoded_copy_test` finds no literal and
  /// `localization_test` compares the catalogues against each other, so a missing one renders
  /// `screens.labels.field_team` at the user. `flutter-app.md` names this exactly and I did it anyway.
  ///
  /// `location` is deliberately absent: a product's stock sits in several places at once, so choosing
  /// one belongs to a batch and the endpoint's vocabulary refuses it for now.
  Map<String, String> get _fields => <String, String>{
    'name': Lang.get('screens.labels.field_name'),
    'code': Lang.get('screens.labels.field_code'),
    'team': Lang.get('screens.labels.field_team'),
  };

  /// One sheet option. Every option carries a fill so the group reads as a set of choices.
  Widget _templateRow(SheetTemplate template, bool isSelected) {
    return OptionRow(
      label: template.label,
      isSelected: isSelected,
      semanticLabel: Lang.get('screens.labels.pick_layout', {'label': template.label}),
      onTap: () => unawaited(_controller?.setTemplate(template.key) ?? Future<void>.value()),
      // Pages and waste together. Pages alone would show 24-up and 65-up as one sheet each and hide
      // that one prints 3 blanks and the other 44, which is the whole difference between them.
      trailing: WText(
        Lang.get('screens.labels.layout_meta', {
          'sheets': plural('screens.labels.sheet_count', _sheetsFor(template), {
            'count': _sheetsFor(template),
          }),
          'wasted': _wastedCells(template),
        }),
        className: 'font-mono text-xs text-fg-muted',
      ),
    );
  }

  /// Print, or take the file away.
  ///
  /// The PDF path is not a fallback bolted on: a user with no printer at hand still gets
  /// something, and on web it is frequently the whole flow.
  Widget _buildActions(SheetTemplate template) {
    final bool busy = _controller?.working ?? false;
    final bool hasSomething = _pending > 0;
    final String? failure = _controller?.error;

    return WDiv(
      className: 'flex flex-col gap-2 pb-2',
      children: [
        if (failure != null)
          Callout(
            intent: CalloutIntent.danger,
            title: Lang.get('screens.labels.failed'),
            message: failure,
          ),
        WText(
          hasSomething
              ? Lang.get('screens.labels.submit_note', {
                  'labels': plural('screens.labels.label_count', _pending, {'count': _pending}),
                  'sheets': plural('screens.labels.sheet_count', _sheetsFor(template), {
                    'count': _sheetsFor(template),
                  }),
                })
              : Lang.get('screens.labels.nothing_to_print'),
          className: 'text-sm text-fg-muted',
        ),
        MSButton(
          onPressed: hasSomething && !busy ? () => unawaited(_print()) : null,
          disabled: !hasSomething || busy,
          intent: hasSomething ? ButtonIntent.primary : ButtonIntent.secondary,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(LabelPrintView._printIcon, className: 'size-4'),
              WText(Lang.get('screens.labels.submit')),
            ],
          ),
        ),
        MSButton(
          onPressed: hasSomething && !busy ? () => unawaited(_open()) : null,
          disabled: !hasSomething || busy,
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: WDiv(
            className: 'flex flex-row items-center justify-center gap-2',
            children: [
              const WIcon(LabelPrintView._pdfIcon, className: 'size-4'),
              WText(Lang.get('screens.labels.download')),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the sheet, then ASKS whether it printed before recording that it did.
  ///
  /// **The client does not know either, and settling on "the file opened" was the same lie one layer
  /// up.** `Launch.url` answers true when a tab opened or the system viewer launched, so closing that
  /// tab without printing marked the whole batch and there is no un-settle. Moving the mark from the
  /// server to the client did not fix that; it moved it to something equally uninformed.
  ///
  /// So the only party who knows is asked. It is also what a jammed printer needs: the user says no,
  /// nothing is marked, and the same sheet is still there to try again.
  Future<void> _print() async {
    if (!await _open()) return;

    if (!mounted) return;

    await MagicStarterConfirmDialog.show(
      context,
      title: Lang.get('screens.labels.confirm_title'),
      description: Lang.get('screens.labels.confirm_description'),
      confirmLabel: Lang.get('screens.labels.confirm_yes'),
      onConfirm: _recordPrinted,
    );
  }

  /// Records that the sheet came off a printer.
  Future<void> _recordPrinted() async {
    final String? failure = await _controller?.settle();

    if (!mounted) return;

    if (failure != null) {
      MagicFeedback.error(Lang.get('screens.labels.title'), failure);

      return;
    }

    MagicFeedback.success(
      Lang.get('screens.labels.title'),
      Lang.get('screens.labels.printed'),
    );
  }

  /// Opens the rendered PDF, which is where printing, saving and sending all already live.
  Future<bool> _open() async {
    final String? url = await _controller?.pdfUrl();

    if (url == null) return false;

    // Through magic's own `Launch` facade rather than `url_launcher` directly: the package arrives
    // transitively, so importing it would trip `depend_on_referenced_packages`, and the facade is the
    // registered idiom (`LaunchServiceProvider` is already in `lib/config/app.dart`). It returns false
    // on failure and never throws.
    //
    // `externalApplication`: on web this is a tab and on mobile the system viewer with its own share
    // sheet, which is what `labeling-and-printing.md` asks for rather than an in-app PDF renderer
    // nobody asked us to build.
    final bool opened = await Launch.url(url, mode: LaunchMode.externalApplication);

    // **A refusal here was the one silent failure left on this screen.** `pdfUrl` succeeded, so
    // `_controller.error` is null and the callout above the buttons stays empty; the sheet rendered,
    // the tab never opened, and both buttons looked like they had done nothing at all. A pop-up
    // blocker on web and a desktop with no PDF handler are both this path.
    if (!opened && mounted) {
      MagicFeedback.error(
        Lang.get('screens.labels.title'),
        Lang.get('screens.labels.open_failed'),
      );
    }

    return opened;
  }
}
