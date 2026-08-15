import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/icon_catalogue.dart';
import 'app_icon.dart';

/// A catalogue that answers from memory, so the preview needs no server.
///
/// The svg is the real vendored one, copied out of `catalogue.ndjson`. A stub rectangle would let a
/// broken `srcIn` filter or a mishandled viewBox pass review, and that is what this component has to
/// be reviewed for: Material Symbols draws on a `0 -960 960 960` box, not the `0 0 24 24` anyone
/// sketching an outline would reach for.
class _StubCatalogue extends IconCatalogue {
  static const CatalogueIcon _kitchen = CatalogueIcon(
    name: 'kitchen',
    title: 'Kitchen',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="M32'
        '0-640v-120h80v120h-80Zm0 360v-200h80v200h-80ZM240-80q-33 0-56.5-23.5T160-160v-640q0-33 23.5-56.5T240'
        '-880h480q33 0 56.5 23.5T800-800v640q0 33-23.5 56.5T720-80H240Zm0-80h480v-360H240v360Zm0-440h480v-200'
        'H240v200Z"/></svg>',
  );

  _StubCatalogue() {
    remember(_kitchen);
  }
}

/// Static variant-matrix preview for [AppIcon].
///
/// **Three states, and the two fallbacks are the point.** This component's whole promise is that it
/// never blocks and never fails: a null name, a name the catalogue has never heard of, and the frame
/// before an svg arrives all have to draw the same neutral glyph at the same size as a real one. A
/// tree row's leading box is never allowed to be absent or a different width, because a leading
/// glyph that changes size shifts the text beside it, which is what once made child locations appear
/// to the LEFT of their parents.
///
/// The sizes and tints are the ones real callers pass, so the row here is what the tree looks like.
class AppIconPreview extends StatelessWidget {
  /// Creates the AppIcon preview.
  const AppIconPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final IconCatalogue catalogue = _StubCatalogue();

    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            const WText(
              'Katalogdan gelen, adsiz, ve bilinmeyen ad',
              className: 'text-xs text-fg-muted',
            ),
            WDiv(
              className: 'flex flex-row items-center gap-4',
              children: [
                AppIcon(name: 'kitchen', className: 'size-5 text-fg', catalogue: catalogue),
                AppIcon(name: null, className: 'size-5 text-fg', catalogue: catalogue),
                AppIcon(name: 'not_a_real_glyph', className: 'size-5 text-fg', catalogue: catalogue),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            const WText('Konum tonlari', className: 'text-xs text-fg-muted'),
            WDiv(
              className: 'flex flex-row items-center gap-4',
              children: [
                AppIcon(
                  name: 'kitchen',
                  className: 'size-5 text-blue-location',
                  catalogue: catalogue,
                ),
                AppIcon(
                  name: 'kitchen',
                  className: 'size-5 text-green-location',
                  catalogue: catalogue,
                ),
                AppIcon(
                  name: 'kitchen',
                  className: 'size-5 text-red-location',
                  catalogue: catalogue,
                ),
                AppIcon(
                  name: 'kitchen',
                  className: 'size-5 text-violet-location',
                  catalogue: catalogue,
                ),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
          children: [
            const WText(
              'Boyutlar: gercek ve yedek yan yana, ayni kutuda',
              className: 'text-xs text-fg-muted',
            ),
            WDiv(
              className: 'flex flex-row items-center gap-4',
              children: [
                AppIcon(name: 'kitchen', className: 'size-4 text-fg', catalogue: catalogue),
                AppIcon(name: null, className: 'size-4 text-fg', catalogue: catalogue),
                AppIcon(name: 'kitchen', className: 'size-6 text-fg', catalogue: catalogue),
                AppIcon(name: null, className: 'size-6 text-fg', catalogue: catalogue),
                AppIcon(name: 'kitchen', className: 'size-8 text-fg', catalogue: catalogue),
                AppIcon(name: null, className: 'size-8 text-fg', catalogue: catalogue),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
