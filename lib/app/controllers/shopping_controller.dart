import 'package:magic/magic.dart';

import '../models/shopping_line.dart';
import '../support/mapped_or_null.dart';

/// The shopping list, from `api/v1/shopping`.
///
/// ### A tick is optimistic, and it has to be
///
/// The user is standing in a shop tapping down a list, and a round trip per tap would make the
/// screen feel like it is arguing with them. So the flag flips immediately and the request follows;
/// a failure puts it back and says so.
///
/// **The revert re-reads rather than flipping twice.** Flipping back locally assumes nothing else
/// changed in between, and something did in the case that matters: two taps in flight at once. A
/// refetch is the only answer that cannot leave the screen holding a state the server never had.
class ShoppingController extends MagicController with MagicStateMixin<List<ShoppingLine>> {
  /// The shared instance, keyed by type.
  static ShoppingController get instance => Magic.findOrPut(ShoppingController.new);

  bool _loaded = false;

  /// Every line, unticked first.
  List<ShoppingLine> get lines => rxState ?? const <ShoppingLine>[];

  /// Still to get.
  List<ShoppingLine> get pending =>
      lines.where((ShoppingLine l) => !l.isChecked).toList(growable: false);

  /// Already in the trolley. Not stock (D47).
  List<ShoppingLine> get checked =>
      lines.where((ShoppingLine l) => l.isChecked).toList(growable: false);

  /// Whether the server has answered at all, as opposed to answered with nothing.
  ///
  /// An empty list is the GOOD outcome here, which makes it the one wrong thing to say while the
  /// request is in flight.
  bool get loaded => _loaded;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// Fetch the list.
  Future<void> load() async {
    setLoading();

    final dynamic response = await Http.get('/shopping');

    if (!response.successful) {
      setError(response.message ?? Lang.get('screens.shopping.load_failed'));

      return;
    }

    final List<ShoppingLine>? rows = _parse(response['data']);

    if (rows == null) {
      setError(Lang.get('screens.shopping.load_failed'));

      return;
    }

    _loaded = true;

    setSuccess(rows);
  }

  /// Put a line in the trolley, or take it back out.
  ///
  /// Never a stock movement (D47). Stock arrives when the receipt is scanned or a stock-in is
  /// recorded, which is why the receipt action sits under the ticked group.
  Future<void> toggle(ShoppingLine line) async {
    _replace(line.toggled());

    final dynamic response = await Http.put(
      '/shopping/${line.id}',
      data: <String, dynamic>{'is_checked': !line.isChecked},
    );

    if (response.successful) return;

    setError(response.message ?? Lang.get('screens.shopping.save_failed'));

    // The server is the answer, not the inverse of the guess: a second tap may already be in
    // flight, and flipping back would leave the screen holding a state nobody ever had.
    await load();
  }

  /// Take a line off the list.
  Future<void> remove(ShoppingLine line) async {
    setSuccess(lines.where((ShoppingLine l) => l.id != line.id).toList(growable: false));

    final dynamic response = await Http.delete('/shopping/${line.id}');

    if (response.successful) return;

    setError(response.message ?? Lang.get('screens.shopping.save_failed'));

    await load();
  }

  /// Swap one line for its updated self, keeping the order.
  void _replace(ShoppingLine line) {
    setSuccess(<ShoppingLine>[
      for (final ShoppingLine held in lines)
        if (held.id == line.id) line else held,
    ]);
  }

  List<ShoppingLine>? _parse(Object? data) {
    return mappedOrNull<List<ShoppingLine>?>(
      () {
        if (data is! List) return null;

        final List<ShoppingLine> found = <ShoppingLine>[];

        for (final Object? row in data) {
          if (row is! Map<String, dynamic>) return null;

          found.add(ShoppingLine.fromApi(row));
        }

        return found;
      },
      describing: 'the shopping list',
    );
  }
}
