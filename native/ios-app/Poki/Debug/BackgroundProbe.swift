#if POKI_EXPERIMENTS
import Foundation
import UIKit

// Poki Lab only (issue #656): `-pokiInProcess background -pokiProbeApp BUNDLE` runs PokiCore's
// background tool as an agent would, against the background fixture (AXFixture in
// experiments/background-ax-probe). The app is opened and moved one screen in with do, Settings is
// put in front, and every later step goes to the app while Settings stays in front. The last steps
// check that the front app never changed, then fall back to do for the control that needs a touch.
// Results go to Documents/inprocess-probe.json, one entry per step.
extension InProcessProbe {
    func backgroundCycle(model: AppModel, app bundle: String) async {
        guard begin("background tool through PokiCore") else { return }
        defer { end() }
        guard await prepare() else { return }
        model.inProcessReadyForProbe()
        UserDefaults.standard.set(true, forKey: BackgroundRoute.key)
        let task = UIApplication.shared.beginBackgroundTask(withName: "Background probe")
        defer { UIApplication.shared.endBackgroundTask(task) }
        func call(_ label: String, _ name: String, _ arguments: String) async -> String {
            let t = ProcessInfo.processInfo.systemUptime
            let result = await model.phoneTool(name, arguments: arguments)
            let head = result.text.split(separator: "\n").prefix(2).joined(separator: " | ")
            note("\(label): \(result.isError ? "failed" : "ok") \(head.prefix(240))",
                 ["step": "tool", "label": label, "tool": name, "error": result.isError, "seconds": ProcessInfo.processInfo.systemUptime - t, "text": String(result.text.prefix(6000))])
            return result.text
        }
        func front() async -> String {
            let info = await withCheckedContinuation { (c: CheckedContinuation<[String: Any], Never>) in queue.async { c.resume(returning: PKInProcess.shared().frontApp()) } }
            return info["bundleId"] as? String ?? "?"
        }
        /// The number of the first element whose line holds `text`, from a background answer.
        func ref(_ text: String, in answer: String) -> Int? {
            for line in answer.split(separator: "\n") where line.contains(text) {
                if line.hasPrefix("["), let close = line.firstIndex(of: "]"), let n = Int(line[line.index(after: line.startIndex)..<close]) { return n }
            }
            return nil
        }
        func lastEvent(_ answer: String) -> String {
            answer.split(separator: "\n").first { $0.contains("\"lastEvent") || $0.contains("lastEvent") }.map(String.init) ?? ""
        }

        _ = await call("look first", "look", "{}")
        _ = await call("open the app", "do", "{\"actions\":[{\"launch\":\"\(bundle)\"},{\"wait_until\":{\"text\":\"Push level 2\",\"ms\":5000}}]}")
        _ = await call("go one screen in", "do", "{\"actions\":[{\"scroll_to\":\"Push level 2\"}]}")
        _ = await call("tap Push level 2", "do", "{\"actions\":[{\"path\":{\"goal\":\"open level 2\",\"steps\":[{\"tap\":\"Push level 2\"}],\"expect\":[\"Activate push\"]}}]}")
        _ = await call("open Settings", "do", "{\"actions\":[{\"launch\":\"com.apple.Preferences\"},{\"wait\":1500}]}")
        let settled = await front()
        note("the app in front before the background steps: \(settled)", ["step": "front_before", "bundle": settled])

        var jumps = 0
        func check(_ label: String) async {
            let now = await front()
            if now != settled { jumps += 1 }
            note("\(label): front app \(now)", ["step": "front_check", "label": label, "bundle": now, "jumped": now != settled])
        }
        func bg(_ label: String, _ args: String) async -> String {
            let text = await call(label, "background", "{\"app\":\"BUNDLE\",ARGS}".replacingOccurrences(of: "BUNDLE", with: bundle).replacingOccurrences(of: "ARGS", with: args))
            await check("after \(label)")
            return text
        }
        func front(_ label: String, _ actions: String) async -> String {
            await call(label, "do", "{\"app\":\"BUNDLE\",\"actions\":ACTIONS}".replacingOccurrences(of: "BUNDLE", with: bundle).replacingOccurrences(of: "ACTIONS", with: actions))
        }
        func putSettingsInFront() async {
            _ = await call("Settings in front", "do", "{\"app\":false,\"actions\":[{\"launch\":\"com.apple.Preferences\"},{\"wait\":1500}]}")
        }
        func verdict(_ step: String, _ ok: Bool, _ text: String) { note("\(step): \(ok ? "PASS" : "FAIL")", ["step": "verify", "what": step, "pass": ok, "answer": String(text.prefix(400))]) }

        // 1. Back, from a screen reached in front.
        let look = await bg("background look", "\"op\":\"look\"")
        verdict("look reads Level 2 with Settings in front", look.contains("\"Level 2\"") && look.hasPrefix("background look"), look)
        let back = await bg("background back", "\"op\":\"back\"")
        verdict("back returns to Controls", back.hasPrefix("done_in_background") && back.contains("Plain button"), back)
        let controls = back.contains("Plain button") ? back : await bg("background look at Controls", "\"op\":\"look\"")
        // 2. Text, scroll, and a control that only takes a touch.
        if let field = ref("\"field", in: controls) ?? ref("Field", in: controls) {
            let set = await bg("background set the field", "\"op\":\"set\",\"ref\":\(field),\"text\":\"typed in the background\"")
            verdict("set text", set.hasPrefix("done_in_background") && set.contains("typed in the background"), set)
        } else { verdict("set text (no field found)", false, controls) }
        if let table = ref("bigTable", in: controls) {
            let scrolled = await bg("background scroll the table", "\"op\":\"scroll\",\"ref\":\(table),\"direction\":\"down\"")
            verdict("scroll moves the table", scrolled.hasPrefix("done_in_background"), scrolled)
        } else { verdict("scroll (no table found)", false, controls) }
        if let plain = ref("Plain button", in: controls) {
            let pressed = await bg("background activate Plain button", "\"op\":\"activate\",\"ref\":\(plain)")
            verdict("plain UIButton answers needs_front", pressed.hasPrefix("needs_front"), pressed)
        } else { verdict("plain button (not found)", false, controls) }
        let jumpsInBackground = jumps
        note("foreground jumps during background steps so far: \(jumps)", ["step": "jumps", "count": jumps])
        // 3. The fallback: do with app brings it forward and taps.
        let fallback = await front("fallback do taps Plain button", "[{\"path\":{\"goal\":\"press the plain button\",\"steps\":[{\"tap\":\"Plain button\"}],\"expect\":[\"button\"]}}]")
        verdict("fallback through do (foreground)", fallback.contains("end check passed"), fallback)
        // 4. An alert opened in front, answered from the background.
        _ = await front("open the alert in front", "[{\"path\":{\"goal\":\"show the alert\",\"steps\":[{\"tap\":\"Show alert\"}],\"expect\":[\"OK\"]}}]")
        await putSettingsInFront()
        let alertLook = await bg("background look at the alert", "\"op\":\"look\"")
        if let ok = ref("\"OK\"", in: alertLook) {
            let answered = await bg("background activate OK", "\"op\":\"activate\",\"ref\":\(ok)")
            verdict("alert button in the background", answered.hasPrefix("done_in_background") && answered.contains("alert.ok"), answered)
        } else { verdict("alert (no OK found)", false, alertLook) }
        // 5. A control with an accessibility action opens the next screen from the background.
        _ = await front("open Level 2 in front", "[{\"path\":{\"goal\":\"open level 2\",\"steps\":[{\"tap\":\"Push level 2\"}],\"expect\":[\"Activate push\"]}}]")
        await putSettingsInFront()
        let level2 = await bg("background look at Level 2", "\"op\":\"look\"")
        if let n = ref("Activate push", in: level2) {
            let pushed = await bg("background activate Activate push", "\"op\":\"activate\",\"ref\":\(n)")
            verdict("activate opens Level 3", pushed.hasPrefix("done_in_background") && pushed.contains("\"Level 3\""), pushed)
        } else { verdict("activate (no Activate push found)", false, level2) }
        note("foreground jumps during all background steps: \(jumps) (\(jumpsInBackground) before the fallback)", ["step": "jumps_total", "count": jumps])
        _ = await call("let go", "do", "{\"app\":false,\"actions\":[]}")
        UserDefaults.standard.removeObject(forKey: BackgroundRoute.key)
        note("background probe done", ["step": "done", "jumps": jumps])
    }
}
#endif

#if POKI_EXPERIMENTS
import SwiftUI

/// Poki Lab only: `-pokiShowExperiments 1` opens General › Testing Options' switches over the app at
/// launch, for screenshots of the experiment's switch without tapping through.
struct ExperimentsPreview: ViewModifier {
    @State private var shown = UserDefaults.standard.bool(forKey: "pokiShowExperiments")
    func body(content: Content) -> some View {
        content.sheet(isPresented: $shown) {
            NavigationStack { Form { SpeedTestingSection() }.navigationTitle("Testing Options") }
        }
    }
}
#endif
