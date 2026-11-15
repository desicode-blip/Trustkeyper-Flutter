# TK Lead Format v1

One JSON object: `{"format":"tk-leads-1","tenants":[...],"homes":[...]}`. Every field is optional; a row needs a phone, the post text or the basic details. A CSV with the sheet's own column headers ("Tenanat Rent" or "OWNER- FOR RENT") also works.

Field names, types and the rules for other AI tools: see `lib/src/tkdesk/tkdesk_lead.dart` (fields) and `leadFormatRules` in `lib/src/tkdesk/tkdesk_helpers.dart` (the text given to other AI tools; the desk's "AI helpers" page has a Copy button per job).

Example:
```json
{"format":"tk-leads-1",
 "tenants":[{"name":"Ravi","phone":"9800000000","bhk":2,"budgetMax":45000,"areas":["Gachibowli"],"who":"family","at":"2026-11-15","source":{"type":"WhatsApp group","group":"Hyderabad buddies - 5","text":"Need 2bhk in Gachibowli, 45k, family"}}],
 "homes":[{"society":"ASBL Spectra","area":"financial district","bhk":3,"rent":75000,"maint":6000,"furnishing":"semi-furnished","ownerPhone":"9800000001","at":"2026-11-15","source":{"type":"Facebook group","group":"Flat and Flatmates Hyderabad","text":"3BHK semi furnished ASBL Spectra 75k + maintenance"}}]}
```
Import never overwrites what a salesperson typed: an existing lead (same phone; for homes same society + tower + flat) only gets its empty fields filled. Lead data files are never committed to the repo.
