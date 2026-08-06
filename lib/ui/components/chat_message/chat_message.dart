import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'chat_message.recipe.dart';

/// Who said it.
enum ChatSpeaker {
  /// The user. Gets a bubble, right-aligned.
  user,

  /// The assistant. Gets no bubble: its text is a caption over the card below it.
  assistant,
}

/// **ChatMessage**
///
/// One line of the transcript.
///
/// **The assistant deliberately has no bubble** (D49). Its answers are components, not
/// prose, and the sentence it renders is the caption on the component below. Two facing
/// bubble columns would make an inventory tool read like a chat app, which is the shape
/// `ai-assistant.md` warns about: users cannot get an overview from a transcript, and
/// dressing state changes as utterances makes that worse.
@immutable
class ChatMessage extends StatelessWidget {
  /// The already-localised text.
  final String text;

  /// Who said it.
  final ChatSpeaker speaker;

  /// Creates a [ChatMessage].
  const ChatMessage({super.key, required this.text, this.speaker = ChatSpeaker.assistant});

  @override
  Widget build(BuildContext context) {
    final slots = chatMessageRecipe()(variants: {'speaker': speaker.name});

    return WDiv(
      className: slots['root'],
      child: WDiv(
        className: slots['body'],
        child: WText(text, className: slots['text']),
      ),
    );
  }
}
