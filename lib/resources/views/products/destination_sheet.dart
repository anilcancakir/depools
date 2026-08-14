import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart' show MSInput;

import '../../../ui/components/option_row/option_row.dart';

/// One location, as this sheet needs it.
@immutable
class DestinationOption {
  /// The stored value.
  final String id;

  /// The location's own name: the leaf, without its ancestors.
  final String name;

  /// The full hierarchy, `Depo › Raf A`.
  final String fullPath;

  /// How deep it sits. Never above six (invariant 7).
  final int depth;

  /// How many products the subtree holds, so an empty shelf can say so.
  final int productCount;

  /// Creates a [DestinationOption].
  const DestinationOption({
    required this.id,
    required this.name,
    required this.fullPath,
    required this.depth,
    this.productCount = 0,
  });

  /// The ancestors, without the leaf: `Depo` for `Depo › Raf A`.
  ///
  /// Null at the root, where there is nothing above to show and an empty line would leave a hole in
  /// every top-level row.
  String? get parentPath {
    final int cut = fullPath.lastIndexOf(' › ');

    return cut <= 0 ? null : fullPath.substring(0, cut);
  }
}

/// Picking where a scan batch goes, out of a hierarchy that can be a thousand nodes and six deep.
///
/// **Two sections, because a receiving bench and a stranger to the catalogue need different things.**
///
/// 1. **Recent destinations**, from the ledger's last `purchase` movements. A bench has two or three
///    places, so this is one tap and it is the ordinary case. The alternative costs the frequent case
///    to serve the rare one: walking six levels to reach a shelf chosen an hour ago.
/// 2. **Everything, searchable** over the name AND the full path, so `raf a` finds `Depo › Raf A`.
///    The materialised path is already on every row and a thousand rows filter in microseconds on the
///    client, so this needs no endpoint of its own.
///
/// **The hierarchy is carried by the LABEL, not by indentation, and that is a picker decision rather
/// than a shortcut.** `LocationRow` renders an indented tree and has no selected state, which a
/// picker cannot do without; `OptionRow` is the picker row this app already uses for locations in the
/// move sheet and the count screen. So each row is the leaf name with its ancestors beneath it, which
/// is the same trade `LocationRow`'s own docblock records for the search screen: "there the tree is
/// absent, so the path is the only context". Indentation would also break the moment a search matched
/// a leaf six levels down and rendered six levels of nothing above it.
///
/// **Not read while designing this**, and said plainly rather than implied: Apple's lists-and-tables
/// page and Material's lists guidance are both JavaScript-only and the rendering fetch timed out, so
/// this rests on the repo's own canon and on the measured data shape rather than on a citation.
@immutable
class DestinationSheet extends StatefulWidget {
  /// Every location the tenant has, flattened in reading order.
  final List<DestinationOption> options;

  /// The recent destinations, newest first, as ids.
  final List<String> recentIds;

  /// The destination currently chosen, when there is one.
  final String? selectedId;

  /// Creates the [DestinationSheet].
  const DestinationSheet({
    required this.options,
    required this.recentIds,
    this.selectedId,
    super.key,
  });

  @override
  State<DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends State<DestinationSheet> {
  static const IconData _searchIcon = Icons.search_outlined;
  static const IconData _noMatchIcon = Icons.search_off_outlined;

  /// Below this many locations the search field is noise: the whole list fits in a thumb's scroll.
  ///
  /// Ten is deliberately low. The field costs one row when it is not needed and costs the entire
  /// feature when it is missing, so the threshold errs toward showing it.
  static const int _searchThreshold = 10;

  final TextEditingController _query = TextEditingController();

  String _term = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The recent options, in the order the ledger gave them, skipping any that no longer exist.
  ///
  /// A location can be deleted between a batch starting and this sheet opening, and a recent row
  /// pointing at nothing would write stock into a location the tenant cannot see.
  List<DestinationOption> get _recents {
    final List<DestinationOption> found = <DestinationOption>[];

    for (final String id in widget.recentIds) {
      for (final DestinationOption option in widget.options) {
        if (option.id == id) {
          found.add(option);
          break;
        }
      }
    }

    return found;
  }

  /// Matches on the name AND the full path, folded.
  ///
  /// The fold is `toLowerCase` and nothing more, which is honest about its limit: it does not strip
  /// diacritics, so `sut` will not find `Süt`. The server holds an ASCII fold for exactly that job,
  /// and this list never leaves the client, so matching it here would mean shipping a second
  /// implementation of it. Named rather than left as a surprise.
  List<DestinationOption> get _matches {
    if (_term.isEmpty) return widget.options;

    final String needle = _term.toLowerCase();

    return widget.options
        .where(
          (DestinationOption o) =>
              o.name.toLowerCase().contains(needle) ||
              o.fullPath.toLowerCase().contains(needle),
        )
        .toList();
  }

  Widget _row(DestinationOption option) {
    return OptionRow(
      label: option.name,
      // The ancestors, so two shelves called `Raf A` under different rooms are tellable apart. This
      // is the whole reason a picker over a hierarchy cannot show leaf names alone.
      description: option.parentPath,
      isSelected: option.id == widget.selectedId,
      semanticLabel: option.id == widget.selectedId
          ? Lang.get('components.destination_sheet.current', {'path': option.fullPath})
          : Lang.get('components.destination_sheet.pick', {'path': option.fullPath}),
      onTap: () => Navigator.of(context).pop(option.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DestinationOption> recents = _recents;
    final List<DestinationOption> matches = _matches;
    final bool searching = _term.isNotEmpty;

    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        // **Hidden while searching**, because a result list interrupted by suggestions for something
        // else is two answers to one question.
        if (recents.isNotEmpty && !searching) ...[
          WText(
            Lang.get('components.destination_sheet.recent_group'),
            className: 'text-xs font-medium text-fg-muted',
          ),
          for (final DestinationOption option in recents) _row(option),
          WText(
            Lang.get('components.destination_sheet.all_group'),
            className: 'text-xs font-medium text-fg-muted pt-2',
          ),
        ],
        if (widget.options.length >= _searchThreshold)
          MSInput(
            // The input tone is right here: a sheet's own surface is the page-like one, so `-high`
            // reads as a recessed well rather than as the disabled control it looks like on a card.
            className: 'bg-surface-container-high',
            placeholder: Lang.get('components.destination_sheet.search'),
            prefix: const WIcon(_searchIcon, className: 'size-4 text-fg-muted'),
            controller: _query,
            onChanged: (String value) => setState(() => _term = value.trim()),
          ),
        if (matches.isEmpty)
          WDiv(
            className: 'flex flex-col items-center gap-2 py-6',
            children: [
              const WIcon(_noMatchIcon, className: 'size-8 text-fg-disabled'),
              WText(
                Lang.get('components.destination_sheet.no_match'),
                className: 'text-sm text-fg-muted',
              ),
            ],
          )
        else
          for (final DestinationOption option in matches) _row(option),
      ],
    );
  }
}
