import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'chat_message.dart';

/// Static variant-matrix preview for [ChatMessage].
///
/// The thing to check is the asymmetry, because it is the design rather than an oversight:
/// the user gets a right-aligned bubble and the assistant gets none. Two facing bubble
/// columns would make an inventory tool read like an instant messenger, and the assistant's
/// line is a caption over the card that follows it, not an utterance.
///
/// The long user message is here to prove the `max-w-md` cap. Without it, a sentence spans
/// the whole window on a desktop and the eye has to travel to find the reply.
class ChatMessagePreview extends StatelessWidget {
  /// Creates the ChatMessage preview.
  const ChatMessagePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const WDiv(
      className: 'flex flex-col gap-6 p-6',
      children: [
        WDiv(
          className: 'flex flex-col gap-2 p-4 rounded-lg bg-surface-container',
          children: [
            ChatMessage(text: '1 adet süt aldım', speaker: ChatSpeaker.user),
            ChatMessage(text: 'Süt stoğa eklendi. Nereye koyulacağı sorulacak.'),
            ChatMessage(
              text:
                  'Dün akşam markete gittim, iki litre süt bir de yarım kilo kıyma aldım, '
                  'kıymayı dondurucuya koydum',
              speaker: ChatSpeaker.user,
            ),
            ChatMessage(text: 'İki satır yazıldı, kıyma derin dondurucuya girdi.'),
          ],
        ),
      ],
    );
  }
}
