# iPad workspace prototype (issue #689)

Experimental. Not for alpha, beta, pre-alpha or any release: the code is compiled only into the
Poki Lab build (`native/ios-app/project-lab.yml`, bundle id `nz.zheha.poki.lab`, flag
`POKI_EXPERIMENTS`). Poki's own projects never set that flag, and no workflow builds Poki Lab. This
branch is never merged into `main` or a release branch without the owner saying so.

## Pieces

| Piece | Where | State |
| --- | --- | --- |
| Link client: this Poki calls another Poki's tools over its connector URL | `native/ios/PokiCore/Sources/PokiCore/WorkspaceLink.swift`, tests in `WorkspaceLinkTests.swift` | Written. 9 unit tests pass on Linux (with stand-ins for PokiCore's types, since Approvals.swift does not type-check on Linux Swift 6.1). End to end against the real relay Worker (`wrangler dev --local`) and `test/phone-sim.mjs` as the other Poki: OAuth register, authorize with the owner's consent, token, initialize, two calls on one session, and a wrong secret refused. Still needs `swift test --package-path native/ios/PokiCore` on the Mac |
| iPhone chat tools `ipad_look` and `ipad_do`, declared only while a link is saved | `native/ios-app/Poki/Experiments/WorkspaceLink.swift`, hooks in `Harness.swift` and `ChatModel.swift` | Written, not yet compiled |
| Settings, iPad Workspace (paste the iPad's agent address, check, remove) | same file, row in `SettingsView.swift`, strings in `Shared/Localizable.xcstrings` | Written, not yet compiled |
| iPad workspace display mode in the driver (look and do on a display Poki owns, never the built-in one or a display the owner attached) | `Poki/Native/InProcess.m` and the iPad settings toggle | To do on the Mac, after the external display measurement |

## How the link works

1. On the iPad, Poki Lab with a relay set: Settings, Agents, Add Agent, Copy Address. That is an ordinary
   connector URL, `https://<relay>/v1/<label>/<secret>/mcp`.
2. On the iPhone, Poki Lab: Settings, iPad Workspace, Paste Address. The address is kept in the keychain.
3. The relay asks every agent for OAuth, so the link does too: it registers, asks to be authorized, and
   Poki on the iPad asks the owner once to allow "Poki on iPhone" (the relay waits up to 90 s). The grant
   is kept in the iPhone's keychain and refreshed.
4. The iPhone chat gets `ipad_look` and `ipad_do`, which call the iPad's `look` and `do` through the relay
   with the same arguments, and return the iPad's text and screenshot. The iPad's approval rules apply
   unchanged, and an action it holds for approval waits on the iPad.

Auth is the connector secret through the owner's relay, as for any agent. `http` is accepted only for a
relay on the local machine or network (`wrangler dev` for the simulator demo), never for a public host.

## Simulator demo (for the Mac session)

```sh
# 1. Local relay on the Mac (both simulators share the Mac's network)
npm ci --prefix deploy/cf-relay
npx --prefix deploy/cf-relay wrangler dev --local --port 8787 --config deploy/cf-relay/wrangler.toml

# 2. Poki Lab for the simulator
native/ios-app/scripts/make-assets.sh
xcodegen generate --spec native/ios-app/project-lab.yml
xcodebuild build -project native/ios-app/PokiLab.xcodeproj -scheme Poki -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim-lab CODE_SIGNING_ALLOWED=NO ARCHS=arm64

# 3. Install on an ipadws- iPad and an ipadws- iPhone simulator. On both, set the relay to
#    http://localhost:8787 (start wrangler with --var TOKEN_SECRET:<32+ random characters>). On the iPad, add an agent and copy its address. On the iPhone, paste it in
#    Settings, iPad Workspace, then Check Link. A Mac MCP client against the same address stands in
#    for the iPhone chat when no model key is set.
```

Screenshots and recordings go in this folder (large media not committed). `NOTES.md` here is the
morning status: what works, what was only shown on the simulator, and what needs a real iPad.
