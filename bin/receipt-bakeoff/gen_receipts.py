"""Generates ten synthetic Turkish thermal receipts with known ground truth.

Each scenario targets one failure mode that either ReceiptBench named (value tampering, field
hallucination on absence, day/month swap, line-item structure, column misreads, decimal separator)
or that depools measured for itself (Turkish diacritics mangled by the cheap tier).

The output mirrors the app's own pipeline: JPEG at quality 85 with the longest edge at 2048, which
is `media.documents.stored_edge` and `jpeg_quality`, because that is the copy the gateway sends.

These are NOT photographs of real thermal paper. They narrow the field; they do not settle it.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
# Results and images stay OUT of the repository: they are regenerable, one is a directory of JPEGs,
# and the other holds model output that has no business in git history.
WORK = os.environ.get('BAKEOFF_DIR', '/tmp/bakeoff')
os.makedirs(WORK, exist_ok=True)
sys.path.insert(0, HERE)
import json
import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

OUT = os.path.join(WORK, 'receipts')
os.makedirs(OUT, exist_ok=True)

MONO = '/System/Library/Fonts/Supplemental/Courier New.ttf'
MONO_BOLD = '/System/Library/Fonts/Supplemental/Courier New Bold.ttf'

WIDTH = 700
MARGIN = 26
LINE_H = 34


def font(size, bold=False):
    return ImageFont.truetype(MONO_BOLD if bold else MONO, size)


def render(scenario):
    """Draws one receipt.

    Returns the image plus the y of each ITEM's quantity row, so a scenario can wash out a value
    by index instead of by hand-measured pixels.
    """
    rows = []
    qty_rows = []

    def add(text='', size=24, bold=False, align='left'):
        rows.append((text, size, bold, align))
        return len(rows) - 1

    head = scenario['header']
    add(head['name'], 28, True, 'center')
    for extra in head['extra']:
        add(extra, 22, False, 'center')
    add()
    add('-' * 42, 22)
    add('FIS NO: %s' % scenario['invoice_number'], 22)
    add('TARIH : %s        SAAT : %s' % (scenario['printed_date'], scenario['printed_time']), 22)
    add('-' * 42, 22)

    for line in scenario['lines']:
        add(line['printed_name'], 24, True)
        qty_rows.append(add('  ' + line['printed_qty_line'], 24))

    add('-' * 42, 22)
    for label, value in scenario['footer']:
        add('%-28s%14s' % (label, value), 24)
    add('-' * 42, 22)
    add('TESEKKUR EDERIZ', 24, False, 'center')
    add(scenario['tail'], 20, False, 'center')

    height = MARGIN * 2 + LINE_H * len(rows) + 40
    image = Image.new('L', (WIDTH, height), 250)
    draw = ImageDraw.Draw(image)

    ys = []
    y = MARGIN
    for text, size, bold, align in rows:
        ys.append(y)
        f = font(size, bold)
        x = (WIDTH - draw.textlength(text, font=f)) / 2 if align == 'center' else MARGIN
        # Thermal print is uneven: jitter each row and vary the ink density.
        draw.text((x + random.uniform(-1, 1), y), text, font=f, fill=random.randint(28, 62))
        y += LINE_H

    return image, [ys[i] for i in qty_rows]


def degrade(image, spec, qty_ys):
    if spec.get('fade_item') is not None:
        # A washed-out patch over one line's numbers. The printed value is genuinely unreadable, so
        # ground truth for those fields is null and any number returned is an invention.
        y = qty_ys[spec['fade_item']]
        box = (int(WIDTH * spec.get('fade_from', 0.46)), y - 6,
               int(WIDTH * spec.get('fade_to', 0.96)), y + LINE_H)
        patch = image.crop(box)
        patch = ImageEnhance.Brightness(patch).enhance(2.3)
        patch = patch.filter(ImageFilter.GaussianBlur(4.2))
        image.paste(patch, (box[0], box[1]))

    if spec.get('fold_at_frac'):
        y = int(image.height * spec['fold_at_frac'])
        band = image.crop((0, y - 16, image.width, y + 16))
        band = ImageEnhance.Brightness(band).enhance(0.82)
        image.paste(band, (0, y - 16))
        ImageDraw.Draw(image).line([(0, y), (image.width, y)], fill=160, width=2)

    if spec.get('contrast'):
        image = ImageEnhance.Contrast(image).enhance(spec['contrast'])

    if spec.get('blur'):
        image = image.filter(ImageFilter.GaussianBlur(spec['blur']))

    if spec.get('rotate'):
        image = image.rotate(spec['rotate'], resample=Image.BICUBIC, expand=True, fillcolor=248)

    if spec.get('noise'):
        px = image.load()
        for _ in range(int(image.width * image.height * spec['noise'])):
            x = random.randrange(image.width)
            y = random.randrange(image.height)
            px[x, y] = max(0, min(255, px[x, y] + random.randint(-70, 70)))

    return image


def finish(image):
    """The app's own downscale: longest edge 2048, JPEG quality 85."""
    scale = 2048 / max(image.size)
    if scale != 1:
        image = image.resize(
            (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
            Image.LANCZOS,
        )
    return image.convert('RGB')


def build(scenarios):
    manifest = []
    for s in scenarios:
        random.seed(s['seed'])
        image, qty_ys = render(s)
        image = degrade(image, s.get('degrade', {}), qty_ys)
        image = finish(image)
        path = os.path.join(OUT, '%s.jpg' % s['id'])
        image.save(path, 'JPEG', quality=85)
        manifest.append({
            'id': s['id'],
            'path': path,
            'tests': s['tests'],
            'size': list(image.size),
            'truth': s['truth'],
        })
        print('%-22s %-10s %6dkB  %s' % (
            s['id'], '%dx%d' % image.size, os.path.getsize(path) // 1024, s['tests'],
        ))

    with open(os.path.join(WORK, 'truth.json'), 'w') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print('\nwrote %s with %d scenarios' % (os.path.join(WORK, 'truth.json'), len(manifest)))


if __name__ == '__main__':
    from scenarios import SCENARIOS
    build(SCENARIOS)
