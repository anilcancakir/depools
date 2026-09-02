# Receipt extraction bake-off

The harness O2 asks for. It runs every candidate model against a set of Turkish receipts whose
ground truth we hold, scores them on the failure modes that actually cost us, and prints a ranking.

`config/ai_gateways.php` records what the first run decided. This directory is how the next one is
run, and O2 is not closed until it runs against real photographs.

## Running it

From the repository root, with `OPENROUTER_API_KEY` in `backend/.env`:

```sh
python3 bin/receipt-bakeoff/gen_receipts.py    # renders the receipts + writes truth.json
python3 bin/receipt-bakeoff/run.py            # the matrix: every model x every scenario
python3 bin/receipt-bakeoff/score.py          # scores each answer against ground truth
python3 bin/receipt-bakeoff/report.py         # the tables worth reading
```

Everything it writes goes to `/tmp/bakeoff` (override with `BAKEOFF_DIR`), deliberately outside the
repository: the images are regenerable and the results are model output, neither of which belongs in
git history. The whole matrix billed $0.19 for 120 calls, so cost is not a reason to skip a re-run.

Editing the candidate list is `CANDIDATES` in `run.py`, one `(label, model, reasoning)` triple per
row. The same model at two reasoning levels is two rows, which is how the `minimal` against `low`
question got answered.

## The prompt is copied, and that is the point

`run.py` holds `INSTRUCTIONS` and the JSON schema **verbatim** from
`app/Ai/LaravelAi/LaravelAiReceiptExtractionGateway.php`. This repository has already been burned
once by a bake-off run against a paraphrase of its own prompt: it ranked a model first that returns
the name in the source language against the real instructions. A model is accurate at the task it is
actually given, so when the gateway's prompt changes, change the copy here in the same commit.

## What the scoring measures

Weights are in `score.py`, stated rather than buried. They follow the gateway's own rule order and
what the published evidence says goes wrong:

| Dimension | Weight | Why |
|---|---|---|
| `numeric` | 25 | quantity, unit price, line total, VAT rate against the printed value |
| `name_exact` | 20 | rule 1 is the first rule: the resolver needs the string as printed |
| `no_invention` | 20 | a number where the paper is unreadable is silent wrong stock |
| `lines_found` | 15 | the right set of lines came back at all |
| `no_furniture` | 10 | TOPLAM offered as a product is a row the user must delete |
| `date` | 5 | a day/month swap files stock on the wrong day |
| `total` | 5 | a "corrected" total is tampering |

Alignment between the answer and the truth is by diacritic-folded name, so a model that writes
`KAŞAR` where the till printed `KASAR` is scored as a NAME error rather than as a missing line.
Counting it as missing would penalise the same mistake twice and hide what it actually is.

## What it cannot prove

The receipts are **rendered, not photographed**. Crisp glyphs, one degraded scenario out of ten, no
thermal paper, no glare, no curl, no phone sensor. On the first run five models scored a perfect 100,
which is the tell: the set does not discriminate at the top, and the choice between the leaders fell
to cost and latency rather than accuracy.

Two failures the published benchmarks report for the leading family also failed to reproduce here:
nobody tampered with the total that is deliberately printed wrong, and nobody swapped a day for a
month. That is either the gateway's rules 2 and 7 earning their place or the paper being too clean,
and the cheap way to tell them apart is an ablation of the prompt rather than another model.

So: use it to narrow the field and to catch a model that breaks a rule. Do not use it to close O2.
