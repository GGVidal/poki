import Foundation

// Experimental (issue #656): the background tool. It reads and operates an app that stays in the
// background while the owner keeps using the phone. It is listed only while the host's
// `Config.background` answers true, which only Poki Lab builds (POKI_EXPERIMENTS) ever set, behind
// an off-by-default switch. Steps the background route cannot do answer needs_front, and the model
// goes on with the normal look and do, which bring the app to the front.

extension PokiCore {
    public static let backgroundInstructions = "Experimental: background reads and operates an app without bringing it to the front, so the owner can keep using the phone. Start with background {op: \"look\", app} (it keeps the app running in the background and lists its elements by number). Then activate, back, custom (a named custom action such as a swipe action), set (a text field's value), scroll and escape act on those numbers. Each answer says done_in_background or needs_front. needs_front means that step only works with the app in front: do it with the normal do {app, actions}, which brings the app forward, and do not repeat the background step."

    static let backgroundTool: JSON = [
        "name": "background",
        "description": "Experimental. Operates an app kept in the background, without bringing it forward. op look lists the app's elements (numbered in tree order, type, label, value, frame, custom actions). op activate {ref} presses a button, toggle, cell or alert button by accessibility activate. op back goes back one screen. op custom {ref, name} runs a named custom action of the element (swipe actions, More Info). op set {ref, text} sets a text field's value (it does not submit). op scroll {ref, direction: down or up} scrolls by a page. op escape cancels an alert or action sheet. Every action answers done_in_background with the elements after it, or needs_front when the control only answers a touch (then use do with app, which brings the app to the front; never retry the same background step). Numbers come from the latest background answer for that app.",
        "inputSchema": ["type": "object", "properties": [
            "op": ["type": "string", "enum": ["look", "activate", "back", "custom", "set", "scroll", "escape"]],
            "app": ["type": "string", "description": "Bundle id or app name."],
            "ref": ["type": "integer"],
            "name": ["type": "string"],
            "text": ["type": "string"],
            "direction": ["type": "string", "enum": ["down", "up"]],
        ], "required": ["op", "app"], "additionalProperties": false],
    ]

    var isBackgroundEnabled: Bool { config.background?() == true }

    func backgroundCall(_ args: JSON) async -> ToolResult {
        guard isBackgroundEnabled else {
            return ToolResult(text: "background is not turned on; use look and do.", jpeg: nil, isError: true)
        }
        guard let op = args["op"]?.string, let app = args["app"]?.string, !app.isEmpty else {
            return ToolResult(text: "error: op and app are required; nothing was sent.", jpeg: nil, isError: true)
        }
        let bundle = config.resolveApp(app) ?? app
        var body: [String: JSON] = ["op": .string(op), "bundle": .string(bundle)]
        if let ref = args["ref"]?.double { body["ref"] = .number(ref) }
        for key in ["name", "text", "direction"] { if let v = args[key]?.string { body[key] = .string(v) } }
        if op != "look", op != "back", op != "escape", body["ref"] == nil {
            return ToolResult(text: "error: \(op) needs ref, a number from background look; nothing was sent.", jpeg: nil, isError: true)
        }
        if config.isPoki(Foreground(bundleID: bundle, name: nil)) {
            return ToolResult(text: "error: background does not act on Poki itself; nothing was sent.", jpeg: nil, isError: true)
        }
        // The approval rules apply as they do to do: a step they flag is never sent from here, it goes
        // through do, which asks the owner. A step on a number no background look listed is refused.
        if op != "look" {
            let target: Element?
            if let ref = body["ref"]?.int {
                guard let known = backgroundLooks.value[bundle]?[ref] else {
                    return ToolResult(text: "error: \(ref) is not in the latest background look of \(bundle); call background {op: \"look\"} first. Nothing was sent.", jpeg: nil, isError: true)
                }
                target = op == "custom" ? Element(type: known.type, label: body["name"]?.string, value: nil, identifier: nil, frame: known.frame, depth: 0) : known
            } else {
                target = nil
            }
            let app = Foreground(bundleID: bundle, name: nil)
            var why = config.sensitive.reason(touching: target, typing: op == "set", app: app, secureOnScreen: false)
            if op == "custom", why == nil, let known = body["ref"]?.int.flatMap({ backgroundLooks.value[bundle]?[$0] }) {
                why = config.sensitive.reason(touching: known, typing: false, app: app, secureOnScreen: false)
            }
            if let why {
                return ToolResult(text: "needs_front: \(op) is \(why), which needs the owner's approval. Nothing was sent. Do it with do {app: \"\(bundle)\", actions: [...]}, which asks the owner.", jpeg: nil, isError: false)
            }
        }
        // One phone call at a time, with look and do.
        guard await gate.enter(waiting: config.busyWait) else {
            return ToolResult(text: "busy: another call is still running (\(gate.current ?? "a tool")); nothing was sent. Call again in a moment.", jpeg: nil, isError: true)
        }
        gate.current = "background: \(op) in \(bundle)"
        defer { gate.current = nil; gate.leave() }
        let answer: JSON
        do {
            answer = try await computer.runner.raw("POST", "/poki/background", .object(body), timeout: 30, countsAsMiss: false)
        } catch {
            return ToolResult(text: "background: not answered (\(error)); what was sent is unknown. Use look and do with app \(bundle).", jpeg: nil, isError: true)
        }
        let value = answer["value"] ?? answer
        if let elements = value["elements"]?.array {
            var byRef: [Int: Element] = [:]
            for e in elements {
                guard let ref = e["ref"]?.int else { continue }
                let f = e["frame"]?.array?.compactMap(\.double) ?? []
                byRef[ref] = Element(type: e["type"]?.string ?? "Other", label: e["label"]?.string, value: e["value"]?.string, identifier: nil,
                                     frame: f.count == 4 ? Rect(x: f[0], y: f[1], width: f[2], height: f[3]) : Rect(x: 0, y: 0, width: 0, height: 0), depth: 0)
            }
            backgroundLooks.update { $0[bundle] = byRef }
        }
        return Self.backgroundText(op: op, bundle: bundle, answer: value)
    }

    /// The runner's answer as the model reads it.
    static func backgroundText(op: String, bundle: String, answer: JSON) -> ToolResult {
        if let error = answer["error"]?.string {
            return ToolResult(text: "background \(op): \(error) \(answer["message"]?.string ?? ""); use look and do with app \(bundle).", jpeg: nil, isError: true)
        }
        var lines: [String] = []
        if op == "look" {
            lines.append("background look: \(bundle) kept in the background (pid \(Int(answer["pid"]?.double ?? 0))).")
        } else if answer["needsFront"]?.bool == true {
            let why = answer["failure"]?.string.map { " (\($0))" } ?? ""
            lines.append("needs_front: \(op) did not take effect with \(bundle) in the background\(why). Do this step with do {app: \"\(bundle)\", actions: [...]}, which brings the app forward. Do not retry it in the background.")
            return ToolResult(text: lines.joined(separator: "\n"), jpeg: nil, isError: false)
        } else if let failure = answer["failure"]?.string {
            return ToolResult(text: "background \(op): not done (\(failure)); nothing changed. Use look and do with app \(bundle).", jpeg: nil, isError: true)
        } else {
            lines.append("done_in_background: \(op) ran with \(bundle) kept in the background.")
        }
        if let elements = answer["elements"]?.array {
            if elements.isEmpty { lines.append("no elements: the app has no window in the background yet; one do {app} brings it forward once, then background works.") }
            for e in elements {
                let ref = Int(e["ref"]?.double ?? -1)
                let type = e["type"]?.string ?? "?"
                var label = e["label"]?.string ?? ""
                if let value = e["value"]?.string, !value.isEmpty { label += " = \(value)" }
                let frame = e["frame"]?.array?.compactMap { $0.double.map { Int($0) } } ?? []
                var line = "[\(ref)] \(type) \"\(label)\""
                if !frame.isEmpty { line += " [\(frame.map(String.init).joined(separator: ","))]" }
                if e["selected"]?.bool == true { line += " selected" }
                if let actions = e["actions"]?.array?.compactMap(\.string), !actions.isEmpty { line += " actions: \(actions.joined(separator: ", "))" }
                lines.append(line)
            }
        }
        return ToolResult(text: lines.joined(separator: "\n"), jpeg: nil, isError: false)
    }
}
