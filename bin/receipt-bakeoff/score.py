"""Scores the bake-off against ground truth, on the failure modes the evidence named.

Weights are stated here rather than buried, because a hidden weight cannot be argued with. They
follow the gateway's own rule order and ReceiptBench's findings:

- `invention` is the heaviest single penalty. A fabricated number where the paper is unreadable is
  the failure this whole category is accuracy-weighted for: it becomes wrong stock nobody notices.
- `furniture` is next. A TOPLAM row offered as a product is a line the user must delete, and rule 3
  of the instructions is explicit about it.
- `name_exact` carries real weight because rule 1 is the first rule: the resolver downstream needs
  the original string, so a tidied name is a broken contract even when it reads better.
- `numeric` covers quantity, unit price, line total and VAT rate together.
- `date` and `total` are single fields but both are silent-corruption vectors: a day/month swap
  files stock on the wrong day, and a "corrected" total is tampering.
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
import re
import unicodedata

WEIGHTS = {
    'lines_found': 15,
    'name_exact': 20,
    'numeric': 25,
    'no_invention': 20,
    'no_furniture': 10,
    'date': 5,
    'total': 5,
}

FURNITURE = [
    'TOPLAM', 'ARA TOPLAM', 'KDV', 'KDV ORANI', 'KDV TOPLAM', 'NAKIT', 'KREDI KARTI',
    'PARA USTU', 'FIS NO', 'TARIH', 'SAAT', 'MERSIS', 'EKU NO', 'Z NO', 'INDIRIM',
    'KAMPANYA', 'TESEKKUR', 'MF',
]

DIACRITICS = set('ıİğĞşŞüÜöÖçÇ')


def norm_name(value):
    if not isinstance(value, str):
        return ''
    return re.sub(r'\s+', ' ', value.strip()).upper()


def fold(value):
    """Strips diacritics, so a fold-equal pair differs only in Turkish characters."""
    decomposed = unicodedata.normalize('NFKD', value)
    stripped = ''.join(c for c in decomposed if not unicodedata.combining(c))
    return stripped.replace('ı', 'i').replace('İ', 'I').upper()


def number(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    try:
        return float(value.replace(',', '.').strip())
    except ValueError:
        return None


def same_number(a, b):
    na, nb = number(a), number(b)
    if na is None or nb is None:
        return na is None and nb is None
    return abs(na - nb) < 0.005


def align(truth_lines, got_lines):
    """Pairs returned lines to truth lines by folded-name match, then by order.

    Folded rather than exact so a diacritic error still ALIGNS and is then counted as a name error
    rather than as a missing line, which would double-penalise it.
    """
    pairs = []
    remaining = list(enumerate(got_lines))

    for ti, t in enumerate(truth_lines):
        target = fold(norm_name(t['raw_name']))
        hit = None
        for slot, (gi, g) in enumerate(remaining):
            if fold(norm_name(g.get('raw_name'))) == target:
                hit = slot
                break
        if hit is None:
            pairs.append((ti, None))
        else:
            gi, g = remaining.pop(hit)
            pairs.append((ti, g))

    return pairs, [g for _, g in remaining]


def score_one(truth, parsed):
    got = parsed.get('lines') if isinstance(parsed.get('lines'), list) else []
    got = [g for g in got if isinstance(g, dict) and str(g.get('raw_name') or '').strip()]

    truth_lines = truth['lines']
    pairs, extra = align(truth_lines, got)

    matched = [(t, g) for (ti, g), t in zip(pairs, truth_lines) if g is not None]
    missed = sum(1 for _, g in pairs if g is None)

    # 1. Did the right set of lines come back at all?
    lines_found = len(matched) / len(truth_lines) if truth_lines else 0.0

    # 2. Rule 1: the name exactly as printed.
    name_exact = sum(
        1 for t, g in matched if norm_name(g.get('raw_name')) == norm_name(t['raw_name'])
    ) / len(truth_lines) if truth_lines else 0.0

    # Diacritic-only misses, reported separately: same word, wrong Turkish characters.
    diacritic_errors = sum(
        1 for t, g in matched
        if norm_name(g.get('raw_name')) != norm_name(t['raw_name'])
        and fold(norm_name(g.get('raw_name'))) == fold(norm_name(t['raw_name']))
    )
    diacritic_lines = sum(1 for t in truth_lines if DIACRITICS & set(t['raw_name']))

    # 3. The numbers, excluding any field the paper does not actually show.
    illegible = set(truth.get('illegible') or [])
    checked = 0
    correct = 0
    for ti, (t, g) in enumerate(matched):
        index = truth_lines.index(t)
        for field in ('quantity', 'unit_price', 'line_total', 'vat_rate'):
            if 'lines.%d.%s' % (index, field) in illegible:
                continue
            checked += 1
            if same_number(g.get(field), t[field]):
                correct += 1
    numeric = correct / checked if checked else 0.0

    unit_checked = 0
    unit_correct = 0
    for t, g in matched:
        index = truth_lines.index(t)
        if 'lines.%d.raw_unit_code' % index in illegible:
            continue
        unit_checked += 1
        if str(g.get('raw_unit_code') or '').strip().upper() == t['raw_unit_code']:
            unit_correct += 1
    unit_exact = unit_correct / unit_checked if unit_checked else 0.0

    # 4. Inventions: a value where the paper shows nothing readable.
    inventions = 0
    for key in illegible:
        _, index, field = key.split('.')
        index = int(index)
        target = truth_lines[index]
        for t, g in matched:
            if t is target and g.get(field) is not None:
                inventions += 1
    no_invention = 1.0 if not illegible else max(0.0, 1 - inventions / len(illegible))

    # 5. Furniture offered as a product.
    furniture = 0
    for g in got:
        name = norm_name(g.get('raw_name'))
        if any(name == f or name.startswith(f + ' ') or name == f.replace(' ', '') for f in FURNITURE):
            furniture += 1
    no_furniture = 1.0 if furniture == 0 else max(0.0, 1 - furniture / 3)

    date_ok = (parsed.get('issued_on') or None) == truth['issued_on']
    total_ok = same_number(parsed.get('total_amount'), truth['total_amount'])

    parts = {
        'lines_found': lines_found,
        'name_exact': name_exact,
        'numeric': numeric,
        'no_invention': no_invention,
        'no_furniture': no_furniture,
        'date': 1.0 if date_ok else 0.0,
        'total': 1.0 if total_ok else 0.0,
    }
    total_score = sum(parts[k] * WEIGHTS[k] for k in WEIGHTS)

    return {
        'score': total_score,
        'parts': parts,
        'returned': len(got),
        'expected': len(truth_lines),
        'missed': missed,
        'extra': len(extra),
        'furniture': furniture,
        'inventions': inventions,
        'illegible_fields': len(illegible),
        'diacritic_errors': diacritic_errors,
        'diacritic_lines': diacritic_lines,
        'unit_exact': unit_exact,
        'date_got': parsed.get('issued_on'),
        'total_got': parsed.get('total_amount'),
    }


def main():
    manifest = {m['id']: m for m in json.load(open(os.path.join(WORK, 'truth.json')))}
    raw = json.load(open(os.path.join(WORK, 'raw.json')))

    rows = []
    for r in raw:
        entry = {
            'label': r['label'],
            'model': r['model'],
            'effort': r['effort'],
            'scenario': r['scenario'],
            'ms': r.get('ms'),
            'cost': r.get('cost_usd'),
            'prompt_tokens': r.get('prompt_tokens'),
            'completion_tokens': r.get('completion_tokens'),
            'finish_reason': r.get('finish_reason'),
        }

        if not r.get('content'):
            entry.update({'status': 'call_failed', 'error': r.get('error'), 'score': 0.0})
            rows.append(entry)
            continue

        try:
            parsed = json.loads(r['content'])
        except (json.JSONDecodeError, TypeError) as exc:
            entry.update({'status': 'unparseable', 'error': str(exc)[:120], 'score': 0.0})
            rows.append(entry)
            continue

        if not isinstance(parsed, dict):
            entry.update({'status': 'not_an_object', 'score': 0.0})
            rows.append(entry)
            continue

        entry.update({'status': 'ok'})
        entry.update(score_one(manifest[r['scenario']]['truth'], parsed))
        rows.append(entry)

    with open(os.path.join(WORK, 'scored.json'), 'w') as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=2)

    print('scored %d rows -> %s' % (len(rows), os.path.join(WORK, 'scored.json')))


if __name__ == '__main__':
    main()
