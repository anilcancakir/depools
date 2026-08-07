import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ChatMessage component.
///
/// **Only the user gets a bubble.** The assistant's text runs at full width with no fill,
/// because it is not a speech act: it is a caption introducing the card underneath it. Two
/// facing bubble columns make a work surface read like an instant-messenger thread, and
/// `ai-assistant.md` is explicit that chat is a strong capture surface and a weak system of
/// record. Giving the assistant a bubble would push it further toward the weak end.
///
/// **No vertical padding on the root.** The transcript is a `ListView.separated` and it owns the
/// rhythm between messages; padding here too made a card-to-bubble gap and a bubble-to-bubble gap
/// come out different sizes.
///
/// The user's bubble caps at `max-w-md`. A transcript where the user's own sentence spans
/// 1100px on a desktop window is one where the eye has to travel to find the reply, and the
/// user's messages here are short by construction ("1 adet süt aldım").
WindSlotRecipe chatMessageRecipe() {
  return const WindSlotRecipe(
    slots: {
      'root': 'flex flex-row w-full',
      'body': 'px-4 py-2.5 rounded-lg max-w-md',
      'text': 'text-sm text-fg',
    },
    variants: {
      'speaker': {
        'user': {
          'root': 'flex flex-row w-full justify-end',
          'body': 'px-4 py-2.5 rounded-lg max-w-md bg-primary-container',
        },
        'assistant': {
          'root': 'flex flex-row w-full justify-start',
          // No fill, no padding, no cap: it is a caption, not an utterance.
          'body': 'flex-1 min-w-0',
        },
      },
    },
    defaultVariants: {'speaker': 'assistant'},
  );
}
