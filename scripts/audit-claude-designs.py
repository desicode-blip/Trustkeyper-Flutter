import argparse
import csv
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SECTIONS = [
    'Common authentication', 'Admin workspace', 'Broker new agreement',
    'Bank, UPI and document links', 'Tenants, rent and brokerage',
    'Review, edit and send', 'Signing and move-in', 'Renewal and sign-only',
    'Broker tabs', 'Owner login and documents', 'Owner dashboard',
    'Tenant web', 'Discarded broker flow', 'Discarded review flow',
    'Agreement approval and signing', 'Move-out', 'Owner self-onboarding', 'Late rent',
]


def implementation(section, board):
    if section in (13, 14):
        return 'Archived reference; not a shipping requirement'
    if section == 1 and board in (1, 2, 3, 4, 5, 6, 7, 8, 19, 20):
        return 'Native UI updated; visual acceptance and real-provider testing pending'
    if section == 1 and board == 9:
        return 'Native layout updated; same-UID email OTP binding still pending'
    if section == 1 and board == 11:
        return 'Native role choices updated; multi-role identity behavior pending'
    if section == 3 and board == 1:
        return 'Native empty-account home updated; live agreement and notification states pending'
    if section == 3 and board == 2:
        return 'Native choices updated; renewal and sign-only downstream workflows incomplete'
    if section == 3 and 4 <= board <= 12:
        return 'Native property journey added; exact state-by-state acceptance pending'
    if section == 3 and board == 3:
        return 'Native dotted five-step introduction updated; visual and device acceptance pending'
    if section == 2:
        return 'Existing Firebase admin workspace; export comparison pending'
    return 'Pending parity; existing generic or preview UI is not accepted'


def build_audit(directory):
    manifest = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
    if len(manifest) != 18 or sum(len(section['boards']) for section in manifest) != 438:
        raise ValueError('The export inventory changed; review the design baseline before continuing')
    contacts = directory / 'contacts'
    contacts.mkdir(exist_ok=True)
    font = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 13)
    style = 'body{font:16px system-ui;color:#172231;margin:24px;background:#f6f9fd}a{color:#1f4ad1}section{padding:20px;background:white;border-radius:16px;margin:20px 0}img{max-width:100%;height:auto}figure{margin:0}figcaption{padding:10px}.boards{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:20px}h1{font-size:26px}'
    rows = []
    overview = ['<!doctype html><meta charset="utf-8"><title>TrustKeyper design audit</title>', f'<style>{style}</style>', '<h1>TrustKeyper — all 18 local design exports</h1>', '<p>438 reference artboards; 44 in two discarded exports. These screenshots are design references, not completed app screens. No board is marked visually accepted yet.</p>', '<p><a href="coverage.csv">Complete screen-by-screen coverage ledger</a></p>']
    rendered = 0
    for section in manifest:
        number = section['number']
        name = SECTIONS[number - 1]
        boards = section['boards']
        contact = Image.new('RGB', (1180, ((len(boards) + 5) // 6) * 448 + 42), '#f6f9fd')
        drawing = ImageDraw.Draw(contact)
        drawing.text((10, 10), f'{number:02d} — {name} — {len(boards)} references', fill='#172231', font=font)
        detail = ['<!doctype html><meta charset="utf-8">', f'<title>{html.escape(name)}</title><style>{style}</style>', '<a href="../index.html">All exports</a>', f'<h1>{number:02d} — {html.escape(name)}</h1><div class="boards">']
        for index, board in enumerate(boards):
            reference = board['file'].replace('.html', '')
            screenshot = directory / f'{reference}.png'
            if not screenshot.is_file():
                raise ValueError(f'Missing reference screenshot: {reference}')
            rendered += 1
            rows.append({
                'reference': reference,
                'section': name,
                'title': board['title'],
                'scope': 'Discarded' if number in (13, 14) else 'Active reference; variant applicability to be checked',
                'implementation': implementation(number, board['number']),
                'visual_acceptance': 'Pending',
                'device_acceptance': 'Pending on updated Play-signed build',
                'export_sha256': section['sha256'],
            })
            thumbnail = Image.open(screenshot).convert('RGB')
            thumbnail.thumbnail((180, 392))
            left = (index % 6) * 196 + 8
            top = (index // 6) * 448 + 40
            contact.paste(thumbnail, (left, top))
            title = f'{reference} · {board["title"]}'
            for line in range(3):
                drawing.text((left, top + 396 + line * 15), title[line * 26:(line + 1) * 26], fill='#172231', font=font)
            detail.extend([f'<figure><a href="../{reference}.png"><img loading="lazy" src="../{reference}.png" alt="{html.escape(board["title"], quote=True)}"></a>', f'<figcaption>{html.escape(title)}<br>{html.escape(implementation(number, board["number"]))}</figcaption></figure>'])
        contact.save(contacts / f'{number:02d}.jpg', quality=92)
        detail.append('</div>')
        (contacts / f'{number:02d}.html').write_text('\n'.join(detail), encoding='utf-8')
        overview.extend([f'<section><h2><a href="contacts/{number:02d}.html">{number:02d} — {html.escape(name)} ({len(boards)})</a></h2>', f'<a href="contacts/{number:02d}.html"><img loading="lazy" src="contacts/{number:02d}.jpg" alt="Export {number:02d} contact sheet"></a></section>'])
    (directory / 'index.html').write_text('\n'.join(overview), encoding='utf-8')
    with (directory / 'coverage.csv').open('w', newline='', encoding='utf-8-sig') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    native = directory.parent / 'ui-audit/native'
    comparisons = {
        'onboarding': '01/02', 'login': '01/06', 'otp': '01/08',
        'profile': '01/09', 'roles': '01/11', 'approval-pending': '01/19',
        'approval-verified': '01/19', 'paused': '01/20', 'broker-home': '03/01',
        'broker-start': '03/02', 'broker-steps': '03/03',
        'property-picker': '03/04', 'property-address-empty': '03/05',
        'property-rooms': '03/07', 'property-inventory': '03/08', 'property-saved': '03/10',
    }
    review = ['<!doctype html><meta charset="utf-8"><title>Reference and native UI comparison</title>', f'<style>{style}.pair{{display:flex;flex-wrap:wrap;gap:20px}}.pair figure{{width:440px;max-width:100%}}</style>', '<a href="index.html">All 18 exports</a><h1>Reference vs native test capture</h1>', '<p>These are manual comparison pairs, not accepted pixel goldens. Captures use test fixtures. Entered values, verified channels, enabled actions and OTP countdowns can differ from an artboard. No claim of complete visual parity or live-backend readiness.</p>']
    for name, reference in comparisons.items():
        if not (native / f'{name}.png').is_file():
            continue
        review.extend([
            f'<section><h2>{html.escape(name)} — {reference}</h2><div class="pair">',
            f'<figure><figcaption>Aman’s reference</figcaption><img loading="lazy" src="{reference}.png" alt="Reference {reference}"></figure>',
            f'<figure><figcaption>Native Flutter test capture — acceptance pending</figcaption><img loading="lazy" src="../ui-audit/native/{name}.png" alt="Native {name}"></figure></div></section>',
        ])
    (directory / 'native-review.html').write_text('\n'.join(review), encoding='utf-8')
    print(f'Prepared {rendered} reference screenshots, 18 contact sheets and a coverage ledger; no visual acceptance claimed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=Path('output/design-reference'))
    build_audit(parser.parse_args().directory)
