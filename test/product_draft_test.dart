import 'package:depools/app/models/product_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing a `products/recognise` response, and what editing a field does to it.
///
/// The payloads below mirror `backend/tests/Feature/ProductRecogniseTest.php`'s own assertions
/// rather than an imagined shape: `found` and `outcome` beside the card, a hash present even on a
/// read that recognised nothing, and every card field nullable.
void main() {
  group('ProductDraft.fromApi', () {
    test('a successful read carries the card and marks what arrived', () {
      final ProductDraft draft = ProductDraft.fromApi(<String, dynamic>{
        'found': true,
        'cached': false,
        'outcome': 'succeeded',
        'image_phash': '0000000000000000c3a5f0e1d2b47896',
        'name': 'Süt Tam Yağlı 1 L',
        'brand': 'Pınar',
        'description': null,
        'category_id': 'cat-1',
        'category_label': 'Milk',
        'unit': 'C62',
      });

      expect(draft.recognised, isTrue);
      expect(draft.name, 'Süt Tam Yağlı 1 L');
      expect(draft.unit, 'C62');

      // The description came back null, so it was never inferred and must never carry a mark: a
      // field the user is about to fill from nothing is theirs, not a guess of ours.
      expect(draft.inferred, <String>{'name', 'brand', 'category', 'unit'});
      expect(draft.isUnconfirmed('description'), isFalse);
      expect(draft.isUnconfirmed('unit'), isTrue);
    });

    test('a read that recognised nothing still carries its hash', () {
      final ProductDraft draft = ProductDraft.fromApi(<String, dynamic>{
        'found': false,
        'cached': false,
        'outcome': 'no_credit',
        'image_phash': '0000000000000000c3a5f0e1d2b47896',
        'name': null,
      });

      expect(draft.recognised, isFalse);
      expect(draft.outcome, 'no_credit');
      // A card typed by hand is still a card for that photograph, so the hash has to survive to the
      // save: it is what makes the next photograph of the same box free.
      expect(draft.imagePhash, '0000000000000000c3a5f0e1d2b47896');
      expect(draft.inferred, isEmpty);
    });

    test('a cached read says so and reports no outcome', () {
      final ProductDraft draft = ProductDraft.fromApi(<String, dynamic>{
        'found': true,
        'cached': true,
        'outcome': null,
        'image_phash': '0000000000000000c3a5f0e1d2b47896',
        'name': 'Süt Tam Yağlı 1 L',
      });

      expect(draft.cached, isTrue);
      // Null rather than `succeeded`: nothing was asked of a model, and an outcome here would put a
      // call that never happened into the story the screen tells.
      expect(draft.outcome, isNull);
    });
  });

  group('editing', () {
    final ProductDraft read = ProductDraft.fromApi(<String, dynamic>{
      'found': true,
      'image_phash': 'h',
      'name': 'Süt',
      'brand': 'Pınar',
      'unit': 'C62',
    });

    test('saving a field clears its mark even when the value did not change', () {
      final ProductDraft after = read.withField('unit', 'C62');

      // D53: looking is not confirming, but agreeing is. A mark surviving an unchanged save would
      // tell the user the app had not noticed them agreeing.
      expect(after.unit, 'C62');
      expect(after.isUnconfirmed('unit'), isFalse);
    });

    test('clearing a field really clears it', () {
      final ProductDraft after = read.withField('brand', null);

      // The conventional `brand ?? this.brand` shape would put the model's answer back, which is
      // the opposite of what deleting a wrong brand means.
      expect(after.brand, isNull);
      expect(after.isUnconfirmed('brand'), isFalse);
    });

    test('editing one field leaves every other one alone', () {
      final ProductDraft after = read.withField('brand', 'Sütaş');

      expect(after.brand, 'Sütaş');
      expect(after.name, 'Süt');
      expect(after.unit, 'C62');
      expect(after.imagePhash, 'h');
      expect(after.recognised, isTrue);
    });

    test('a field name nothing renders is a failure rather than a no-op', () {
      // An editor that silently did nothing is the failure this screen already shipped once, as a
      // page of empty `onTap`s, and a typo in a key is exactly how it would come back.
      expect(() => read.withField('colour', 'red'), throwsArgumentError);
    });
  });

  group('toCreatePayload', () {
    test('an unfilled optional field is absent rather than null', () {
      final ProductDraft draft = ProductDraft.fromApi(<String, dynamic>{
        'image_phash': 'h',
        'name': 'Süt',
      });

      final Map<String, dynamic> payload = draft.toCreatePayload();

      // `base_unit: null` passes validation on the server and then throws inside the model's own
      // mutator, so "the caller named nothing" has to arrive as an omission.
      expect(payload.containsKey('base_unit'), isFalse);
      expect(payload.containsKey('brand'), isFalse);
      expect(payload['name'], 'Süt');
      expect(payload['image_phash'], 'h');
    });

    test('a hash-less draft does not send an empty hash', () {
      final ProductDraft draft = ProductDraft(
        imagePhash: '',
        name: 'Süt',
      );

      // The server validates this as 32 hex characters, so an empty string is a 422 on a field the
      // user never touched.
      expect(draft.toCreatePayload().containsKey('image_phash'), isFalse);
    });

    test('every filled field reaches the payload under its api name', () {
      final ProductDraft draft = ProductDraft(
        imagePhash: 'h',
        name: 'Süt',
        brand: 'Pınar',
        sku: 'SUT-1',
        unit: 'C62',
        categoryId: 'cat-1',
        shelfLifeDays: 7,
      );

      expect(draft.toCreatePayload(), <String, dynamic>{
        'name': 'Süt',
        'brand': 'Pınar',
        'sku': 'SUT-1',
        'base_unit': 'C62',
        'product_category_id': 'cat-1',
        'default_shelf_life_days': 7,
        'image_phash': 'h',
      });
    });

    test('the category the read resolved is sent, not just drawn', () {
      final ProductDraft draft = ProductDraft.fromApi(<String, dynamic>{
        'image_phash': 'h',
        'name': 'Süt',
        'category_id': 'cat-1',
        'category_label': 'Milk',
      });

      // Without this the whole two-pass resolver produced a value the screen drew as a tag and
      // then dropped, `location_category_affinity` learned nothing from a photographed product,
      // and `Product::creating`'s category-to-unit inference could never fire.
      expect(draft.toCreatePayload()['product_category_id'], 'cat-1');
    });

    test('a shelf life the server would refuse never leaves the client', () {
      final ProductDraft draft = ProductDraft(imagePhash: 'h', name: 'Süt');

      // `default_shelf_life_days` is `min:1`, so a typed `0` would come back as a validation
      // sentence about a field the user thought they had cleared.
      expect(draft.withField('shelf_life', '0').shelfLifeDays, isNull);
      expect(draft.withField('shelf_life', '-3').shelfLifeDays, isNull);
      expect(draft.withField('shelf_life', '7').shelfLifeDays, 7);
    });
  });
}
