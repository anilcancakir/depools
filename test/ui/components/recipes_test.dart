import 'package:flutter_test/flutter_test.dart';
import 'package:depools/ui/components/callout/callout.recipe.dart';
import 'package:depools/ui/components/tag/tag.recipe.dart';

/// Recipe functions are pure: they map variant selections to a className string
/// with no theme dependency (the semantic aliases resolve at render time). These
/// tests pin the recipe output so a token change is a deliberate, reviewed diff.
void main() {
  group('tagRecipe', () {
    test('neutral + sm carries the base, intent, and size tokens in order', () {
      final cls = tagRecipe(variants: {'intent': 'neutral', 'size': 'sm'});
      expect(cls, contains('rounded-full')); // base
      expect(cls, contains('bg-surface-container-high')); // neutral intent
      expect(cls, contains('px-2 py-0.5 text-xs')); // size sm
      // Emission order: base before variants.
      expect(cls.indexOf('rounded-full'), lessThan(cls.indexOf('bg-surface-container-high')));
    });

    test('danger + md swaps the intent and size tokens', () {
      final cls = tagRecipe(variants: {'intent': 'danger', 'size': 'md'});
      expect(cls, contains('bg-destructive-container'));
      expect(cls, contains('px-2.5 py-1 text-sm'));
      expect(cls, isNot(contains('bg-surface-container-high')));
    });

    test('defaults resolve when no variants are passed', () {
      final cls = tagRecipe();
      expect(cls, contains('bg-surface-container-high')); // default neutral
      expect(cls, contains('text-xs')); // default sm
    });

    test('caller className appends last', () {
      final cls = tagRecipe(variants: {'intent': 'primary', 'size': 'sm'}, className: 'ml-2');
      expect(cls, endsWith('ml-2'));
    });
  });

  group('calloutRecipe', () {
    test('each intent selects its own container tone', () {
      expect(calloutRecipe(variants: {'intent': 'neutral'}), contains('bg-surface-container-high'));
      expect(calloutRecipe(variants: {'intent': 'info'}), contains('bg-primary-container'));
      expect(calloutRecipe(variants: {'intent': 'danger'}), contains('bg-destructive-container'));
    });

    test('base layout tokens are always present', () {
      final cls = calloutRecipe(variants: {'intent': 'info'});
      expect(cls, contains('rounded-lg'));
      expect(cls, contains('flex flex-col'));
    });
  });
}
