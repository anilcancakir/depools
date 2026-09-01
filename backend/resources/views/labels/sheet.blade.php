{{--
    One sheet of labels, in millimetres, for both artefacts (D18 reversed, D71).

    This template produces the PDF that prints AND the PNG that previews, which is the whole point of
    reversing D18: rendering the same sheet twice, once in Dart for the preview and once for the file,
    means two layouts that drift.

    Four Chromium facts shape the CSS below and each is a failure mode rather than a footnote:

    1. Millimetres come from `Browsershot::paperSize`, not from `@page`, because Chromium ignores an
       `@page` size unless told to prefer it. So `@page` here only zeroes the margin.
    2. Turkish glyphs come from base64 `@font-face`, not from a font installed in the image, because a
       laptop and a container never have the same set and `Ğ ğ İ Ş ş` live in `latin-ext`.
    3. Assets are inline: external URLs do not load, so the barcode is an SVG element rather than an
       image the template fetches.
    4. Print media strips backgrounds, so anything relying on a fill needs `print-color-adjust: exact`
       alongside Browsershot's own `showBackground()`.

    Absolute positioning rather than a grid or flex, deliberately: every cell's millimetres come from
    the catalogue, and a die-cut does not care about content flow. `page-break-after` is what splits
    the sheets, so a batch of 30 on a 24-up template is two pages of one document.
--}}
<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <style>
        @font-face {
            font-family: 'LabelSans';
            src: url(data:font/ttf;base64,{{ $fontSans }}) format('truetype');
            font-weight: 100 900;
        }

        @font-face {
            font-family: 'LabelMono';
            src: url(data:font/ttf;base64,{{ $fontMono }}) format('truetype');
            font-weight: 100 900;
        }

        @page { margin: 0; }

        * { box-sizing: border-box; }

        html, body {
            margin: 0;
            padding: 0;
            font-family: 'LabelSans', sans-serif;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }

        .sheet {
            position: relative;
            width: {{ $template->pageWidth }}mm;
            height: {{ $template->pageHeight }}mm;
            overflow: hidden;
        }

        /* **Insurance, not the mechanism, and a mutation test is what established that.** Each
           sheet is exactly the page height, so the sheets already fall one per page without this and
           removing it changes nothing measurable: `LabelRenderTest` still counted 2 pages for 66
           stickers on a 65-cell template. It stays because "one sheet per page" should be stated
           rather than left to two numbers happening to be equal, and because a future template whose
           height is a hair under the page would otherwise slide every cell after it. What the test
           DOES guard is that N sheets produce exactly N pages, so a rounding error that inserted a
           blank one would be caught. */
        .sheet + .sheet { page-break-before: always; }

        .cell {
            position: absolute;
            overflow: hidden;
            display: flex;
            flex-direction: column;
            justify-content: center;
            /* 1 mm of breathing room inside the die-cut, because a printer's registration drifts by
               more than nothing and ink at the very edge of a sticker peels first. */
            padding: 1mm 1.5mm;
        }

        .name {
            font-weight: 700;
            line-height: 1.15;
            overflow: hidden;
        }

        .code {
            font-family: 'LabelMono', monospace;
            letter-spacing: 0.02em;
        }

        .meta { color: #333; }

        .barcode { display: block; }

        .barcode svg { display: block; }
    </style>
</head>
<body>
@foreach ($pages as $page)
    <div class="sheet">
        @foreach ($page as $cell)
            <div class="cell" style="
                left: {{ $cell['x'] }}mm;
                top: {{ $cell['y'] }}mm;
                width: {{ $template->labelWidth }}mm;
                height: {{ $template->labelHeight }}mm;
                font-size: {{ $cell['fontSize'] }}pt;
            ">
                @if ($sheet->shows('name'))
                    <div class="name">{{ $cell['line']->name }}</div>
                @endif

                @if ($sheet->shows('code') && $cell['line']->code !== null)
                    <div class="barcode">{!! $cell['barcode'] !!}</div>
                    <div class="code">{{ $cell['line']->code }}</div>
                @endif

                @if ($sheet->shows('location') && $cell['line']->location !== null)
                    <div class="meta">{{ $cell['line']->location }}</div>
                @endif

                @if ($sheet->shows('team') && $cell['line']->team !== null)
                    <div class="meta">{{ $cell['line']->team }}</div>
                @endif
            </div>
        @endforeach
    </div>
@endforeach
</body>
</html>
