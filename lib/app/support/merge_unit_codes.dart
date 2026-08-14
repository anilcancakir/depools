/// The server's vocabulary, plus anything a screen already knew that it did not mention.
///
/// **A late response must not drop what the user did while it was in flight.** `GET /units` is started
/// when a screen opens, and a user can register a unit of their own before it lands; assigning the
/// answer would then replace the list, delete the code they just created, and leave a combobox holding a
/// `value` that is no longer among its `options`.
///
/// That is the same shape as the scan batch's commit sweep, which removed rows by a predicate after an
/// await and deleted work that had arrived in between. Twice in two changes is enough to make it a
/// named function with a test rather than care taken at each call site.
///
/// Server order leads, because that is the order the picker is meant to read in: the countable unit
/// first, then the rest. Whatever the screen holds and the server did not send follows, in the order the
/// screen holds it, with [selected] last so a chosen code is never missing from its own list.
List<String> mergeUnitCodes({
  required List<String> fromServer,
  required List<String> known,
  required String selected,
}) {
  final Set<String> seen = fromServer.toSet();

  return <String>[
    ...fromServer,
    for (final String code in <String>[...known, selected])
      if (seen.add(code)) code,
  ];
}
