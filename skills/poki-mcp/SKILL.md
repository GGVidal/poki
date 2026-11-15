---
name: poki-mcp
description: Operate an iPhone and troubleshoot Poki errors with Poki MCP. Read before the first Poki call that types text, answers a prompt, or uses hardware buttons, and whenever Poki reports an error, stops responding, or needs a GitHub issue.
license: AGPL-3.0-only
---

# Poki MCP

For installation or updates of the standalone iPhone app, read [install-poki](../install-poki/SKILL.md) in the repository. If this skill was copied alone, use `skills/install-poki/SKILL.md` in the Poki checkout. The iPhone update branch checks the existing data, signing identity and release channel before installation. Updating the Mac's MCP service does not update the iPhone app.

## Tool discovery

The default `tools/list` contains the tools for device selection, screen reads, app launch, touch, text input, navigation, prompts, and batches. For tools outside that list, read `docs/tools.md` in the Poki checkout used by your registered MCP server. This skill can be copied into a client skill directory.

Set `POKI_MCP_TOOLS=all` in the MCP client's process environment and reconnect to list the complete catalog. Tools absent from the default list still accept direct calls. Device actions can run inside `batch_commands`; lease management calls must stay outside a batch. Consecutive calls do not require `acquire_device`. Poki Agent selects the complete catalog for its own MCP process and retains its own tool allowlist.

`run_code` is in the complete catalog, not the default list. It runs an async JavaScript function that calls device tools with `await tools.<name>(args)`, so the code reads a result and decides the next step in one call instead of a model round trip per step. Prefer it when a task is predictable but depends on what each step returns, such as scrolling until a row appears and then reading its value. A tool error throws and the code can catch it; an action that reports `sent=false` or an unknown outcome stops the script, as a batch stops. The sandbox has no require, file system, network, process or timers.

The examples below record earlier physical-iPhone checks. They are not a guarantee for every iOS version or app. Verify the current screen after each task.

## Send known text in one batch

When the text is already decided, send the steps that open the field and the `fill` in one `batch_commands` call, with `submit: true` on the `fill` when Return sends. `fill` reads the text back from that field before it sends Return, and a failed `fill` stops a batch with the default `stop_on_error: true`, so no look at the draft is needed in between. Keep them apart when the user asked to review the draft.

Basis: tapping `Add Row` then `fill` with `submit: true` in one batch, in a list of text fields: only the new row changed and Return followed the read-back, 3 of 3. A search typed into Chrome's address bar the same way reached the results, 1 of 1.

## When `fill` refuses

`fill` types nothing unless it can confirm the field being edited is the one you aimed at. A field-confirmation error says nothing was typed or sent. The default batch stops there. Read `screen` in the reply, aim again, and retry only the unfinished steps. A `batch_commands` failure returns `remaining_steps` for that batch.

Basis: a tap that gave the edit to the next row, 3 of 3; a list that kept moving, 3 of 3; coordinates with no field under them while another row was being edited, 1 of 1. Every row kept its text and Return was not sent.

## Paste permission

`fill` answers the system paste prompt itself: it taps Allow Paste, reads the text back, then sends Return. The receipt says `paste_permission_answered: true`, and no `handle_alert` call is needed.

Basis: Chrome's address bar, 1 of 1.

## Other prompts

Use `handle_alert` with `action: "accept"`, then read `screen` to confirm the prompt closed. A `button` label that is not there returns `Nothing was tapped` and leaves the prompt up.

Basis: a test alert, both paths, 1 of 1.

## Go to the Home screen

On a physical iPhone, use `press_button` with `button: "home"`. `press_key` with `key: "home"` sends a keyboard Home key and does not navigate to the iPhone Home screen. Read the screen after the button event to confirm navigation.

## Optional iPhone unlock

Poki Agent's host-integrated `unlock_device` is separate from the MCP tool catalog. Only the user may choose and configure `POKI_IPHONE_PASSCODE` in a private local launcher environment. Ask "Do you want Poki Agent to unlock this iPhone when it is locked?" and stop for that decision. Default to no configuration. Anyone or any program with access to this Mac may be able to read the passcode. If the user agrees, give them the hidden-input zsh commands in `agent/README.md` to run themselves. Never ask for the passcode in chat. Never read or write their passcode for them. The host passes it to the helper over stdin, outside model inputs and logs.

The verified hardware case is only iPhone17,1 in portrait orientation with a six-digit passcode and a 402-by-874-point keypad. Read `agent/skills/iphone-unlock/SKILL.md` in the Poki checkout before use. Setup builds `build/native-target/release/examples/unlock_iphone`. Confirm the current keypad layout and inspect the resulting screen. Without configuration, ask the user to unlock manually.

## Handle prompts

Read the visible prompt and its reported kind. Use `handle_alert` with a button label or `action: "accept"` / `"dismiss"` to choose a visible button. For a purchase prompt, generic `action: "accept"` leaves the prompt open and returns its kind and available buttons. After the action, read the screen to confirm the dialog closed and the task reached its intended state.

For login or verification, use the credentials available for the authorized task. Read a requested SMS verification code from Messages or notifications, enter it, and verify the resulting screen. Confirm a purchase only when the user's task explicitly requests that purchase. In that case, set `button` to the visible purchase button text. Otherwise dismiss the prompt or continue the task without purchasing.

## When something goes wrong

Diagnose with Poki MCP tools before asking the user to act or opening a GitHub issue. Follow [references/troubleshooting.md](references/troubleshooting.md) (or `skills/poki-mcp/references/troubleshooting.md` in the Poki checkout) for exact error strings, log commands, redaction rules, and GitHub issue templates.

### 1. Read state first

Run the read-only checks for the active MCP server before retrying failed actions:

- **Mac `poki-mcp` server.** Call `poki_mcp_status` for the server version, commit, `native_build`, connected `devices` count, `selected` device, `approval_mode`, and any `update` notice. Call `list_devices` to inspect attached USB, `RemotePairing`, or Simulator targets, their `readiness`, `occupied` lease state, or any `blocked` message and `action`. Call `get_device_info` for `model`, `osVersion`, and `mirror_status`, and call `observe_device` for the current screenshot, `foreground` app, elements, and `prompt` check. On USB or Simulator, call `list_crashes` and `get_crash` (`process` or `path`) when an app or runner quit unexpectedly. Tools outside default `tools/list` (`get_device_info`, `observe_device`, `list_crashes`, `get_crash`, `reconnect_device`, `disconnect_device`) still accept direct `tools/call` requests.
- **Poki iPhone app MCP connector.** Call `status` to read the `runner` line (`running`, `starting`, or `failed` with its phone fix), the `relay` state, pending `approval`, and `handoff`. Then call `look` to read the foreground app, visible elements, or `screen: locked`.

Done when you have the server or app version, iPhone model and iOS version, connection or runner state, and exact error text.

### 2. Classify and fix what you can

Match the observed error or status to a failure class:

| Failure class | How to tell | What you fix yourself | When you cannot fix it |
| --- | --- | --- | --- |
| **Disk image missing or outdated** | Mac `poki-mcp` reads screens yet fails taps or typing with `display_service_missing` (`no display service: ServiceNotFound`). The iPhone app reports `"Disk Image Outdated"` (`ddi_refused`), `"Update the Disk Image"`, `"Fetching Disk Image"` (`ddi_bad`), `"No Internet"` (`ddi_timeout`), or `developer_framework_unavailable`. Setup Wizard can still show all 5 steps done and Developer Disk Image `"Ready"`, because `"Ready"` checks downloaded files while mounting and `XCTest` loading happen only when Automation starts. | On a Mac checkout with the trusted, unlocked iPhone on USB, run `node bin/prepare-device.mjs <UDID>`, or run `poki-setup ddi --udid <UDID>` when Poki Setup is installed. Wait and re-check `status` if `ddi_bad` is redownloading. | If `prepare-device.mjs` reports `STATUS=94`, Xcode is too old for the phone's iOS and the user must update Xcode first. After a phone restart on cellular, the user must join Wi-Fi once so Poki can mount the disk image. Draft an issue if Poki is up to date on a supported iOS, Setup or `prepare-device.mjs` ran, and tasks still fail with `"Disk Image Outdated"` or `developer_framework_unavailable`. |
| **Runner stopped or Automation turns off** | Settings shows `Disconnected`, `"Runner stopped"`, `"The runner stopped"`, `"Poki is off"`, or `"Automation did not start"`. `status` reports `runner: starting` or `runner: failed`. All 5 Setup steps can show green while **Settings > Connection > Automation** snaps back to off with `no automation since this iPhone restarted` in the log. | If `status` says `starting again after being idle` or `opening the in-process session`, wait 3 to 5 seconds and call `status` or `look` again. On Mac `poki-mcp`, if `"The service is running old code"` or a token error appears after an update, restart `npm start` with the same `POKI_MCP_STATE_DIR`. Check `list_crashes` and `get_crash` for recent crashes. | After an iPhone restart or 8 idle hours, iOS requires the device passcode on screen. Full-screen **Settings** can hide `"Enter Your Passcode Next"`. Ask the user to close **Settings** and tap **Continue** on Poki's main screen, or toggle **Automation** off and on and enter the passcode, and confirm iOS **Developer Mode** and **Enable UI Automation** are on. Draft an issue if no passcode prompt appears on the main screen after reopening Poki, or the runner stays stopped. |
| **Disconnected, loopback off, or pairing failed** | `list_devices` reports `blocked` or the `usbmuxd` `notice`, Mac `poki-mcp` reports `Remote pairing is unreachable`, Relay returns HTTP `503` (`"The phone is offline"`), or the iPhone shows `Disconnected`, `"Loopback Off"`, `"Tunnel On, No Answer"`, `"Pairing Refused"`, or `"Loopback or Pairing"`. | On Mac `poki-mcp` with `RemotePairing`, call `reconnect_device`. To return a `remote-devices.json` iPhone to USB, call `disconnect_device`, remove that device entry from `remote-devices.json`, and restart `npm start`. Plugging in USB alone does not override `remote-devices.json`. | Ask the user to connect a USB data cable, unlock, and tap **Trust This Computer**. On the phone, ask them to turn on `10.7.0.1` loopback in LocalDevVPN or their proxy app on Wi-Fi, open Poki when Relay returns `503`, grant **Local Network** permission if macOS 15+ or iOS blocks local discovery, or re-pair in **Setup > Pair This iPhone**. Draft an issue if pairing or `usbmuxd` still fails once those checks pass. |
| **Locked screen, Poki in front, or blocked input** | `observe_device` reports `prompt.warning.kind: "passcode"`, `look` or `do` reports `screen: locked`, `screen: dark`, `poki: Poki is in front`, `paste_permission`, `approval_required`, or `handoff`, or `fill` refuses field confirmation. | When `Poki is in front`, call `launch_app` (or `do {"launch": "<bundle_id>"}`) or `press_button` with `button: "home"`. On `paste_permission`, answer with `handle_alert` and verify the field, or type with keys. On `fill` refusal, inspect `screen` and retry only `remaining_steps`. | Ask the user to unlock a locked phone (unless Poki Agent's local `unlock_device` is already configured on supported hardware) or answer pending `approval_required` and `handoff` prompts on the phone. |
| **Signing expiry, stalled update, or installer error** | Poki warns `"Poki's signing ends soon"`, stops opening after 7 days on a free Apple Account, stays on `"Finishing the update"`, or `node bin/install-iphone.mjs` exits with an error such as `bridge_start_failed` (including `spawn Unknown system error -86` on an Intel Mac with an arm64-only build) or `apple_account_limit`. | If an in-app update stays on `"Finishing the update"`, ask the user to swipe Poki away in the app switcher, reopen it, and check **Poki Version** (never delete Poki, which deletes its conversations). For computer-assisted updates, follow [install-poki](../install-poki/SKILL.md) (`--update-only --json`). On installer failure, run `node bin/install-iphone.mjs diagnose`. | Do not replace certificates or force `--reinstall` without user approval. Draft an issue when `diagnose` shows an unsupported host binary, a reproducible installer error, or an update failure that `--update-only` cannot safely resolve. |

Done when the task succeeds on a fresh screen read, or when you have confirmed the failure requires user action or a GitHub issue.

### 3. Draft a GitHub issue when you cannot fix it

When recovery fails and the cause is not an unfinished user prompt:

1. Search existing issues with `gh issue list --repo JosssphZhou/poki --state all --search "<keywords>"`. If an issue already covers the problem, draft a comment with your new evidence instead of opening a duplicate.
2. Gather the Poki MCP or Poki app version and commit or numeric build, Poki Setup or installer version, host OS and CPU architecture, iPhone model and iOS version, diagnostic tool outputs, Setup Wizard step states, and a concise log excerpt around the failure (`get_crash`, daemon log, `node bin/install-iphone.mjs diagnose`, or the iPhone log from **Settings > Advanced > Log > More > Copy Log** or `node bin/install-iphone.mjs records`). Separate what you observed from what you inferred.
3. Strip all secrets and personal data before showing or saving the draft. Remove passcodes, `mcp.json` tokens, relay URLs and capability secrets, pairing files (`pairing.plist`, `.rppairing.plist`), Apple Account emails and codes, Team IDs, API keys, device UDIDs, phone and computer names, phone numbers, IP addresses, and private chat or screen contents.
4. Format the body with the exact English `### <label>` headings and verbatim dropdown options from the matching `.github/ISSUE_TEMPLATE` form in [references/troubleshooting.md](references/troubleshooting.md) (`bug_report.yml`, `ios_app_bug.yml`, `install-failure.yml`, or `task_failure.yml`) so the repository check does not add `needs-template`. For installer failures, `node bin/install-iphone.mjs issue` writes a redacted draft file and prints the `gh issue create` command without submitting it.
5. Show the complete title and body draft to the user and ask for confirmation. Never submit an issue or comment on your own. Done when the user confirms and `gh issue create` (or `gh issue comment`) succeeds, or when the user chooses to keep the draft without posting.
