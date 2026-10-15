import argparse
import base64
import gzip
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path


class ExportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.script_type = None
        self.blocks = {}
        self.frames = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == 'script':
            self.script_type = attributes.get('type')
            if self.script_type and self.script_type.startswith('__bundler/'):
                self.blocks[self.script_type] = ''
        if tag == 'iframe':
            self.frames.append(attributes)

    def handle_data(self, data):
        if self.script_type in self.blocks:
            self.blocks[self.script_type] += data

    def handle_endtag(self, tag):
        if tag == 'script':
            self.script_type = None


class BoardParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hidden_depth = 0
        self.text = []
        self.assets = []

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden_depth += 1
        if tag in ('img', 'link'):
            self.assets.append(dict(attrs))

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden_depth = max(0, self.hidden_depth - 1)

    def handle_data(self, data):
        if not self.hidden_depth and data.strip():
            self.text.append(' '.join(data.split()))


def extract_exports(source, destination):
    exports = sorted(
        source.glob('*Rent Agreement Mobile Flow*.html'),
        key=lambda file: file.stat().st_mtime,
    )
    if len(exports) != 18:
        raise ValueError(f'Expected 18 design exports, found {len(exports)}')
    destination.mkdir(parents=True, exist_ok=True)
    sections = []
    for file in exports:
        parser = ExportParser()
        parser.feed(file.read_text(encoding='utf-8'))
        manifest = json.loads(parser.blocks['__bundler/manifest'])
        template = json.loads(parser.blocks['__bundler/template'])
        template_parser = ExportParser()
        template_parser.feed(template)
        section_number = len(sections) + 1
        section_directory = destination / f'{section_number:02d}'
        section_directory.mkdir(exist_ok=True)
        resources = {}
        for resource_id, entry in manifest.items():
            content = base64.b64decode(entry['data'], validate=True)
            if entry.get('compressed'):
                content = gzip.decompress(content)
            resources[resource_id] = content
        boards = []
        for board_number, frame in enumerate(template_parser.frames, start=1):
            resource_id = frame.get('src', '').split('#')[-1]
            content = unpack_board(resources[resource_id].decode('utf-8'), destination)
            board_parser = BoardParser()
            board_parser.feed(content)
            name = f'{board_number:02d}.html'
            (section_directory / name).write_text(content, encoding='utf-8')
            boards.append({
                'number': board_number,
                'title': frame.get('title', ''),
                'width': frame.get('width'),
                'height': frame.get('height'),
                'file': f'{section_number:02d}/{name}',
                'text': board_parser.text,
            })
        sections.append({
            'number': section_number,
            'export': file.name,
            'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
            'boards': boards,
        })
    (destination / 'manifest.json').write_text(
        json.dumps(sections, ensure_ascii=False, indent=2), encoding='utf-8'
    )
    lines = ['# Claude export inventory', '']
    for section in sections:
        lines.extend([
            f"## Export {section['number']:02d} — {len(section['boards'])} artboards",
            f"Source: {section['export']}",
            '',
        ])
        for board in section['boards']:
            lines.append(f"- {board['number']:02d}: {board['title']}")
        lines.append('')
    (destination / 'inventory.md').write_text('\n'.join(lines), encoding='utf-8')
    print(f"Extracted {len(sections)} exports and {sum(len(section['boards']) for section in sections)} artboards")


def unpack_board(content, destination):
    parser = ExportParser()
    parser.feed(content)
    if '__bundler/template' not in parser.blocks:
        return content
    template = json.loads(parser.blocks['__bundler/template'])
    manifest = json.loads(parser.blocks['__bundler/manifest'])
    assets_directory = destination / 'assets'
    assets_directory.mkdir(exist_ok=True)
    extensions = {
        'image/png': '.png',
        'image/jpeg': '.jpg',
        'image/webp': '.webp',
        'image/svg+xml': '.svg',
        'font/woff2': '.woff2',
        'font/woff': '.woff',
        'font/ttf': '.ttf',
        'text/css': '.css',
    }
    for resource_id, entry in manifest.items():
        resource = base64.b64decode(entry['data'], validate=True)
        if entry.get('compressed'):
            resource = gzip.decompress(resource)
        if entry['mime'] == 'text/html':
            raise ValueError('Unexpected nested HTML inside an individual artboard')
        name = hashlib.sha256(resource).hexdigest() + extensions.get(entry['mime'], '.bin')
        (assets_directory / name).write_bytes(resource)
        template = template.replace(f'about:blank#{resource_id}', f'../assets/{name}')
        template = template.replace(resource_id, f'../assets/{name}')
    template = template.replace('sc-camel-view-box=', 'viewBox=')
    return template


def extract_app_assets(destination, app_assets):
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    fonts_directory = app_assets / 'fonts'
    fonts_directory.mkdir(parents=True, exist_ok=True)
    board = (destination / '01/06.html').read_text(encoding='utf-8')
    logo = re.search(r'<img src="([^"]+)"[^>]*alt="TrustKeyper"', board).group(1)
    logo_source = (destination / '01' / logo).resolve()
    (app_assets / 'images/trustkeyper-logo-approved.png').write_bytes(logo_source.read_bytes())
    latin = re.search(r'/\* latin \*/\s*@font-face\s*\{.*?url\("([^"]+)"\)', board, re.S)
    font = TTFont((destination / '01' / latin.group(1)).resolve(), recalcTimestamp=False)
    for weight in (400, 500, 600, 700):
        instance = instantiateVariableFont(font, {'wght': weight}, inplace=False)
        instance.recalcTimestamp = False
        instance.flavor = None
        instance.save(fonts_directory / f'Roboto-{weight}.ttf')
    icons_directory = app_assets / 'design'
    icons_directory.mkdir(exist_ok=True)
    introduction = (destination / '03/03.html').read_text(encoding='utf-8')
    introduction_icons = re.findall(r'<svg.*?</svg>', introduction, re.S)
    for index, name in {0: 'back', 1: 'call', 2: 'sparkle', 4: 'check', 5: 'clock', 7: 'property', 8: 'people', 9: 'documents', 10: 'rent', 11: 'brokerage', 12: 'review', 13: 'next'}.items():
        icon = re.sub(r'stroke="[^\"]+"', 'stroke="#000000"', introduction_icons[index])
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'steps-{name}.svg').write_text(icon, encoding='utf-8')
    roles = (destination / '01/11.html').read_text(encoding='utf-8')
    role_icons = re.findall(r'<svg width="30".*?</svg>', roles, re.S)
    for name, icon in zip(('broker', 'owner', 'tenant'), role_icons, strict=True):
        icon = re.sub(r'stroke="[^\"]+"', 'stroke="#000000"', icon)
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'role-{name}.svg').write_text(icon, encoding='utf-8')
    for number, name in [(2, 'welcome-agreement'), (3, 'welcome-rent'), (4, 'welcome-home'), (5, 'welcome-trust')]:
        board = (destination / f'01/{number:02d}.html').read_text(encoding='utf-8')
        icon = re.search(r'<svg width="92".*?</svg>', board, re.S).group(0)
        icon = icon.replace('stroke="currentColor"', 'stroke="#000000"')
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'{name}.svg').write_text(icon, encoding='utf-8')
    choice_board = (destination / '03/02.html').read_text(encoding='utf-8')
    choice_icons = re.findall(r'<svg width="34".*?</svg>', choice_board, re.S)
    for name, icon in zip(('new-agreement', 'renew-agreement', 'sign-agreement'), choice_icons, strict=True):
        icon = icon.replace('stroke="currentColor"', 'stroke="#000000"')
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'{name}.svg').write_text(icon, encoding='utf-8')
    home = (destination / '03/01.html').read_text(encoding='utf-8')
    home_icons = re.findall(r'<svg.*?</svg>', home, re.S)
    for index, name in {0: 'profile', 1: 'updates', 2: 'language', 3: 'down', 4: 'agreement', 5: 'next', 6: 'house', 7: 'tenants', 8: 'bank', 9: 'call'}.items():
        icon = re.sub(r'stroke="[^\"]+"', 'stroke="#000000"', home_icons[index])
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'home-{name}.svg').write_text(icon, encoding='utf-8')
    navigation = re.search(r'<nav.*?</nav>', home, re.S).group(0)
    navigation_icons = re.findall(r'<svg.*?</svg>', navigation, re.S)
    for name, icon in zip(('home', 'agreements', 'records', 'payments', 'profile'), navigation_icons, strict=True):
        icon = icon.replace('stroke="currentColor"', 'stroke="#000000"')
        icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
        (icons_directory / f'nav-{name}.svg').write_text(icon, encoding='utf-8')
    property_icons = {
        '05': {0: 'call', 1: 'back', 2: 'address', 3: 'size', 4: 'compass', 5: 'north-west', 6: 'north', 7: 'north-east', 8: 'west', 10: 'east', 11: 'south-west', 12: 'south', 13: 'south-east', 14: 'car', 15: 'minus', 16: 'plus', 17: 'bike', 22: 'next'},
        '07': {2: 'rooms', 3: 'floor', 6: 'building', 9: 'furnished', 10: 'empty', 11: 'semi', 12: 'full'},
        '08': {2: 'fan', 5: 'light', 8: 'ac', 11: 'geyser', 14: 'cupboard', 17: 'bed', 22: 'check'},
    }
    for number, names in property_icons.items():
        board = (destination / f'03/{number}.html').read_text(encoding='utf-8')
        icons = re.findall(r'<svg.*?</svg>', board, re.S)
        for index, name in names.items():
            icon = re.sub(r'stroke="[^\"]+"', 'stroke="#000000"', icons[index])
            icon = icon.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ')
            (icons_directory / f'property-{name}.svg').write_text(icon, encoding='utf-8')


if __name__ == '__main__':
    arguments = argparse.ArgumentParser()
    arguments.add_argument('--source', required=True, type=Path)
    arguments.add_argument('--destination', required=True, type=Path)
    arguments.add_argument('--app-assets', type=Path)
    options = arguments.parse_args()
    extract_exports(options.source, options.destination)
    if options.app_assets:
        extract_app_assets(options.destination, options.app_assets)
