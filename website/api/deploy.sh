#!/usr/bin/env bash
# One-command deploy to Cloud Run, in the same Google project as Firebase.
# Usage:  PROJECT=your-firebase-project-id ./deploy.sh
# Secrets are read from Secret Manager (created once, see README step 3).
set -euo pipefail
: "${PROJECT:?Set PROJECT to your Firebase project id}"
REGION="${REGION:-asia-south1}"   # Mumbai
SERVICE="${SERVICE:-tk-web-api}"

gcloud run deploy "$SERVICE" \
  --project "$PROJECT" --region "$REGION" --source . \
  --allow-unauthenticated --min-instances 0 --max-instances 3 --memory 256Mi \
  --set-env-vars "STORE=firestore,GCP_PROJECT=$PROJECT,SMS_PROVIDER=msg91,EMAIL_PROVIDER=resend,LEADS_TO=${LEADS_TO:-info@trustkeyper.com},EMAIL_FROM=${EMAIL_FROM:-TrustKeyper <noreply@trustkeyper.com>}" \
  --set-secrets "TK_SECRET=tk-web-secret:latest,MSG91_AUTH_KEY=tk-msg91-key:latest,MSG91_TEMPLATE_ID=tk-msg91-template:latest,RESEND_API_KEY=tk-resend-key:latest"

echo "Deployed. Health check:"
curl -fsS "$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)')/healthz" && echo
