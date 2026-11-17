#!/usr/bin/env bash
# One-time: the permanent signing key for the APK on GitHub Releases.
#
# Creates ~/wimg-apk.p12 (alias wimg-apk, RSA 4096, 30 years) with a random
# password, keeps the password in the macOS Keychain (service "wimg-apk-key"),
# and stores both as GitHub secrets (WIMG_APK_KEYSTORE_BASE64,
# WIMG_APK_KEYSTORE_PASSWORD). The password is never printed.
#
# Back up ~/wimg-apk.p12 and the Keychain entry together. Losing the key means
# every GitHub install needs one more uninstall; never commit it.
#
# Read the password later:  security find-generic-password -s wimg-apk-key -w
set -euo pipefail

KEY="$HOME/wimg-apk.p12"
SERVICE="wimg-apk-key"

if [ -e "$KEY" ]; then
  echo "$KEY already exists. Refusing to overwrite the permanent key." >&2
  exit 1
fi
# /usr/bin/keytool is macOS's stub without a system Java: prefer JAVA_HOME,
# then Android Studio's bundled JBR.
KEYTOOL=""
for j in "${JAVA_HOME:-}" "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
  if [ -n "$j" ] && [ -x "$j/bin/keytool" ]; then KEYTOOL="$j/bin/keytool"; break; fi
done
if [ -z "$KEYTOOL" ] && keytool -help >/dev/null 2>&1; then KEYTOOL=keytool; fi
[ -n "$KEYTOOL" ] || { echo "keytool not found (install a JDK or Android Studio)" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
# Only the active account: `gh auth status` also fails on a stale second one.
gh auth token >/dev/null 2>&1 || { echo "gh is not logged in: gh auth login" >&2; exit 1; }

PASS="$(openssl rand -base64 33 | tr -d '/+=\n')"

"$KEYTOOL" -genkeypair -storetype PKCS12 -keystore "$KEY" -alias wimg-apk \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -dname "CN=wimg" \
  -storepass "$PASS" -keypass "$PASS" >/dev/null
chmod 600 "$KEY"

security add-generic-password -a "$USER" -s "$SERVICE" -w "$PASS" -U

base64 < "$KEY" | tr -d '\n' | gh secret set WIMG_APK_KEYSTORE_BASE64
printf '%s' "$PASS" | gh secret set WIMG_APK_KEYSTORE_PASSWORD

echo "Key: $KEY (password in the Keychain as \"$SERVICE\")"
echo "SHA-256 fingerprint:"
"$KEYTOOL" -list -v -keystore "$KEY" -storepass "$PASS" -alias wimg-apk | grep 'SHA256:'
echo "Back up $KEY now (password manager or encrypted backup)."
