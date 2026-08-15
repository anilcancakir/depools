import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/support/icon_catalogue.dart';
import 'icon_picker.dart';

/// A catalogue that answers from memory, so the preview needs no server.
///
/// **The svgs are the real vendored ones**, copied out of `catalogue.ndjson` rather than written by
/// hand. A stub rectangle would let a broken `srcIn` filter or a mishandled viewBox pass review, and
/// that is precisely what this component has to be reviewed for: Material Symbols draws on a
/// `0 -960 960 960` box, not the `0 0 24 24` anyone sketching an outline would reach for. Writing
/// three of them from memory produced a `warehouse` that was not the real path, which is the reason
/// this note exists.
class _StubCatalogue extends IconCatalogue {
  static const List<CatalogueIcon> _icons = <CatalogueIcon>[
    CatalogueIcon(
      name: 'kitchen',
      title: 'Kitchen',
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="M32'
          '0-640v-120h80v120h-80Zm0 360v-200h80v200h-80ZM240-80q-33 0-56.5-23.5T160-160v-640q0-33 23.5-56.5T240'
          '-880h480q33 0 56.5 23.5T800-800v640q0 33-23.5 56.5T720-80H240Zm0-80h480v-360H240v360Zm0-440h480v-200'
          'H240v200Z"/></svg>',
    ),
    CatalogueIcon(
      name: 'warehouse',
      title: 'Warehouse',
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="M16'
          '0-200h80v-320h480v320h80v-426L480-754 160-626v426Zm-80 80v-560l400-160 400 160v560H640v-320H320v320H'
          '80Zm280 0v-80h80v80h-80Zm80-120v-80h80v80h-80Zm80 120v-80h80v80h-80ZM240-520h480-480Z"/></svg>',
    ),
    CatalogueIcon(
      name: 'ac_unit',
      title: 'Ac unit',
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="M44'
          '0-80v-166L310-118l-56-56 186-186v-80h-80L174-254l-56-56 128-130H80v-80h166L118-650l56-56 186 186h80v'
          '-80L254-786l56-56 130 128v-166h80v166l130-128 56 56-186 186v80h80l186-186 56 56-128 130h166v80H714l1'
          '28 130-56 56-186-186h-80v80l186 186-56 56-130-128v166h-80Z"/></svg>',
    ),
    CatalogueIcon(
      name: 'shelves',
      title: 'Shelves',
      svg:
          '<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24"><path d="M12'
          '0-40v-880h80v80h560v-80h80v880h-80v-80H200v80h-80Zm80-480h80v-160h240v160h240v-240H200v240Zm0 320h24'
          '0v-160h240v160h80v-240H200v240Zm160-320h80v-80h-80v80Zm160 320h80v-80h-80v80ZM360-520h80-80Zm160 320'
          'h80-80Z"/></svg>',
    ),
  ];

  /// The query the empty state is reachable with, so the preview can show it.
  static const String noMatch = 'zzz';

  _StubCatalogue() {
    for (final CatalogueIcon icon in _icons) {
      remember(icon);
    }
  }

  @override
  Future<List<CatalogueIcon>> search(String query) async =>
      query == noMatch ? const <CatalogueIcon>[] : _icons;
}

/// Static variant-matrix preview for [IconPicker].
///
/// Two states that a static preview can hold still: results with nothing chosen, and results with
/// one chosen. The loading and empty states depend on a query, so they are reachable by typing in
/// the field rather than rendered as their own tile: `zzz` returns nothing from this stub.
///
/// What to check here is the glyph itself. These are svgs recoloured through a `srcIn` filter, not
/// font glyphs, so they are the one place in this app where a wrong viewBox or a lost tint shows up
/// as a blank tile rather than as a compile error.
class IconPickerPreview extends StatelessWidget {
  /// A tear-off rather than a closure, so the `const` in this file survives.
  static void _noop(String name) {}

  /// Creates the IconPicker preview.
  const IconPickerPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            const WText('Sonuclar, hicbiri secili degil', className: 'text-xs text-fg-muted'),
            IconPicker(
              onSelected: _noop,
              searchPlaceholder: 'Ikon arayin',
              searchingLabel: 'Araniyor',
              emptyLabel: 'Eslesen ikon yok',
              catalogue: _StubCatalogue(),
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            const WText('Biri secili', className: 'text-xs text-fg-muted'),
            IconPicker(
              selected: 'warehouse',
              onSelected: _noop,
              searchPlaceholder: 'Ikon arayin',
              searchingLabel: 'Araniyor',
              emptyLabel: 'Eslesen ikon yok',
              catalogue: _StubCatalogue(),
            ),
          ],
        ),
      ],
    );
  }
}
