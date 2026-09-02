"""Aggregates the scored bake-off into the tables worth reading."""

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
import statistics as st
from collections import defaultdict


def pct(x):
    return '%.0f%%' % (100 * x)


def main():
    rows = json.load(open(os.path.join(WORK, 'scored.json')))
    by_model = defaultdict(list)
    for r in rows:
        by_model[r['label']].append(r)

    print('=== OVERALL, ranked by mean score out of 100 ===\n')
    print('%-26s %6s %6s %6s %6s %6s %5s %5s %7s %7s %9s' % (
        'model', 'score', 'lines', 'names', 'nums', 'noInv', 'date', 'total', 'p50ms', 'p95ms',
        '$/receipt'))

    summary = []
    for label, rs in by_model.items():
        ok = [r for r in rs if r.get('status') == 'ok']
        scores = [r['score'] for r in rs]
        lat = sorted(r['ms'] for r in rs if r.get('ms'))
        costs = [r['cost'] for r in rs if r.get('cost') is not None]

        def mean(field):
            vals = [r['parts'][field] for r in ok]
            return st.mean(vals) if vals else 0.0

        summary.append({
            'label': label,
            'score': st.mean(scores) if scores else 0.0,
            'lines': mean('lines_found'),
            'names': mean('name_exact'),
            'nums': mean('numeric'),
            'noinv': mean('no_invention'),
            'date': mean('date'),
            'total': mean('total'),
            'p50': lat[len(lat) // 2] if lat else 0,
            'p95': lat[max(0, int(len(lat) * 0.95) - 1)] if lat else 0,
            'cost': st.mean(costs) if costs else None,
            'failures': len(rs) - len(ok),
            'inventions': sum(r.get('inventions', 0) for r in ok),
            'furniture': sum(r.get('furniture', 0) for r in ok),
            'diacritic': sum(r.get('diacritic_errors', 0) for r in ok),
            'missed': sum(r.get('missed', 0) for r in ok),
            'extra': sum(r.get('extra', 0) for r in ok),
        })

    summary.sort(key=lambda s: -s['score'])
    for s in summary:
        print('%-26s %6.1f %6s %6s %6s %6s %5s %5s %7d %7d %9s' % (
            s['label'], s['score'], pct(s['lines']), pct(s['names']), pct(s['nums']),
            pct(s['noinv']), pct(s['date']), pct(s['total']), s['p50'], s['p95'],
            ('$%.4f' % s['cost']) if s['cost'] is not None else 'n/a'))

    print('\n=== FAILURE COUNTS (lower is better; totals across 10 scenarios) ===\n')
    print('%-26s %10s %10s %11s %8s %7s %9s' % (
        'model', 'inventions', 'furniture', 'diacritic', 'missed', 'extra', 'call fail'))
    for s in summary:
        print('%-26s %10d %10d %11d %8d %7d %9d' % (
            s['label'], s['inventions'], s['furniture'], s['diacritic'],
            s['missed'], s['extra'], s['failures']))

    print('\n=== THE FOUR DECISIVE SCENARIOS ===')
    interesting = {
        's05_faded_price': 'inventions (expected 2 nulls)',
        's10_total_mismatch': 'printed total 499.99 vs line sum 520.05',
        's04_date_ambiguous': 'issued_on must be 2026-03-05',
        's08_skew_blur': 'rotated, blurred, folded',
    }
    for sid, what in interesting.items():
        print('\n-- %s: %s' % (sid, what))
        subset = [r for r in rows if r['scenario'] == sid]
        subset.sort(key=lambda r: -r.get('score', 0))
        for r in subset:
            if r.get('status') != 'ok':
                print('   %-26s %s' % (r['label'], r.get('status')))
                continue
            print('   %-26s score %5.1f  lines %d/%d  inv %d  furn %d  date %s  total %s' % (
                r['label'], r['score'], r['returned'] - r['extra'], r['expected'],
                r['inventions'], r['furniture'], r.get('date_got'), r.get('total_got')))

    total_spend = sum(r['cost'] for r in rows if r.get('cost'))
    print('\ntotal billed for the whole bake-off: $%.4f' % total_spend)


if __name__ == '__main__':
    main()
