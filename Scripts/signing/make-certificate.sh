#!/usr/bin/env bash
# Creates a self-signed code signing certificate as a .p12 with a random password.
# Usage: make-certificate.sh <output directory> [common name]
# Writes signing.p12, cert.pem and password.txt. Keep signing.p12 and password.txt private.
set -euo pipefail

out="$1"
name="${2:-Windows Self-Signed Code Signing}"
openssl_bin=/usr/bin/openssl   # macOS LibreSSL writes a .p12 that the Keychain can import
mkdir -p "$out"
chmod 700 "$out"

password="$("$openssl_bin" rand -hex 24)"
cat > "$out/cert.cnf" <<CONFIG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -keyout "$out/key.pem" -out "$out/cert.pem" -config "$out/cert.cnf" 2>/dev/null
"$openssl_bin" pkcs12 -export -inkey "$out/key.pem" -in "$out/cert.pem" -name "$name" \
    -out "$out/signing.p12" -passout "pass:$password"
printf '%s' "$password" > "$out/password.txt"
chmod 600 "$out/signing.p12" "$out/password.txt"
rm -f "$out/key.pem" "$out/cert.cnf"
echo "Created $out/signing.p12 for \"$name\""
