#!/bin/zsh
set -eu
cd "${0:A:h:h}"
signing_dir="$HOME/Library/Application Support/Lense/Signing"
if [[ ! -f "$signing_dir/certificate.der" || ! -f "$signing_dir/lense.keychain-db" ]]; then
    print -u2 'Run ./scripts/setup-signing.sh once before packaging. Temporary signing is disabled.'
    exit 1
fi
signing_hash=$(/usr/bin/openssl x509 -inform DER -in "$signing_dir/certificate.der" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
security unlock-keychain -p "$(cat "$signing_dir/keychain-password")" "$signing_dir/lense.keychain-db"
swift build -c release
app="$PWD/dist/Lense.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Assets/Lense.icns "$app/Contents/Resources/Lense.icns"
bin_dir=$(swift build -c release --show-bin-path)
cp "$bin_dir/Lense" "$app/Contents/MacOS/Lense"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.lense.desktop</string>
<key>CFBundleName</key><string>Lense</string>
<key>CFBundleIconFile</key><string>Lense.icns</string>
<key>CFBundleExecutable</key><string>Lense</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>仅截取您拖框选中的屏幕区域并发送给 AI 解答。</string>
</dict></plist>
PLIST
codesign --force --sign "$signing_hash" --keychain "$signing_dir/lense.keychain-db" --timestamp=none \
    --requirements "=designated => identifier \"com.lense.desktop\" and certificate leaf = H\"$signing_hash\"" "$app"
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --keepParent "$app" "$PWD/dist/Lense.zip"
