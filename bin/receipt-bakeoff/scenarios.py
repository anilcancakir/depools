"""The ten scenarios and their ground truth.

The printed string and the expected answer come from ONE source per field, so the truth cannot drift
from the paper. `tr()` is the only place a decimal separator changes: the till prints a comma, rule 6
of the gateway's instructions asks for a dot, so `printed` carries the comma and `truth` the dot.
"""


def tr(value):
    """A decimal string as a Turkish till prints it."""
    return value.replace('.', ',')


def item(name, qty, unit, price, total, vat):
    """One item line: the two rows the till prints, plus what the answer should hold."""
    left = '%s %s x %s' % (tr(qty), unit, tr(price))
    return {
        'printed_name': name,
        'printed_qty_line': '%-22s%12s  %%%s' % (left, tr(total), vat),
        'truth': {
            'raw_name': name,
            'quantity': qty,
            'raw_unit_code': unit,
            'unit_price': price,
            'line_total': total,
            'vat_rate': vat,
        },
    }


def receipt(sid, tests, lines, printed_date, issued_on, total, footer, seed,
            supplier='MIGROS TICARET A.S.', invoice='0042', time='14:37',
            extra=None, degrade=None, illegible=None, tail='EKU NO: 0123  Z NO: 0456'):
    return {
        'id': sid,
        'tests': tests,
        'seed': seed,
        'header': {
            'name': supplier,
            'extra': extra if extra is not None else [
                'ATASEHIR SUBESI  NO: 1234',
                'TEL: 0216 123 45 67',
                'VKN: 1234567890',
            ],
        },
        'invoice_number': invoice,
        'printed_date': printed_date,
        'printed_time': time,
        'lines': lines,
        'footer': footer,
        'tail': tail,
        'degrade': degrade or {},
        'truth': {
            'supplier_name': supplier,
            'invoice_number': invoice,
            'issued_on': issued_on,
            'total_amount': total,
            'currency': 'TRY',
            'lines': [line['truth'] for line in lines],
            'illegible': illegible or [],
        },
    }


def totals(*pairs):
    return [(label, tr(value)) for label, value in pairs]


# --- 1. baseline -----------------------------------------------------------------------------

S1_LINES = [
    item('PNR SUT 1LT', '2', 'AD', '24.50', '49.00', '10'),
    item('ETI CIKOLATALI GOFRET', '3', 'AD', '7.75', '23.25', '10'),
    item('SEK KAYMAK 200G', '1', 'AD', '32.90', '32.90', '10'),
    item('COCA COLA 1LT', '2', 'AD', '19.95', '39.90', '10'),
    item('ELMA GOLDEN', '1.250', 'KG', '18.90', '23.63', '1'),
    item('DOMATES SALKIM', '0.840', 'KG', '24.50', '20.58', '1'),
    item('AYCICEK YAGI 2LT', '1', 'AD', '128.75', '128.75', '20'),
    item('DETERJAN 3KG', '1', 'AD', '89.90', '89.90', '20'),
]

# --- 2. diacritics ---------------------------------------------------------------------------

S2_LINES = [
    item('BEYPAZARI MADEN SUYU 200ML', '6', 'AD', '3.75', '22.50', '10'),
    item('ÜLKER ÇİKOLATALI BİSKÜVİ', '2', 'AD', '11.25', '22.50', '10'),
    item('SÜTAŞ AYRAN 250ML', '4', 'AD', '6.50', '26.00', '10'),
    item('ÇAYKUR RİZE ÇAYI 1KG', '1', 'AD', '154.90', '154.90', '10'),
    item('TORKU ŞEKER 1KG', '2', 'AD', '38.40', '76.80', '10'),
    item('KIRIKKALE BULGUR 1KG', '1', 'AD', '29.95', '29.95', '10'),
    item('İÇİM SÜT YARIM YAĞLI 1LT', '3', 'AD', '26.75', '80.25', '10'),
    item('YÖRSAN BEYAZ PEYNİR 600G', '1', 'AD', '112.50', '112.50', '10'),
]

# --- 3. multiply form ------------------------------------------------------------------------

S3_LINES = [
    item('SU 5LT', '3', 'AD', '12.50', '37.50', '10'),
    item('MAKARNA BURGU 500G', '12', 'AD', '9.95', '119.40', '10'),
    item('YUMURTA 15LI', '2', 'AD', '89.90', '179.80', '10'),
    item('TUVALET KAGIDI 16LI', '1', 'AD', '149.90', '149.90', '20'),
    item('CAMASIR SUYU 1LT', '4', 'AD', '18.75', '75.00', '20'),
    item('KURU FASULYE 1KG', '2', 'AD', '54.50', '109.00', '1'),
]

# --- 4. ambiguous date ----------------------------------------------------------------------

S4_LINES = [
    item('EKMEK TAM BUGDAY', '2', 'AD', '15.00', '30.00', '1'),
    item('KASAR PEYNIR 400G', '1', 'AD', '96.75', '96.75', '10'),
    item('ZEYTIN SIYAH 500G', '1', 'AD', '74.90', '74.90', '10'),
    item('CAY DEMLIK POSET 100', '1', 'AD', '48.50', '48.50', '10'),
    item('SALCA 700G', '2', 'AD', '42.25', '84.50', '10'),
]

# --- 5. faded price -------------------------------------------------------------------------

S5_LINES = [
    item('PIRINC BALDO 1KG', '2', 'AD', '68.50', '137.00', '1'),
    item('NOHUT 1KG', '1', 'AD', '46.90', '46.90', '1'),
    # This line's numbers are washed out by `fade_item`, so its truth is null.
    item('MERCIMEK KIRMIZI 1KG', '1', 'AD', '39.95', '39.95', '1'),
    item('BULGUR PILAVLIK 1KG', '1', 'AD', '27.50', '27.50', '1'),
    item('SIVI SABUN 1.5LT', '1', 'AD', '64.90', '64.90', '20'),
]

# --- 7. long receipt ------------------------------------------------------------------------

S7_POOL = [
    ('SUT 1LT', '2', 'AD', '24.50', '49.00', '10'),
    ('YOGURT 1KG', '1', 'AD', '54.90', '54.90', '10'),
    ('TEREYAG 250G', '1', 'AD', '98.75', '98.75', '10'),
    ('BEYAZ PEYNIR 500G', '1', 'AD', '104.50', '104.50', '10'),
    ('KASAR 200G', '2', 'AD', '58.25', '116.50', '10'),
    ('ZEYTIN YESIL 400G', '1', 'AD', '68.90', '68.90', '10'),
    ('EKMEK', '3', 'AD', '15.00', '45.00', '1'),
    ('SIMIT', '4', 'AD', '10.00', '40.00', '1'),
    ('CAY 500G', '1', 'AD', '84.50', '84.50', '10'),
    ('KAHVE 200G', '1', 'AD', '129.90', '129.90', '10'),
    ('SEKER 1KG', '2', 'AD', '38.40', '76.80', '10'),
    ('UN 2KG', '1', 'AD', '44.75', '44.75', '10'),
    ('MAKARNA 500G', '6', 'AD', '9.95', '59.70', '10'),
    ('PIRINC 1KG', '2', 'AD', '68.50', '137.00', '1'),
    ('NOHUT 1KG', '1', 'AD', '46.90', '46.90', '1'),
    ('SALCA 700G', '1', 'AD', '42.25', '42.25', '10'),
    ('AYCICEK YAGI 1LT', '2', 'AD', '68.90', '137.80', '20'),
    ('ZEYTINYAGI 500ML', '1', 'AD', '189.50', '189.50', '20'),
    ('DOMATES', '1.420', 'KG', '24.50', '34.79', '1'),
    ('SALATALIK', '0.680', 'KG', '19.90', '13.53', '1'),
    ('MUZ', '1.150', 'KG', '54.90', '63.14', '1'),
    ('ELMA', '2.300', 'KG', '18.90', '43.47', '1'),
    ('DETERJAN 3KG', '1', 'AD', '89.90', '89.90', '20'),
    ('BULASIK DETERJANI 1LT', '1', 'AD', '38.75', '38.75', '20'),
    ('CAMASIR YUMUSATICI 2LT', '1', 'AD', '72.50', '72.50', '20'),
]

S7_LINES = [item(*row) for row in S7_POOL]

# --- 8. skew and blur -----------------------------------------------------------------------

S8_LINES = [
    item('GAZOZ 250ML', '6', 'AD', '8.50', '51.00', '10'),
    item('CIPS 150G', '2', 'AD', '24.90', '49.80', '10'),
    item('KURUYEMIS KARISIK 250G', '1', 'AD', '134.50', '134.50', '10'),
    item('SU 0.5LT 12LI', '1', 'AD', '48.00', '48.00', '10'),
    item('KEK 300G', '2', 'AD', '31.75', '63.50', '10'),
    item('BISKUVI 200G', '3', 'AD', '14.25', '42.75', '10'),
]

# --- 9. weighed goods plus a discount -------------------------------------------------------

S9_LINES = [
    item('KIYMA DANA', '0.384', 'KG', '389.90', '149.72', '1'),
    item('TAVUK BUT', '1.240', 'KG', '89.90', '111.48', '1'),
    item('BALIK LEVREK', '0.615', 'KG', '249.50', '153.44', '1'),
    item('PATATES', '2.850', 'KG', '16.90', '48.17', '1'),
    item('SOGAN KURU', '1.075', 'KG', '14.50', '15.59', '1'),
]

# --- 10. printed total does not sum ---------------------------------------------------------

S10_LINES = [
    item('MISIR GEVREGI 500G', '1', 'AD', '78.90', '78.90', '10'),
    item('BAL 850G', '1', 'AD', '164.50', '164.50', '10'),
    item('RECEL VISNE 380G', '2', 'AD', '38.75', '77.50', '10'),
    item('FINDIK EZMESI 350G', '1', 'AD', '112.90', '112.90', '10'),
    item('SUSAM EZMESI 300G', '1', 'AD', '86.25', '86.25', '10'),
]


SCENARIOS = [
    receipt(
        's01_baseline', 'clean 8-line baseline, mixed VAT, comma decimals',
        S1_LINES, '18/08/2026', '2026-08-18', '407.91',
        totals(('ARA TOPLAM', '365.24'), ('KDV %1', '0.88'), ('KDV %10', '13.19'),
               ('KDV %20', '28.60'), ('TOPLAM', '407.91'), ('NAKIT', '450.00'),
               ('PARA USTU', '42.09')),
        seed=101,
    ),
    receipt(
        's02_diacritics', 'Turkish diacritics in every product name',
        S2_LINES, '19/08/2026', '2026-08-19', '525.40',
        totals(('ARA TOPLAM', '477.64'), ('KDV %10', '47.76'), ('TOPLAM', '525.40'),
               ('KREDI KARTI', '525.40')),
        seed=102, supplier='ŞOK MARKETLER TİC. A.Ş.',
        extra=['KADIKÖY ŞUBESİ  NO: 88', 'TEL: 0216 987 65 43', 'VKN: 9876543210'],
    ),
    receipt(
        's03_multiply', 'quantity is the multiplier, not the line total',
        S3_LINES, '20/08/2026', '2026-08-20', '624.28',
        totals(('ARA TOPLAM', '570.20'), ('KDV %1', '1.08'), ('KDV %10', '30.62'),
               ('KDV %20', '22.38'), ('TOPLAM', '624.28'), ('NAKIT', '650.00'),
               ('PARA USTU', '25.72')),
        seed=103,
    ),
    receipt(
        's04_date_ambiguous', 'DD/MM date that a day/month swap would ruin',
        S4_LINES, '05/03/2026', '2026-03-05', '360.86',
        totals(('ARA TOPLAM', '334.65'), ('KDV %1', '0.30'), ('KDV %10', '25.91'),
               ('TOPLAM', '360.86'), ('KREDI KARTI', '360.86')),
        seed=104,
    ),
    receipt(
        's05_faded_price', 'one line washed out: nulls expected, not inventions',
        S5_LINES, '21/08/2026', '2026-08-21', '316.25',
        totals(('ARA TOPLAM', '297.42'), ('KDV %1', '2.51'), ('KDV %20', '16.32'),
               ('TOPLAM', '316.25'), ('NAKIT', '320.00'), ('PARA USTU', '3.75')),
        seed=105,
        degrade={'fade_item': 2},
        # Only the RIGHT of that row is washed out. Inspected the render: `1 AD x 39,95` stays
        # legible, so quantity, unit and unit price are still expected answers and marking them
        # illegible would have penalised a model for reading correctly.
        illegible=['lines.2.line_total', 'lines.2.vat_rate'],
    ),
    receipt(
        's06_furniture', 'a till full of non-item furniture that must not become lines',
        S4_LINES, '22/08/2026', '2026-08-22', '360.86',
        totals(('ARA TOPLAM', '334.65'), ('INDIRIM', '0.00'), ('KDV ORANI %1', '0.30'),
               ('KDV ORANI %10', '25.91'), ('KDV TOPLAM', '26.21'), ('TOPLAM', '360.86'),
               ('NAKIT', '400.00'), ('PARA USTU', '39.14'), ('KAMPANYA PUANI', '12'),
               ('MERSIS NO', '1234567890123456')),
        seed=106, tail='EKU NO: 0456  Z NO: 0789  MF: AB1234567',
    ),
    receipt(
        's07_long', '25 lines: truncation and repetition',
        S7_LINES, '23/08/2026', '2026-08-23', '1836.75',
        totals(('ARA TOPLAM', '1687.45'), ('KDV %1', '2.79'), ('KDV %10', '84.31'),
               ('KDV %20', '62.20'), ('TOPLAM', '1836.75'), ('KREDI KARTI', '1836.75')),
        seed=107,
    ),
    receipt(
        's08_skew_blur', 'rotated, blurred and low contrast',
        S8_LINES, '24/08/2026', '2026-08-24', '428.05',
        totals(('ARA TOPLAM', '389.55'), ('KDV %10', '38.50'), ('TOPLAM', '428.05'),
               ('NAKIT', '450.00'), ('PARA USTU', '21.95')),
        seed=108,
        degrade={'rotate': -6.5, 'blur': 1.5, 'contrast': 0.62, 'noise': 0.012,
                 'fold_at_frac': 0.55},
    ),
    receipt(
        's09_weighed', 'fractional KG quantities on every line',
        S9_LINES, '25/08/2026', '2026-08-25', '483.20',
        totals(('ARA TOPLAM', '478.40'), ('KDV %1', '4.80'), ('TOPLAM', '483.20'),
               ('KREDI KARTI', '483.20')),
        seed=109, supplier='KASAP ALI OGLU GIDA LTD.',
    ),
    receipt(
        's10_total_mismatch', 'printed TOPLAM disagrees with the line sum on purpose',
        S10_LINES, '26/08/2026', '2026-08-26', '499.99',
        # The lines sum to 520.05. The paper says 499.99, and 499.99 is the answer: a model that
        # "corrects" this is tampering, which is ReceiptBench's headline failure for this family.
        totals(('ARA TOPLAM', '520.05'), ('KDV %10', '52.00'), ('TOPLAM', '499.99'),
               ('NAKIT', '500.00'), ('PARA USTU', '0.01')),
        seed=110,
    ),
]
