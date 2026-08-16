/// The icon catalogue, as the client sees it: names in, svg out.
///
/// **Icons are fetched rather than bundled, and the reason is measured rather than stylistic.**
/// Flutter's `IconTreeShaker` runs `ConstFinder` over the compiled kernel's CONSTANT POOL, so it
/// keeps every entry of a `const Map` and drops anything built at runtime from a stored codepoint.
/// A searchable picker over the whole Material set therefore has to reference the whole set as
/// constants, which cost +1.81 MB when measured on this app: `main.dart.js` 5,132,437 -> 5,796,655
/// and the icon font 23,376 -> 1,261,120, with the tree-shaking reduction collapsing from 98.6% to
/// 23.3%. Serving the svg from our own `icons` table takes that to zero.
///
/// **A name is fetched once and then held.** A tenant uses perhaps five to twenty distinct icons
/// across their whole location tree, so after the first screen the working set is resident and the
/// app draws them with no network at all. That is what makes this acceptable for a product whose
/// core loop is counting stock in a stockroom.
///
/// **Nothing here throws and nothing here blocks a build.** An icon is an appearance hint: if the
/// fetch fails, or the catalogue never heard of the name, the caller draws a bundled fallback glyph
/// and the screen is still usable. A location the user can see and open beats a screen that cannot
/// paint.
library;

import 'package:flutter/foundation.dart' show immutable, protected;
import 'package:magic/magic.dart';

/// One icon's drawable source.
@immutable
class CatalogueIcon {
  /// The stored name, which is Material's own (`kitchen`, `shelves`, `local_shipping`).
  final String name;

  /// The human label, for a picker's tooltip and its semantic label.
  final String title;

  /// The 24px outlined svg source, roughly 490 bytes.
  final String svg;

  /// Creates a [CatalogueIcon].
  const CatalogueIcon({required this.name, required this.title, required this.svg});

  /// The largest svg this will accept.
  ///
  /// The vendored catalogue averages 490 bytes and its longest entry is under two thousand, so 16 KB
  /// is roughly thirty times the worst real icon: comfortably out of the way of anything genuine and
  /// well short of a payload worth handing to a parser. The bound is here rather than absent because
  /// `SvgPicture.string` PARSES what it is given, so an oversized string is CPU rather than just
  /// bytes, and a client should not be the only thing standing between a bad response and a frozen
  /// frame.
  static const int _maxSvgBytes = 16 * 1024;

  /// Reads one from the API's shape.
  ///
  /// Returns null rather than throwing on anything unusable, because one malformed entry in a batch
  /// of forty should cost that icon and not the screen. That is the same reason the caller draws a
  /// fallback: an icon is an appearance hint.
  static CatalogueIcon? fromMap(Map<String, dynamic> map) {
    final Object? rawName = map['name'];
    final Object? rawSvg = map['svg'];

    if (rawName is! String || rawSvg is! String) {
      return null;
    }

    final String name = rawName.trim();
    final String svg = rawSvg.trim();

    // Trimmed BEFORE the emptiness test, so a whitespace-only value is rejected rather than stored:
    // it passes `isEmpty` untrimmed and then renders as nothing, or becomes a semantic label made of
    // spaces, which is worse than a missing one because a screen reader announces it.
    if (name.isEmpty || svg.isEmpty || svg.length > _maxSvgBytes) {
      return null;
    }

    final Object? rawTitle = map['title'];
    final String title = rawTitle is String ? rawTitle.trim() : '';

    return CatalogueIcon(
      name: name,
      // The name is a worse label than a real title and a much better one than blank.
      title: title.isEmpty ? name : title,
      svg: svg,
    );
  }
}

/// Fetches icons and remembers them for the life of the app.
///
/// Resolved from the container as a singleton, so the tree, the detail header and the picker share
/// one cache rather than three.
class IconCatalogue {
  /// What is already held, keyed by name.
  final Map<String, CatalogueIcon> _held = <String, CatalogueIcon>{};

  /// Names asked for and answered with nothing, so a miss is not retried on every rebuild.
  ///
  /// Without this a location carrying a name the catalogue dropped in a re-vendor would fire a
  /// request per rebuild forever, and the user would see the fallback either way.
  final Set<String> _missing = <String>{};

  /// A fetch already in flight, so forty rows sharing five icons make one request rather than five.
  Future<void>? _inFlight;

  /// Names wanted but not yet requested.
  final Set<String> _wanted = <String>{};

  /// Hold an icon without fetching it.
  ///
  /// Exists for the preview catalog, which renders these components with no server and no session.
  /// `@visibleForTesting` would be the honest annotation if a test were the only caller, and a
  /// preview is the other one: both are the app looking at itself.
  @protected
  void remember(CatalogueIcon icon) => _held[icon.name] = icon;

  /// What the app already holds for [name], or null when it has to be fetched.
  CatalogueIcon? held(String? name) => name == null ? null : _held[name];

  /// Whether this name has been asked for and answered with nothing.
  bool isMissing(String? name) => name != null && _missing.contains(name);

  /// Ask for a name, and get back whatever the catalogue has.
  ///
  /// **Batched deliberately.** A list of locations calls this once per row in the same frame, and
  /// each one alone would be a request. Wanted names accumulate until the current microtask drains,
  /// so a screen resolves its icons in one call to `?names[]=`.
  Future<CatalogueIcon?> resolve(String name) async {
    if (_held.containsKey(name)) {
      return _held[name];
    }

    if (_missing.contains(name)) {
      return null;
    }

    _wanted.add(name);
    _inFlight ??= Future<void>.microtask(_drain);

    await _inFlight;

    return _held[name];
  }

  /// Search the catalogue, for the picker.
  ///
  /// Results are held too, so tapping one of them draws instantly rather than fetching the icon the
  /// user is already looking at.
  Future<List<CatalogueIcon>> search(String query) async {
    final dynamic response = await Http.get('/icons?q=${Uri.encodeQueryComponent(query)}');

    if (!response.successful) {
      return const <CatalogueIcon>[];
    }

    final List<CatalogueIcon> icons = _read(response['data']);

    for (final CatalogueIcon icon in icons) {
      _held[icon.name] = icon;
    }

    return icons;
  }

  /// The icon a place's NAME suggests, or null when there is nothing worth defaulting to.
  ///
  /// **Null is the ordinary answer and every reason for it looks the same from here**: the kill
  /// switch, an empty credit balance, a provider timeout, a model unsure of the name, and a name
  /// whose English words match nothing in the catalogue. The caller shows the neutral icon with the
  /// picker one tap away, which is what it would have shown anyway.
  ///
  /// POST rather than GET, matching the endpoint: this spends a model call and one of the tenant's
  /// AI credits, and a GET is the verb clients and proxies feel free to repeat.
  Future<CatalogueIcon?> suggest(String name) async {
    final dynamic response = await Http.post('/icons/suggest', data: <String, dynamic>{'name': name});

    if (!response.successful) {
      return null;
    }

    final Object? raw = response['data']?['icon'];

    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final CatalogueIcon? icon = CatalogueIcon.fromMap(raw);

    if (icon != null) {
      // Held like any other, so the form draws it without a second request and the tree that
      // follows already has it.
      _held[icon.name] = icon;
    }

    return icon;
  }

  /// Fetch everything wanted so far, in one request.
  Future<void> _drain() async {
    final List<String> names = _wanted.toList();
    _wanted.clear();
    _inFlight = null;

    if (names.isEmpty) {
      return;
    }

    // **The endpoint caps a batch at 100 names**, so a tree wider than that is chunked here rather
    // than answered with a 422 the caller cannot act on.
    for (int i = 0; i < names.length; i += 100) {
      final List<String> chunk = names.sublist(i, (i + 100).clamp(0, names.length));

      final String query = chunk
          .map((String name) => 'names[]=${Uri.encodeQueryComponent(name)}')
          .join('&');

      final dynamic response = await Http.get('/icons?$query');

      // **A failed fetch is not an error state and must not mark anything missing.** The caller
      // draws the fallback either way, and the next screen should try again; leaving these unheld
      // and unmissed is exactly that. Marking them would make one flaky request permanent.
      if (!response.successful) {
        continue;
      }

      for (final CatalogueIcon icon in _read(response['data'])) {
        _held[icon.name] = icon;
      }

      // Asked for, answered, and still absent: the catalogue genuinely does not have it, which
      // happens when a re-vendor drops a name a tenant already stored.
      for (final String name in chunk) {
        if (!_held.containsKey(name)) {
          _missing.add(name);
        }
      }
    }
  }

  /// The icons in a payload, skipping anything malformed.
  List<CatalogueIcon> _read(Object? data) {
    if (data is! List) {
      return const <CatalogueIcon>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(CatalogueIcon.fromMap)
        .whereType<CatalogueIcon>()
        .toList();
  }
}
