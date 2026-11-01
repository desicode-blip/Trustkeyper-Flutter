# TrustKeyper Website – Developer Guide

Last updated: 1 November 2026 (evening, change log up to CHG-056) · Owner: Aman Maheshwari · Readers: developers and AI agents

The new trustkeyper.com website and its backend are **built and tested**. This guide explains what was done, what the developer still has to do before go-live, and the decisions behind it.

**Contents**
1. Your to-do list (only what needs TrustKeyper's accounts)
2. What has been built
3. How the website is built and edited
4. The enquiry form and its backend
5. Deploying
6. Considerations and decisions
7. Go-live test list
8. File map

---

## 1. Your to-do list

Nothing in the code needs editing. These steps need TrustKeyper's own accounts or access, so they could not be done in advance.

| # | Task | Time | Detail |
|---|---|---|---|
| 1 | **MSG91 account + DLT approval** (start first) | 30 min + 2–7 days wait | Section 4.4 |
| 2 | **Resend account + verify trustkeyper.com** | 30 min | Section 4.4 |
| 3 | **Store 4 secrets in Google Secret Manager** | 15 min | Section 5.2 |
| 4 | **Deploy the backend** (`api/deploy.sh`) | 10 min | Section 5.2 |
| 5 | **Host the website + route `/api/*` to the backend** | 30 min | Section 5.3 |
| 6 | **Firestore housekeeping** (TTL + rules) | 10 min | Section 5.4 |
| 7 | **Run the go-live tests** | 30 min | Section 7 |

Before deploying, confirm with Aman: who receives lead emails (`LEADS_TO`), and who is allowed to run billable deploys (see `AGENTS.md`).

---

## 2. What has been built

Starting point: an exact copy of the old live trustkeyper.com, verified pixel-for-pixel on all seven pages. Then:

**Whole site**
- Images resized and converted to WebP: 10.5 MB → 0.56 MB, with lazy loading. Pages look the same.
- "Broker" renamed to **"Property Agent"** everywhere visitors see it. The name is set in one place (`site/site.config.json`), so a future rename is one edit. The old URL `/for-brokers` redirects to `/for-property-agents`.
- Footer: all three offices (Noida head office, Bengaluru, Hyderabad) in their own row so they don't overlap the artwork; GST line moved to the bottom bar; bold "Legal / Company / Our Offices" labels.
- Page changes: the page scrolls to the top and fades, so visitors see the change. Respects "reduce motion".
- Floating **WhatsApp** button on every page (+91 8088516875).
- Top menu: For Homeowners · For Property Agents · For Builders.
- **Every screen size is supported** (see section 3.1): phones, tablets and desktops each have their own layout; nothing scrolls sideways from 360 px up.

**Homeowner page (`/`)** – restructured from 10 sections to 7, removing repetition:
1. Hero: "Your home in Hyderabad, looked after while you're away." Button **Register now →** (compact, with shadow). On phones only: shorter line ("Tenants, rent and repairs, handled by one local team."), darker shade behind the text, no manager photo, and a small 2-row Property Status card so the house photo shows.
2. Trust strip: 2 years in Hyderabad · rent paid on our platform · tenants verified · approval over ₹1,000.
3. All services (7 cards), including new **property tax paid on time** (wide card with a subtle green tint and NEW tag), **care while you're away** and **car care**.
4. "Clear rules. No surprises." – six written promises.
5. How it works (3 steps). Step 1 has a **Start now →** button to the form. Numbers are white badges with a soft shadow. On phones the number sits beside the text.
6. Owner stories (3 quotes, approved by the owners).
7. FAQ (single heading "Frequently asked questions.", all questions collapsed by default) + enquiry form.

**Property Agent page (`/for-property-agents`)** – redesigned for agents with limited reading:
- One message: "Every visit should earn you money." Customers pay a **₹100** visit-booking fee through the agent's link (amount set in `site.config.json`).
- **English / हिंदी / తెలుగు** switch at the top; the choice is remembered. Text lives in `site/src/i18n/agent-page.json`.
- Simple sections: the problem vs the new way, 4 steps, app tools (property records, rent agreements, call for help), FAQ (collapsed by default, heading "Frequently asked questions" in all three languages).
- App screens on this page are illustrations, not real screenshots.

**Builders page (`/for-builders`)** – new:
- One message: "Sell faster." Supporting points: less dependence on channel partners, live visibility for builder and buyers.
- Use cases: construction updates for buyers, post-sales care through an **on-site rental office**, white label, ERP and automation, leadership roles, how we work.
- Planned next (not built yet): restructure to 7 sections and add a **security automation** use case (face recognition, number-plate recognition, automatic tenant registration). Waiting for Aman's answers on case study vs use case, and on naming partner builders.

---

## 3. How the website is built and edited

The site is plain HTML/CSS/JS (no framework). `site/build.py` (Python 3, no packages) turns `site/src/` into `site/dist/`, which is what gets hosted. **Never edit `dist/` by hand.**

What the build does:
- Fills tokens in pages: `{{agent.singular}}`, `{{agent.plural}}`, `{{agent.singular_lc}}`, `{{agent.plural_lc}}`, `{{agent.slug}}`, `{{visitFee}}`, `{{offices}}`, `{{faq}}`.
- Inserts shared pieces: `{{> footer}}`, `{{> enquiry}}` from `site/src/_partials/`.
- Fills English text into every `data-i18n` element and embeds Hindi/Telugu for the language switch.
- Publishes `src/__agent_page__/` at the agent slug and writes redirect pages for old slugs.

Common edits:

| To change | Edit |
|---|---|
| Name for property agents (all languages) | `site.config.json` → `agent` |
| Visit fee (₹100) | `site.config.json` → `visitFee` |
| Office addresses | `site.config.json` → `offices` |
| Agent page text (EN/HI/TE) | `src/i18n/agent-page.json` |
| Footer | `src/_partials/footer.html` |
| Enquiry form | `src/_partials/enquiry.html` + "Enquiry form v4" in `src/website.js` |
| WhatsApp number/text | "Floating WhatsApp button" in `src/website.js` |

### 3.1 Screen sizes (standing rule)
Aman's rule: **every change applies to all screen sizes** unless he explicitly says it is for one size only. Check each change at phone, tablet and desktop widths before calling it done.

| Range | Name | Notes |
|---|---|---|
| under 640 px | Phone | Single column; phone-only tweaks use `@media (max-width: 639px)` |
| 640–1199 px | Tablet | Two/three-column grids; header shows ☰ menu + Contact Us + Sign Up |
| 1200 px and up | Desktop | Full header menu on one line |

Phone-only text variants on the homepage hero use the classes `tkh-hero-m` (phone) and `tkh-hero-d` (tablet/desktop). Responsive rules live at the end of `website.css`, `agent.css` and `builder.css` under "Responsive pass".

### 3.2 Styles
Styles: `src/assets/index-*.css` is the original compiled Tailwind file (do not edit). New styles are in `src/website.css` (site-wide), `src/agent.css` (agent page) and `src/builder.css` (builders page). Because the Tailwind file is precompiled, new Tailwind class names will not work; use those three files.

---

## 4. The enquiry form and its backend

### 4.1 What the visitor sees
1. **Name.**
2. **Phone number** or **Email address** → a popup asks for it → **Send OTP** → enter the 6-digit code (auto-checks on the 6th digit; resend after 30 s).
3. After verification the form opens: **I am a** Property owner / Tenant / Property Agent / Builder.
4. One "need the most" question for that role, with **All of the above** highlighted, then a few role questions and an optional note.
5. **Send** → thank-you message.

On the homepage the form sits beside a photo that resizes with it (desktop, 901 px and up). Below 900 px the photo is hidden and the form is one full-width column; on `/contact-us` it is always full width. On phones the floating WhatsApp button fades away while the form is on screen so it never covers a field.

### 4.2 Preview mode
On any host other than `trustkeyper.com`, the form does **not** call the backend for codes and accepts **123456** (a yellow note says so). On trustkeyper.com this switches off automatically (`OTP_PREVIEW` in `website.js`). For a staging domain, keep preview on or add the host to that check.

### 4.3 Backend (`api/`)
A Dart server (Dart is the language Flutter uses) with three endpoints. It is complete, passes 18 automated tests, and needs no code changes.

| Endpoint | Request | Response |
|---|---|---|
| `POST /api/otp/send` | `{"channel":"phone","target":"9876543210"}` or email | `{"sent":true}` · 400 invalid · 429 too soon/many · 502 provider failed |
| `POST /api/otp/verify` | `{"channel","target","code":"482913"}` | `{"verified":true,"token":"…"}` or `{"verified":false}` · 429 after 5 wrong |
| `POST /api/contact` | name, `phone` or `email`, `role`, `serviceTiming`, `message`, `otpToken`, `requestId` | `{"accepted":true}` · 400 with `fields` · 429 |

- Roles: `property_owner`, `tenant`, `broker` (shown as Property Agent), `builder`.
- Each enquiry is saved to Firestore `web_leads` (with `status: "new"`) and emailed to `LEADS_TO`. A repeat submit with the same `requestId` is not saved or emailed twice. If the email fails, the lead is still saved.
- Firestore collections used: `web_otp`, `web_rate`, `web_leads` (prefixed so they never clash with the app).

Built-in protections: codes expire in 10 minutes and work once; 5 wrong tries cancel a code; 30 s resend gap; 5 codes per contact per hour; 10 codes and 10 enquiries per IP per hour; tokens last 30 minutes and must match the submitted phone/email; codes stored only as hashes and never logged; bot honeypot.

### 4.4 Accounts to create
**MSG91 (SMS)**
- Create the account; copy the Auth Key (Settings → API).
- Complete DLT registration (Indian telecom rule) for sender ID "TRSTKP" and the template:
  `Your TrustKeyper code is ##otp##. It expires in 10 minutes. Do not share it with anyone.`
- Add the approved template in MSG91 (Flow); copy its Template ID. The variable must be named `otp`.

**Resend (email)**
- Create the account, add domain `trustkeyper.com`, add the DNS records it shows until Verified.
- Create an API key with sending access.

---

## 5. Deploying

### 5.1 Where things run
- **Website** (`site/dist/`): any static host. Recommended: a separate Firebase Hosting site in the same project (the existing `firebase.json` hosting entry serves the Flutter web app, so do not overwrite it).
- **Backend** (`api/`): Google Cloud Run, region `asia-south1` (Mumbai), same Google project as Firebase. Scales to zero when idle.

### 5.2 Backend
```bash
# Secrets (once)
openssl rand -hex 32 | gcloud secrets create tk-web-secret --data-file=-
printf '%s' 'MSG91_AUTH_KEY_HERE'    | gcloud secrets create tk-msg91-key --data-file=-
printf '%s' 'MSG91_TEMPLATE_ID_HERE' | gcloud secrets create tk-msg91-template --data-file=-
printf '%s' 'RESEND_API_KEY_HERE'    | gcloud secrets create tk-resend-key --data-file=-
```
Give the Cloud Run service account the roles **Secret Manager Secret Accessor** and **Cloud Datastore User**. Then:
```bash
cd website/api
PROJECT=<firebase-project-id> ./deploy.sh     # prints "ok" when live
```
All settings are listed in `api/.env.example`; `deploy.sh` sets them. The server refuses to start if a required setting is missing.

### 5.3 Website
```bash
cd website/site && python3 build.py
```
Host `site/dist/` and add the rewrite from `api/firebase.hosting.example.json` so `/api/**` goes to the Cloud Run service `tk-web-api`. With Firebase Hosting, create a second hosting site (e.g. `trustkeyper-web`), point trustkeyper.com at it, and use a hosting target so the app's hosting entry is untouched.

### 5.4 Firestore housekeeping
- TTL policy on `web_otp`, field `expiresAt`.
- Firestore rules: deny all client access to `web_otp`, `web_rate`, `web_leads` (only the server, via its service account, uses them; service accounts bypass rules).

---

## 6. Considerations and decisions

- **Backend language.** Aman asked for the backend in Dart. The repo's existing Firebase Functions are in Node, so this adds a second backend runtime (Cloud Run). It is self-contained in `website/api/`. If the team prefers one runtime, the same three endpoints can be ported to Functions; the website would not change.
- **Separate from the app.** Nothing under `apps/`, `functions/`, or the root Firebase config was changed.
- **Pushed directly to `staging`.** `AGENTS.md` asks for feature branches; by the owner's standing instruction this folder was pushed to `staging` directly (as with the change log's earlier entries). No CI workflow exists, so the push deploys nothing.
- **"Broker" internals.** Visitors only see "Property Agent". Internal IDs and the form's role value stay `broker` so stored data and the backend stay consistent.
- **Testimonials.** The three owner quotes (Krishna J., Kalyana C., Ghanalaxmi T.) were drafted and approved by the owners. Google reviews are not on the page yet: Aman to supply them.
- **Pricing** is intentionally not shown anywhere.
- **₹100 visit fee wording** says agents "earn from every visit"; the agent's share is not stated. Confirm with Aman before launch.
- **Agent page translations** (Hindi, Telugu) should be read by a native speaker before launch.
- **Testimonial wording.** Ghanalaxmi T.'s quote was rewritten on 1 Nov (tenant found and onboarded within 24 hours; "Owner, ASBL Spectra"); confirm with her before launch like the others.
- **Old assets.** `contact-illustration-*.webp` and a few original images remain in `src/assets/`; the form uses a cropped copy, `contact-photo.webp`.

---

## 7. Go-live test list

Run on trustkeyper.com after deploying (preview code 123456 no longer works there).

- [ ] All pages load; menu links work; `/for-brokers` redirects to `/for-property-agents`.
- [ ] Tablet (768–1199 px): the ☰ menu opens and lists For Homeowners / For Property Agents / For Builders.
- [ ] FAQs on the homepage and agent page start collapsed; tapping a question opens it.
- [ ] Homepage hero on a phone: text readable over the photo, button reads "Register now".
- [ ] Agent page: English / Hindi / Telugu switch works and is remembered.
- [ ] Phone OTP: SMS arrives within ~10 s and verifies; a wrong code is rejected; resend after 30 s.
- [ ] Email OTP: code arrives (check spam in Gmail and Outlook) and verifies.
- [ ] Enquiry sent as each role arrives in Firestore `web_leads` and at the `LEADS_TO` inbox.
- [ ] WhatsApp button opens a chat with +91 8088516875.
- [ ] Phone layout (390 px wide) has no sideways scrolling.

---

## 8. File map

```
website/
├── README.md
├── docs/DEVELOPER_GUIDE.md        this guide
├── site/
│   ├── build.py                    builds src/ → dist/
│   ├── site.config.json            agent name, visit fee, offices
│   └── src/
│       ├── index.html              homeowner page
│       ├── __agent_page__/         property agent page (published at the agent slug)
│       ├── for-builders/           builders page
│       ├── contact-us/ about-us/ faqs/ privacy-policy/ terms-and-conditions/ delete-account/
│       ├── _partials/              footer.html, enquiry.html
│       ├── i18n/agent-page.json    EN / HI / TE text
│       ├── website.js / .css       site-wide behaviour and styles
│       ├── agent.js / .css         agent page (language switch, reveal)
│       ├── builder.css             builders page
│       └── assets/                 images, fonts, original compiled CSS
└── api/
    ├── bin/server.dart             entry point
    ├── lib/src/                    api, security, store, firestore_store, senders, config
    ├── test/api_test.dart          18 tests
    ├── Dockerfile · deploy.sh · firebase.hosting.example.json · .env.example
```
