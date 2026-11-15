# Poki MCP troubleshooting and issue drafting

Use this reference when a Poki MCP call fails, when the Poki iPhone app or Poki Setup reports an error, or when you need to draft a GitHub issue for the user.

## 1. Diagnostic tools and what they return

Call read-only tools first to collect facts before retrying any action. On the Mac `poki-mcp` server, tools outside default `tools/list` still accept direct `tools/call` requests without `POKI_MCP_TOOLS=all`.

### Mac `poki-mcp` server

| Tool | In default `tools/list` | Arguments | Key return fields |
| --- | --- | --- | --- |
| `poki_mcp_status` | Yes | `{}` | `implementation` (`"Poki MCP <version>"`), `commit`, `native_build`, `total_tools`, `devices` count, `selected` device ID, `approval_mode`, and optional `update` (`version`, `summary`, `url`, `command`). Runs even when the daemon reports outdated code. |
| `list_devices` | Yes | `{ include_all_simulators?: boolean }` | `devices[]` with `id`, `connection` (`"USB"`, `"RemotePairing"`, or `"Simulator"`), `kind`, `name`, `model`, `osVersion`, `readiness`, `occupied`, or `blocked` and `action` when a phone is locked, untrusted, or unreachable. Includes `notice` when `usbmuxd` sees no USB iPhone. |
| `get_device_info` | No (callable directly) | `{ device?: string, include_settings?: boolean }` | `id`, `name`, `kind`, `connection`, `model` (`ProductType` on USB, such as `iPhone17,1`), `osVersion` (`ProductVersion`), `engine`, `mirror_status`, `screen` (`width`, `height`, `scale`, `units`), and optional `settings` (`appearance`, `text_size`, accessibility flags, unavailable over `RemotePairing`). |
| `observe_device` | No (callable directly) | `{ device?: string, source?: "auto" \| "accessibility" \| "ocr", max_elements?: number, include_offscreen?: boolean, include_image?: boolean }` | Current PNG screenshot (unless `include_image: false`), `foreground` (`pid`, `bundle_id`, `name`), `elements[]` with `ref` and `frame`, `source`, `fallback_reason`, and `prompt` (`warning.kind: "passcode"` or alert buttons when a system prompt blocks the screen). |
| `list_crashes` | No (callable directly) | `{ device?: string, process?: string, kind?: "crash" \| "spin" \| "log" \| "diagnostic" \| "all", limit?: number }` | `source` (`"device systemCrashLogs"` on USB or `"host DiagnosticReports"` on Simulator) and `reports[]` (`path`, `name`, `modified`, `kind`). Unavailable over `RemotePairing`. |
| `get_crash` | No (callable directly) | `{ device?: string, path?: string, process?: string, full?: boolean }` | Copies the `.ips` or `.crash` file into `POKI_MCP_STATE_DIR/crashes/` and returns `process`, `bundle_id`, `exception`, `termination`, `faulting_thread`, and top `frames[]` (or raw text with `full: true`). Unavailable over `RemotePairing`. |
| `reconnect_device` | No (callable directly) | `{ device?: string }` | Attempts a fresh `RemotePairing` tunnel and re-resolves `.local` Bonjour names while keeping an existing working tunnel if replacement fails. Never replays prior input. |
| `disconnect_device` | No (callable directly) | `{ device?: string }` | Closes the detached `poki-native --remote-server` helper and its `RemotePairing` connection. |

### Poki iPhone app MCP connector

When the MCP client connects to the standalone Poki iPhone app through its relay connector (`poki` server exposing `status`, `look`, `do`, `routines`):

| Tool | Arguments | Key return fields |
| --- | --- | --- |
| `status` | `{}` | Plain-text lines that bypass the action queue: `runner: running`, `runner: starting (<detail>)`, or `runner: failed: <detail>. Fix on the phone: <fix>`, followed by `relay: ready \| connecting \| offline (<why>)`, optional `approval waiting on the phone`, optional `handoff`, and optional `running` call summary. |
| `look` | `{ full?: boolean }` | Foreground app, numbered elements, Vision OCR fallback text when accessibility is empty or slow, and a JPEG screenshot. Reports `screen: locked` when the phone is locked, or `poki: Poki is in front` when Poki itself is open on screen. |

## 2. Failure classes, exact error strings, and recovery

### 2.1 Disk image missing or outdated

**Observed error strings**

- **Mac `poki-mcp`.** Input tools return `outcome: "not_sent"`, `reason: "display_service_missing"`, and `error: "Cannot establish input media session: no display service: ServiceNotFound"`. Screenshots, `list_elements`, and `observe_device` still succeed without `com.apple.coredevice.displayservice`, so working screen reads do not prove touch or text input is ready.
- **Mac `prepare-device.mjs`.** Output contains `STATUS=94`, `TSS server responded with non-success status`, `This device isn't eligible for the requested build`, or `[17: File exists]`.
- **Poki iPhone app and Live Activity.** Status or task output shows `"Disk Image Outdated"` (`ddi_refused`), `"Update the Disk Image"`, `"Fetching Disk Image"` (`ddi_bad`), `"No Internet"` (`ddi_timeout` or `network` on first mount after a phone restart), `"the developer disk image was installed but its services did not appear"`, or `developer_framework_unavailable` (`dlopen` could not load `XCTest.framework`, `XCTestSupport.framework`, or `XCTAutomationSupport.framework`).

**Why Setup Wizard can show everything ready while tasks fail**

Poki's 5 Setup Wizard steps (`Developer Mode`, `Local Connection`, `Pair This iPhone`, `UI Automation`, `Stay On in Background`) check saved flags, TCP reachability on `10.7.0.1:62078`, pairing file presence, and downloaded disk image files (`"Ready"`). Apple TSS personalization, mounting `/System/Developer`, and `dlopen` of developer frameworks happen only when Automation starts. All 5 steps can show done while mounting or framework loading fails on every task.

**What you fix yourself**

- On a Mac checkout with the unlocked, trusted iPhone connected over USB, run `node bin/prepare-device.mjs <UDID>`. That command mounts the local Xcode developer disk image without reinstalling Poki or altering app data.
- When Poki Setup is installed (`"/Applications/Poki Setup.app/Contents/MacOS/poki-setup"` on macOS, `"$HOME/Applications/Poki Setup.app/Contents/MacOS/poki-setup"`, or `"%LOCALAPPDATA%\Poki Setup\poki-setup.exe"` on Windows), run `poki-setup ddi --udid <UDID>` to mount a personalized disk image without Xcode.
- When `status` or the app shows `"Fetching Disk Image"` (`ddi_bad`), Poki redownloads the image on its own. Wait a few seconds and call `status` again.

**When user action is required**

- **Xcode disk image rejected (`STATUS=94`).** The Mac's Xcode is older than the phone's iOS (for example iOS 27 requires Xcode 27). Ask the user to update Xcode, open it once until component installation finishes, and let you rerun `node bin/prepare-device.mjs <UDID>`.
- **Mount conflict (`[17: File exists]` at `/System/Developer`).** Ask the user to quit Xcode, restart the iPhone, reconnect it over USB unlocked, and let you rerun `prepare-device.mjs` with Xcode closed.
- **Phone restarted on cellular data only.** Mounting the developer disk image once after each phone restart requires Wi-Fi and internet access to Apple's signing server. Ask the user to connect to Wi-Fi so Poki can retry the mount.

**When you cannot fix it**

Draft a GitHub issue (`ios_app_bug.yml` or `bug_report.yml`) when Poki is on the newest build for its channel, Wi-Fi and loopback work, re-running Setup or computer `ddi` preparation succeeded, and tasks still fail with `"Disk Image Outdated"` or `developer_framework_unavailable` after a phone restart.

### 2.2 Runner stopped or Automation turns back off

**Observed error strings**

- **Poki iPhone app Settings and home cards.** The screen shows `Status = Disconnected`, `"Runner stopped"`, `"Runner Stopped"`, `"The runner stopped"`, `"Poki is off"`, `"Poki is off. Agents can't reach this iPhone."`, `"Automation did not start"`, `"Needs attention"`, `"Poki Runner Missing"` (`runner`), or `"Poki Runner Didn't Start"` (`runner_blocked`).
- **Poki iPhone app MCP `status` or `do`.** Output shows `runner: starting (<detail>)`, `runner: failed: <detail>. Fix on the phone: <fix>`, `open_poki_first`, `passcodeMissed`, or `the runner is not running (connection refused at http://127.0.0.1:8100)`.
- **Mac `poki-mcp`.** Tool calls return `"The service is running old code. Stop the running service and restart it with npm start."` or `"The running Poki MCP rejected the token in ... Restart it with npm start."`

**Why the Automation switch snaps back to off with no error text**

Before the first automation session after an iPhone restart, and again 8 hours after the previous passcode check, iOS requires the owner to enter the iPhone passcode on screen. Poki logs `no automation since this iPhone restarted: telling the owner iOS will ask for the passcode` and presents the `"Enter Your Passcode Next"` alert before starting the session. On builds where full-screen **Settings** covers that alert on the main view, tapping **Settings > Connection > Automation** flips the switch straight back to off with no red text under the switch.

**What you fix yourself**

- If `status` reports `starting again after being idle`, `opening the in-process session`, or `it is being restarted`, wait 3 to 10 seconds and call `status` or `look` again. Do not report an idle wake-up as a failure.
- On Mac `poki-mcp`, if `"The service is running old code"` or a rejected token error appears after `poki update` or `./bin/setup`, restart `npm start` using the same `POKI_MCP_STATE_DIR` and verify with `poki_mcp_status`.
- On USB or Simulator, call `list_crashes` and `get_crash` to inspect whether `Poki`, `WebDriverAgentRunner`, or the target app crashed.

**When user action is required**

- **Passcode gate (`waiting for the owner to enter the iPhone passcode`, `passcodeMissed`, `open_poki_first`, or Automation snapping off).** Ask the user to close **Settings** and check Poki's main chat screen for the `"Enter Your Passcode Next"` (**Continue**) prompt, or turn **Automation** off and on and enter the iPhone passcode when iOS asks.
- **System switches.** Ask the user to confirm on the iPhone that **Settings > Privacy & Security > Developer Mode** is on and **Settings > Developer > Enable UI Automation** is on. Poki's Setup steps 1 and 4 record earlier checks and do not detect if a system switch was turned off later.

**When you cannot fix it**

Draft an issue (`ios_app_bug.yml`) when **Automation** still snaps back to off with no `"Enter Your Passcode Next"` or iOS passcode prompt even from the main chat screen after force-quitting and reopening Poki, or when `runner: failed` persists after Developer Mode, UI Automation, loopback, and passcode checks pass.

### 2.3 Disconnected, loopback off, or pairing failed

**Observed error strings**

- **Mac `poki-mcp`.** Output returns `"No device is connected. Connect and trust an iPhone, or start a simulator."`, `"Device is not connected or the selected device disconnected. Use list_devices and select_device."`, `list_devices` `notice` (`"usbmuxd answered, but no iPhone is attached over USB..."`), `"Remote pairing is unreachable (...)"`, `"The remote pairing control connection closed: ..."`, or `"The iPhone refused a new tunnel. Reconnect it to Wi-Fi, then reconnect the device."`
- **Relay HTTP `503` (JSON-RPC `-32001`).** Response says `"The phone is offline: open Poki on the phone, or check its network."` Turning Poki off on the iPhone closes its relay WebSocket, which produces the same `503` response.
- **Poki iPhone app.** Status shows `"Loopback Off"` (`loopback`), `"Tunnel On, No Answer"`, `"10.7.0.1 takes the connection, but the phone's remote pairing service does not answer through it"` (`servicesSilent`), `"Another VPN appears to be on..."`, `"Finding Pairing Port"` (`pairing_port`), `"Pairing Refused"` (`pairing`), `"Loopback or Pairing"` (`handshake`), or `"Can't Reach iPhone"` (`unreachable`).

**What you fix yourself**

- On Mac `poki-mcp` with `RemotePairing`, call `reconnect_device`. If the host uses a `.local` Bonjour name, `reconnect_device` resolves the current address again without dropping an existing working tunnel if replacement fails.
- If a user plugs in USB to recover a phone that is still listed in `POKI_MCP_STATE_DIR/remote-devices.json`, Mac `poki-mcp` keeps using `RemotePairing` and ignores USB. Call `disconnect_device`, remove only that device's entry from `remote-devices.json` (keep `remote/<UDID>/pairing.plist` private and intact), and restart `npm start`.
- If a detached `poki-native --remote-server` helper is wedged across daemon restarts (`Remote operation timed out`), call `disconnect_device` before reconnecting.

**When user action is required**

- **Missing USB attachment.** Ask the user to connect the iPhone directly with a USB data cable, unlock it, tap **Trust This Computer**, and check whether Finder lists the iPhone.
- **Relay `503` (`"The phone is offline"`).** Ask the user to open Poki on the iPhone, check internet access, and confirm **Settings > Connection > Automation** is on.
- **Loopback down (`"Loopback Off"`, `"Tunnel On, No Answer"`, or `"Another VPN appears to be on"`).** Ask the user to connect Wi-Fi and enable the `10.7.0.1` loopback route in LocalDevVPN, Surge, Loon, Shadowrocket (`Include route 10.7.0.1/32`), or sing-box, or turn off a conflicting VPN and tap **Enable Local Connection** in Poki.
- **Local Network permission (`"Finding Pairing Port"` on iOS or `No route to host` on macOS 15+).** On the iPhone, ask the user to allow **Settings > Privacy & Security > Local Network** for Poki on Wi-Fi. On macOS 15+, ask them to grant **System Settings > Privacy & Security > Local Network** to the desktop client or editor that spawned `poki-mcp`.
- **Pairing rejected (`"Pairing Refused"` or a computer lockdown pairing file on iOS 27).** Ask the user to connect Wi-Fi, confirm loopback is on, and pair directly on the phone in **Setup > Pair This iPhone**.

**When you cannot fix it**

Draft an issue when Finder sees a trusted, unlocked USB iPhone that `usbmuxd` still omits, or when on-device pairing keeps failing on Wi-Fi with `10.7.0.1` loopback verified.

### 2.4 Locked screen, Poki in front, or blocked input

**Observed error strings**

- **Locked or dark display.** `observe_device` or `take_screenshot` returns `prompt.warning.kind: "passcode"`. `look` or `do` returns `screen: locked` or `screen: dark`.
- **Self-touch guard.** `look` returns `poki: Poki is in front...`. `do` returns `not_sent: only the phone's owner can approve, by tapping it on the phone themselves; Poki takes no taps or typing inside the Poki app`.
- **Paste or field errors.** Tools return `reason: "paste_permission"` (`Allow Paste` prompt remained on screen), `the clipboard could not be read`, `the field's menu showed no Paste item`, or a `fill` field-confirmation error.
- **Owner gates.** Tools return `approval_required` or `not_sent: a step is handed to the owner` (`handoff`).

**What you fix yourself**

- **Poki in front.** Launch the target app with `launch_app` (or `do {"launch": "<bundle_id>"}`) or leave Poki with `press_button` (`button: "home"`).
- **Paste blocked.** Call `handle_alert` to accept `Allow Paste` and inspect `screen` to confirm whether text landed, or type with `type_text` (or `do {"type": "..."}`) instead of pasting.
- **Field confirmation refused.** Nothing was typed or submitted. Read `screen` from the error response, adjust your selector or coordinates, and run only `remaining_steps`.

**When user action is required**

- **Locked phone.** Ask the user to unlock the iPhone manually, unless Poki Agent's host `unlock_device` was already configured by the user for a verified `iPhone17,1` portrait 6-digit passcode setup.
- **Pending approval or handoff.** Wait for the user to tap **Allow** or **Done** on the iPhone before resending the gated step.

### 2.5 Signing expiry, stalled update, or installer error

**Observed error strings**

- **Signing expiry.** Poki shows `"Poki's signing ends soon"` in the last 2 days of a 7-day free Apple Account profile, or iOS refuses to open Poki once expired.
- **Stalled in-app update.** Poki stays on `"Finishing the update: Poki will close to finish it"` or `"Installing the update. Features are unavailable until you reopen Poki."`
- **Installer error codes (`node bin/install-iphone.mjs`).** Output reports `bridge_start_failed` or `unknown` with `spawn Unknown system error -86` (`EBADARCH`, such as an arm64-only Poki Setup binary on an `x86_64` Intel Mac), `setup_download_failed` or `network` (GitHub HTTP 403 or 429 rate limits), `apple_account_limit` (free account limit of 10 App IDs per week, 3 active apps, or an existing development certificate), `ddi_refused`, `sign_failed`, or `install_failed`.

**What you fix yourself**

- **Stalled on `"Finishing the update"`.** Ask the user to swipe Poki away in the app switcher, reopen it, and read **Settings > Connection > Signing & Updates > Poki Version** (`Settings > General > Updates` in older 0.4.0 builds). Never tell the user to delete Poki, because deleting Poki erases all saved conversations and settings.
- **Computer-assisted update or renewal.** From the original signing Mac, follow [install-poki](../../install-poki/SKILL.md) (`node bin/install-iphone.mjs --update-only --json` for a newer build, or `poki-setup status --json` and `poki-setup renew` for an expired profile on the same signing identity).
- **Installer failure on a Mac checkout.** Run `node bin/install-iphone.mjs diagnose` to generate `diagnostics.json` (`poki.install-diagnostics/1`), which checks `system.arch`, USB versus `usbmuxd` versus `devicectl` versus Bonjour, and the last 40 log lines with identifiers removed.

**When user action or an issue is required**

- **GitHub 403 or 429 during release lookup.** Ask the user to switch network or proxy node, or retry after the hourly unauthenticated rate limit resets.
- **Account or certificate limit (`apple_account_limit`).** Stop and explain the exact limit Apple returned. Replacing a development certificate invalidates other apps signed with it, so only the user may decide.
- **Unrecoverable install failure.** Draft an issue (`install-failure.yml`, which `node bin/install-iphone.mjs issue` writes) when `diagnose` reveals an unsupported binary architecture, a signing or installation failure that persists past preflight checks, or a contradiction between `usbmuxd` and USB hardware discovery.

## 3. Collecting logs and stripping personal data

Collect only the minimum technical evidence needed to explain the failure, and strip every secret and identifier before showing or saving an issue draft.

### Safe diagnostic sources

- **Mac `poki-mcp`.** Use `poki_mcp_status`, `list_devices`, `get_device_info`, `get_crash` frame summaries, and relevant error lines from the daemon log or `POKI_MCP_CALL_LOG`.
- **Mac checkout installer.** `node bin/install-iphone.mjs diagnose` writes a pre-redacted `poki.install-diagnostics/1` JSON bundle. Over wired USB with Xcode installed, `node bin/install-iphone.mjs records` copies Poki's container log and chat records into `~/Library/Application Support/PokiInstall/records/`. Extract only technical `[app]`, `[session]`, `[runner]`, `[loopback]`, and `[pairing]` log lines around the failure, and never copy the user's chat messages into an issue.
- **Poki iPhone app UI.** Ask the user to open the conversations drawer, tap **Settings > Advanced > Log > More (...) > Copy Log** (or **Settings > Diagnostics > Copy Log**), or run **Settings > Advanced > Diagnostics > Run Checks**, and share only the lines around the failure with private text removed.

### Secrets and private files you must never print or attach

Never print environment variables, and never paste or upload raw contents from:

- `POKI_MCP_STATE_DIR/mcp.json` (contains the local daemon bearer `token`)
- `POKI_MCP_STATE_DIR/remote/<UDID>/pairing.plist` and Poki Setup `pairings/*.plist` or `*.rppairing.plist`
- Poki Setup `state/connectors.json` or `poki-setup mcp list --json` output (contains unredacted relay capability URLs `https://<relay>/v1/<label>/<secret>/mcp`, whereas `poki-setup mcp list` without `--json` redacts the secret)
- Poki Setup `keys/*.p8`, `state/account.json`, and `state/*.secret`
- `~/.pi/agent/auth.json` or any model API key, Apple Account email, password, two-factor code, Team ID, bundle ID, iPhone passcode, device UDID, serial number, device or computer name, phone number, IP address, or private screen and chat content
- `poki-setup support` zip archives without first removing device UDIDs, phone names, Team IDs, Wi-Fi IPs, and relay URLs

## 4. GitHub issue forms and required headings

GitHub Actions checks every new issue in `JosssphZhou/poki` against `.github/ISSUE_TEMPLATE`. If an issue created with `gh issue create` omits a required `### <label>` heading or leaves a required heading as `_No response_`, the workflow adds `needs-template` and asks for an edit.

### Workflow

1. Search first:
   ```sh
   gh issue list --repo JosssphZhou/poki --state all --search "<keywords>"
   ```
   If an existing issue covers the same root problem, draft a concise comment with your new version, device, and log evidence instead of opening a duplicate.
2. Pick the matching form from the table below. Put every required field as an exact English `### <label>` heading in the listed order, with a real answer underneath. Use `_No response_` only under optional headings. For dropdown fields, copy one allowed option verbatim.
3. Keep observations separate from inferences. Quote exact error strings. Never promise fix dates or release timelines.
4. Show the full title and Markdown body to the user and wait for confirmation before running `gh issue create --repo JosssphZhou/poki --title "<title>" --body-file <file>` (or `gh issue comment`). Never submit on your own. If a filed issue receives `needs-template`, fix it in place with `gh issue edit <number> --body-file <file>`.

### Form reference

| Form | When to use | Required `### <label>` headings (in order) | Optional headings | Verbatim dropdown options |
| --- | --- | --- | --- | --- |
| `bug_report.yml` | Poki MCP, Poki Agent, iMessage or Telegram channel, `bin/setup`, `poki-native`, or relay on a computer | `What happened`, `Steps to reproduce`, `Component`, `Connection`, `Versions` | `Logs`, `Suspected cause or fix` | **Component:** `Poki MCP`, `Poki Agent`, `iMessage or Telegram channel`, `Setup or update (bin/setup, poki update)`, `Native helper (poki-native)`, `Relay or remote MCP (deploy/)`<br>**Connection:** `Physical iPhone over USB`, `Physical iPhone over LAN (RemotePairing)`, `Physical iPhone over Tailscale or VPN`, `iOS Simulator`, `Not device-related` |
| `ios_app_bug.yml` | Standalone Poki iPhone app or Poki Setup desktop app runtime bug | `What happened`, `Steps to reproduce`, `Area`, `App version`, `Installed with`, `iPhone and iOS` | `Debug log` | **Area:** `Install or signing (Poki Setup, iLoader, refresh)`, `Pairing or Developer Mode`, `Automation on the phone (reads, taps, typing)`, `Chat, voice, or sessions`, `Live Activity or background`, `Remote MCP, relay, or connectors`, `Updates or release channel`, `Other` |
| `install-failure.yml` | Installing Poki stopped at a step (`node bin/install-iphone.mjs issue` writes this form) | `What happened`, `Step it stopped at`, `Install path`, `Diagnostics`, `Versions` | `Error code`, `What you or the agent tried` | **Step it stopped at:** `Get Poki Setup`, `Start Poki Setup`, `Sign in with the Apple Account`, `Find the iPhone`, `Pair (Trust This Computer)`, `Developer Mode`, `Sign and install Poki`, `Trust the developer and open Poki`, `Relay`, `Self-check`, `Don't know`<br>**Install path:** `Agent installer (node bin/install-iphone.mjs)`, `Poki Setup for Mac (window)`, `Poki Setup for Windows (window)`, `poki-setup command line` |
| `task_failure.yml` | Tools work, yet a real task inside a specific app could not finish | `Task`, `Where it stopped`, `Driven by`, `Versions` | `Trace` | **Driven by:** `Poki Agent (terminal)`, `Poki Agent over iMessage or Telegram`, `Another MCP client (Claude Code, Codex, ...)`, `Poki iPhone app` |
