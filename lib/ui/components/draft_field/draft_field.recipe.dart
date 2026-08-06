import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the DraftField component.
///
/// Three states, and the point is that they are **distinguishable without a number**
/// (D31). No consumer product surveyed shows numeric AI confidence, and the research is
/// against it: miscalibrated confidence increases over-trust in wrong answers and
/// under-trust in right ones with no offsetting accuracy gain. Apple's own pattern is
/// binary presence, so these are states, not scores.
///
/// `unsure` is the one that has to be designed rather than defaulted. An empty field
/// that looks like an optional field the user chose to skip is the failure: the model
/// gave up and nobody was told. So it carries its own prompt text.
///
/// **The tone is the `ai` family (teal), and that is a semantic choice.** DESIGN.md
/// defines that family as "AI-driven surface", and this prompt is precisely the model
/// reporting its own silence. A first pass used `text-accent`, which does not exist:
/// `accent` is declared in DESIGN.md but `design:sync` emits only `bg-accent`, so the
/// token dropped silently and the prompt rendered at full foreground brightness,
/// indistinguishable from a real value. That is exactly the silent-no-op DESIGN.md
/// warns about, and it is why an unknown token has to be checked against the generated
/// theme rather than assumed.
///
/// `unconfirmed` is a separate marker from the states, because an inferred value is
/// filled AND provisional at the same time. D32 requires it: a wrongly inferred unit
/// silently changes what every quantity in the ledger means, so the inference has to
/// stay visibly an inference until someone accepts it.
/// **Two layouts, one state machine.** The `row` layout is a labelled line in a card;
/// the `chip` layout is an inline capsule for D13's grouped tap-chips, which is how
/// location, date and quantity are collected after a draft is created ("never as
/// sequential questions"). Keeping them as one component rather than two is deliberate:
/// two components with the same three states is exactly the drift that put a value and
/// a total out of step twice already in this codebase.
///
/// The chip carries no label when it has a value, because "1 adet" and "Buzdolabı" say
/// what they are. It falls back to the label only in the unsure state, where "Konum" is
/// the only thing that can be said.
WindSlotRecipe draftFieldRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-1 py-2',
      'label': 'text-xs font-medium uppercase tracking-wide text-fg-muted',
      // `flex-auto`, not `flex-1`, and the difference is visible. The value sits in a
      // row so the `tahmin` marker can stand beside it, and an unbounded text inside a
      // nested flex overflows rather than wrapping: a product description ran 227px off
      // the right edge. But `flex-1` maps to a TIGHT fit, which made the value claim the
      // whole row and shoved the marker to the far edge, so "adet" and "tahmin" sat a
      // card apart. `flex-auto` is the loose fit: take what you need, wrap when
      // squeezed, and let the marker stay adjacent.
      'value': 'text-sm text-fg flex-auto min-w-0',
      'prompt': 'text-sm text-ai',
      'marker': 'text-xs text-fg-muted',
      // The chip mirrors FilterChip's geometry (capsule, px-3, py-2.5, axis-min) so the
      // two read as the same family of control. Padding rather than `min-h-11`, per the
      // measured finding that min-height grows a box downward without re-centring.
      'chipRoot':
          'flex flex-row items-center gap-1.5 px-3 py-2.5 rounded-full axis-min '
          'bg-surface-container-high',
      'chipValue': 'text-sm font-medium text-fg',
      'chipPrompt': 'text-sm font-medium text-ai',
      'chipMarker': 'text-xs text-fg-muted',
    },
  );
}
