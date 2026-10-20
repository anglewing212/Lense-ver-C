#!/bin/zsh
set -eu
umask 077
signing_dir="$HOME/Library/Application Support/Lense/Signing"
mkdir -p "$signing_dir"
chmod 700 "$signing_dir"
if [[ -f "$signing_dir/certificate.der" && -f "$signing_dir/lense.keychain-db" ]]; then
    print 'Lense signing identity already exists.'
    exit 0
fi
if [[ -e "$signing_dir/lense.keychain-db" ]]; then
    print -u2 'Incomplete signing setup; preserve the existing keychain and inspect it before retrying.'
    exit 1
fi
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
/usr/bin/openssl rand -base64 32 > "$signing_dir/keychain-password"
security create-keychain -p "$(cat "$signing_dir/keychain-password")" "$signing_dir/lense.keychain-db"
security unlock-keychain -p "$(cat "$signing_dir/keychain-password")" "$signing_dir/lense.keychain-db"
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -subj '/CN=Lense Local Development/O=Lense Local Development/' \
    -keyout "$tmp_dir/key.pem" -out "$tmp_dir/cert.pem" \
    -addext 'basicConstraints=critical,CA:false' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' > "$tmp_dir/openssl.log" 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$tmp_dir/key.pem" -in "$tmp_dir/cert.pem" \
    -name 'Lense Local Development' -passout file:"$signing_dir/keychain-password" -out "$tmp_dir/identity.p12"
security import "$tmp_dir/identity.p12" -k "$signing_dir/lense.keychain-db" \
    -P "$(cat "$signing_dir/keychain-password")" -T /usr/bin/codesign
/usr/bin/openssl x509 -in "$tmp_dir/cert.pem" -outform DER -out "$signing_dir/certificate.der"
print 'Created persistent Lense-only local signing identity.'
