// Poki's chat harness shares its core execution rules and harness tools (report_plan, finish_task)
// with agent/task-runner.mjs and agent/prompts/pi-app.md, adapted to the app's in-process tools
// (look, do, routines, status) and sandbox browser tools (WebTools).
import Foundation
import PokiCore

/// One tool as the model sees it, before a provider puts it in its own form.
struct ToolSpec {
    var name: String
    var description: String
    var schema: [String: Any]
}

enum Harness {
    static let system: String = {
        guard let url = Bundle.main.url(forResource: "agent-system", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    static var instructions: String { [system, PokiCore.toolInstructions, WebTools.instructions].joined(separator: "\n\n") }

    static let splitViewInstructions = """
    You are Poki, the owner's personal assistant, completing their task across two visible iPhone Split View apps while Poki stays in the background. Keep replies brief and reply in the owner's language. Publish a short plan with report_plan before acting.
    Start with look on pane left or right, and confirm the app identity and screen before acting. Call a fresh look when switching panes or after any layout change; restore both windows with the owner's help if the pair cannot be confirmed. Keep actions within these two apps and leave both windows in place.
    For cross-pane drag, read the destination pane first, then select the source pane with look and send do with {drag: {from: ref or [x,y], to: [x,y], to_pane: left or right}} using destination-local coordinates. Read the destination again to verify arrival, including the image itself for photos, and report unconfirmed transfers rather than risking duplicates.
    Check the target field and content before typing, and verify the result in the same pane. Wait for the owner's decision on approvals, leave password manager apps unopened, stop on checkout or payment pages unless purchase was explicitly requested, and use handoff for passwords, verification, or owner-only prompts. Call finish_task after verifying the final result, setting success=false when unverified.
    """

    /// The instructions for a task: the above, then the saved notes and the routines that fit it.
    @MainActor static func instructions(for task: String, inSplitView: Bool = false) -> String {
        if inSplitView {
            if ApprovalClassifier.mode == .reply { return splitViewInstructions + "\n\n" + replyApprovals }
            return splitViewInstructions
        }
        let brief = PokiCore.memoryBrief(for: task)
        var parts = [instructions]
        parts.append("To continue or resume, match one unfinished task from this conversation or an explicitly selected saved task; if none or several match, ask which task before calling action tools. Treat long-term notes and saved routines strictly as preferences and reusable steps, never pending tasks.")
        // Matching routines sit in the brief below, so the first call can invoke the routine directly.
        // Poki is in front when a task starts, and finish_task brings Poki back when the task ends,
        // so saving a new routine happens in the same reply as finish_task.
        parts.append("Start an app task with do {run: name} when a routine below fits, else do {launch: bundle id}, sending report_plan with that first action and updating currentStep as you progress. When an iPhone bundle id is uncertain or launch reports it missing, go home ({button: \"home\"}), swipe down on the Home Screen to search, type the app's name and tap it; say the app is not installed only when that search finds nothing. After a new app task succeeds, call finish_task together with routines {action: \"save\", name, description} named as the owner would ask for it.")
        // A model decides approvals from what the owner said. A refused step goes through once the
        // owner says yes to it, so the agent asks in words and tries again.
        if ApprovalClassifier.mode == .reply {
            parts.append(replyApprovals)
        }
        if let apps = appIDs(for: task) { parts.append(apps) }
        if !brief.isEmpty { parts.append(brief) }
        return parts.joined(separator: "\n\n")
    }

    private static let replyApprovals = "Approvals in this chat come from the owner's messages. When a step is declined, ask in plain words whether to run that named step, and resend the identical step once confirmed."

    @MainActor private static func appIDs(for task: String) -> String? {
        let apps = AppIconStore.bundleIDs(namedIn: task).compactMap { KnownApps.byID[$0.lowercased()] }
        guard !apps.isEmpty else { return nil }
        let lines = apps.map { app -> String in
            let names = app.names.joined(separator: " / ")
            let others = app.otherIDs.isEmpty ? "" : " (another edition: \(app.otherIDs.joined(separator: ", ")))"
            return "- \(names): \(app.id)\(others)"
        }
        return "Use these iPhone bundle ids for apps named in this request:\n" + lines.joined(separator: "\n")
    }

    /// Poki's sandbox browser tools sit beside the phone tools.
    static let tools: [ToolSpec] = phoneTools + WebTools.specs + [reportPlan, finishTask]

    static let splitViewTools: [ToolSpec] = [
        ToolSpec(name: "look", description: "Read the app, numbered UI elements and screenshot of the left or right pane. Select a pane explicitly when you first read and whenever moving between apps. Points use the selected screenshot’s own coordinates.",
                 schema: object(["pane": ["type": "string", "enum": ["left", "right"]], "full": ["type": "boolean"]], [])),
        ToolSpec(name: "do", description: "Act in the selected pane, then read it. Actions include {tap: ref or [x,y]}, {type: text, ref?: number}, {key: return|delete|tab|space|escape}, {scroll_to: text}, {swipe: direction}, {back: true}, {wait_until: text}, {handoff: {kind, text}}, and {drag: {from: ref or [x,y], to: [x,y], to_pane: left or right}} for a continuous cross-pane drag. Read the destination first and the source second. The drop point uses destination-local coordinates. Read the destination after sending the drag. Do not switch apps or end Split View.",
                 schema: object(["actions": ["type": "array", "items": ["type": "object"], "minItems": 0, "maxItems": 20], "full": ["type": "boolean"]], ["actions"])),
    ] + phoneTools.filter { $0.name == "status" } + [reportPlan, finishTask]

    /// PokiCore's catalog: look, do and status.
    static let phoneTools: [ToolSpec] = {
        guard let data = PokiCore.toolCatalogJSON.data(using: .utf8), let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list.compactMap { tool in
            guard let name = tool["name"] as? String, let description = tool["description"] as? String, let schema = tool["inputSchema"] as? [String: Any] else { return nil }
            return ToolSpec(name: name, description: description, schema: schema)
        }
    }()

    private static func object(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    private static let string: [String: Any] = ["type": "string"]

    static let reportPlan = ToolSpec(
        name: "report_plan",
        description: "Publish a plan before actions. Update currentStep (1-based) on each step. title names the task in two to four words, as a heading in the user's language (\"Text Mom\", \"Order the usual\"), not the user's sentence; send it with the first plan. When the task sends a message to someone, to is that person as the user named them (\"Mom\"); leave it out otherwise.",
        schema: object(["steps": ["type": "array", "items": string, "minItems": 1, "maxItems": 8], "currentStep": ["type": "integer", "minimum": 1, "maximum": 8], "title": string, "to": string], ["steps", "currentStep"]))

    static let finishTask = ToolSpec(
        name: "finish_task",
        description: "Finish after the last observation verifies the requested result. If unable to complete, set success=false and explain what was completed, what blocked completion and what was tried. details must contain the requested facts, not only a page title; every value must match a whole current label or value. Declare answer.kind: action for a performed change, field for fixed values, list for requested entries. Read tasks must never use action. For field, items select current refs and label/value; when a field is combined into a label such as \"Capacity,90%\", use prefix \"Capacity,\" and suffix \"%\" to preserve the field identity while reading a new value. For list, items select all requested current rows in order with their names/times; start_ref and end_ref identify unique section labels immediately before and after those rows. Omit section refs if no reliable boundaries exist. Never invent refs or use a heading as a requested value.",
        schema: object([
            "success": ["type": "boolean"], "summary": string,
            "details": ["type": "array", "items": object(["label": string, "value": string], ["label", "value"])],
            "answer": object([
                "kind": ["type": "string", "enum": ["action", "field", "list"]],
                "items": ["type": "array", "items": object(["ref": string, "field": ["type": "string", "enum": ["label", "value"]], "prefix": string, "suffix": string], ["ref", "field"])],
                "start_ref": string, "end_ref": string,
            ], ["kind"]),
        ], ["success", "summary", "details", "answer"]))

    /// task-runner.mjs's answers to its harness tools.
    static let planPublished = "Plan published. Continue."
    static let resultRecorded = "Result recorded. Explain it briefly to the user."
    static let invalidPlan = "Invalid model plan"
    static let invalidResult = "Invalid task result"
}
