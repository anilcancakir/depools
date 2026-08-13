/// How far to trust what a scanned barcode resolved to.
///
/// **In the app layer rather than beside the widget that renders it, and that was a correction.**
/// It lived in `ui/components/scan_row/`, so `ScanEntry` and `ScanController` imported a UI
/// component to name a domain fact: non-UI logic pulling widget dependencies behind it, and a
/// circular import waiting for the component to need a model. `ScanRow` re-exports it, so reaching
/// it through the component still works for the widgets that already do.
/// Which stage of `barcode-and-catalog.md`'s resolution cascade answered a scan.
///
/// Five values rather than a confidence number, for the reason `open-decisions.md` D31
/// already settled for enrichment: a percentage invites arithmetic the user cannot do
/// anything with, while a named source tells them exactly how much to trust the row.
enum ScanSource {
  /// Stage 1: the tenant's own products. Authoritative, and the case the MVP broke.
  own,

  /// Stages 2 to 4: community catalog, Open Food Facts, or a paid lookup. Trustworthy
  /// enough to write without a mark.
  catalog,

  /// Stage 5: scraped, or a community row nobody has confirmed. Written, but presented
  /// as unverified because criterion 7 requires it.
  unverified,

  /// This barcode missed the whole cascade before and the user typed the product in.
  /// Their own past answer, replayed.
  recalled,

  /// Stage 6: nothing anywhere. Needs a photo or typing.
  unmatched,
}
