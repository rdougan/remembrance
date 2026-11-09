#!/bin/bash
# Sets the five secrets the Mac release workflow needs, on rdougan/remembrance. Run on the Mac that
# holds the Developer ID certificate and an App Store Connect API key (the same ones the finances app uses).
#
# Usage: scripts/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXXXXXXXX.p8> <issuer-id>
#   The Key ID is read from the .p8 filename. The Issuer ID is on App Store Connect →
#   Users and Access → Integrations → App Store Connect API (top of the page).
set -euo pipefail
REPO="rdougan/remembrance"
P12="${1:?path to the Developer ID .p12}"
P8="${2:?path to the AuthKey_XXXX.p8}"
ISSUER="${3:?App Store Connect Issuer ID}"
KEY_ID="$(basename "$P8" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"

read -r -s -p "Password for $(basename "$P12"): " P12_PASSWORD; echo
# Fail early on a wrong password rather than in CI.
openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -noout -legacy 2>/dev/null \
  || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -noout \
  || { echo "That password doesn't open $P12"; exit 1; }

base64 -i "$P12" | gh secret set BUILD_CERTIFICATE_BASE64 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set P12_PASSWORD -R "$REPO"
base64 -i "$P8" | gh secret set NOTARY_KEY_BASE64 -R "$REPO"
printf '%s' "$KEY_ID" | gh secret set NOTARY_KEY_ID -R "$REPO"
printf '%s' "$ISSUER" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
echo "Set 5 secrets on $REPO (key $KEY_ID)."
