import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:magic/magic.dart';

import '../../../app/support/icon_catalogue.dart';

/// **AppIcon**
///
/// A glyph the USER chose, drawn from the catalogue rather than from a bundled font.
///
/// Every other icon in this app is an `Icons.*` constant, because the app chose it and the shaker
/// can see it. This one is different in kind: the name comes out of a database column, so a
/// `const IconData` cannot exist for it and building one from a codepoint gets its glyph dropped
/// from the font. The svg arrives from `/api/v1/icons` and is held by name.
///
/// **It never blocks and never fails.** Before the svg arrives, and forever if the catalogue has
/// never heard of the name, this draws a neutral bundled glyph at the same size. An icon is an
/// appearance hint: a location the user can still see and open beats a screen that will not paint.
///
/// **The tint comes from the className**, not from a colour parameter, so a caller styles this the
/// way it styles a `WIcon`. The svg's own path carries no `fill`, which is what makes recolouring
/// it a `srcIn` filter rather than a rewrite.
///
/// ### Example
///
/// ```dart
/// AppIcon(name: 'kitchen', className: 'size-5 text-blue-location')
/// ```
@immutable
class AppIcon extends StatefulWidget {
  /// The neutral glyph shown while the real one is in flight, and kept when it never arrives.
  ///
  /// A box rather than a question mark: the user picked something, we simply do not have it yet,
  /// and an error mark would report a problem they cannot act on.
  static const IconData fallback = Icons.inventory_2_outlined;

  /// The stored icon name, which is Material's own (`kitchen`, `shelves`, `local_shipping`).
  ///
  /// Null is a real state rather than a caller's mistake: `locations.icon` is nullable, and a
  /// location created by a scan has never been given one.
  final String? name;

  /// Wind classes for the box, carrying both the size and the tint.
  final String className;

  /// What a screen reader says. The catalogue's own title when absent.
  final String? semanticLabel;

  /// Where the svg comes from. The container's singleton unless a caller says otherwise.
  ///
  /// **The seam exists for the preview catalog**, which has to render this component without a
  /// server and without an authenticated session. A preview that fires a real request would show
  /// whatever the developer's backend happens to be doing, which is not a component review.
  final IconCatalogue? catalogue;

  /// Creates an [AppIcon].
  const AppIcon({
    super.key,
    required this.name,
    this.className = 'size-5',
    this.semanticLabel,
    this.catalogue,
  });

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  CatalogueIcon? _icon;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A list row is recycled onto a different location as the user scrolls, so the name changes
    // under a state that would otherwise keep drawing the previous tenant's glyph.
    if (oldWidget.name != widget.name) {
      _icon = null;
      _resolve();
    }
  }

  /// Take what the catalogue already holds, and fetch only when it does not.
  ///
  /// The synchronous read first is what keeps a scroll smooth: an icon already held draws on this
  /// frame rather than after a microtask, so a list of forty rows does not flash forty fallbacks.
  void _resolve() {
    final String? name = widget.name;

    if (name == null) return;

    final IconCatalogue catalogue = widget.catalogue ?? Magic.make<IconCatalogue>('icons');
    final CatalogueIcon? held = catalogue.held(name);

    if (held != null) {
      _icon = held;

      return;
    }

    if (catalogue.isMissing(name)) return;

    catalogue.resolve(name).then((CatalogueIcon? icon) {
      // The widget can be gone by now, and a list scrolled fast enough can have been recycled onto
      // another name while this was in flight. Both checks, because they are different failures.
      if (!mounted || icon == null || icon.name != widget.name) return;

      setState(() => _icon = icon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final CatalogueIcon? icon = _icon;

    if (icon == null) {
      return WIcon(
        AppIcon.fallback,
        className: widget.className,
        semanticLabel: widget.semanticLabel,
      );
    }

    // **The same parser `WIcon` uses, for the same reason: one className has to mean one thing.**
    // A caller styles this exactly as it styles a `WIcon` (`size-5 text-blue-location`), so the size
    // and the tint are resolved here from the class string rather than taken as parameters. Falling
    // back to the inherited text style matches `WIcon`'s own behaviour when a class does not set one.
    final WindStyle styles = WindParser.parse(widget.className, context);
    final TextStyle inherited = DefaultTextStyle.of(context).style;

    final double size = styles.width ?? styles.height ?? styles.fontSize ?? inherited.fontSize ?? 24;
    // `IconTheme` as the last resort, which is where `WIcon` lands too when it hands `Icon` a null
    // colour. **Nullable all the way down rather than defaulting to a literal:** a hardcoded black
    // would fail `bin/design-tokens`, and rightly, since it would be the one colour in this app that
    // answers to nothing. Nothing resolved means the svg is drawn as it was authored.
    final Color? colour = styles.color ?? inherited.color ?? IconTheme.of(context).color;

    // `srcIn` paints the glyph in the resolved foreground and keeps its shape. That works because
    // the catalogue's svgs carry no `fill` on their real path: verified on the vendored source,
    // where the only `fill` is `none` on the transparent bounding rectangle.
    return Semantics(
      label: widget.semanticLabel ?? icon.title,
      child: SvgPicture.string(
        icon.svg,
        width: size,
        height: size,
        colorFilter: colour == null ? null : ColorFilter.mode(colour, BlendMode.srcIn),
      ),
    );
  }
}
