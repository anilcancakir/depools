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
WindSlotRecipe draftFieldRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-col gap-1 py-2',
      'label': 'text-xs font-medium uppercase tracking-wide text-fg-muted',
      'value': 'text-sm text-fg',
      'prompt': 'text-sm text-ai',
      'marker': 'text-xs text-fg-muted',
    },
  );
}
