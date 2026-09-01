import 'package:flutter/foundation.dart';

/// The "you passed nothing" marker for [ProductDraft.copyWith].
///
/// Its own type rather than a shared constant, so `identical()` against it cannot accidentally match
/// something a caller passed: there is exactly one instance of it in the program and no way to name
/// a second.
class _Unset {
  const _Unset();
}

const _Unset _unset = _Unset();

/// A product being created from a photograph: what the model read, plus what the user changed.
///
/// **One immutable value rather than a bag of fields on the controller**, because the screen has to
/// tell three things apart on every field: what arrived, what the user has since typed, and what the
/// user has merely LOOKED at. D53 turns on that last one, and a mutable field cannot carry it.
///
/// ### Two sets, and they are not the same question
///
/// [inferred] is what the read produced. [confirmed] is what the user opened the editor on and
/// saved, whether or not they changed it: D53 says looking is not confirming but agreeing is, so
/// saving clears the mark even when the value is identical. A field is marked exactly when it is in
/// the first set and not the second, which is why neither can be replaced by a per-field flag: a
/// value the user typed into an empty field was never inferred and must never be marked.
@immutable
class ProductDraft {
  /// The perceptual hash of the photograph this came from.
  ///
  /// Travels back with the save so the catalogue can record it against the confirmed card, which is
  /// what makes the next photograph of the same box free. Present even when nothing was recognised,
  /// because a card the user typed by hand is still a card for that photograph.
  final String imagePhash;

  /// Whether the catalogue answered instead of a model, in which case nothing was charged.
  final bool cached;

  /// Whether the READ produced a card, as opposed to what the draft holds now.
  ///
  /// Its own field rather than `name != null`, because the two answer different questions and drift
  /// apart the moment the user types: a read that found nothing and a name typed by hand is exactly
  /// the state where the screen should still be explaining why it found nothing.
  final bool recognised;

  /// The `AiOutcome` value the read ended on, or null when the catalogue answered.
  ///
  /// The screen branches on `no_credit`, which is the one the user can act on. Everything else is
  /// "we could not read it", and telling those apart in the interface would be offering a
  /// distinction nobody can use.
  final String? outcome;

  final String? name;
  final String? brand;
  final String? description;

  /// The tenant's own code. Never inferred: no model can know it.
  final String? sku;

  final String? categoryId;
  final String? categoryLabel;

  /// A Rec 20 code, or null when neither the model nor the category supplied one.
  final String? unit;

  /// The shelf life in days, or null when it is not tracked.
  ///
  /// **There is no content pair here and that is deliberate.** `content_amount` and `content_unit`
  /// are one declaration the database enforces as a pair, and the shared editor sheet returns a
  /// single string, so a draft that could hold half of it could only ever send half of it.
  final int? shelfLifeDays;

  /// The fields the read produced, by the keys this class uses.
  final Set<String> inferred;

  /// The fields the user has opened and saved, which clears their mark (D53).
  final Set<String> confirmed;

  const ProductDraft({
    required this.imagePhash,
    this.cached = false,
    this.recognised = false,
    this.outcome,
    this.name,
    this.brand,
    this.description,
    this.sku,
    this.categoryId,
    this.categoryLabel,
    this.unit,
    this.shelfLifeDays,
    this.inferred = const <String>{},
    this.confirmed = const <String>{},
  });

  /// The draft a `products/recognise` response describes.
  ///
  /// [inferred] is built from which fields actually came back non-null rather than from the fact
  /// that a read happened: a read that could not make out the brand leaves that field empty, and an
  /// empty field the user then fills is theirs, not a guess of ours to mark.
  factory ProductDraft.fromApi(Map<String, dynamic> json) {
    final String? name = json['name'] as String?;
    final String? brand = json['brand'] as String?;
    final String? description = json['description'] as String?;
    final String? categoryId = json['category_id'] as String?;
    final String? unit = json['unit'] as String?;

    return ProductDraft(
      imagePhash: json['image_phash'] as String? ?? '',
      cached: json['cached'] as bool? ?? false,
      recognised: json['found'] as bool? ?? false,
      outcome: json['outcome'] as String?,
      name: name,
      brand: brand,
      description: description,
      categoryId: categoryId,
      categoryLabel: json['category_label'] as String?,
      unit: unit,
      inferred: <String>{
        if (name != null) 'name',
        if (brand != null) 'brand',
        if (description != null) 'description',
        if (categoryId != null) 'category',
        if (unit != null) 'unit',
      },
    );
  }

  /// Whether this field still carries the "we guessed this" mark.
  bool isUnconfirmed(String field) =>
      inferred.contains(field) && !confirmed.contains(field);

  /// The same draft with one field changed and its mark cleared.
  ///
  /// **The mark clears on every call, including the one that changes nothing.** That is D53 rather
  /// than a shortcut: the sheet's save button is the user saying they have read the value, and a
  /// mark surviving that would tell them the app had not noticed them agreeing.
  ProductDraft withField(String field, String? value) {
    final Set<String> seen = <String>{...confirmed, field};

    return switch (field) {
      'name' => copyWith(name: value, confirmed: seen),
      'brand' => copyWith(brand: value, confirmed: seen),
      'description' => copyWith(description: value, confirmed: seen),
      'sku' => copyWith(sku: value, confirmed: seen),
      'unit' => copyWith(unit: value, confirmed: seen),
      // Non-positive parses to null rather than to a number the column refuses: a shelf life is
      // `min:1` on the server, so `0` typed into the sheet would come back as a validation sentence
      // about a field the user thought they had cleared.
      'shelf_life' => copyWith(
        shelfLifeDays: _positive(int.tryParse(value ?? '')),
        confirmed: seen,
      ),
      // A field name nothing renders. Returning the draft unchanged would hide a typo in a key
      // until somebody noticed an editor that silently did nothing, which is the failure this app
      // has already paid for once on a screen full of empty `onTap`s.
      _ => throw ArgumentError.value(field, 'field', 'Not a draft field'),
    };
  }

  /// The same draft with the named fields replaced.
  ///
  /// **Absent and null are different here, which is why this takes `Object?` and a sentinel rather
  /// than the usual nullable parameters.** Clearing a field is a real edit on this screen: a user
  /// who deletes a brand the model invented means it to be empty, and the conventional `name ??
  /// this.name` shape would silently put the model's answer back. The sentinel is the only way Dart
  /// lets a named parameter tell "you passed null" from "you passed nothing".
  ProductDraft copyWith({
    Object? name = _unset,
    Object? brand = _unset,
    Object? description = _unset,
    Object? sku = _unset,
    Object? categoryId = _unset,
    Object? categoryLabel = _unset,
    Object? unit = _unset,
    Object? shelfLifeDays = _unset,
    Set<String>? confirmed,
  }) {
    return ProductDraft(
      imagePhash: imagePhash,
      cached: cached,
      recognised: recognised,
      outcome: outcome,
      name: _or(name, this.name),
      brand: _or(brand, this.brand),
      description: _or(description, this.description),
      sku: _or(sku, this.sku),
      categoryId: _or(categoryId, this.categoryId),
      categoryLabel: _or(categoryLabel, this.categoryLabel),
      unit: _or(unit, this.unit),
      shelfLifeDays: _or(shelfLifeDays, this.shelfLifeDays),
      inferred: inferred,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  /// The passed value, or the current one when nothing was passed.
  static T? _or<T>(Object? passed, T? current) =>
      identical(passed, _unset) ? current : passed as T?;

  /// The number, or null when it is not one the server would accept.
  static int? _positive(int? value) => value != null && value > 0 ? value : null;

  /// What `POST /products` is sent, with the fields nobody filled left out.
  ///
  /// Absent rather than null for every optional one: `base_unit: null` was measured to pass
  /// validation and then throw inside the model's own mutator, so the server reads "the caller named
  /// nothing" only from an omission.
  Map<String, dynamic> toCreatePayload() {
    return <String, dynamic>{
      'name': name,
      if (brand != null) 'brand': brand,
      if (description != null) 'description': description,
      if (sku != null) 'sku': sku,
      if (unit != null) 'base_unit': unit,
      if (categoryId != null) 'product_category_id': categoryId,
      if (shelfLifeDays != null) 'default_shelf_life_days': shelfLifeDays,
      if (imagePhash.isNotEmpty) 'image_phash': imagePhash,
    };
  }
}
