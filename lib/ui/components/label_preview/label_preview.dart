import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'label_preview.recipe.dart';

/// One entry from the label size and page catalog, in millimetres.
///
/// **The catalogue is the SERVER's**, fetched from `labels/templates`, and this is the shape the
/// preview needs to draw a page at its real proportion. It used to say the catalogue was "ported from
/// the MVP's `config/labels.php`"; that file is not reachable (both MVP checkouts are gone from disk),
/// so `config/labels.php` on this backend was authored against A4 arithmetic instead.
@immutable
class SheetTemplate {
  /// The key `print_batches.template` stores, for example `a4_8_up_105x70`.
  ///
  /// Empty on a fixture, because a preview has no server to name one.
  final String key;

  /// The human name, for example `A4 · 8'li · 105×70 mm`.
  final String label;

  /// Page width in millimetres.
  final int pageWidthMm;

  /// Page height in millimetres.
  final int pageHeightMm;

  /// Labels across.
  final int columns;

  /// Labels down.
  final int rows;

  /// One label's width in millimetres.
  final int labelWidthMm;

  /// One label's height in millimetres.
  final int labelHeightMm;

  /// The longest Code 128 payload this label can print at a scannable density.
  ///
  /// The server's own arithmetic, because it owns the encoder: a Code 128 set B symbol is
  /// `11(n + 2) + 13` modules plus 20 of quiet zone, and GS1's absolute floor is a 0.250 mm module. A
  /// 38 mm label holds seven characters. Null on a fixture, where there is nothing to compare against.
  final int? maxCodeLength;

  /// Creates a [SheetTemplate].
  const SheetTemplate({
    required this.label,
    this.key = '',
    this.maxCodeLength,
    required this.pageWidthMm,
    required this.pageHeightMm,
    required this.columns,
    required this.rows,
    required this.labelWidthMm,
    required this.labelHeightMm,
  });

  /// Labels per sheet.
  int get perSheet => columns * rows;

  /// The horizontal margin the grid leaves, halved, in millimetres.
  int get sideMarginMm => (pageWidthMm - columns * labelWidthMm) ~/ 2;

  /// The vertical margin the grid leaves, halved, in millimetres.
  int get topMarginMm => (pageHeightMm - rows * labelHeightMm) ~/ 2;

  /// The template a `labels/templates` entry describes.
  ///
  /// Parsed here rather than in a controller because this is the type the PREVIEW needs, the same
  /// reason `DestinationOption` is fetched in its own view: a controller building a component's input
  /// shape would be the dependency pointing the wrong way.
  factory SheetTemplate.fromApi(Map<String, dynamic> json) {
    return SheetTemplate(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      pageWidthMm: _mm(json['page_width_mm']),
      pageHeightMm: _mm(json['page_height_mm']),
      columns: (json['columns'] as num?)?.toInt() ?? 1,
      rows: (json['rows'] as num?)?.toInt() ?? 1,
      labelWidthMm: _mm(json['label_width_mm']),
      labelHeightMm: _mm(json['label_height_mm']),
      maxCodeLength: (json['max_code_length'] as num?)?.toInt(),
    );
  }

  /// Millimetres as an int.
  ///
  /// The server stores them as `decimal` and PHP sends a whole float as an int, so `105.0` arrives as
  /// `105` and a fractional margin would arrive as a double. Floored rather than cast, because a
  /// `double` reaching an `int` field is a runtime type error rather than a rounding.
  static int _mm(Object? value) => value is num ? value.floor() : 0;
}

/// **LabelPreview**
///
/// The sheet a print will produce: the server's own render of it, at the page's real proportion.
///
/// ### It shows the render and draws nothing itself (D18, reversed)
///
/// The sheet is an HTML template rendered on the backend, so drawing an accurate page here would
/// mean re-implementing the renderer in order to preview it: two layouts of one thing, drifting
/// apart, which is exactly the duplication that reversing D18 exists to avoid. So [url] carries the
/// render and this component is the frame around it, which is what makes the preview and the print
/// one artefact by construction rather than by care.
///
/// **This heading used to say it drew a placeholder on purpose**, and the paragraph under it argued
/// against doing the thing [_buildPage] has done since the endpoint landed. Left alone it invites
/// the next reader to re-add a client-side renderer, which is the duplication above.
///
/// The proportion box is what is left when there is no render: a fixture, a first frame, an expired
/// link. The cell grid this used to draw inside it is gone rather than commented out, because it was
/// accurate about a layout that is no longer ours to decide, which makes it worse than absent. The
/// waste D43 asks about is carried as a figure per template on the screen instead.
@immutable
class LabelPreview extends StatelessWidget {
  /// Which sheet template, used for the page proportion and nothing else.
  final SheetTemplate template;

  /// An already-formatted line under the sheet, for example `21 etiket · 3 sayfa`.
  final String? caption;

  /// A signed url for the server's own rendered sheet, if it has been fetched.
  ///
  /// **This is the promise the docblock above has been making since D18 was reversed.** With it the
  /// preview and the print are the same artefact by construction rather than by care; without it this
  /// is still the proportion box, which is what a fixture and a first frame both have.
  ///
  /// A url rather than bytes, and that is the client's own limit rather than a preference: magic's
  /// `Http` facade has no binary response mode, so the app cannot fetch a PNG as bytes at all. The
  /// signature travels in the url, which is what `MediaUrl` already established for product
  /// photographs, and its expiry is rounded to the hour precisely so Flutter's url-keyed `ImageCache`
  /// keeps holding while the link still dies.
  final String? url;

  /// Whether the sheet is being fetched, which is a third state rather than an absent one.
  final bool isLoading;

  /// Creates a [LabelPreview].
  const LabelPreview({
    super.key,
    required this.template,
    this.caption,
    this.url,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final slots = labelPreviewRecipe()();

    return WDiv(
      className: slots['root'],
      children: [
        WDiv(
          className: slots['tray'],
          child: WDiv(
            className: slots['page'],
            child: AspectRatio(
              aspectRatio: template.pageWidthMm / template.pageHeightMm,
              // No `w-full h-full`: `AspectRatio` already hands this child tight constraints, and
              // wind resolves `h-full` against the ambient SCROLL scope rather than against the
              // nearest bounded parent, so it asserted by name inside the page's vertical scroll.
              // The rule is in `.claude/rules/design.md`; the component caught it before I did.
              child: _buildPage(),
            ),
          ),
        ),
        ?caption != null ? WText(caption!, className: slots['caption']) : null,
      ],
    );
  }

  /// What sits inside the page's proportion box.
  ///
  /// `BoxFit.contain` rather than `cover`: the sheet is a picture of paper, and cropping it would cut
  /// the labels at the page's edge, which are the ones worth seeing when the question is whether the
  /// grid lands where the sheet's own cells are. The proportions already agree, so `contain` costs
  /// nothing and survives a template whose page is not A4.
  ///
  /// This paragraph used to justify itself by D43 "drawing the diagram", which the class docblock
  /// above now says outright it does not.
  Widget _buildPage() {
    final String? source = url;

    if (source != null) {
      return Image.network(
        source,
        fit: BoxFit.contain,
        // The sheet is re-rendered on every change, so a frame of blank paper between two versions
        // reads as a flicker rather than as progress.
        gaplessPlayback: true,
        // A url that has expired or a render that vanished from the cache is not a crash: the
        // proportion box is still the honest thing to show, and the screen's own error line says why.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  /// The proportion box with nothing in it yet.
  Widget _buildPlaceholder() {
    return WDiv(
      className: 'flex items-center justify-center',
      child: WText(
        isLoading
            ? Lang.get('components.label_preview.rendering')
            : Lang.get('components.label_preview.placeholder'),
        className: 'text-xs text-fg-disabled',
      ),
    );
  }
}
