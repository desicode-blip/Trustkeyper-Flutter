# Agreement template copies

**The files now live in `apps/flutter_app/assets/agreements/`** (the app reads them from there). This folder only keeps this note.

Blank copies (no personal details) of the owner-and-manager agreements. Kept here because the Google Drive links could not be shared as links. **Replace a file only when Aman asks.**

| File | id | Use when | Drive source |
|---|---|---|---|
| `assets/agreements/monthly_percent.md` | monthly_percent | Fee is a percent of rent every month | 1AMTnUD7EdTP_V2CDBRumZbF9b80aDZNa (Word) |
| `assets/agreements/monthly_days_3days.md` | monthly_days | Fee is days of rent every month (3 days = 10%), rent on our app | link not shared |
| `assets/agreements/yearly_15days.md` | yearly_days | One time per year, 15 days of rent | 12Duaqq-_kU3H_915GM3mLh0mIp2dbcYgniTnHQCjNZ0 |
| `assets/agreements/nri_hybrid.md` | nri_hybrid | Owner is an NRI, we collect and pay the owner | 13cdao3RgQ5r8VaH5Tepk6S4Ri28qr-P6fKV5XcBX0EQ |

Each file starts with a comment block listing its placeholders, written like `[OWNER 1 FULL NAME]`. Fill them from the owner's answers; leave any not yet known visibly empty.
Which one to pick: `lib/src/features/broker/data/agreement_templates.dart` and `docs/AGREEMENT-TEMPLATES.md`.

## How the app fills them (Change 34)
`lib/src/features/broker/data/agreement_filler.dart` reads the template, fills what we know (owner names, property address, fee, start date, months, notes, owner email) and leaves everything else as a grey gap showing its label. It never guesses. The page is drawn by `presentation/agreement_paper.dart`.
Placeholders it understands: `[OWNER n FULL NAME]`, `[OWNER NAMES]`, `[PROPERTY ADDRESS]`, `[FULL ADDRESS OF THE PROPERTY WITH PIN CODE]`, `[EXECUTION DATE]`, `[EFFECTIVE DATE]`, `[END DATE OF INITIAL TERM]`, `[FEE PERCENT]`, `[OWNER EMAIL ADDRESS]`. The words for the term ("one (1) year") and the fee days ("three (3) days", "ten percent (10%)", "15days") are swapped in by the filler from the answers.
