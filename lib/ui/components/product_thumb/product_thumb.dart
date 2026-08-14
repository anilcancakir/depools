import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'product_thumb.recipe.dart';

/// Which size a [ProductThumb] renders at.
enum ProductThumbSize {
  /// A list row's leading element.
  sm,

  /// A card or a sheet, where the picture is part of what is being checked.
  md,
}

/// **ProductThumb**
///
/// A product's picture, or its initial when there is none.
///
/// **The box is always there.** `design.md` names the alternative as an anti-pattern: a leading element
/// that appears on some rows and not others shifts the text beside it, and a list of rows is a table
/// even when it is built from flex boxes. Most of this catalogue has no photograph yet, so a thumbnail
/// that rendered only when it could would leave every list ragged for exactly the tenant who has just
/// started.
///
/// The empty state is the first letter of the name on a neutral fill, which is what `magic_starter`
/// already does for a user with no photo. A blank box reads as a picture that failed to load; a letter
/// reads as an identity, and it also tells two adjacent rows apart at a glance.
///
/// ### A failed load falls back to the same letter
///
/// Two of the three sources are urls on somebody else's server: an Open Food Facts photograph is
/// CC-BY-SA and deliberately not copied to our disk, so it can 404, move, or be blocked by a network
/// this app has no control over. `errorBuilder` sends that to the same initial rather than to Flutter's
/// broken-image glyph, because a product with an unreachable photograph is not a product in an error
/// state.
@immutable
class ProductThumb extends StatelessWidget {
  /// The picture's url, when the cascade or the product itself had one.
  final String? imageUrl;

  /// The product's name, which supplies the initial and the image's alternative text.
  final String name;

  /// How large to draw it.
  final ProductThumbSize size;

  /// Extra classes from the caller, appended last.
  final String? className;

  /// Creates a [ProductThumb].
  const ProductThumb({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = ProductThumbSize.sm,
    this.className,
  });

  /// The letter shown when there is no picture.
  ///
  /// Upper-cased for the same reason the avatar does it: a list of initials is a column, and a mix of
  /// cases reads as noise. `?` rather than an empty box for a nameless row, which is a real state on
  /// this screen: a barcode that resolved to nothing has no name yet.
  String get _initial {
    final String trimmed = name.trim();

    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final slots = productThumbRecipe()(
      variants: {'size': size.name},
      classNames: className == null ? null : {'root': className!},
    );

    final String? url = imageUrl?.trim();

    if (url == null || url.isEmpty) {
      return WDiv(
        className: slots['root'],
        child: WText(_initial, className: slots['initial']),
      );
    }

    return WDiv(
      className: slots['root'],
      child: WImage(
        src: url,
        alt: name,
        className: slots['image'],
        // Both of these land on the initial rather than on a spinner or a broken glyph. A row is small
        // and short-lived: something flickering in a 40pt box while a list scrolls is worse than a
        // letter that simply becomes a picture.
        placeholder: WText(_initial, className: slots['initial']),
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            WText(_initial, className: slots['initial']),
      ),
    );
  }
}
