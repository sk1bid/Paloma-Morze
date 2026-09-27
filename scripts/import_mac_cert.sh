#!/bin/bash

# Paloma Morse - import the macOS code-signing certificate into a temporary keychain.
# Used by the release workflow before electron-builder runs; ui/scripts/mac-sign.cjs
# then signs the app with it. Every release MUST be signed with this same
# certificate, otherwise installed apps reject auto-updates (Squirrel.Mac).
#
# Env:
#   MAC_CERT_P12_BASE64  base64 of the .p12 (secret)
#   MAC_CERT_PASSWORD    .p12 password (secret)
#   KEYCHAIN_DIR         where to create the keychain (default: $RUNNER_TEMP or /tmp)
# Exports MAC_SIGN_IDENTITY and MAC_SIGN_KEYCHAIN to $GITHUB_ENV when present,
# otherwise prints them.

set -euo pipefail

if [ -z "${MAC_CERT_P12_BASE64:-}" ] || [ -z "${MAC_CERT_PASSWORD:-}" ]; then
    echo "::error::MAC_CERT_P12_BASE64 / MAC_CERT_PASSWORD are not set."
    echo "Refusing to build an ad-hoc signed macOS release: installed apps could not auto-update from it."
    exit 1
fi

KEYCHAIN_DIR="${KEYCHAIN_DIR:-${RUNNER_TEMP:-/tmp}}"
KEYCHAIN="$KEYCHAIN_DIR/paloma-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$KEYCHAIN_DIR/paloma-signing.p12"

echo "$MAC_CERT_P12_BASE64" | base64 --decode > "$P12"

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$MAC_CERT_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f "$P12"

# Self-signed, so macOS lists it as untrusted; codesign still signs with it by hash
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | grep -m1 -oE '[0-9A-F]{40}' || true)"
if [ -z "$IDENTITY" ]; then
    echo "::error::No code-signing identity found in the imported certificate."
    exit 1
fi

# On CI the keychain must be on the user search list: codesign resolves the
# identity's certificate chain only through that list.
if [ -n "${CI:-}" ]; then
    # shellcheck disable=SC2046
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
fi

# Prove the identity can actually sign before the (long) app build starts
probe_sign() {
    local probe="$KEYCHAIN_DIR/paloma-sign-probe"
    cp /usr/bin/true "$probe"
    local ok=0
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" "$probe" >/dev/null 2>&1 || ok=1
    rm -f "$probe"
    return $ok
}

if ! probe_sign; then
    if [ -n "${CI:-}" ]; then
        # Throwaway CI machine: trust the self-signed certificate for code signing
        echo "Signing probe failed; trusting the certificate for code signing on this runner"
        CERT_PEM="$KEYCHAIN_DIR/paloma-signing.pem"
        security find-certificate -a -p "$KEYCHAIN" > "$CERT_PEM"
        sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$CERT_PEM"
        rm -f "$CERT_PEM"
    fi
    if ! probe_sign; then
        echo "::error::codesign cannot sign with identity $IDENTITY from $KEYCHAIN."
        exit 1
    fi
fi

echo "Imported signing identity $IDENTITY (signing probe OK)"
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "MAC_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
    echo "MAC_SIGN_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
else
    echo "MAC_SIGN_IDENTITY=$IDENTITY"
    echo "MAC_SIGN_KEYCHAIN=$KEYCHAIN"
fi
