#!/bin/bash
# Run after xcodebuild. Syncs one target's catalog: scripts/sync-strings.sh [Mac|iOS|iOSWidgets] (default Mac).
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-Mac}" in
  Mac) catalog=Mac; build=Debug/NokoriMac.build ;;
  iOS) catalog=iOS; build=Debug-iphonesimulator/NokoriiOS.build ;;
  iOSWidgets) catalog=iOSWidgets; build=Debug-iphonesimulator/NokoriWidgets.build ;;
  *) echo 'Usage: scripts/sync-strings.sh [Mac|iOS|iOSWidgets]' >&2; exit 1 ;;
esac
objects=DerivedData/Build/Intermediates.noindex/NokoriAI.build/$build/Objects-normal
args=()
while IFS= read -r -d '' data; do args+=(--stringsdata "$data"); done < <(find "$objects" -name '*.stringsdata' -print0 2>/dev/null)
if [ "${#args[@]}" -eq 0 ]; then echo "Build the $catalog target (Debug) before syncing strings." >&2; exit 1; fi
xcrun xcstringstool sync "$catalog/Localizable.xcstrings" "${args[@]}"
