/// The two figures a count sheet reports about itself, as arithmetic that can be asserted.
///
/// **They live here because both of them shipped wrong and the first tests for them were vacuous.**
/// Written inline in the view, each one could only be checked by re-implementing it in the test, and
/// a test that mirrors the code it checks certifies the bug rather than catching it. Pulled out, the
/// view and the test call the same function.
///
/// Neither is a business rule, so neither belongs on a model: they are what the screen says about its
/// own progress. What makes them worth naming is that both were wrong in ways nothing could see, and
/// one of them printed a negative quantity at the user.
library;

/// How many rows on this shelf are still untouched.
///
/// **From the shelf total, never from the rows on screen.** It was `lines.length - counted`, and the
/// sheet excludes settled rows while the count deliberately includes them: four saved rows hidden on
/// a shelf of twenty-five reported seventeen skipped instead of twenty-one, and a whole shelf settled
/// reported `-25`.
///
/// Floored at zero, because the two inputs come from different places (the server's total and the
/// screen's own state) and a disagreement has to read as nothing left rather than as a negative
/// quantity.
int rowsLeftToCount({required int shelfTotal, required int counted}) {
  final int left = shelfTotal - counted;

  return left < 0 ? 0 : left;
}

/// Whether every row on this shelf has been counted and committed.
///
/// **False while a search is narrowing the sheet, and that is the whole content of this function.**
/// The shelf total is the count MATCHING THE QUERY, so searching two rows out of twenty-five and
/// saving both made `settled >= shelfTotal` true and announced the shelf finished over twenty-three
/// untouched rows. Settled rows can also come from outside the current query, counted before the
/// search was typed, so the comparison could pass without the visible rows being touched at all.
///
/// A shelf cannot be declared finished from a slice of it. Clearing the search brings the state back,
/// which is the honest sequence: see the whole shelf, then be told it is done.
bool shelfIsFinished({
  required bool searching,
  required int settled,
  required int shelfTotal,
  required int pendingCounts,
}) {
  if (searching || shelfTotal <= 0 || pendingCounts > 0) return false;

  return settled >= shelfTotal;
}
