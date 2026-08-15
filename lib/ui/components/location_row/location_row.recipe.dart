import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the LocationRow component.
///
/// **Depth is expressed by indent, not by a tree glyph.** The schema caps depth at 6, so
/// the deepest row is 5 steps in; at `pl-4` per step that is 80px of gutter, which a
/// phone cannot spare. `pl-3` per step (12px) keeps the deepest row inside 60px and still
/// reads as nesting, and the parent's own name stays the anchor rather than a run of
/// connector lines.
///
/// The row's own name never truncates the path. A location row shows only its OWN name,
/// because the ancestors are literally above it on screen; repeating "Mutfak › Buzdolabı"
/// inside a tree is the redundancy that makes a hierarchy unreadable. `LocationStockRow`
/// on the product screen does show the full path, because there the tree is absent and
/// the path is the only context.
WindSlotRecipe locationRowRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row items-center gap-3 py-2 min-h-11',
      'body': 'flex flex-col gap-0.5 flex-1 min-w-0',
      'name': 'text-sm font-semibold text-fg truncate',
      'meta': 'text-xs text-fg-muted truncate',
      // Size only. The tint is the location's own hue and arrives from the caller, so
      // putting a colour here would be a default that is overridden on every single row:
      // dead weight that reads like the real value when you grep for it.
      'icon': 'size-5',
    },
    variants: {
      // A location holding nothing is not an error, it is a shelf waiting to be used.
      // It recedes rather than disappearing, because it is still a valid destination and
      // hiding it would make the tree look smaller than it is.
      'state': {
        'stocked': {'name': 'text-sm font-semibold text-fg truncate'},
        'empty': {'name': 'text-sm font-semibold text-fg-muted truncate'},
      },
    },
    defaultVariants: {'state': 'stocked'},
  );
}
