// xpc-hello: open a raw socket to one named RemoteXPC service through CoreDevice's
// Create Service Socket capability, send only the empty RemoteXPC handshake
// (HTTP/2 preface + SETTINGS + WINDOW_UPDATE, root channel 1 and reply channel 3
// with empty XPC wrappers), then record every frame the service sends for a few
// seconds and close. No request is sent on either channel.
import CoreDevice
import Foundation

enum H2 {
  static func frame(_ type: UInt8, _ flags: UInt8, _ stream: UInt32, _ payload: [UInt8]) -> [UInt8] {
    let n = payload.count
    return [UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff), type, flags,
            UInt8(stream >> 24 & 0x7f), UInt8(stream >> 16 & 0xff), UInt8(stream >> 8 & 0xff), UInt8(stream & 0xff)] + payload
  }
  static func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
  static func le64(_ v: UInt64) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
  static func be32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.bigEndian, Array.init) }
  // XPC wrapper: magic 0x29b00b92, flags, body length, message id, then optional payload.
  static func wrapper(flags: UInt32, emptyDict: Bool) -> [UInt8] {
    var body: [UInt8] = []
    if emptyDict {
      body = le32(0x42133742) + le32(5) + le32(0xf000) + le32(4) + le32(0)
    }
    return le32(0x29b00b92) + le32(flags) + le64(UInt64(body.count)) + le64(0) + body
  }
}

func xpcHello(_ args: Args) async {
  guard let service = args.positional.first else { fail("usage: xpc-hello <service-name> --device <CoreDevice id>") }
  let d = await Device.find(args.flags["device"])
  do {
    let a = try await Device.assertion(d, "bgdisplay xpc-hello")
    defer { a.releaseAssertion() }
    let sock = try await d.getImplementation(for: .createServiceSocket)
    let fh = try await sock.fileHandle(toServiceNamed: service)
    log("socket to \(service): fd \(fh.fileDescriptor)")
    if args.flags["open-only"] != nil { try? fh.close(); log("open-only: closed without sending"); return }
    var out = Array("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    out += H2.frame(4, 0, 0, [0, 3] + H2.be32(100) + [0, 4] + H2.be32(1_048_576))   // SETTINGS
    out += H2.frame(8, 0, 0, H2.be32(983_041))                                        // WINDOW_UPDATE
    out += H2.frame(1, 4, 1, [])                                                      // HEADERS root channel
    out += H2.frame(0, 0, 1, H2.wrapper(flags: 0x1, emptyDict: true))                 // empty dict
    out += H2.frame(0, 0, 1, H2.wrapper(flags: 0x201, emptyDict: false))              // init handshake
    out += H2.frame(1, 4, 3, [])                                                      // HEADERS reply channel
    out += H2.frame(0, 0, 3, H2.wrapper(flags: 0x00400001, emptyDict: false))
    fh.write(Data(out))
    log("sent \(out.count) bytes of handshake")
    let fd = fh.fileDescriptor
    var flags = fcntl(fd, F_GETFL); flags |= O_NONBLOCK; _ = fcntl(fd, F_SETFL, flags)
    var got = Data()
    let deadline = Date().addingTimeInterval(4)
    var buf = [UInt8](repeating: 0, count: 65536)
    while Date() < deadline {
      let n = read(fd, &buf, buf.count)
      if n > 0 { got.append(buf, count: n) } else if n == 0 { log("peer closed"); break } else { usleep(50_000) }
    }
    log("received \(got.count) bytes")
    var i = 0
    let b = [UInt8](got)
    while i + 9 <= b.count {
      let len = Int(b[i]) << 16 | Int(b[i+1]) << 8 | Int(b[i+2])
      let type = b[i+3], fl = b[i+4]
      let sid = (UInt32(b[i+5]) & 0x7f) << 24 | UInt32(b[i+6]) << 16 | UInt32(b[i+7]) << 8 | UInt32(b[i+8])
      let end = min(b.count, i + 9 + len)
      let payload = Array(b[(i+9)..<end])
      var note = ""
      if type == 0, payload.count >= 24 {
        let magic = payload[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) }
        let wflags = payload[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
        let blen = payload[8..<16].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        note = String(format: " xpc magic=%08x flags=%08x body=%llu", magic, wflags, blen)
        let strs = String(decoding: payload.map { (32...126).contains($0) ? $0 : 46 }, as: UTF8.self)
        note += " ascii=\(strs.prefix(400))"
      }
      print("frame type=\(type) flags=\(fl) stream=\(sid) len=\(len)\(note)")
      i = end
    }
    try? fh.close()
    log("closed")
  } catch { print("xpc-hello error: \(errorText(error))") }
}
