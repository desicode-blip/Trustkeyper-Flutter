# Supported architecture

`apps/flutter_app` is the only application. Flutter provides broker, owner,
tenant and administrator interfaces on Android, iOS and web. Recipient links
enter the same app's scoped document-request flow. The offline UI Test entry
uses synthetic gateways and a separate debug-only Android package.

Firebase Authentication identifies users; Firestore stores participant-scoped
records. Firestore and Storage rules enforce access boundaries. Node.js 22
Cloud Functions in `functions` handle privileged identity, document, agreement,
notification and lifecycle operations. Firebase Hosting serves
`apps/flutter_app/build/web` with SPA fallback and cache-revalidation headers.
The functions codebase remains `authentication` for selected deployments.

Client state must not authorize an account merge, signed agreement, payment,
payout or beneficiary verification. Administrators publish actual externally
signed documents using the protected admin workflow. Demo agreements are not
legally signable. Final provider transfer work remains deferred.

The primary Firebase project is `trustkeyper`; existing `.firebaserc` aliases
are preserved. Emulator tests use `demo-trustkeyper-rules`. Signing keys live
outside the repository. Secret Manager stores backend provider credentials;
no legacy application's environment file is required.

There is no active Expo/React app, Express API, pnpm monorepo, SQL schema,
Supabase client or Vercel build. Historical local code/data were archived, not
automatically migrated into Firebase. Remote services, DNS and customer records
remain unchanged. See `docs/handoff-status.md` and
`docs/product-requirements-coverage.md` for current product acceptance.
