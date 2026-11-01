#!/usr/bin/env python3
"""
TrustKeyper website build.

    python3 build.py

Reads  site.config.json + src/   ->   writes dist/  (the folder that gets deployed).

Tokens you can use in any src/*.html file:
  {{agent.singular}}     e.g. "Property Agent"
  {{agent.plural}}       e.g. "Property Agents"
  {{agent.singular_lc}}  e.g. "property agent"   (mid-sentence)
  {{agent.plural_lc}}    e.g. "property agents"
  {{agent.slug}}         e.g. "for-property-agents"  (page URL)
  {{offices}}            office address cards, built from config "offices"
  {{visitFee}}           visit booking fee from config, e.g. "₹100"
  {{faq}}                Property Agent page FAQ, built from src/i18n/agent-page.json
  data-i18n="key"        an empty element gets the English text from src/i18n/agent-page.json;
                         the page's language switch swaps in Hindi / Telugu
  {{> name}}             contents of src/_partials/name.html

Folders:
  src/__agent_page__/    becomes dist/<agent.slug>/
  src/_partials/         shared snippets, not published
Every slug listed in agent.oldSlugs gets a redirect page, so old links keep working.
"""
import html, json, re, shutil
from pathlib import Path

ROOT = Path(__file__).parent
SRC, DIST = ROOT / "src", ROOT / "dist"
cfg = json.loads((ROOT / "site.config.json").read_text())
agent = cfg["agent"]

PIN = ('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" '
       'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" '
       'class="lucide lucide-map-pin mt-0.5 shrink-0" aria-hidden="true"><path d="M20 10c0 4.993-5.539 '
       '10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"></path>'
       '<circle cx="12" cy="10" r="3"></circle></svg>')


def offices_html():
    cards = []
    for o in cfg["offices"]:
        lines = "<br>".join(html.escape(l) for l in o["lines"])
        cards.append(
            f'<address class="flex items-start gap-3 not-italic text-sm text-white">{PIN}<div>'
            f'<p class="text-base font-medium leading-6 text-white">{html.escape(o["city"])}'
            f' <span class="font-roboto text-xs font-normal tk-text-muted">· {html.escape(o["label"])}</span></p>'
            f'<p class="mt-1 font-roboto leading-[22px] tk-text-soft">{lines}</p></div></address>')
    return "".join(cards)


TOKENS = {
    "agent.singular": agent["singular"],
    "agent.plural": agent["plural"],
    "agent.singular_lc": agent["singular"].lower(),
    "agent.plural_lc": agent["plural"].lower(),
    "agent.slug": agent["slug"],
    "offices": offices_html(),
    "visitFee": cfg.get("visitFee", ""),
}

# ---- Multi-language text (src/i18n/<page>.json) ----
def agent_names(lang):
    if lang == "en":
        return agent["singular"], agent["plural"]
    t = agent.get("translations", {}).get(lang, {})
    return t.get("singular", agent["singular"]), t.get("plural", agent["plural"])


def load_i18n(name):
    raw = json.loads((SRC / "i18n" / f"{name}.json").read_text())
    out = {}
    for lang, strings in raw.items():
        if lang.startswith("_"):
            continue
        one, many = agent_names(lang)
        out[lang] = {k: v.replace("{agents}", many).replace("{agent}", one).replace("{fee}", cfg.get("visitFee", ""))
                     for k, v in strings.items()}
    return out


I18N = {"agent": load_i18n("agent-page")}
TOKENS["i18n.agent"] = json.dumps(I18N["agent"], ensure_ascii=False).replace("</", "<\\/")

CHEVRON = ('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" '
           'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
           '<path d="m6 9 6 6 6-6"></path></svg>')


def faq_html():
    en = I18N["agent"]["en"]
    items = []
    n = 1
    while f"q{n}" in en:
        first = n == 1
        items.append(
            f'<div class="tka-faq-item"><button type="button" id="tka-faq-{n}-t" aria-expanded="{str(first).lower()}" '
            f'aria-controls="tka-faq-{n}" data-faq-toggle=""><span data-i18n="q{n}"></span>'
            f'{CHEVRON.replace("<svg ", "<svg class=\"rotate-180\" ", 1) if first else CHEVRON}</button>'
            f'<div id="tka-faq-{n}" role="region" aria-labelledby="tka-faq-{n}-t"{"" if first else " hidden"}>'
            f'<p data-i18n="a{n}"></p></div></div>')
        n += 1
    return "".join(items)


TOKENS["faq"] = faq_html()


def fill_i18n(text):
    """Put the English text into every empty data-i18n element, so the page works without JavaScript and for search engines."""
    en = I18N["agent"]["en"]
    def sub(m):
        key = m.group(3)
        if key not in en:
            raise SystemExit(f"Missing English text for data-i18n=\"{key}\"")
        return m.group(1) + html.escape(en[key], quote=False) + m.group(4)
    return re.sub(r'(<(\w+)\b[^>]*\bdata-i18n="([^"]+)"[^>]*>)(</\2>)', sub, text)


def render(text):
    text = re.sub(r"\{\{>\s*([\w-]+)\s*\}\}", lambda m: (SRC / "_partials" / f"{m.group(1)}.html").read_text(), text)
    def sub(m):
        key = m.group(1).strip()
        if key not in TOKENS:
            raise SystemExit(f"Unknown token {{{{{key}}}}}")
        return TOKENS[key]
    return re.sub(r"\{\{([^}>]+)\}\}", sub, text)


def build():
    if DIST.exists():
        shutil.rmtree(DIST)
    for path in SRC.rglob("*"):
        rel = path.relative_to(SRC)
        if path.is_dir() or rel.parts[0] in ("_partials", "i18n"):
            continue
        if rel.parts[0] == "__agent_page__":
            rel = Path(agent["slug"], *rel.parts[1:])
        out = DIST / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".html":
            out.write_text(fill_i18n(render(path.read_text())))
        else:
            shutil.copy2(path, out)
    for old in agent.get("oldSlugs", []):
        if old == agent["slug"]:
            continue
        d = DIST / old
        d.mkdir(parents=True, exist_ok=True)
        url = f"/{agent['slug']}"
        (d / "index.html").write_text(
            f'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Redirecting…</title>'
            f'<link rel="canonical" href="https://trustkeyper.com{url}"><meta name="robots" content="noindex">'
            f'<meta http-equiv="refresh" content="0; url={url}"><script>location.replace("{url}"+location.hash)</script>'
            f'</head><body><a href="{url}">Continue</a></body></html>')
    print(f"Built dist/ — agent = '{agent['singular']}', page = /{agent['slug']}")


if __name__ == "__main__":
    build()
