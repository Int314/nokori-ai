#!/bin/bash
# Builds Nokori AI with your own Apple developer team, so that the Mac app and the iPhone app share your iCloud container.
#   scripts/setup.sh           write Config/Local.xcconfig for your team and generate NokoriAI.xcodeproj
#   scripts/setup.sh mac       then build the Mac app, put it in /Applications and open it
#   scripts/setup.sh iphone    then build the iPhone app and install it on your connected iPhone
# --team <team ID> picks one of several teams signed in to Xcode, --id <prefix> sets the identifier prefix
# (default com.<team ID>.nokori) and --device <UDID> picks one of several iPhones. Run it again after pulling a new version.
set -euo pipefail
cd "$(dirname "$0")/.."

target= team= id= device=
while (($#)); do
  case $1 in
    mac | iphone) target=$1 ;;
    --team) team=$2; shift ;;
    --id) id=$2; shift ;;
    --device) device=$2; shift ;;
    *) echo "usage: scripts/setup.sh [mac|iphone] [--team <team ID>] [--id <prefix>] [--device <UDID>]" >&2; exit 2 ;;
  esac
  shift
done
fail() { echo "$*" >&2; exit 1; }

xcodebuild -version >/dev/null 2>&1 || fail "Install Xcode, open it once, and run: sudo xcode-select -s /Applications/Xcode.app"
command -v xcodegen >/dev/null || fail "Install XcodeGen: brew install xcodegen"

local_config=Config/Local.xcconfig
if [[ ! -f $local_config ]]; then
  if [[ -z $team ]]; then
    # Xcode lists the teams of the accounts signed in under Settings > Accounts. iCloud and App Groups need a paid one.
    teams=$(defaults export com.apple.dt.Xcode - | plutil -extract IDEProvisioningTeamByIdentifier json -o - - 2>/dev/null | python3 -c '
import json, sys
for account in json.load(sys.stdin).values():
    for t in account:
        if not t.get("isFreeProvisioningTeam"): print(t["teamID"])' | sort -u || true)
    [[ -n $teams ]] || fail "Sign in to Xcode (Settings > Accounts) with an Apple Account in the paid Apple Developer Program."
    (($(wc -l <<<"$teams") == 1)) || fail "Several teams are signed in to Xcode. Pick one with --team: $(tr '\n' ' ' <<<"$teams")"
    team=$teams
  fi
  # This project's own team keeps its identifiers: a new prefix would register a new iCloud container, which can never be deleted.
  if [[ $team == "$(sed -n 's/^DEVELOPMENT_TEAM = //p' Config/Identity.xcconfig)" ]]; then
    echo "Team $team is this project's own; using Config/Identity.xcconfig as it is."
  else
    id=${id:-com.$(tr '[:upper:]' '[:lower:]' <<<"$team").nokori}
    printf '// Written by scripts/setup.sh. See Identity.xcconfig.\nDEVELOPMENT_TEAM = %s\nNOKORI_ID = %s\n' "$team" "$id" >"$local_config"
    echo "Wrote $local_config: team $team, identifiers $id"
  fi
fi
xcodegen generate --quiet

build() {
  xcodebuild -project NokoriAI.xcodeproj -scheme "$1" -configuration Debug -destination "$2" -derivedDataPath DerivedData \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration -skipPackagePluginValidation -skipMacroValidation -quiet build
}
bundle_id() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || true; }

case $target in
  mac)
    build NokoriMac "platform=macOS,arch=$(uname -m)"
    app="DerivedData/Build/Products/Debug/Nokori AI.app"
    installed="/Applications/Nokori AI.app"
    id=$(bundle_id "$app/Contents" CFBundleIdentifier)
    # A copy from Homebrew or Releases has another team's iCloud container and updates itself, so it is not replaced silently.
    if [[ -d $installed && ($(bundle_id "$installed/Contents" CFBundleIdentifier) != "$id" || -n $(bundle_id "$installed/Contents" SUFeedURL)) ]]; then
      fail "$installed is a release copy. Quit it and remove it first (brew uninstall --cask nokori-ai, or move it to the Trash)."
    fi
    osascript -e "if application id \"$id\" is running then tell application id \"$id\" to quit" >/dev/null
    rm -rf "$installed"
    ditto "$app" "$installed"
    open "$installed"
    echo "Installed $installed. Turn on Settings > Sync to iPhone in it."
    ;;
  iphone)
    if [[ -z $device ]]; then
      json=$(mktemp)
      xcrun devicectl list devices --json-output "$json" >/dev/null
      phones=$(python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    h = d["hardwareProperties"]
    if h.get("reality") == "physical" and h.get("platform") == "iOS": print(h["udid"], d["deviceProperties"]["name"])' "$json")
      rm -f "$json"
      [[ -n $phones ]] || fail "Connect your iPhone with a cable, unlock it and tap Trust."
      (($(wc -l <<<"$phones") == 1)) || fail "Several iPhones are paired. Pick one with --device <UDID>:"$'\n'"$phones"
      device=${phones%% *}
    fi
    build NokoriiOS "id=$device"
    app="DerivedData/Build/Products/Debug-iphoneos/Nokori AI.app"
    xcrun devicectl device install app --device "$device" "$app" >/dev/null
    xcrun devicectl device process launch --device "$device" "$(bundle_id "$app" CFBundleIdentifier)" >/dev/null 2>&1 || true
    echo "Installed on the iPhone. Add the widgets from the Home Screen."
    ;;
esac
