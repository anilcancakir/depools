# Feature: barcode labels and printing

> Summary depth. Deepens after the design mockups settle the interaction decisions.

Print barcode labels for items that have none, so they can be scanned later.

Decision D18 in `open-decisions.md`.

## Why this is in v1

It closes the loop. A workshop's bin of unmarked brackets cannot be scanned, so it cannot be tracked quickly. Print a label, stick it on, and every future interaction becomes a scan instead of a search.

It is also a paid-tier feature in the category (Sortly gates label creation by tier), which makes it a reasonable thing for a business user to expect.

## v1 scope: A4 sheets, generated client-side

Standard label sheets on an ordinary office printer. Multi-up layouts at exact millimetre dimensions.

Generated in Dart with `pdf` plus `barcode_widget`, laid out with precise `PdfPageFormat.mm` dimensions. This is a deliberate change from the MVP, which generated label PDFs server-side with Browsershot and headless Chrome.

Three reasons client-side wins here:

1. **It removes the server Chrome dependency entirely**, which was the MVP's most fragile operational component. Chrome path, Node path and npm path were all environment configuration, and deploys broke on them.
2. **Fidelity is equal or better.** Vector barcode and text drawing beats rasterising an HTML page.
3. A label sheet is a deterministic grid with no JavaScript, no webfonts and no dynamic content. It is exactly the case where a headless browser earns nothing.

The label size and page catalog is ported from the MVP's `config/labels.php`, which is genuinely good: 17 label sizes, 5 page sizes, and multi-up sheet definitions like `a4_8_up_105x70`.

## Flow

Three steps, not the MVP's eight-state modal machine with no back button.

1. **Choose what to print.** One product, a selection, or everything in a location. Quantity per item.
2. **Choose the layout.** Label size, sheet template, and what appears on the label (product name, barcode, location, team name).
3. **Preview and print.** A real preview of the sheet, then the system print dialog or a PDF download.

Defaults are remembered per tenant, so the second print is two taps.

## Barcode generation for items with none

An item without a barcode gets one generated. Internal codes use a symbology that will not collide with real retail barcodes (Code128 with a tenant prefix rather than a fabricated EAN-13), so scanning an internal label can never be mistaken for a manufacturer barcode.

## Batch printing

A batch is a saved set of labels to print together, which matters when labelling a new delivery or relabelling a shelf. Items can be added to a batch over time and printed once. Printed items are marked, so a partially printed batch is resumable.

This existed in the MVP (`print_batches`, `print_batch_items`) and the data model was sound. The wizard around it was not.

## v2: Bluetooth thermal printers

Deferred at Anılcan's direction, and treated as a placeholder here. Two findings to carry into that work, both verified:

**Niimbot enforces consumable DRM in firmware.** From the maintainer of the leading reverse-engineered client: "Printer does not allow to print on non-rfid labels (you will get near-zero density). This is firmware limitation... The only way to bypass that is using rfid tags that the printer considers valid or using patched firmware." Users report generic label rolls are half the price, and a firmware update has been reported to retroactively break previously working third-party rolls. This is a consumables cost we cannot engineer around, and it must be disclosed rather than discovered.

**iOS may be impossible for some units.** iOS cannot use Bluetooth Classic SPP without MFi certification, which no Niimbot unit has. Only units exposing BLE GATT are reachable from iOS, and Niimbot has shipped batches both ways. Web cannot print to Bluetooth thermal printers at all.

**Protocol reality.** The wire protocol is well reverse-engineered and documented in a community wiki, but model divergence is real: `PrintStart` has four different byte-length formats and `SetPageSize` has six, depending on model generation. A correct implementation branches per detected model.

**Licensing.** Port from MIT-licensed reference implementations (`niimblue`, `niimbluelib`, `AndBondStyle/niimprint`). Do not copy from `labbots/NiimPrintX`, which is GPL-3.0 and would create a licensing obligation on a proprietary codebase. Verified by reading the LICENSE files directly; GitHub's own licence detection reports nothing for these repositories, which is misleading.

**Protocol priority when it happens.** TSPL first, not Niimbot. It is officially documented rather than reverse-engineered, and it is what the cheap Xprinter, TSC and Argox units sold in Turkey actually speak. Niimbot second, because it is the cheapest hardware a Turkish small business actually buys (roughly 1.000 to 2.000 TRY against 18.000+ for a TSC industrial unit).

## Error and empty states

- **No printer available.** Offer PDF download. A user with no printer at hand still gets the file.
- **Product with no barcode.** Offer to generate one, do not block.
- **Layout does not fit.** If the chosen label size cannot hold the requested content, say which field will not fit rather than silently truncating.
- **Partial print.** A jammed printer means the user reprints a range. Batch items track printed state so this is possible.
- **Web platform.** A4 sheet generation and printing work. Thermal printing is unavailable and is not advertised there.

## Quota effects

None. Label generation is local computation.

## Acceptance criteria

1. A sheet of 8 labels at 105x70mm prints at correct physical dimensions on a real A4 printer, measured with a ruler.
2. Generated barcodes scan successfully with our own scanner and with a third-party scanner app.
3. No server-side Chrome, Node or Browsershot dependency exists anywhere in the label path.
4. The flow completes in three steps, and every step has a back path.
5. A partially printed batch is resumable.
6. An internally generated barcode cannot be confused with a manufacturer EAN-13.
7. Preview matches print output.

## Open

- Which sheet templates Turkish stationery shops actually sell. The MVP's catalog is generic and may not match locally available label sheets, which would make the feature useless in practice. Worth checking before finalising the list.
- Whether QR codes should be offered alongside linear barcodes. QR holds more and scans faster on phones, but linear barcodes work with cheap handheld scanners a shop may already own.
- Whether labels should encode a URL that opens the product in the app, which would make a label useful to someone without the app installed.
