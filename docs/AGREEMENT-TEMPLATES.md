# Agreement templates (owner and manager)

For humans and AI agents. Last updated 2026-10-28 (staging).

The legal words of every owner-and-manager agreement come from **Google Docs kept by the TrustKeyper team**. The app must **fetch the doc every time** an agreement is made, so an edit in the doc reaches all new agreements. Never copy the words into the app.

## The templates

| id | Name | Used when | Drive doc |
|---|---|---|---|
| `monthly_percent` | Every month: percent of rent | Fee type `percent`. Owner pays directly, or we deduct it | link not shared yet (file "tem_PRO_MAN_") |
| `monthly_days` | Every month: days of rent | Fee type `daysMonthly` (3 days = 10% of rent). Rent must be paid on our app and we deduct the fee | link not shared yet (file "tem_PRO_MAN_3_Days") |
| `yearly_days` | Once a year: 15 days of rent | Fee type `days` (one time, each year) | `12Duaqq-_kU3H_915GM3mLh0mIp2dbcYgniTnHQCjNZ0` ("tem Pro Man 15 Days") |
| `nri_hybrid` | Owner lives outside India | Owner is an NRI. TrustKeyper is the broker, collects rent, pays the owner | `13cdao3RgQ5r8VaH5Tepk6S4Ri28qr-P6fKV5XcBX0EQ` ("Tem Prop M A NRI") |

Picking is in `apps/flutter_app/lib/src/features/broker/data/agreement_templates.dart` (`AgreementTemplates.pick`). Today: broker must be TrustKeyper (templates for other brokers do not exist yet); fee `none`, `later`, `fixed`, `once` have no template; NRI wins over the fee type.

## What the templates leave open (fill before signing)

Placeholders written as `[LIKE THIS]`: `[TITLE]`, `[OWNER 1 FULL NAME]`, `[OWNER 2 FULL NAME]`, `[OWNER n FATHER'S NAME]`, `[AGE]`, `[OWNER ADDRESS]`, `[PROPERTY ADDRESS]`, `[EXECUTION DATE]`, `[EFFECTIVE DATE]`, `[END DATE OF INITIAL TERM]`, `[SWITCH DEADLINE DATE]`, `[OWNER 1 EMAIL]`, `[OWNER 2 EMAIL]`, `[PROPERTY DESCRIPTION]`, stamp paper certificate no, area (sq.ft), owner bank block (Annexure 1), fixtures table.

Asked in the app today: owner name(s), phone or email, house address (from documents), rent, deposit, fee, start date, months. **Not asked yet:** father's name, age, owner home address, title (Mr/Ms), property description and area, fixtures list, owner bank account, NRI yes/no, who the broker is (TrustKeyper or another).

## Things to fix in the docs (found while reading)

- `yearly_days`: clause 3.1 has a fixed date "25 June 2026" instead of `[EFFECTIVE DATE]`. Fee words ("15days", "fifteen (15) days") are typed in, not placeholders.
- `monthly_percent`: clause 2.1 has "9.1%" and clause 3.1 has "1st August 2025 ... 31st July 2026" typed in.
- `nri_hybrid`: a filled agreement for one real owner (name, PAN, bank, address, stamp paper no, "8%", dates). It must be turned into a template with placeholders before it can be reused. Do not send it to other owners as it is.
- Fee numbers are inside sentences, so the fetch step must replace them from the answers (percent, days, amount).

## How the fetch must work (needs the backend, not built)

The phone cannot read private Google Docs. Plan:
1. A Cloud Function `getAgreementTemplate(templateId)` reads the doc with a service account that has Viewer access to the 4 docs (Drive API `files.export`), keeps it for a few minutes, and returns the text.
2. The function fills the placeholders from the house record and the answers, and returns the full agreement text plus the list of placeholders still empty.
3. The app shows that text in "Your agreement" (yellow = filled from answers, green = changed), and the edit screens change the answers, then the text is made again.
4. The agreement team gets the same text for the stamp paper.
Until then the app shows a plain-word summary. It is not the legal text.

## Open questions for the team

1. Links for `monthly_percent` and `monthly_days`.
2. How do we know the broker is TrustKeyper? (a flag on the broker account)
3. Where is "owner is an NRI" asked?
4. Templates for outside brokers: same text with their name instead of Paravent, or different?
5. For fee kinds with no template (fixed amount, one time fixed, no fee, decide each deal): which template, or do we hide them?
