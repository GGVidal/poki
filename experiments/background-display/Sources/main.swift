// bgdisplay: host-side prototype that asks a paired iPhone for a virtual external
// display over CoreDevice, receives its video, and sends display-targeted touches.
//
// Private bindings live only in ../Stubs (CoreDevice, CoreDeviceMediaStreamSupport).
// Everything in this file that touches them is in the `Device` section below.

import CoreDevice
import CoreDeviceMediaStreamSupport
import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Small helpers

let isoFormatter: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.timeZone = TimeZone(identifier: "America/New_York")
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}()

func stamp() -> String { isoFormatter.string(from: Date()) }

func log(_ s: String) {
  FileHandle.standardError.write("[\(stamp())] \(s)\n".data(using: .utf8)!)
}

func fail(_ s: String) -> Never {
  log("error: \(s)")
  exit(1)
}

struct Args {
  var positional: [String] = []
  var flags: [String: String] = [:]
  init(_ raw: [String]) {
    var i = 0
    while i < raw.count {
      let a = raw[i]
      if a.hasPrefix("--") {
        let key = String(a.dropFirst(2))
        if i + 1 < raw.count, !raw[i + 1].hasPrefix("--") {
          flags[key] = raw[i + 1]; i += 2
        } else {
          flags[key] = "1"; i += 1
        }
      } else {
        positional.append(a); i += 1
      }
    }
  }
  func size(_ key: String, _ def: CGSize) -> CGSize {
    guard let v = flags[key] else { return def }
    let p = v.split(separator: "x").compactMap { Double($0) }
    guard p.count == 2 else { fail("--\(key) expects WxH, got \(v)") }
    return CGSize(width: p[0], height: p[1])
  }
}

func errorText(_ error: Error) -> String {
  let ns = error as NSError
  var parts = ["\(error)", "domain=\(ns.domain) code=\(ns.code)"]
  if !ns.localizedDescription.isEmpty { parts.append("desc=\(ns.localizedDescription)") }
  if let u = ns.userInfo[NSUnderlyingErrorKey] { parts.append("underlying=\(u)") }
  if let r = ns.localizedFailureReason { parts.append("reason=\(r)") }
  return parts.joined(separator: " | ")
}

func defaultStateDir() -> String {
  ProcessInfo.processInfo.environment["BGDISPLAY_STATE"]
    ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("bgdisplay")
}

// MARK: - Device (private CoreDevice bindings)

enum Device {
  static func find(_ wanted: String?) async -> RemoteDevice {
    let manager = DeviceManager(serviceConnection: CoreDeviceService.sharedConnection)
    await manager.awaitFullInitialization()
    let all = manager.devices
    if let wanted, let uuid = UUID(uuidString: wanted), let d = all[uuid] { return d }
    if let wanted { fail("no CoreDevice device with identifier \(wanted); known: \(all.keys.map(\.uuidString))") }
    guard all.count == 1, let only = all.values.first else {
      fail("pass --device <CoreDevice identifier>; known: \(all.keys.map(\.uuidString))")
    }
    return only
  }

  static func assertion(_ d: RemoteDevice, _ reason: String) async throws -> DeviceUsageAssertion {
    try await d.acquireDeviceUsageAssertion(
      withReason: reason,
      options: UsageAssertionOptions(requiredPreparedness: DevicePreparedness(rawValue: 0)))
  }

  static func target(_ name: String) -> DigitizerTarget {
    switch name {
    case "main", "mainScreen": return .mainScreen
    case "display1": return .display1
    case "display2": return .display2
    case "display3": return .display3
    default:
      if let n = UInt(name), let t = DigitizerTarget(rawValue: n) { return t }
      fail("unknown digitizer target \(name)")
    }
  }
}

// MARK: - probe

func probe(_ args: Args) async {
  let d = await Device.find(args.flags["device"])
  print("coredevice_identifier=\(d.deviceIdentifier.uuidString)")
  print("constants: displayModeKey=\(DeviceMediaStream.kVideoStreamDisplayMode) virtualExternal=\(DeviceMediaStream.kVideoStreamDisplayModeVirtualExternal) secondaryVirtual=\(DeviceMediaStream.kVideoStreamDisplayModeSecondaryVirtual) byDisplayID=\(DeviceMediaStream.kVideoStreamDisplayModeByDisplayID) displayIDKey=\(DeviceMediaStream.kVideoStreamForDisplayID)")
  print("feature bits: virtualExternalDisplayOutput=\(MediaStreamSupportedFeatures.virtualExternalDisplayOutput.rawValue) mediaStreamVirtualExternalVideo=\(MediaStreamSupportedFeatures.mediaStreamVirtualExternalVideo.rawValue) secondaryVirtualDisplayOutput=\(MediaStreamSupportedFeatures.secondaryVirtualDisplayOutput.rawValue) mediaStreamSecondaryVirtualVideo=\(MediaStreamSupportedFeatures.mediaStreamSecondaryVirtualVideo.rawValue) hostCurrent=\(MediaStreamSupportedFeatures.current.rawValue)")
  for (name, t) in [("mainScreen", DigitizerTarget.mainScreen), ("display1", .display1), ("display2", .display2), ("display3", .display3)] {
    print("digitizer target \(name) rawValue=\(t.rawValue)")
  }
  do {
    let a = try await Device.assertion(d, "bgdisplay probe")
    defer { a.releaseAssertion() }
    print("usage_assertion=ok")
    let info = try await d.mediaStreamSupportInfo
    print("support.device=\(info.device.supportedFeatures) [\(info.device.supportedFeaturesDescription)]")
    print("support.client=\(info.client.supportedFeatures) [\(info.client.supportedFeaturesDescription)]")
    print("support.common=\(info.common.supportedFeatures) [\(info.common.supportedFeaturesDescription)]")
    let support = MediaStreamSupport(device: d)
    for (name, f) in [("virtualExternalDisplayOutput", MediaStreamSupportedFeatures.virtualExternalDisplayOutput),
                      ("mediaStreamVirtualExternalVideo", .mediaStreamVirtualExternalVideo)] {
      do { print("deviceCanReceive(\(name))=\(try await support.deviceCanReceive(f))") }
      catch { print("deviceCanReceive(\(name)) error: \(errorText(error))") }
      do { print("canSend(\(name))=\(try await support.canSend(f))") }
      catch { print("canSend(\(name)) error: \(errorText(error))") }
    }
  } catch {
    print("probe error: \(errorText(error))")
  }
}

// MARK: - server-status (read-only)

func serverStatus(_ args: Args) async {
  let d = await Device.find(args.flags["device"])
  do {
    let a = try await Device.assertion(d, "bgdisplay server-status")
    defer { a.releaseAssertion() }
    let st = try await d.mediaStreamServerStatus
    print("running=\(st.running) runDurationSeconds=\(st.runDurationSeconds) sessions=\(st.sessions?.count ?? 0)")
    var out = ""
    dump(st, to: &out, maxDepth: 12)
    print(out)
  } catch { print("server-status error: \(errorText(error))") }
}

// MARK: - start-display (the daemon that owns the stream)

final class FrameWaiter: @unchecked Sendable {
  private let lock = NSLock()
  private var waiters: [CheckedContinuation<Data, Never>] = []
  private(set) var frameCount = 0
  private(set) var lastAttributes = "none"
  private(set) var firstFrameAt: String?
  func add(_ c: CheckedContinuation<Data, Never>) { lock.lock(); waiters.append(c); lock.unlock() }
  func deliver(_ d: Data) {
    lock.lock(); let w = waiters; waiters = []; frameCount += 1; lock.unlock()
    for c in w { c.resume(returning: d) }
  }
  func setAttributes(_ s: String) { lock.lock(); lastAttributes = s; lock.unlock() }
  func setFirstFrame() { lock.lock(); firstFrameAt = firstFrameAt ?? stamp(); lock.unlock() }
}

final class Daemon: @unchecked Sendable {
  let device: RemoteDevice
  let mode: String
  let size: CGSize
  let stateDir: String
  let sessionID = UUID()
  let layer = CALayer()
  let frames = FrameWaiter()
  var assertion: DeviceUsageAssertion?
  var stream: (any VideoStream)?
  var digitizer: (any HIDDigitizer)?
  var eventsTask: Task<Void, Never>?
  var streamEnded: String?
  let startedAt = stamp()

  init(device: RemoteDevice, mode: String, size: CGSize, stateDir: String) {
    self.device = device; self.mode = mode; self.size = size; self.stateDir = stateDir
  }

  func start(timeout: UInt) async throws {
    assertion = try await Device.assertion(device, "bgdisplay virtual display prototype")
    log("usage assertion \(assertion!.identifier)")
    layer.frame = CGRect(origin: .zero, size: size)
    let config: VideoStreamConfiguration
    switch mode {
    case "external": config = .receiveVirtualExternal(layer: layer, resolution: size, timeout: timeout)
    case "secondary": config = .receiveVirtualSecondary(layer: layer, resolution: size, timeout: timeout)
    case "primary": config = .receiveMirroredPrimary(layer: layer, timeout: timeout)
    default:
      if mode.hasPrefix("display:"), let id = UInt32(mode.dropFirst(8)) {
        config = .receiveMirroredDisplayByIdentifier(id, layer: layer, timeout: timeout)
      } else { fail("unknown --mode \(mode)") }
    }
    let session = MediaStreamSession(clientSessionID: sessionID)
    log("client session \(sessionID.uuidString) mode=\(mode) requested=\(Int(size.width))x\(Int(size.height)) timeout=\(timeout)s")
    let s = try await session.makeVideoStream(withConfiguration: config, fromRemoteDevice: device)
    log("makeVideoStream returned \(type(of: s))")
    stream = s
    // activate() starts the phone-side session, then waits on the host decoder. On an
    // ad-hoc host avconferenced refuses that decoder (LOG.md, Gate 1), so activate()
    // never returns; the phone-side session and display still exist. Run it detached.
    Task { [weak self] in
      do { try await self?.activate(s) } catch {
        self?.streamEnded = "activate error at \(stamp()): \(errorText(error))"
        log("activate error: \(errorText(error))")
      }
    }
  }

  private func activate<S: VideoStream>(_ s: S) async throws {
    log("calling activate()")
    let events = try await s.activate()
    log("activate() returned; consuming events")
    eventsTask = Task { [frames, weak self] in
      do {
        for try await e in events {
          guard let ve = e as? VideoStreamEvent else { log("event (non-video) \(e)"); continue }
          switch ve {
          case .receivedFirstFrame:
            frames.setFirstFrame(); log("event receivedFirstFrame")
          case .remoteVideoAttributesChanged(let a):
            let t = "ratio=\(a.ratio) contentsRect=\(a.contentsRect) scale=\(a.scaleFactor)"
            frames.setAttributes(t); log("event remoteVideoAttributesChanged \(t)")
          case .receivedLastDecodedFrame(let d):
            frames.deliver(d)
          @unknown default:
            log("event unknown \(ve)")
          }
        }
        self?.streamEnded = "stream finished at \(stamp())"
        log("event stream finished")
      } catch {
        self?.streamEnded = "stream error at \(stamp()): \(errorText(error))"
        log("event stream error: \(errorText(error))")
      }
    }
  }

  func capture(to path: String, timeout: Double = 5) async -> String {
    guard let s = stream else { return "error no stream" }
    let data: Data? = await withTaskGroup(of: Data?.self) { g in
      g.addTask { [frames] in
        await withCheckedContinuation { c in
          frames.add(c)
          Task { await s.requestLastDecodedFrame() }
        }
      }
      g.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9)); return nil }
      let first = await g.next() ?? nil
      g.cancelAll()
      return first
    }
    guard let data else { return "error no frame within \(timeout)s" }
    let (png, w, h) = toPNG(data)
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return "error write: \(error)" }
    return "ok \(path) \(w)x\(h) bytes=\(data.count) raw_magic=\(data.prefix(4).map { String(format: "%02x", $0) }.joined())"
  }

  func ensureDigitizer() async throws -> any HIDDigitizer {
    if let d = digitizer { return d }
    let d = try await device.getImplementation(for: .hid.digitizer)
    digitizer = d
    return d
  }

  // x, y are normalized 0...1 in the target display's own coordinate space.
  func tap(x: Double, y: Double, target: DigitizerTarget, holdMs: UInt64 = 80) async -> String {
    do {
      let dig = try await ensureDigitizer()
      let p = DigitizerPoint(x: x, y: y)
      try dig.send(pointOne: p, pointTwo: nil, eventType: .start, edge: .none, target: target)
      dig.sendBarrier()
      try await Task.sleep(nanoseconds: holdMs * 1_000_000)
      try dig.send(pointOne: p, pointTwo: nil, eventType: .end, edge: .none, target: target)
      dig.sendBarrier()
      return "ok tap \(x),\(y) target=\(target) raw=\(target.rawValue)"
    } catch { return "error \(errorText(error))" }
  }

  func swipe(_ a: (Double, Double), _ b: (Double, Double), target: DigitizerTarget, edge: DigitizerEdge, steps: Int = 12) async -> String {
    do {
      let dig = try await ensureDigitizer()
      try dig.send(pointOne: DigitizerPoint(x: a.0, y: a.1), pointTwo: nil, eventType: .start, edge: edge, target: target)
      dig.sendBarrier()
      for i in 1...steps {
        let t = Double(i) / Double(steps)
        try await Task.sleep(nanoseconds: 16_000_000)
        try dig.send(pointOne: DigitizerPoint(x: a.0 + (b.0 - a.0) * t, y: a.1 + (b.1 - a.1) * t), pointTwo: nil, eventType: .position, edge: edge, target: target)
        dig.sendBarrier()
      }
      try dig.send(pointOne: DigitizerPoint(x: b.0, y: b.1), pointTwo: nil, eventType: .end, edge: edge, target: target)
      dig.sendBarrier()
      return "ok swipe \(a)->\(b) target=\(target) raw=\(target.rawValue) edge=\(edge)"
    } catch { return "error \(errorText(error))" }
  }

  func status() -> String {
    var d: [String: Any] = [
      "pid": getpid(), "mode": mode, "requested": "\(Int(size.width))x\(Int(size.height))",
      "clientSessionID": sessionID.uuidString, "coreDeviceIdentifier": device.deviceIdentifier.uuidString,
      "assertion": assertion?.identifier.uuidString ?? "none", "startedAt": startedAt,
      "frames": frames.frameCount, "firstFrameAt": frames.firstFrameAt ?? "none",
      "attributes": frames.lastAttributes, "streamEnded": streamEnded ?? "no",
    ]
    d["digitizer"] = digitizer == nil ? "not acquired" : "acquired"
    let j = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
    return String(data: j, encoding: .utf8)!
  }

  func stop() async {
    log("stopping: invalidate stream, release assertion")
    if let s = stream { await s.invalidate() }
    eventsTask?.cancel()
    assertion?.releaseAssertion()
    log("stopped session \(sessionID.uuidString)")
  }
}

func toPNG(_ data: Data) -> (Data, Int, Int) {
  guard let src = CGImageSourceCreateWithData(data as CFData, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return (data, 0, 0) }
  let out = NSMutableData()
  let dst = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dst, img, nil)
  CGImageDestinationFinalize(dst)
  return (out as Data, img.width, img.height)
}

// MARK: - devicectl helpers (public tool; used for display identity, capture and launch)

func devicectl(_ args: [String]) -> (Int32, String) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  p.arguments = ["devicectl"] + args
  let pipe = Pipe()
  p.standardOutput = pipe; p.standardError = pipe
  do { try p.run() } catch { return (-1, "\(error)") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// The secondary display(s) as devicectl reports them: (numeric displayId, uniqueId, name, WxH).
func secondaryDisplays(udid: String) -> [(Int, String, String, String)] {
  let tmp = NSTemporaryDirectory() + "bgdisplay-displays-\(getpid()).json"
  _ = devicectl(["device", "info", "displays", "--device", udid, "--json-output", tmp])
  defer { try? FileManager.default.removeItem(atPath: tmp) }
  guard let data = FileManager.default.contents(atPath: tmp),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let result = root["result"] as? [String: Any],
        let displays = result["displays"] as? [[String: Any]] else { return [] }
  return displays.compactMap { d in
    guard (d["primary"] as? Bool) != true, let uid = d["uniqueId"] as? String else { return nil }
    var size = "?"
    if let b = d["bounds"] as? [[Double]], b.count == 2 { size = "\(Int(b[1][0]))x\(Int(b[1][1]))" }
    return ((d["displayId"] as? Int) ?? -1, uid, (d["name"] as? String) ?? "?", size)
  }
}

func requireUDID(_ args: Args) -> String {
  guard let u = args.flags["udid"] ?? ProcessInfo.processInfo.environment["BGDISPLAY_UDID"] else {
    fail("pass --udid <phone UDID> (devicectl namespace), or set BGDISPLAY_UDID")
  }
  return u
}

// MARK: - Control socket (one line in, one line out)

// sun_path holds 104 bytes; scratch paths are longer, so bind and connect relative to the
// state directory (the process changes into it first).
func socketPath(_ dir: String) -> String {
  FileManager.default.changeCurrentDirectoryPath(dir)
  return "ctl.sock"
}

func withSockaddr<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8)
  precondition(bytes.count < MemoryLayout.size(ofValue: addr.sun_path), "socket path too long")
  withUnsafeMutableBytes(of: &addr.sun_path) { raw in
    for (i, b) in bytes.enumerated() { raw[i] = b }
    raw[bytes.count] = 0
  }
  return withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
  }
}

func readLine(fd: Int32) -> String {
  var buf = [UInt8](repeating: 0, count: 4096)
  var out = Data()
  while true {
    let n = read(fd, &buf, buf.count)
    if n <= 0 { break }
    out.append(buf, count: n)
    if out.contains(0x0a) { break }
  }
  return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func serve(_ daemon: Daemon) {
  let path = socketPath(daemon.stateDir)
  unlink(path)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard withSockaddr(path, { bind(fd, $0, $1) }) == 0, listen(fd, 8) == 0 else { fail("bind \(path): \(errno)") }
  log("control socket \(path)")
  Thread.detachNewThread {
    while true {
      let c = accept(fd, nil, nil)
      if c < 0 { continue }
      let line = readLine(fd: c)
      let sem = DispatchSemaphore(value: 0)
      var reply = ""
      Task {
        reply = await handle(line, daemon)
        sem.signal()
      }
      sem.wait()
      _ = (reply + "\n").withCString { write(c, $0, strlen($0)) }
      close(c)
      if line == "stop" {
        unlink(path)
        log("exit after stop")
        exit(0)
      }
    }
  }
}

func handle(_ line: String, _ d: Daemon) async -> String {
  let p = line.split(separator: " ").map(String.init)
  log("ctl: \(line)")
  switch p.first {
  case "status": return d.status()
  case "capture":
    guard p.count >= 2 else { return "error usage: capture <path>" }
    return await d.capture(to: p[1])
  case "tap":
    guard p.count >= 4, let x = Double(p[1]), let y = Double(p[2]) else { return "error usage: tap x y target" }
    return await d.tap(x: x, y: y, target: Device.target(p[3]))
  case "swipe":
    guard p.count >= 7, let x1 = Double(p[1]), let y1 = Double(p[2]), let x2 = Double(p[3]), let y2 = Double(p[4]) else { return "error usage: swipe x1 y1 x2 y2 target edge" }
    let edge: DigitizerEdge = ["none": .none, "top": .top, "bottom": .bottom, "left": .left, "right": .right][p[6]] ?? .none
    return await d.swipe((x1, y1), (x2, y2), target: Device.target(p[5]), edge: edge)
  case "stop":
    await d.stop()
    return "ok stopped \(d.sessionID.uuidString)"
  default: return "error unknown command"
  }
}

func client(_ line: String, stateDir: String) {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard withSockaddr(socketPath(stateDir), { connect(fd, $0, $1) }) == 0 else {
    fail("no running display (connect \(socketPath(stateDir)) errno \(errno))")
  }
  _ = (line + "\n").withCString { write(fd, $0, strlen($0)) }
  let reply = readLine(fd: fd)
  print(reply)
  close(fd)
  if reply.hasPrefix("error") { exit(2) }
}

// MARK: - Entry

@main
struct Main {
  static func main() {
    // AVConference and CoreDevice deliver some callbacks through the main run loop,
    // so the main thread runs CFRunLoop instead of an async main.
    Task { await run(); exit(0) }
    while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
  }

  static func run() async {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard let cmd = raw.first else {
      print("usage: bgdisplay probe|server-status|start-display|displays|launch-on-display|capture|act|status|stop [flags]  (see README.md)")
      exit(64)
    }
    let args = Args(Array(raw.dropFirst()))
    let stateDir = args.flags["state"] ?? defaultStateDir()
    switch cmd {
    case "probe":
      await probe(args)
    case "server-status":
      await serverStatus(args)
    case "xpc-hello":
      await xpcHello(args)
    case "start-display":
      try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
      let dev = await Device.find(args.flags["device"])
      let daemon = Daemon(device: dev, mode: args.flags["mode"] ?? "external",
                          size: args.size("size", CGSize(width: 1280, height: 720)), stateDir: stateDir)
      for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        src.setEventHandler { Task { await daemon.stop(); unlink(socketPath(stateDir)); exit(0) } }
        src.resume()
        signals.append(src)
      }
      do {
        try await daemon.start(timeout: UInt(args.flags["timeout"] ?? "1800") ?? 1800)
      } catch {
        log("start failed: \(errorText(error))")
        await daemon.stop()
        exit(3)
      }
      serve(daemon)
      print("ready \(daemon.status())")
      fflush(stdout)
      while true { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
    case "displays":
      for (id, uid, name, size) in secondaryDisplays(udid: requireUDID(args)) { print("displayId=\(id) uniqueId=\(uid) name=\(name) size=\(size)") }
    case "capture":
      // The host-side AVConference decoder is refused on an ad-hoc host (LOG.md, Gate 1), so
      // capture uses devicectl's per-display screenshot of the virtual display.
      guard let path = args.positional.first else { fail("usage: capture <out.png> --udid <UDID> [--display <uniqueId>]") }
      let udid = requireUDID(args)
      guard let uid = args.flags["display"] ?? secondaryDisplays(udid: udid).first?.1 else { fail("no secondary display; run start-display first") }
      let (rc, out) = devicectl(["device", "capture", "screenshot", "--device", udid, "--destination", path, "--display-unique-id", uid])
      print(out.split(separator: "\n").suffix(3).joined(separator: "\n"))
      exit(rc == 0 ? 0 : 2)
    case "launch-on-display":
      // launch-on-display <bundle-id> --udid <UDID> [--display <uniqueId>]; never --terminate-existing.
      guard let bundle = args.positional.first else { fail("usage: launch-on-display <bundle-id> --udid <UDID> [--display <uniqueId>]") }
      let udid = requireUDID(args)
      guard let uid = args.flags["display"] ?? secondaryDisplays(udid: udid).first?.1 else { fail("no secondary display; run start-display first") }
      log("launch \(bundle) on display uniqueId \(uid)")
      let (rc, out) = devicectl(["device", "process", "launch", "--device", udid, "--display", uid, bundle])
      print(out)
      exit(rc == 0 ? 0 : 2)
    case "act":
      // act tap <x> <y> [--target display2]   |   act swipe <x1> <y1> <x2> <y2> [--target display2] [--edge bottom]
      let p = args.positional
      let target = args.flags["target"] ?? "display2"
      if p.count >= 3, p[0] == "tap" {
        client("tap \(p[1]) \(p[2]) \(target)", stateDir: stateDir)
      } else if p.count >= 5, p[0] == "swipe" {
        client("swipe \(p[1]) \(p[2]) \(p[3]) \(p[4]) \(target) \(args.flags["edge"] ?? "none")", stateDir: stateDir)
      } else { fail("usage: act tap x y | act swipe x1 y1 x2 y2 [--target main|display1|N] [--edge bottom]") }
    case "status":
      client("status", stateDir: stateDir)
    case "stop":
      client("stop", stateDir: stateDir)
    default:
      fail("unknown command \(cmd)")
    }
  }
}

nonisolated(unsafe) var signals: [DispatchSourceSignal] = []
