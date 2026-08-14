import 'package:depools/app/support/merge_unit_codes.dart';
import 'package:flutter_test/flutter_test.dart';

/// A late `GET /units` must not delete what the user did while it was in flight.
///
/// The request starts when the screen opens and a user can register a unit of their own before it
/// lands. Assigning the answer would replace the list, drop the code they just created, and leave the
/// combobox holding a `value` that is no longer among its `options`.
///
/// Same shape as the scan batch's commit sweep, which removed rows by a predicate after an await and
/// deleted work that had arrived in between. Twice in two changes is why this is a named function with a
/// test rather than care taken at the call site.
void main() {
  test('the server decides the order', () {
    // The picker is meant to read countable-first, then the rest, and that ordering is the server's
    // to make: it is the one place that knows which row is the default.
    expect(
      mergeUnitCodes(
        fromServer: <String>['C62', 'KGM', 'LTR'],
        known: <String>['C62'],
        selected: 'C62',
      ),
      <String>['C62', 'KGM', 'LTR'],
    );
  });

  test('a unit registered while the request was out survives it', () {
    // The defect this exists for. Assigning the response here would drop `KOLI` entirely.
    expect(
      mergeUnitCodes(
        fromServer: <String>['C62', 'KGM'],
        known: <String>['C62', 'KGM', 'KOLI'],
        selected: 'KOLI',
      ),
      <String>['C62', 'KGM', 'KOLI'],
    );
  });

  test('the selected code is present even when neither list holds it', () {
    // A combobox whose `value` is missing from its `options` is the render this protects against, so
    // the selection is appended rather than assumed to be in one of the two lists.
    expect(
      mergeUnitCodes(
        fromServer: <String>['C62'],
        known: <String>['C62'],
        selected: 'GONE',
      ),
      <String>['C62', 'GONE'],
    );
  });

  test('nothing is listed twice', () {
    // The three sources overlap by construction: the selection is usually in both lists already.
    expect(
      mergeUnitCodes(
        fromServer: <String>['C62', 'KGM'],
        known: <String>['KGM', 'C62'],
        selected: 'KGM',
      ),
      <String>['C62', 'KGM'],
    );
  });

  test('a server list that lost a code the screen still holds keeps it', () {
    // Not a case anything produces today, and the honest behaviour anyway: the screen cannot render a
    // selection it has thrown away, and a vocabulary shrinking under a user mid-form is not something to
    // resolve silently in favour of the server.
    expect(
      mergeUnitCodes(
        fromServer: <String>['C62'],
        known: <String>['C62', 'KGM'],
        selected: 'KGM',
      ),
      <String>['C62', 'KGM'],
    );
  });
}
