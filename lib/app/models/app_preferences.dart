import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

/// Which capture surface is pinned at the top of the overview (D66).
///
/// `product.md` used to offer two front doors chosen by the user. There is one home now, and this
/// is what the choice became: not WHICH screen opens, but which way of capturing sits at the top of
/// the one that does.
enum CaptureVerb {
  /// The assistant composer, for someone who describes what happened.
  assistant,

  /// Search plus the stock list, for someone who looks things up.
  inventory,
}

/// How much the app decides about placement on its own.
///
/// `location-assignment.md`'s dial, verbatim. The names are its names so no translation layer is
/// needed between the setting and the behaviour it controls.
///
/// **It lives here rather than on the locations screen, and that was a correction.** The dial was
/// declared inside `LocationIndexView` and rendered BELOW the location tree, on the argument that a
/// setting belongs next to what it governs. Anılcan named what that ignores: the tree is an
/// infinite-scrolling list, so anything under it is unreachable for any tenant with enough
/// locations to care about placement in the first place. A setting cannot sit downstream of an
/// unbounded list.
enum PlacementAutomation {
  /// The user always picks. Nothing is proposed.
  manual,

  /// A location is proposed with a visible reason. The user confirms or overrides.
  semiAuto,

  /// The location is assigned without asking. Undoable, and in the activity feed.
  fullAuto,
}

/// The preferences this app owns, as opposed to the ones `magic_starter` already manages.
///
/// ### Local, and deliberately so for now
///
/// These are stored in magic's local cache rather than on the user's account. There is no
/// preferences endpoint yet, and inventing one here would mean guessing at a shape the backend has
/// not agreed to. A local preference is also the honest failure mode: the worst case is that a user
/// re-picks it on a second device, rather than a sync that silently loses a choice.
///
/// The sync is a real follow-up rather than a footnote. When it lands, this class keeps its API and
/// changes where it reads from, which is why callers go through it instead of touching `Cache`.
///
/// ### A `ChangeNotifier`, because the assistant affordance sits outside the screen that toggles it
///
/// The toggle is on the settings screen and the thing it hides is in the app shell, so the shell
/// has to hear about the change without the settings screen knowing it exists.
class AppPreferences extends ChangeNotifier {
  static const String _assistantKey = 'depools.assistant_everywhere';
  static const String _verbKey = 'depools.capture_verb';
  static const String _placementKey = 'depools.placement_automation';

  /// The single instance the shell and the settings screen share.
  static final AppPreferences instance = AppPreferences._();

  AppPreferences._();

  bool? _assistantEverywhere;
  CaptureVerb? _captureVerb;
  PlacementAutomation? _placementAutomation;

  /// Whether the assistant is reachable from every screen (D67).
  ///
  /// Defaults to ON. The AI is the layer this product is operated through, so the affordance being
  /// present is the product working as designed; the toggle exists because the research on
  /// conversational interfaces is clear that a persistent chat affordance taxes users who would
  /// rather click, and one they cannot dismiss makes that tax permanent.
  bool get assistantEverywhere =>
      _assistantEverywhere ??= Cache.get(_assistantKey, defaultValue: true) as bool;

  /// Which capture surface leads on the overview.
  ///
  /// Defaults to the assistant for the same reason the affordance does, and because a user who has
  /// not expressed a preference is better served by the surface that accepts a sentence than by one
  /// that expects them to know what they are looking for.
  CaptureVerb get captureVerb =>
      _captureVerb ??= CaptureVerb.values.firstWhere(
        (CaptureVerb v) => v.name == Cache.get(_verbKey, defaultValue: CaptureVerb.assistant.name),
        orElse: () => CaptureVerb.assistant,
      );

  /// How much the app decides about placement on its own.
  ///
  /// Defaults to [PlacementAutomation.semiAuto], which is the position
  /// `location-assignment.md` argues for: a proposal with a visible reason teaches the user what
  /// the app is doing while leaving the decision theirs. Manual gives them nothing to learn from,
  /// and full-auto asks for trust the app has not yet earned on a fresh tenant.
  PlacementAutomation get placementAutomation =>
      _placementAutomation ??= PlacementAutomation.values.firstWhere(
        (PlacementAutomation v) =>
            v.name == Cache.get(_placementKey, defaultValue: PlacementAutomation.semiAuto.name),
        orElse: () => PlacementAutomation.semiAuto,
      );

  /// Choose how much the app decides about placement on its own.
  Future<void> setPlacementAutomation(PlacementAutomation value) async {
    _placementAutomation = value;
    notifyListeners();
    await Cache.put(_placementKey, value.name);
  }

  /// Turn the persistent assistant affordance on or off.
  Future<void> setAssistantEverywhere(bool value) async {
    _assistantEverywhere = value;
    notifyListeners();
    await Cache.put(_assistantKey, value);
  }

  /// Choose which capture surface leads on the overview.
  Future<void> setCaptureVerb(CaptureVerb verb) async {
    _captureVerb = verb;
    notifyListeners();
    await Cache.put(_verbKey, verb.name);
  }
}
