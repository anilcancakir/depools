import 'package:flutter/widgets.dart';

import '../resources/views/search_view.dart';
import 'responsive_screen_preview.dart';

/// Global search, at both widths.
///
/// The state shown is the empty query, which is the one a user always meets: the screen offers the
/// places they keep things rather than a blank box.
@immutable
class SearchScreenPreview extends StatelessWidget {
  /// Creates the [SearchScreenPreview].
  const SearchScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenPreview(builder: (BuildContext context) => const SearchView());
  }
}
