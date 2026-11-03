# Nokori AI

See how much of your Claude Code and Codex subscription is left — the 5-hour and weekly limits — in the Mac menu bar and on iPhone widgets.

- **Mac**: a menu bar meter (four styles) and a popover with reset times and whether you are ahead of an even weekly pace
- **iPhone** (optional, [build it yourself](#iphone-app)): an app and Home Screen / Lock Screen widgets that show what your Mac fetched, synced through your own iCloud

<p>
  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/popover-dark.png"><img src="docs/images/popover-light.png" width="340" alt="The Mac popover with Claude Code and Codex usage"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/iphone-dark.png"><img src="docs/images/iphone-light.png" width="330" alt="The iPhone app showing the same usage"></picture>
</p>

Four menu bar styles:

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/presets-dark.png"><img src="docs/images/presets-light.png" width="284" alt="The four menu bar styles"></picture>

<sub>Screens show sample numbers.</sub>

Nokori AI is not affiliated with, endorsed by, or sponsored by Anthropic or OpenAI. "Claude", "Claude Code", "Codex" and "ChatGPT" are trademarks of their respective owners.

## Requirements

- macOS 14 or later; for the iPhone app, iOS 17 or later and a paid Apple Developer Program membership
- Claude Code signed in with a Claude Pro or Max plan, and/or the Codex CLI signed in with a ChatGPT plan. API-key sign-ins have no subscription limits to show

## Install

1. Install with [Homebrew](https://brew.sh):

   ```bash
   brew trust --cask int314/tap/nokori-ai
   brew install --cask int314/tap/nokori-ai
   ```

   Homebrew loads casks from taps outside its own only once you trust them; the first line does that for this one cask.

   Or download the latest `Nokori AI` from [Releases](../../releases), move it to Applications and open it. It lives in the menu bar; there is no Dock icon.
2. The first time it reads your Claude Code sign-in, macOS asks whether Nokori AI may use the "Claude Code-credentials" keychain item. See [the keychain prompt](#the-keychain-prompt).

The app checks for updates once a day and offers them; turn that off or check now under **Updates** in its settings. Neither service promises the way usage is read here, so updates are how fixes reach you.

## How it gets the numbers

Neither service publishes an API for subscription usage. Nokori AI uses what the official tools themselves use, so it can break without notice when they change.

- **Claude Code**: reads the sign-in Claude Code stores in your keychain (or `~/.claude/.credentials.json`) and asks Anthropic's usage endpoint, identifying itself as Nokori AI
- **Codex**: starts your installed `codex` in read-only mode (`codex -s read-only -a never app-server`) and asks it for the account's rate limits

Nokori AI only reads. It never refreshes or writes either tool's credentials, keeps them in memory only, and sends them nowhere but the service they belong to. Claude Code's sign-in lasts about eight hours and only Claude Code renews it, so when it has expired Nokori AI starts `claude` for a few seconds in an empty folder of its own (no hooks, no MCP servers, nothing sent to the model) and lets it renew itself — useful on days you only use the Claude desktop app, which does not renew it. The iPhone receives the percentages and reset times through your private iCloud database — never credentials.

## The keychain prompt

Claude Code keeps its sign-in in the macOS keychain, and macOS asks before another app reads it. Nokori AI never shows that prompt on its own schedule; automatic refreshes only read what is already allowed. When access is missing, the popover shows **Allow**, and pressing it brings up the prompt.

Claude Code writes that item with Apple's `/usr/bin/security` tool, so Nokori AI reads it through the same tool when the item's access list already trusts it. In that case no prompt appears even after Claude Code renews its sign-in. Otherwise you may be asked again after a renewal.

## iPhone app

The iPhone app is not distributed; developers who want it build it themselves. iCloud sync and the App Group the widgets read from need a paid [Apple Developer Program](https://developer.apple.com/programs/) membership, and an iCloud container belongs to one developer team. So the Mac app from Homebrew or Releases cannot reach your iPhone: build both apps with your own team. A script does the work, and a coding agent such as Claude Code or Codex can run it for you; ask it to set up the iPhone app as this section says.

First, by hand:

- Install a current Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- In Xcode, Settings > Accounts, sign in with the Apple Account of your paid membership
- If you installed Nokori AI from Homebrew or Releases, quit it and remove it (`brew uninstall --cask nokori-ai`)
- On the iPhone, turn on Developer Mode (Settings > Privacy & Security), connect it to the Mac with a cable and trust the Mac

Then:

```bash
scripts/setup.sh mac
scripts/setup.sh iphone
```

The script writes your team and an identifier prefix to `Config/Local.xcconfig` (git ignores it; nothing in the repository changes), registers the bundle IDs, iCloud container and App Group with your team, builds the apps, puts the Mac app in Applications and installs the iPhone app. Run `scripts/setup.sh` without arguments to only generate `NokoriAI.xcodeproj`, then run `NokoriMac` and `NokoriiOS` from Xcode. If registering the iCloud container fails, open the project, select the target's Signing & Capabilities and check the container under iCloud once.

In the Mac app, turn on **Sync to iPhone**, with the Mac and the iPhone signed in to the same Apple Account. These builds use iCloud's development environment, which creates its record types on first use, and never update themselves: pull and run the script again for a new version. They keep working until their development profiles expire, a year at most.

## Privacy

Nothing is sent to the developer. See the [privacy policy](docs/privacy.md).

## License

[MIT](LICENSE)
