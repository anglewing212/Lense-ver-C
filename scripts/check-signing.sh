#!/bin/zsh
set -eu
cd "${0:A:h:h}"
signing_dir="$HOME/Library/Application Support/Lense/Signing"
app="$PWD/dist/Lense.app"
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
signing_hash=$(/usr/bin/openssl x509 -inform DER -in "$signing_dir/certificate.der" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
requirement="identifier \"com.lense.desktop\" and certificate leaf = H\"$signing_hash\""
/usr/bin/ditto "$app" "$check_dir/Lense.app"
mkdir -p "$check_dir/Lense.app/Contents/Resources"
print 'changed build contents' > "$check_dir/Lense.app/Contents/Resources/signing-check.txt"
security unlock-keychain -p "$(cat "$signing_dir/keychain-password")" "$signing_dir/lense.keychain-db"
codesign --force --sign "$signing_hash" --keychain "$signing_dir/lense.keychain-db" --timestamp=none \
    --requirements "=designated => $requirement" "$check_dir/Lense.app"
for target in "$app" "$check_dir/Lense.app"; do
    codesign --verify --strict --test-requirement "=$requirement" "$target"
done
original_requirement=$(codesign -dr - "$app" 2>&1 | sed -n 's/^designated => //p')
updated_requirement=$(codesign -dr - "$check_dir/Lense.app" 2>&1 | sed -n 's/^designated => //p')
original_hash=$(codesign -d --verbose=4 "$app" 2>&1 | sed -n 's/^CDHash=//p')
updated_hash=$(codesign -d --verbose=4 "$check_dir/Lense.app" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$original_requirement" && "$original_requirement" == "$updated_requirement" ]]
[[ -n "$original_hash" && "$original_hash" != "$updated_hash" ]]
print 'Passed: changed app contents retain the same certificate-pinned identity; both signatures verify.'
