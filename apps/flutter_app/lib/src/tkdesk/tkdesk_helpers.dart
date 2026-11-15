/// Jobs we hand to AI tools from other companies (ChatGPT, Gemini…), and the
/// one rule they all follow: return TK Lead Format v1, nothing else. The
/// Import screen is the gate. Same text as docs/AI-HELPERS.md.
library;

class HelperJob {
  const HelperJob(this.no, this.title, this.when, this.give, this.prompt);
  final int no;
  final String title;
  final String when;
  final String give;
  final String prompt;
}

const leadFormatRules = '''
Return ONLY one JSON object, no other text:
{"format":"tk-leads-1","tenants":[...],"homes":[...]}

Tenant fields (leave out what you do not know): name, phone (10 digits), bhk (number, 2.5 allowed), budgetMin, budgetMax (rupees per month, numbers), budgetRentOnly (true if they said "+ maintenance"), areas (list of localities), moveIn (YYYY-MM-DD), who ("family" | "bachelors" | "couple"), food ("veg" | "non-veg"), furnishing ("unfurnished" | "semi-furnished" | "fully furnished"), pets (true/false), parking (number of cars), remarks.
Home fields: society, tower, flat, area, bhk, rent, maint, maintIncl (true if rent includes maintenance), furnishing, sqft, floor, floors, facing, parking, deposit, availableFrom (YYYY-MM-DD), who ("any" | "family" | "bachelors"), food ("any" | "veg only"), pets (true/false), ownerName, ownerPhone, remarks.
Every tenant and home also gets: "at" (date of the post, YYYY-MM-DD) and "source": {"type": "Facebook group" | "WhatsApp group" | "Website" | ..., "group": "<group or site name>", "text": "<the original post, unchanged>"}.
Add "agent": true to a home when the poster is a broker or agent.

Rules:
- Whole flats or houses FOR RENT in Hyderabad only. Skip flatmate, room, PG, co-living, sale, plots and ads.
- Never invent a value. If the post does not say it, leave the field out.
- Write "65k" as 65000. Write "2.5bhk" as 2.5.
- Keep the original post text in source.text.
- Only posts from the last 14 days.
''';

const helperJobs = <HelperJob>[
  HelperJob(
    1,
    'Read Facebook groups for leads',
    'When fewer than 5 new tenants a day come in, or a group needs reading that we have not joined.',
    'A list of Facebook group links, or the copied text of the posts.',
    'You are helping a Hyderabad rental broker find leads. Read the posts in these Facebook groups (links or text below). Find tenants looking for a whole flat and owners or agents offering a whole flat for rent.\n\n$leadFormatRules',
  ),
  HelperJob(
    2,
    'Turn a WhatsApp group export into leads',
    'Every few days for each rental WhatsApp group (WhatsApp Web keeps only about two days of messages).',
    'On the phone: open the group → ⋮ → More → Export chat → Without media. Give the .txt file to the tool.',
    'This is an exported WhatsApp group chat from Hyderabad. Each message starts with a date, time and sender. Find tenants looking for a whole flat and owners or agents offering one for rent. Use the sender\'s number as the phone when the message gives no other number.\n\n$leadFormatRules',
  ),
  HelperJob(
    3,
    'Find owner listings for a society or area',
    'When a tenant has fewer than 3 matching homes.',
    'The tenant\'s need (size, budget, areas) and the area or society names.',
    'Search public rental listings (NoBroker, MagicBricks, 99acres, Housing, Facebook Marketplace) for whole flats for rent in the areas below that fit this need. Prefer listings posted by owners. Give the listing link in source.group.\n\n$leadFormatRules',
  ),
  HelperJob(
    4,
    'Clean a lead file',
    'When more than 30% of a week\'s leads miss size or rent, or more than 20% of imported rows are duplicates.',
    'A lead file (JSON or CSV) exported from the desk or made by another tool.',
    'Clean this lead file. Merge rows that are the same person (same phone) or the same flat (same society + tower + flat). Read each source.text and fill bhk, rent, budget, areas and furnishing when the post says them. Translate Telugu or Hindi posts into English in remarks (keep the original in source.text). Mark agents with "agent": true. Do not drop any row.\n\n$leadFormatRules',
  ),
  HelperJob(
    5,
    'Write a first-call script',
    'Before calling a tenant or owner for the first time.',
    'The lead\'s details from the desk (copy from the lead page).',
    'Write a short, friendly first phone call script (English, with a Hindi and a Telugu version) for a TrustKeyper broker calling this lead. Confirm what is missing: size, budget, areas, move-in date, family or bachelors, food, pets, parking. Do not promise anything about price or brokerage. Plain text, under 150 words per language.',
  ),
];

/// When to bring in another AI tool. Shown on the Helpers page; the desk
/// also raises a notice on Today when one of these is true.
const helperTriggers = [
  'Fewer than 5 new tenants ready to match came in over the last 3 days → Job 1 or Job 2.',
  'A group could not be read (it needs joining, or WhatsApp Web has no history) → Job 1 or Job 2.',
  'More than 15 groups on the reading list, or a reading run was cut short → split the list: Job 1 for half of it.',
  'More than 30% of a week\'s leads are in "Call to get details" → Job 4.',
  'More than 20% of imported rows were already on the desk → Job 4.',
  'A tenant has fewer than 3 matching homes → Job 3.',
];
