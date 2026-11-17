import Darwin
import Foundation
import XCTest
@testable import PokiSetup

@MainActor
final class AppModelTests: XCTestCase {
    func testRateLimitedAccountSkipsBackgroundRenewDueAndTeamRefresh() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poki-mac-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let logPath = dir.appendingPathComponent("commands.log").path
        let helperPath = dir.appendingPathComponent("fake-bridge.py").path
        let script = """
        #!/usr/bin/env python3
        import json, sys
        log_path = \(String(reflecting: logPath))
        sys.stdout.write(json.dumps({"event": "ready", "data": {"version": "0.2.4"}}) + "\\n")
        sys.stdout.flush()
        for raw in sys.stdin:
            raw = raw.strip()
            if not raw:
                continue
            req = json.loads(raw)
            cmd = req.get("cmd", "")
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(cmd + "\\n")
            if cmd == "account":
                res = {
                    "signed_in": True,
                    "apple_id": "person@example.com",
                    "name": "Test Person",
                    "team_id": "TEAM1234",
                    "password_kept": True,
                    "anisette": {"kind": "system"},
                    "pending_factor": None,
                    "rate_limited": True,
                    "rate_limited_until": 4102444800,
                }
            else:
                res = []
            sys.stdout.write(json.dumps({"id": req["id"], "ok": res}) + "\\n")
            sys.stdout.flush()
        """
        try script.write(toFile: helperPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperPath)

        setenv("POKI_SETUP_BRIDGE", helperPath, 1)
        defer { unsetenv("POKI_SETUP_BRIDGE") }

        let model = AppModel()
        await model.refreshAccount()
        await model.renewDue()

        let logged = (try? String(contentsOfFile: logPath, encoding: .utf8))?
            .split(separator: "\n")
            .map(String.init) ?? []
        XCTAssertTrue(logged.contains("account"), "expected account state query, got: \(logged)")
        XCTAssertFalse(logged.contains("teams"), "rate-limited account must not auto-load teams, got: \(logged)")
        XCTAssertFalse(logged.contains("renew_due"), "rate-limited account must not run renew_due, got: \(logged)")
    }
}
