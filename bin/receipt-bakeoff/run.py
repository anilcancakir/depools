"""Runs the receipt bake-off: every candidate model against every scenario.

The prompt and the schema are copied VERBATIM from
`backend/app/Ai/LaravelAi/LaravelAiReceiptExtractionGateway.php`. That is the whole point: this
repository has already been burned once by a bake-off run against a paraphrase, which ranked the
wrong model first. A model is fast and accurate at the task it is actually given.

One model per request, no `models` fallback array, because the question is which model answered.
`usage: {include: true}` asks OpenRouter for the real billed cost rather than trusting local
arithmetic over a price table that has already gone stale once.
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
import base64
import json
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions'

# Verbatim from the gateway. Do not tidy: the wording is the thing under test.
INSTRUCTIONS = """You transcribe a photographed retail receipt for an inventory application.

The receipt is usually Turkish, printed by a fiscal till on thermal paper, and often faded,
creased or photographed at an angle.

Rules, in order of importance:
1. Transcribe each item line EXACTLY as printed, including abbreviations. "PNR SUT 1LT" is
   returned as "PNR SUT 1LT". Never expand, translate, correct or tidy a product name: a
   later step resolves it, and it needs the original string to do that.
2. When you cannot read a value, return null. Never estimate, never infer a price from a
   total, never complete a partly visible number. A null is a correct answer here and a
   plausible invention is the worst possible one.
3. Item lines only. A till prints a great deal that is not an item: TOPLAM, ARA TOPLAM, KDV,
   KDV ORANI, NAKIT, KREDI KARTI, PARA USTU, FIS NO, TARIH, SAAT, MERSIS, EKU NO, Z NO,
   barcodes, campaign lines and thank-you text. None of those is a line.
4. `confidence` is 0 to 100 and describes how clearly you could READ that line, not how well
   you understood the product. A crisp line whose abbreviation means nothing to you is high.
5. `raw_unit_code` is the token the till printed beside the quantity (AD, KG, LT, GR), copied
   verbatim. Do not map it to a standard code.
6. Quantities, prices and rates are returned as decimal strings using a dot, e.g. "1.240".
   The till prints Turkish decimal commas; convert the separator and nothing else.
7. `issued_on` is ISO 8601 (YYYY-MM-DD). A Turkish till prints DD/MM/YYYY, so read the day
   first. Return null when the date is not legible."""

INPUT_TEXT = 'Transcribe this receipt photograph.'


def nullable(kind, description=None):
    node = {'type': [kind, 'null']}
    if description:
        node['description'] = description
    return node


LINE_PROPS = {
    'raw_name': {'type': 'string',
                 'description': 'The item name EXACTLY as printed, abbreviations intact.'},
    'quantity': nullable('string'),
    'raw_unit_code': nullable('string',
                              'The unit token beside the quantity (AD, KG, LT), verbatim.'),
    'unit_price': nullable('string'),
    'line_total': nullable('string'),
    'vat_rate': nullable('string'),
    'confidence': nullable('integer', '0 to 100, how clearly this line could be READ.'),
}

SCHEMA_PROPS = {
    'supplier_name': nullable('string', 'The shop or company name printed at the top, verbatim.'),
    'supplier_tax_id': nullable('string', 'The tax number (VKN/TCKN) if printed, digits only.'),
    'invoice_number': nullable('string',
                               'The receipt or invoice number (FIS NO / FATURA NO) if printed.'),
    'issued_on': nullable('string',
                          'The date on the receipt as YYYY-MM-DD, or null if not legible.'),
    'total_amount': nullable('string',
                             'The grand total (TOPLAM) as a decimal string, or null.'),
    'currency': nullable('string', 'ISO 4217 code, TRY for a Turkish till.'),
    'lines': {
        'type': 'array',
        'description': 'The item lines only, in the order the paper printed them.',
        'items': {
            'type': 'object',
            'properties': LINE_PROPS,
            'required': list(LINE_PROPS),
            'additionalProperties': False,
        },
    },
}

RESPONSE_FORMAT = {
    'type': 'json_schema',
    'json_schema': {
        'name': 'extracted_receipt',
        'strict': True,
        'schema': {
            'type': 'object',
            'properties': SCHEMA_PROPS,
            'required': list(SCHEMA_PROPS),
            'additionalProperties': False,
        },
    },
}

# (label, model id, reasoning effort). The reasoning column is a variable on purpose: socOCRbench
# reports gemini-3.1-flash-lite scoring HIGHER at minimal than at low, and our config runs low.
CANDIDATES = [
    ('gemini-3.5-flash-lite', 'google/gemini-3.5-flash-lite', 'low'),
    ('gemini-2.5-flash-lite', 'google/gemini-2.5-flash-lite', 'low'),
    ('gemini-3.1-flash-lite', 'google/gemini-3.1-flash-lite', 'low'),
    ('gemini-3.1-flash-lite@min', 'google/gemini-3.1-flash-lite', 'minimal'),
    ('gemini-3-flash-preview', 'google/gemini-3-flash-preview', 'low'),
    ('qwen3-vl-32b', 'qwen/qwen3-vl-32b-instruct', 'low'),
    ('qwen3.5-flash', 'qwen/qwen3.5-flash-02-23', 'low'),
    ('qwen3.6-plus', 'qwen/qwen3.6-plus', 'low'),
    ('glm-5.3-flash', 'z-ai/glm-5.3-flash', 'low'),
    ('gpt-5.4-nano', 'openai/gpt-5.4-nano', 'low'),
    ('deepseek-v4-vision', 'deepseek/deepseek-v4-flash-vision-exp', 'low'),
]


def key():
    env = open(os.path.join(REPO, 'backend', '.env')).read()
    return re.search(r'^OPENROUTER_API_KEY=(.+)$', env, re.M).group(1).strip()


def call(api_key, model, effort, image_b64, timeout=90):
    body = {
        'model': model,
        'messages': [
            {'role': 'system', 'content': INSTRUCTIONS},
            {'role': 'user', 'content': [
                {'type': 'text', 'text': INPUT_TEXT},
                {'type': 'image_url',
                 'image_url': {'url': 'data:image/jpeg;base64,' + image_b64}},
            ]},
        ],
        'response_format': RESPONSE_FORMAT,
        'reasoning': {'effort': effort},
        'usage': {'include': True},
        'max_tokens': 8000,
    }

    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={
            'Authorization': 'Bearer ' + api_key,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://depools.ai',
            'X-Title': 'depools receipt bake-off',
        },
    )

    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as fh:
            payload = json.load(fh)
    except urllib.error.HTTPError as exc:
        return {'error': 'http %s: %s' % (exc.code, exc.read().decode()[:300]),
                'ms': int((time.time() - started) * 1000)}
    except Exception as exc:  # noqa: BLE001 - a transport failure is a result here, not a crash
        return {'error': '%s: %s' % (type(exc).__name__, exc),
                'ms': int((time.time() - started) * 1000)}

    ms = int((time.time() - started) * 1000)
    choice = (payload.get('choices') or [{}])[0]
    content = (choice.get('message') or {}).get('content')
    usage = payload.get('usage') or {}

    return {
        'ms': ms,
        'answered_by': payload.get('model'),
        'finish_reason': choice.get('finish_reason'),
        'content': content,
        'prompt_tokens': usage.get('prompt_tokens'),
        'completion_tokens': usage.get('completion_tokens'),
        'cost_usd': usage.get('cost'),
    }


def main():
    api_key = key()
    manifest = json.load(open(os.path.join(WORK, 'truth.json')))

    images = {}
    for entry in manifest:
        with open(entry['path'], 'rb') as fh:
            images[entry['id']] = base64.b64encode(fh.read()).decode()

    jobs = [(label, model, effort, entry['id'])
            for label, model, effort in CANDIDATES
            for entry in manifest]

    print('running %d calls (%d models x %d scenarios)' % (
        len(jobs), len(CANDIDATES), len(manifest)))

    results = []

    def work(job):
        label, model, effort, sid = job
        out = call(api_key, model, effort, images[sid])
        out.update({'label': label, 'model': model, 'effort': effort, 'scenario': sid})
        flag = 'ok ' if out.get('content') else 'ERR'
        print('%s %-26s %-20s %6sms %s' % (
            flag, label, sid, out.get('ms'), (out.get('error') or '')[:80]), flush=True)
        return out

    with ThreadPoolExecutor(max_workers=6) as pool:
        for out in pool.map(work, jobs):
            results.append(out)

    with open(os.path.join(WORK, 'raw.json'), 'w') as fh:
        json.dump(results, fh, ensure_ascii=False, indent=2)

    ok = sum(1 for r in results if r.get('content'))
    spend = sum(r.get('cost_usd') or 0 for r in results)
    print('\n%d/%d answered, total billed $%.4f' % (ok, len(results), spend))
    print('wrote %s' % os.path.join(WORK, 'raw.json'))


if __name__ == '__main__':
    sys.exit(main())
