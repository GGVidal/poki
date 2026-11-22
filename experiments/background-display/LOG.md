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
