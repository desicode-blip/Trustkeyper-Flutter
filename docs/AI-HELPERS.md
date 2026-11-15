# AI helpers

Jobs handed to AI tools from other companies, when to add one, and how their work comes in. The desk shows the same on its "AI helpers" page (copyable prompts, and per-tool counts of leads added, duplicates, rejected and ready to match). Source of truth: `lib/src/tkdesk/tkdesk_helpers.dart`.

Jobs: 1 Read Facebook groups · 2 Turn a WhatsApp chat export into leads · 3 Find owner listings for a society or area · 4 Clean a lead file · 5 Write a first-call script.

When to add a helper (the desk raises a notice on Today): fewer than 5 new matchable tenants in 3 days; a group that could not be read; more than 15 groups to read; more than 30% of a week's leads missing size or rent; more than 20% duplicates in imports; a tenant with fewer than 3 matches.

Every helper returns TK Lead Format v1 only. Nothing enters the desk until someone presses Import.
