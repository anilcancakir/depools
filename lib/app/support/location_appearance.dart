/// How a location's stored appearance becomes something the app can draw.
///
/// A location carries an icon NAME and a colour NAME (D119), never a glyph codepoint and never a
/// hex. Both are resolved here, and both resolve to something constant.
///
/// **The icon is a name because `--tree-shake-icons` defaults to ON.** An `IconData` built at
/// runtime from a stored int is referenced nowhere the shaker can see, so its glyph is dropped from
/// the font and the user's own location renders as tofu. Every entry below is a `const IconData` in
/// a const map, which is exactly what the shaker keeps.
///
/// **The colour is a name because `bin/design-tokens` fails the build on a raw hex**, and because a
/// free colour has no contrast guarantee on either surface. Each hue resolves to a className token
/// from `depoolsLocationAliases` in `lib/config/depools_location_tokens.dart`, and each carries its
/// own `dark:` pair.
///
/// Both vocabularies match `Location::ICONS` and `Location::COLOURS` on the backend, which CHECKs
/// each column against the same set. Adding one is a change in three places: the migration's
/// constraint, the model's constant, and here.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

/// The icon a location falls back to when it has none.
///
/// Both columns are nullable, and a tree row needs its leading glyph unconditionally: a
/// conditionally-rendered one shifts the text beside it, which is what once made children appear to
/// the left of their parents. A neutral box is the honest default for a place we know nothing about.
const IconData locationFallbackIcon = Icons.inventory_2_outlined;

/// The hue a location falls back to when it has none.
const String locationFallbackColour = 'slate';

/// The sixteen icons a location may carry, in the order a picker should offer them.
///
/// **Ordered from the room inwards**, so the list reads as a place getting smaller rather than as an
/// alphabet: home, then the rooms, then the furniture, then the containers, then the buildings.
///
/// Two of these are not the glyph their name suggests, and the mismatch is Material's rather than
/// ours: `Icons.kitchen` draws a REFRIGERATOR, so it belongs to `fridge`, and `kitchen` takes the
/// countertop. Picking by name without looking would put a fridge on every kitchen.
const Map<String, IconData> locationIcons = <String, IconData>{
  'home': Icons.home_outlined,
  'kitchen': Icons.countertops_outlined,
  'fridge': Icons.kitchen_outlined,
  'freezer': Icons.ac_unit_outlined,
  'pantry': Icons.dining_outlined,
  'cupboard': Icons.door_sliding_outlined,
  'shelf': Icons.shelves,
  'drawer': Icons.inbox_outlined,
  'box': Icons.inventory_2_outlined,
  'basket': Icons.shopping_basket_outlined,
  'crate': Icons.widgets_outlined,
  'warehouse': Icons.warehouse_outlined,
  'garage': Icons.garage_outlined,
  'basement': Icons.stairs_outlined,
  'office': Icons.desk_outlined,
  'van': Icons.local_shipping_outlined,
};

/// The seven hues a location may carry, in the order a swatch should offer them.
///
/// Neutral first, then around the wheel, so the picker reads as a spectrum with the opt-out at the
/// start rather than as an arbitrary list.
const List<String> locationColours = <String>[
  'slate',
  'blue',
  'teal',
  'green',
  'amber',
  'red',
  'violet',
];

/// The glyph for a stored icon name, falling back for an unknown or absent one.
///
/// **An unknown name is a fallback rather than a throw**, because the catalogue can grow on the
/// backend before a client that knows the new name has shipped. A location the user can still see
/// and open beats a screen that cannot build.
IconData locationIcon(String? name) => locationIcons[name] ?? locationFallbackIcon;

/// The className for a location's tinted glyph, as it appears in the tree and the picker.
String locationGlyphClassName(String? colour) => 'text-${_hue(colour)}-location';

/// The className for a location's hue as a FILL, which is what the form's swatch draws.
///
/// The same tone as the glyph rather than a soft tint of it, so the swatch the user taps
/// predicts the row they will get.
String locationSwatchClassName(String? colour) => 'bg-${_hue(colour)}-location';

/// A stored colour name, or the fallback when it is absent or not one we know.
///
/// Interpolating an unknown hue would produce a token the alias map does not hold, and wind drops an
/// unknown token SILENTLY: the glyph would render at full foreground brightness and look like a
/// deliberate choice rather than a miss. Narrowing to the known set here is what stops that.
String _hue(String? colour) =>
    locationColours.contains(colour) ? colour! : locationFallbackColour;
