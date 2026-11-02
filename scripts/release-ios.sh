#!/bin/bash
# Builds the iPhone app and uploads it to App Store Connect, where it shows up in TestFlight. Raise
# CURRENT_PROJECT_VERSION first: each upload needs a build number above every earlier one.
# Needs the Apple Distribution certificate in the keychain, the "Nokori AI App Store" and "Nokori AI Widgets App Store"
# profiles, and an App Store Connect API key whose IDs come from the environment, so none sit in this public repository:
#   ASC_KEY_ID=<key ID> ASC_ISSUER_ID=<issuer ID> scripts/release-ios.sh   (the key is ~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8)
set -euo pipefail
: "${ASC_KEY_ID:?Set ASC_KEY_ID}" "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
cd "$(dirname "$0")/.."
out=tmp/release-ios
rm -rf "$out" && mkdir -p "$out"
xcodegen generate >/dev/null
xcodebuild -project NokoriAI.xcodeproj -scheme NokoriiOS -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData -skipPackagePluginValidation -skipMacroValidation -archivePath "$out/NokoriAI.xcarchive" -quiet archive
xcodebuild -exportArchive -archivePath "$out/NokoriAI.xcarchive" -exportOptionsPlist scripts/ExportOptions-ios.plist -exportPath "$out/export" -quiet
xcrun altool --upload-app -f "$out/export/Nokori AI.ipa" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
