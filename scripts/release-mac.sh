#!/bin/bash
# Builds the Mac app for GitHub Releases: archive, sign with Developer ID, notarize, staple, zip, and the files that
# point Sparkle and Homebrew at it. Raise MARKETING_VERSION and CURRENT_PROJECT_VERSION first: Sparkle compares the latter.
# Output in tmp/release/upload: the zip and appcast.xml (attach both to the GitHub release vX.Y.Z) and nokori-ai.rb
# (Casks/ in Int314/homebrew-tap). Needs the Developer ID certificate in the keychain,
# the "Nokori AI Mac Developer ID" profile, and notarization credentials saved once in the keychain, so no key ID
# or issuer sits in this public repository:
#   xcrun notarytool store-credentials nokori-ai-notary --key <AuthKey_XXXX.p8> --key-id <key ID> --issuer <issuer ID>
# and the Sparkle signing key under the keychain account nokori-ai. Its backup is in 1Password; losing it means
# shipped copies can never be updated again. Restore it with generate_keys --account nokori-ai -f <file>.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
repo=https://github.com/Int314/nokori-ai
out=tmp/release
upload="$out/upload"
rm -rf "$out" && mkdir -p "$upload"
xcodegen generate >/dev/null
xcodebuild -project NokoriAI.xcodeproj -scheme NokoriMac -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData -skipPackagePluginValidation -skipMacroValidation -archivePath "$out/NokoriAI.xcarchive" -quiet archive
xcodebuild -exportArchive -archivePath "$out/NokoriAI.xcarchive" -exportOptionsPlist scripts/ExportOptions-mac.plist -exportPath "$out/export" -quiet
app="$out/export/Nokori AI.app"
# The zip sent for notarization is not the one we ship: the ticket is stapled to the app afterwards.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --keychain-profile nokori-ai-notary --wait
xcrun stapler staple "$app"
spctl --assess --type exec "$app"
zip="Nokori-AI-$version.zip"
ditto -c -k --keepParent "$app" "$upload/$zip"
DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --account nokori-ai --link "$repo" \
  --download-url-prefix "$repo/releases/download/v$version/" -o "$upload/appcast.xml" "$upload"
sha=$(shasum -a 256 "$upload/$zip" | cut -d' ' -f1)
cat > "$upload/nokori-ai.rb" <<CASK
cask "nokori-ai" do
  version "$version"
  sha256 "$sha"

  url "$repo/releases/download/v#{version}/Nokori-AI-#{version}.zip"
  name "Nokori AI"
  desc "Claude Code and Codex subscription usage in the menu bar"
  homepage "$repo"

  # Sparkle updates the app itself.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Nokori AI.app"

  zap trash: [
    "~/Library/Application Support/Nokori AI",
    "~/Library/Caches/dev.int314.nokori.mac",
    "~/Library/HTTPStorages/dev.int314.nokori.mac",
    "~/Library/Preferences/dev.int314.nokori.mac.plist",
  ]
end
CASK
ls -1 "$upload"
