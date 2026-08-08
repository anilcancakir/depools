import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'preview_mock_harness.dart';
import 'screen_preview_scaffold.dart';

/// A screen at both of its widths, in one preview.
///
/// ### Why this replaced a second file per screen
///
/// The first attempt at phone verification added a `*PhoneScreenPreview` beside every existing
/// screen preview: eleven new files whose only difference from their neighbour was one `chrome:`
/// argument. That is duplication dressed as coverage, and Anılcan named it: the components are
/// responsive, so the WIDTH is a variant of one preview rather than a reason for two.
///
/// It also contradicted the project's own contract. `.claude/rules/design.md` requires ONE preview
/// widget rendering every variant and state combination, precisely so a reviewer sees the whole
/// range in one place and a divergence between two of them is visible rather than a file away.
/// Splitting by width broke that for screens while components kept it.
///
/// ### Both, stacked, and the wide one first
///
/// The wide arrangement is what the catalog pane shows natively and what most review happens
/// against, so it leads. The 390px frame follows, and it is a FIXED frame rather than a narrowed
/// viewport because the catalog keeps its sidebar at every width: narrowing the window squeezes the
/// harness, not the screen, which is how a "400px" measurement once produced a confident wrong
/// answer.
///
/// The phone frame is also the only place the shell's app bar and bottom nav are mounted, which is
/// what exposed a composer falling behind the nav and a blank dashboard behind a layout assertion.
@immutable
class ResponsiveScreenPreview extends StatelessWidget {
  /// Which mock state the harness installs.
  final PreviewState state;

  /// The view under test, built once per width.
  final WidgetBuilder builder;

  /// Creates a [ResponsiveScreenPreview].
  const ResponsiveScreenPreview({super.key, required this.builder, this.state = PreviewState.success});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 w-full',
      children: <Widget>[
        _labelled('Geniş', ScreenPreviewScaffold(state: state, builder: builder)),
        _labelled(
          'Telefon · 390px',
          ScreenPreviewScaffold(
            state: state,
            chrome: PreviewChrome.appMobile,
            builder: builder,
          ),
        ),
      ],
    );
  }

  /// One width, named, so a screenshot of the pair says which is which.
  Widget _labelled(String label, Widget child) {
    return WDiv(
      className: 'flex flex-col gap-2 w-full',
      children: <Widget>[
        WText(label, className: 'text-xs font-medium uppercase tracking-wide text-fg-muted'),
        child,
      ],
    );
  }
}
