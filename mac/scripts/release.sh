#!/bin/sh
# mac/scripts/release.sh VERSION: Terminal Values.app built, signed with a
# Developer ID, notarized, packed as a .dmg, with Sparkle's update feed.
# GitHub Actions runs it on a version tag (.github/workflows/app.yml); it also
# runs by hand on a Mac whose keychain has the signing identity. Needs:
#   TEAM_ID                     the Apple Developer team
#   NOTARY_KEY                  App Store Connect API key (.p8 file) for notarytool,
#   NOTARY_KEY_ID, NOTARY_ISSUER  and its ids
#   SPARKLE_PUBLIC_KEY          Sparkle's EdDSA public key (goes in the app)
#   SPARKLE_PRIVATE_KEY_FILE    and its private key, to sign the update
#   SPARKLE_BIN                 Sparkle's bin/ directory (generate_appcast)
# Leaves mac/build/release/Terminal-Values-VERSION.dmg and feed/appcast.xml.
set -eu
VERSION=${1:-}
[ -n "$VERSION" ] || { echo "usage: release.sh VERSION" >&2; exit 2; }
missing=
for v in TEAM_ID NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER SPARKLE_PUBLIC_KEY SPARKLE_PRIVATE_KEY_FILE SPARKLE_BIN; do
    eval "[ -n \"\${$v:-}\" ]" || missing="$missing $v"
done
[ -z "$missing" ] || { echo "release.sh: not set:$missing" >&2; exit 2; }

cd "$(dirname "$0")/../.."
OUT=mac/build/release
rm -rf "$OUT" && mkdir -p "$OUT/feed"
rev=$(git rev-parse HEAD)
short=$(printf '%s' "$rev" | cut -c1-7)

# 1. The box image built from this very commit (image.yml publishes it as
#    sha-<7>), so the app's tv and the box's scripts match. Its build may
#    still be running.
digest=
for _ in $(seq 1 60); do
    token=$(curl -fsSL "https://ghcr.io/token?scope=repository:terminal-values/tvbox:pull" |
        sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
    digest=$(curl -fsSI -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        "https://ghcr.io/v2/terminal-values/tvbox/manifests/sha-$short" 2>/dev/null |
        tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *//p')
    [ -n "$digest" ] && break
    echo "Waiting for the box image for $short..."
    sleep 30
done
[ -n "$digest" ] || { echo "release.sh: no box image for $short" >&2; exit 1; }
pin=mac/TerminalValues/BoxImage.plist
trap 'rm -f "$pin"' EXIT
plutil -create xml1 "$pin"
plutil -insert Digest -string "$digest" "$pin"
plutil -insert Revision -string "$rev" "$pin"

# 2. Build, signed with the Developer ID.
(cd mac && xcodegen generate --quiet)
xcodebuild -project mac/TerminalValues.xcodeproj -scheme TerminalValues -configuration Release \
    -derivedDataPath mac/build -archivePath "$OUT/TerminalValues.xcarchive" archive -quiet \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp
cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/TerminalValues.xcarchive" -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/export.plist" -quiet
app="$OUT/Terminal Values.app"

# 3. Notarized, and the ticket stapled to the app, then to the .dmg.
notarize() {
    xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER" --wait
}
ditto -c -k --keepParent "$app" "$OUT/app.zip"
notarize "$OUT/app.zip"
xcrun stapler staple "$app"

# 4. The .dmg: the app, and a link to drag it to Applications.
stage="$OUT/dmg"
mkdir "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="$OUT/feed/Terminal-Values-$VERSION.dmg"
hdiutil create -volname "Terminal Values" -srcfolder "$stage" -format UDZO -ov "$dmg" -quiet
notarize "$dmg"
xcrun stapler staple "$dmg"

# 5. Sparkle's feed, signed, pointing at this release's .dmg.
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "https://github.com/terminal-values/tvbox/releases/download/v$VERSION/" \
    "$OUT/feed"
echo "$dmg"
echo "$OUT/feed/appcast.xml"
