# Background display experiment log

Times are America/New_York (ET). Classification tags: **[device]** observed on the
physical iPhone, **[local]** observed on the Mac only, **[binary]** derived from the
installed binaries, **[hyp]** hypothesis. Pairing material, ECID, serial number and
Secure Element ID are left out of every record.

## Gate 0: environment (2026-11-21 21:22-21:40 ET)

- **[local]** Mac: MacBook Pro Mac15,6 (Apple M3 Pro, 18 GB), arm64, macOS 27.0 (26A428).
- **[local]** Xcode 27.3 (27C5035i) at /Applications/Xcode.app/Contents/Developer; `devicectl --version` 699.2; CoreDevice.framework and CoreDeviceMediaStreamSupport.framework 699.2 under /Library/Developer/PrivateFrameworks.
- **[device]** iPhone 17 Pro (iPhone18,1), iOS 27.3 (24C5037i), physical, booted, Developer Mode enabled, paired (manualPairing), transport `localNetwork` (Wi-Fi), tunnel over TCP. Unlocked (`passcodeRequired: false`). DDI: iOS cryptex DDI build 27C5035i, `isUsable: true`.
- **[local]** Identifier namespaces for this phone: UDID `00008150-000829EA2183C01C`; CoreDevice identifier `147F2F12-B5DE-5CF9-AA3B-7CF5295476B5`.
- **[device]** Baseline display inventory (`devicectl device info displays`, records/displays-baseline.*): one display, `displayId: 1`, name `LCD`, primary, integrated, 1206x2622 px, pointScale 3.
- **[device]** Calculator: `com.apple.calculator`, version 12.0 (225), not running at baseline.
- **[local]** `devicectl device process launch --help` lists `--display <display>`: "The unique identifier of the display to launch the app on. Use 'devicectl device info displays' to list available displays and their unique identifiers. Not supported on all platforms." (records/help-process-launch.txt). `help device appResize|capture|info` print the top-level help instead of the subcommand help on this build.
- **[binary]** CoreDeviceMediaStreamSupport 699.2 exports `VideoStreamConfiguration.receiveVirtualExternal(layer:resolution:timeout:)`, `receiveVirtualSecondary(...)`, `receiveMirroredPrimary(layer:timeout:)`, `receiveMirroredDisplayByIdentifier(_:layer:timeout:)`, `MediaStreamSession(clientSessionID:)`, `makeVideoStream(withConfiguration:fromRemoteDevice:) async throws -> any VideoStream`, `MediaStreamProtocol.activate() async throws -> AsyncThrowingStream<Event, Error>`, `invalidate()`, `VideoStream.requestLastDecodedFrame()`. No .swiftinterface is installed; Stubs/ was written from the demangled exports and links (a wrong name was caught at link time: `makeVideoStream` is a direct, not dispatched, method).
- **[binary]** CoreDevice (CoreDeviceUtilities) 699.2: `DeviceMediaStream.Source` has cases `videoPrimaryDisplay`, `videoFromDisplayID(UInt32)`, `videoSecondaryVirtualDisplay(CGSize)`, `videoVirtualExternalDisplay(CGSize)`, `audioSystemOutput`, `audioSystemInput`. `DigitizerTarget` has `mainScreen`, `display1` ... `display10`, with `init(rawValue: UInt)`.
- **[device]** `bgdisplay probe` (records/probe-gate0.txt): option constants `CoreDeviceVideoDisplayMode` = `VirtualExternalDisplay` | `SecondaryVirtualDisplay` | `DisplayByID`, display key `VideoStreamForDisplayID`. Feature bit 64 = virtual external video. Device supported features 972 (includes "Virtual external video output stream" and "Video output stream by display ID"); this Mac's client features 140; common 140. `deviceCanReceive(virtualExternal)=false`, `canSend(virtualExternal)=true`. DigitizerTarget raw values: mainScreen 0, display1 1, display2 2, display3 3.

## Gate 1: primary stream through the native factory (21:37-21:43 ET)

- **[local]** First attempt with an async `main`: `activate()` never returned. Fix kept: main thread runs `RunLoop.main`, work runs in a Task. No change in outcome, so the run loop was not the cause.
- **[device]** `start-display --mode primary`: `makeVideoStream` returned `PrimaryVideoStreamReceiveAVC`. The phone started a session tagged with our client session `8A1490D3-EE45-4347-9453-D967E1F1C95F` (`server-status`: source "Primary video display", 1216x2624, HEVC, SRTP cipher 0, 60 fps). So the transport and the start request work.
- **[local]** `activate()` stays pending. Host log (`log show --predicate 'processID == <pid>'`): negotiator offer/answer succeed, `AVCVideoStream configure ... didSucceed=1`, `AVCVideoStream start`, then nothing. avconferenced logs, verbatim: `AVConferenceXPCServer [ERROR] ... API name=vcMediaStreamSetSessionConfig failed authorization check error=(null), entitlementStatus=2` followed by `VCXPCServer: XPC Error, Connection invalid`, and it releases our stream token 368205477 (records/avconferenced-authorization.txt). **Cause: Apple's in-process AVConference receive path needs an entitlement an ad-hoc Mac binary does not have.** The negotiation part does not need one.
- **[local]** Native log also shows the client offers only the common feature set: `Requesting negotiator offer with common supported features: ... (Raw Value: 140)`.
- **[device]** Cleanup: SIGTERM -> `invalidate()` -> `MediaStreamStop` reply success -> assertion released; `server-status` afterwards `running=false sessions=0`.
- Gate 1 status: **transport passes; host-side decode blocked by avconferenced authorization.** Frames not yet seen on the Mac. Planned workaround: keep CoreDevice/AVConference for negotiation only and read RTP/HEVC ourselves (the synk and Poki/idevice approach).

## Gate 2: virtual external display request (21:45-21:46 ET)

- **[device]** `start-display --mode external --size 1920x1080 --timeout 120`, client session `DD462596-9765-4FB4-A634-85D09B7B6B86`. `makeVideoStream` returned `VirtualExternalVideoStreamReceiveAVC`. Same avconferenced refusal at 21:45:10 for the host decoder.
- **[device]** Phone accepted the start in spite of common features 140. While the session ran, `devicectl device info displays` listed a new display (records/displays-during-virtual-external.json):
  `displayId: 3`, name `Wireless`, bounds 1920x1088, pointScale 1, `primary: false`, `type: wireless`, `uniqueId: 541A927E-FB33-4107-9FB9-61A4E7ACB1C5`, backlight off. Primary LCD unchanged (1206x2622).
- **[device]** `server-status` during the session (records/server-status-during-virtual-external.txt): `source: Virtual external display with size: (1920.0, 1080.0)`, streamConfig CustomWidth 1920, CustomHeight 1088, VideoStreamMode 4.
- **[binary+device] Observed native request options** (what Apple's factory sends, not a guess): `CoreDeviceVideoDisplayMode = "VirtualExternalDisplay"`, `VideoStreamDisplayWidth = 1920`, `VideoStreamDisplayHeight = 1080`, `avcMediaStreamOptionClientSessionID = <uuid>`, `AVCMediaStreamNegotiatorTransportProtocolType = 2`, `AVCMediaStreamNegotiatorAccessNetworkType = 1`. No top-level `source` field is sent; `source` only appears in the returned connection info.
- **[device]** After stop, display 3 is gone and `server-status` shows no sessions: the display's lifetime is tied to this session.
- Gate 2 status: **allocation observed on device.** Content of the surface not yet seen (needs our own decoder), so independence from a scaled mirror is not yet established.

## Gate 3: launch Calculator on the virtual display (21:45 ET, while display 3 existed)

- **[device]** `xcrun devicectl device process launch --device <UDID> --display 541A927E-FB33-4107-9FB9-61A4E7ACB1C5 com.apple.calculator` failed, verbatim:
  `The request to open "com.apple.calculator" failed. (FBSOpenApplicationServiceErrorDomain error 1) NSLocalizedFailureReason = The request was denied by service delegate (SBMainWorkspace) for reason: Security ("Can't look up displays without the proper entitlement, bub").`
- **[device]** Same refusal with `--display 3` (numeric id) and with `--display 1` (the primary LCD). So SpringBoard refuses any display-targeted open from the CoreDevice launch path, independent of our virtual display. Calculator was not launched by these attempts.
- Gate 3 status: **refused by SpringBoard authorization** (scene placement policy, not allocation).
