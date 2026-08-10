# Feature: barcode labels and printing

Print barcode labels for items that have none, so they can be scanned later.

Decision D18 in `open-decisions.md`.

## Why this is in v1

It closes the loop. A workshop's bin of unmarked brackets cannot be scanned, so it cannot be tracked quickly. Print a label, stick it on, and every future interaction becomes a scan instead of a search.

It is also a paid-tier feature in the category (Sortly gates label creation by tier), which makes it a reasonable thing for a business user to expect.

## v1 scope: A4 sheets, rendered on the backend

Standard label sheets on an ordinary office printer. Multi-up layouts at exact millimetre dimensions.

One Blade template rendered by `spatie/browsershot`, producing the PDF that prints and the PNG that previews. The mechanics, the four Chromium facts that decide whether it works, and the one-engine constraint are in "Rendering happens on the backend" below.

> **This section used to argue the opposite, and the argument is kept because its risk is still real.**
> It proposed generating the sheet in Dart with `pdf` plus `barcode_widget`, for three reasons: it
> removes the server Chrome dependency, which was the MVP's most fragile operational component and
> broke deploys on a Chrome, Node or npm path; vector drawing beats rasterising an HTML page; and a
> label sheet is a deterministic grid with no JavaScript, where a headless browser earns nothing.
>
> D18's reversal accepts every one of those costs and rejects the conclusion, because the alternative
> was not free. Rendering the same sheet twice, once in Dart for the preview and once for the file,
> means two layouts that drift; the printable artefact is a PDF whatever produces it; and a Dart-drawn
> grid has to re-implement text fitting, barcode symbology and page geometry that an HTML renderer
> already does. What the reversal owes in exchange is named rather than waved away: exact millimetres,
> Turkish glyphs, inlined assets and print backgrounds, each below with its mitigation.

The label size and page catalog is ported from the MVP's `config/labels.php`, which is genuinely good: 17 label sizes, 5 page sizes, and multi-up sheet definitions like `a4_8_up_105x70`.

## Flow

Three decisions, not the MVP's eight-state modal machine with no back button.

1. **Choose what to print.** One product, a selection, or everything in a location. Quantity per item.
2. **Choose the layout.** Label size, sheet template, and what appears on the label (product name, barcode, location, team name).
3. **Preview and print.** A real preview of the sheet, then the system print dialog or a PDF download.

**They are three sections of one screen, not three steps of a wizard** (D42). The wizard was
the MVP's failure and "every step has a back path" was the reaction to it; a screen with no
sequential gate at all satisfies that in its strongest form, because there is no step to be
stuck on. It also means changing the sheet template re-renders the preview beside it rather
than requiring two navigations to see the effect, which is the comparison the whole screen
exists to support.

Defaults are remembered per tenant, so the second print is two taps.

## What the screen shows

**Two previews, because one cannot do both jobs.** The sheet is rendered at true A4
proportions with every cell drawn, filled or empty. One label is rendered separately at a
size a person can read. A single zoomable view would have to choose, and at sheet scale 9pt
type is about six pixels: showing it would be noise, and showing it larger would let a user
approve a name that does not actually fit.

**Empty cells are drawn, and that is the point of the sheet view** (D43). Paper is the
consumable, and choosing a template is choosing how much of it to throw away. Each template
in the list therefore carries both figures: pages, and cells printed blank. Pages alone
makes 24-up and 65-up look identical on a 21-label batch, when one wastes 3 labels and the
other wastes 44.

**The sheet is white in dark mode** (D44). It is a picture of paper, and a preview that
flipped with the app theme would be showing a sheet the printer cannot produce.

**A label count means two different things** (D45). A lot-tracked product's label identifies
the product, so twelve stickers are twelve copies of one design and the count is free. A
serial-tracked product's labels are all different, one per unit, so its count is the number
of selected serials and it has no stepper at all. A printed line loses its stepper too,
because its labels are already on a sheet.

**A field that does not fit is named, twice.** The label card keeps the name whole and marks
the casualty, and a callout below states the label's millimetres and the two real ways out.
Truncation reads as a design choice in a preview and as a defect on a sheet of 200.

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
3. The Chrome and Node paths are configuration rather than literals, so the same code renders against a
   laptop's own Chrome and a container's. **This criterion was reversed:** it used to forbid a
   server-side Chrome, Node or Browsershot dependency anywhere in the label path, which D18's reversal
   adopted deliberately. What replaces the prohibition is the constraint that made it attractive, which
   is that no environment may need a different renderer.
4. The flow presents three decisions with no sequential gate: any of them is reachable at any moment, so there is no step to have a back path from. This supersedes the original "three steps, each with a back path" wording; see D42 for why the stronger form is the one to test.
5. A partially printed batch is resumable.
6. An internally generated barcode cannot be confused with a manufacturer EAN-13.
7. Preview matches print output.

## Screens

| Screen | Route | States |
|---|---|---|
| `LabelPrintView` | `/etiket` | sheet preview with the item list and layout controls |

## What the design settled

- **It is reached from the product it labels**, through the detail screen's menu, rather than from a
  global menu. Until that entry point existed the screen was unreachable from the running app.
- **The preview and the controls sit side by side at width and stack below it.** The actions are
  deliberately NOT pinned, unlike every other terminal action in the app: they belong to the control
  column they sit in, and pinning them would break the pairing with the sheet they act on.
- **Millimetre dimensions are the point.** A label sheet that is nearly right is waste, so the
  preview is proportional to the real page rather than a decorative thumbnail.

## Rendering happens on the backend (D18 reversed, D71)

One Blade template, rendered by `spatie/browsershot`, producing two artefacts: the PDF that prints
and a PNG that previews. This is the MVP's shape deliberately, because it is the part of the MVP
that worked; the parts that did not are named below with what replaces them.

`spatie/browsershot` is at 5.4.0 (2026-05-26), MIT, roughly 38.8 million installs, and converts the
same HTML to either output. Verified on Packagist rather than assumed, because reversing D18 means
adopting the dependency it was written to avoid and a dead package would make that indefensible.

### One engine, and the hybrid is the binary path

The development machine may have no Docker and the server has it. That is a real constraint and it
has an answer that does not fork the renderer: Browsershot takes the Chrome and Node paths as
configuration, so local uses the machine's own Chrome and the server uses the image's. The MVP
already did exactly this (`config('app.chrome_path')`), which is the one piece of its label code
worth copying verbatim.

```
config/labels.php    chrome_path => env('CHROME_PATH')
                     node_path   => env('NODE_PATH')

.env  local          CHROME_PATH=/Applications/Google Chrome.app/.../Google Chrome
.env  server         CHROME_PATH=/usr/bin/chromium
```

**A driver per environment was considered and rejected.** `spatie/laravel-pdf` would let local run
Browsershot and the server run Gotenberg, which is attractive: the PHP image would host no Node and
Octane's memory profile would be simpler. Both engines even cover both outputs (Gotenberg 8 has
`/forms/chromium/screenshot/html`, checked). It is still the wrong trade here, because two engines
render subtly differently and this feature is judged on whether a sticker lands on a die-cut. The
thing tested locally has to be the thing that prints.

What that leaves us owing: Node and Puppeteer have to exist on a development machine, and Chrome's
process lifecycle inside a long-lived Octane worker needs attention rather than luck.

### Four Chromium facts that decide whether this works

Each is a failure mode rather than a configuration footnote. Verified against Gotenberg's conversion
documentation, which applies to any Chromium-driven renderer.

**Exact millimetres.** Chromium ignores the `@page` rule unless told to prefer it, so a 38x21 mm
label becomes 38x21 mm of a page that is not the page you asked for and the sheet misses the
die-cut. The MVP sidestepped this by passing `paperSize($width, $height)` with zeroed margins rather
than relying on CSS, which is the more direct route and the one to keep.

**Turkish glyphs.** Only fonts available to the renderer can be used, and a development machine and
a container never have the same set. `DESIGN.md` is explicit that `Ğ ğ İ Ş ş` live in `latin-ext` and
that loading only `latin` fails in a way that looks like a fallback glitch. On a label that failure
is printed onto adhesive paper.

So the fonts are **embedded in the template as base64 `@font-face`**, not installed in the image:
the same bytes render everywhere, and the guarantee survives a change of engine. And it is
**asserted by a test** rather than trusted, because font provisioning fails silently: render a label
carrying all five letters and assert the extracted text matches with no tofu (`U+25A1`). That needs
`pdftotext` from poppler-utils in CI, which is the cost of the guarantee being real.

**Assets must be inlined.** External URLs do not load, so a barcode belongs in the HTML as inline
SVG rather than as an image the template fetches.

**Print media strips backgrounds.** Anything relying on a background colour needs `printBackground`
and `-webkit-print-color-adjust: exact`. Mostly a filled status band; black-on-white text is
unaffected.

### Delivery: synchronous file, cached preview

The PDF returns inside the request. On web it opens in a tab, on mobile it goes to the share sheet,
which is where printing, saving and sending all already live. A sheet is a handful of pages and a
few seconds; a queue plus a notification for 24 labels is ceremony the user did not ask for.

The preview PNG is cached in storage under a hash of the template plus its data, exactly as the MVP
did. That is what makes a preview affordable: the same sheet is never rendered twice, and changing a
template or a field produces a new key rather than a stale image.

The threshold where this stops being right is real and worth naming now: a job large enough to risk
a request timeout belongs on the queue. It is not v1's problem, and the sync path is what v1 ships.

### What the app shows in the meantime

`LabelPreview` draws a placeholder at the page's real proportion. Drawing an accurate sheet in Dart
would mean re-implementing the renderer in order to preview the renderer, which is the duplication
that reversing D18 exists to avoid. Once the endpoint exists the app shows the server's own PNG, so
the preview and the print are the same artefact by construction rather than by care.

This is also why the field chips have no consumer yet: they choose what the TEMPLATE includes, and
the template lives on the backend.

## Open

- Which sheet templates Turkish stationery shops actually sell. The MVP's catalog is generic and may not match locally available label sheets, which would make the feature useless in practice. Worth checking before finalising the list.
- Whether QR codes should be offered alongside linear barcodes. QR holds more and scans faster on phones, but linear barcodes work with cheap handheld scanners a shop may already own.
- Whether labels should encode a URL that opens the product in the app, which would make a label useful to someone without the app installed.
