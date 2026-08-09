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
  static const String _digestKey = 'depools.daily_digest';
  static const String _digestHourKey = 'depools.daily_digest_hour';
  static const String _lowStockAlertKey = 'depools.alert_low_stock';
  static const String _countReminderKey = 'depools.alert_count_reminder';

  /// The single instance the shell and the settings screen share.
  static final AppPreferences instance = AppPreferences._();

  AppPreferences._();

  bool? _assistantEverywhere;
  CaptureVerb? _captureVerb;
  PlacementAutomation? _placementAutomation;
  bool? _dailyDigest;
  int? _digestHour;
  bool? _lowStockAlert;
  bool? _countReminder;

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

  /// Whether the once-a-day summary is sent.
  ///
  /// ### One notification a day, not one per event
  ///
  /// Anılcan's call, and the reasoning is about what survives contact with a real shop. An alert
  /// the moment each product crosses its threshold is more actionable in isolation and unusable in
  /// aggregate: a tenant with two hundred products gets a stream, mutes the app, and the feature
  /// has then made things worse than sending nothing.
  ///
  /// A morning summary matches how a cafe actually works (you look before you open) and it is one
  /// interruption whatever the shop's size. It is also the only shape that serves `product.md`'s
  /// third success criterion, which is not "the user was told" but "the user came back".
  ///
  /// Defaults to ON, because a product whose whole promise is telling you what is about to go wrong
  /// cannot wait to be asked.
  bool get dailyDigest => _dailyDigest ??= Cache.get(_digestKey, defaultValue: true) as bool;

  /// The hour the summary is sent, in the tenant's own timezone.
  ///
  /// Nine in the morning by default: before a shop opens and after a person is awake. It is a
  /// preference rather than a constant because a bakery and a bar do not start at the same time,
  /// and a summary that arrives after the decision it informs is noise.
  int get digestHour => _digestHour ??= Cache.get(_digestHourKey, defaultValue: 9) as int;

  /// Whether shortages join the summary.
  bool get lowStockAlert => _lowStockAlert ??= Cache.get(_lowStockAlertKey, defaultValue: true) as bool;

  /// Whether a periodic reminder to count is sent.
  ///
  /// Off by default. A count is real work, and prompting for it before the user has decided it is
  /// part of how they run the place reads as nagging rather than as help.
  bool get countReminder => _countReminder ??= Cache.get(_countReminderKey, defaultValue: false) as bool;

  /// Turn the daily summary on or off.
  Future<void> setDailyDigest(bool value) async {
    _dailyDigest = value;
    notifyListeners();
    await Cache.put(_digestKey, value);
  }

  /// Choose when the summary arrives.
  Future<void> setDigestHour(int value) async {
    _digestHour = value;
    notifyListeners();
    await Cache.put(_digestHourKey, value);
  }

  /// Turn shortage lines in the summary on or off.
  Future<void> setLowStockAlert(bool value) async {
    _lowStockAlert = value;
    notifyListeners();
    await Cache.put(_lowStockAlertKey, value);
  }

  /// Turn the count reminder on or off.
  Future<void> setCountReminder(bool value) async {
    _countReminder = value;
    notifyListeners();
    await Cache.put(_countReminderKey, value);
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
