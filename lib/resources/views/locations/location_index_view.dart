import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_starter/magic_starter.dart'
    show MSPageScaffold, MSButton, ButtonIntent, MSSegmentedControl, MSEmptyState;

import '../../../ui/components/location_row/location_row.dart';
import '../../../ui/components/section_card/section_card.dart';

/// How much the app decides about placement on its own.
///
/// `location-assignment.md`'s dial, verbatim. The names are its names so no translation
/// layer is needed between the setting and the behaviour it controls.
enum PlacementAutomation {
  /// The user always picks. Nothing is proposed.
  manual,

  /// A location is proposed with a visible reason. The user confirms or overrides.
  semiAuto,

  /// The location is assigned without asking. Undoable, and in the activity feed.
  fullAuto,
}

/// One node in the fixture tree.
@immutable
class LocationNode {
  /// The location's own name.
  final String name;

  /// Depth, 0 for a root.
  final int depth;

  /// Products in the subtree.
  final int productCount;

  /// The already-formatted contents line.
  final String summary;

  /// An optional leading icon, for a root.
  final IconData? icon;

  /// Creates a [LocationNode].
  const LocationNode({
    required this.name,
    required this.depth,
    required this.productCount,
    required this.summary,
    this.icon,
  });
}

/// The location hierarchy: where a tenant keeps things.
///
/// **Nothing in the app showed this tree until now**, even though every screen assumed
/// it: the product detail lists stock per location, the filter offers locations as chips,
/// the stock-in sheet suggests one. All of them presented a flat set of paths, so the
/// structure the schema maintains (`parent_location_id`, a materialised `path`, a depth
/// capped at 6) existed nowhere a user could see or edit it.
///
/// ### The automation dial lives here, not in settings
///
/// `location-assignment.md` makes placement automation a user-set dial. It belongs on this
/// screen rather than buried in preferences, because the thing it automates is exactly
/// what this screen is about, and because the dial is only meaningful once the user has a
/// tree for it to choose from.
///
/// **Full-auto is gated on a measured reversion rate, not a predicted confidence.** The
/// doc is explicit: if the tenant's corrections exceed the threshold the action drops back
/// to semi-auto and the user is told why. So the dial is a request, not a guarantee, and
/// the screen says so rather than implying the setting is the last word.
@immutable
class LocationIndexView extends StatelessWidget {
  static const IconData _addIcon = Icons.add_outlined;
  static const IconData _emptyIcon = Icons.location_on_outlined;

  static const List<PlacementAutomation> _dial = PlacementAutomation.values;

  /// Whether the tenant has no locations yet.
  final bool isEmpty;

  /// Where the dial currently sits.
  final PlacementAutomation automation;

  /// Creates the [LocationIndexView].
  const LocationIndexView({super.key}) : isEmpty = false, automation = PlacementAutomation.semiAuto;

  /// Creates the view for a tenant with no locations yet.
  const LocationIndexView.empty({super.key})
    : isEmpty = true,
      automation = PlacementAutomation.semiAuto;

  /// The tree, flattened in reading order with its depths.
  ///
  /// Flat plus a depth rather than nested children, because that is what the screen
  /// renders and what a materialised `path` gives cheaply. Nesting the fixture would model
  /// the database and complicate the view for no gain.
  static const List<LocationNode> _tree = <LocationNode>[
    LocationNode(
      name: 'Mutfak',
      depth: 0,
      productCount: 5,
      summary: '5 ürün · 2 alt konum',
      icon: Icons.kitchen_outlined,
    ),
    LocationNode(name: 'Buzdolabı', depth: 1, productCount: 3, summary: '3 ürün'),
    LocationNode(name: 'Derin dondurucu', depth: 1, productCount: 1, summary: '1 ürün'),
    LocationNode(
      name: 'Kiler',
      depth: 0,
      productCount: 4,
      summary: '4 ürün · 3 alt konum',
      icon: Icons.shelves,
    ),
    LocationNode(name: 'Raf 1', depth: 1, productCount: 1, summary: '1 ürün'),
    LocationNode(name: 'Raf 2', depth: 1, productCount: 2, summary: '2 ürün'),
    LocationNode(name: 'Çekmece 2', depth: 1, productCount: 1, summary: '1 ürün'),
    LocationNode(
      name: 'Depo',
      depth: 0,
      productCount: 2,
      summary: '2 ürün · 1 alt konum',
      icon: Icons.warehouse_outlined,
    ),
    LocationNode(name: 'Raf A', depth: 1, productCount: 2, summary: '2 ürün'),
    LocationNode(name: 'Raf B', depth: 1, productCount: 0, summary: 'Boş'),
  ];

  /// The already-localised label for a dial position.
  static String _dialLabel(PlacementAutomation value) => switch (value) {
    PlacementAutomation.manual => 'Elle',
    PlacementAutomation.semiAuto => 'Önerili',
    PlacementAutomation.fullAuto => 'Otomatik',
  };

  /// What the current dial position actually does, in one line.
  ///
  /// Stated rather than left to the label, because "Otomatik" alone does not tell a user
  /// that a placement will happen without asking, and that is the part they would want to
  /// know before choosing it.
  String get _dialExplanation => switch (automation) {
    PlacementAutomation.manual => 'Konumu her zaman siz seçersiniz, öneri gösterilmez.',
    PlacementAutomation.semiAuto => 'Konum gerekçesiyle önerilir, onaylanır ya da değiştirilir.',
    PlacementAutomation.fullAuto =>
      'Konum sorulmadan atanır. Geri alınabilir ve hareket geçmişine yazılır. '
          'Düzeltme oranı yükselirse otomatik olarak Önerili moda düşer.',
  };

  @override
  Widget build(BuildContext context) {
    final int roots = _tree.where((n) => n.depth == 0).length;

    return MSPageScaffold(
      title: 'Konumlar',
      subtitle: isEmpty ? null : '${_tree.length} konum · $roots ana konum',
      actions: [
        MSButton(
          onPressed: () {},
          className: 'min-h-11 min-w-11 justify-center',
          semanticLabel: 'Konum ekle',
          child: const WIcon(_addIcon),
        ),
      ],
      children: [
        if (isEmpty) _buildEmpty() else ...[_buildTree(), _buildAutomation()],
      ],
    );
  }

  /// The tree itself, in reading order.
  Widget _buildTree() {
    return SectionCard(
      label: 'Yerleşim',
      count: '${_tree.length} konum',
      children: [
        for (final LocationNode node in _tree)
          LocationRow(
            name: node.name,
            depth: node.depth,
            productCount: node.productCount,
            itemSummary: node.summary,
            icon: node.icon,
            onTap: () {},
          ),
      ],
    );
  }

  /// The placement dial, with what it does spelled out.
  Widget _buildAutomation() {
    return SectionCard(
      label: 'Yerleştirme',
      children: [
        WDiv(
          className: 'flex flex-col gap-2 py-1',
          children: [
            MSSegmentedControl<PlacementAutomation>(
              options: _dial.map(_dialLabel).toList(),
              selectedIndex: _dial.indexOf(automation),
              onChanged: (_) {},
            ),
            WText(_dialExplanation, className: 'text-xs text-fg-muted'),
          ],
        ),
      ],
    );
  }

  /// The first-run state, which is where every tenant starts.
  ///
  /// A tenant with no locations cannot receive stock anywhere, so this is not a decorative
  /// empty state: it is a blocker with one way out. The two suggested starting points are
  /// the ones `location-assignment.md`'s scenario is written around.
  Widget _buildEmpty() {
    return WDiv(
      className: 'flex flex-col gap-3 p-4 rounded-lg bg-surface-container',
      children: [
        WDiv(
          className: 'w-full',
          child: MSEmptyState(
            icon: _emptyIcon,
            title: 'Henüz konum yok',
            description:
                'Stok bir konuma girer, o yüzden en az bir konum gerekir. '
                'Mutfak ve Kiler gibi ana konumlarla başlanır, rafları sonra eklenir.',
          ),
        ),
        MSButton(
          onPressed: () {},
          fullWidth: true,
          className: 'justify-center',
          child: const WText('Konum ekle'),
        ),
        MSButton(
          onPressed: () {},
          intent: ButtonIntent.ghost,
          fullWidth: true,
          className: 'justify-center',
          child: const WText('Hazır şablonla başla'),
        ),
      ],
    );
  }
}
