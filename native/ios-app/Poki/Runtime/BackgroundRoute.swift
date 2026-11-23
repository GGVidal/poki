#if POKI_EXPERIMENTS
import Foundation
import PokiCore

// Experimental (issue #656): the runner side of PokiCore's background tool, POST /poki/background.
// Only Poki Lab compiles it, and the tool that sends it is listed only while the switch is on.
enum BackgroundRoute {
    /// The switch on the Testing Options page. Off until the owner turns it on.
    static let key = "experiments.background"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// An action that ran but changed nothing in the tree is not taken as done: in the background a
    /// control that wants a touch takes the activate and drops it. The model is told to check.
    static func answer(_ body: JSON?) -> JSON {
        guard let op = body?["op"]?.string, let bundle = body?["bundle"]?.string else {
            return ["error": "invalid argument", "message": "op and bundle are required"]
        }
        let bg = PKBackground.shared()
        let ref = body?["ref"]?.int ?? -1
        let before = op == "look" ? nil : digest(bundle)
        let outcome: PKBackgroundOutcome?
        switch op {
        case "look": outcome = nil
        case "activate": outcome = bg.activate(ref, in: bundle)
        case "back": outcome = bg.back(bundle)
        case "custom": outcome = bg.customAction(body?["name"]?.string ?? "", of: ref, in: bundle)
        case "set": outcome = bg.setValue(body?["text"]?.string ?? "", of: ref, in: bundle)
        case "scroll": outcome = bg.scroll(ref, direction: body?["direction"]?.string == "up" ? -1 : 1, in: bundle)
        case "escape": outcome = bg.escape(bundle)
        default: return ["error": "invalid argument", "message": .string("unknown op \(op)")]
        }
        if let outcome, outcome.needsFront || outcome.failure != nil {
            var out: [String: JSON] = ["needsFront": .bool(outcome.needsFront)]
            if let failure = outcome.failure { out["failure"] = .string(failure) }
            return .object(out)
        }
        if outcome != nil {
            // A push, pop or presentation in a background app waits for a layout pass: two, with time
            // for the transition between them.
            bg.layoutPass(bundle); usleep(700_000); bg.layoutPass(bundle)
        }
        var code: NSString?
        let elements = bg.elements(of: bundle, code: &code)
        guard let elements else {
            return ["error": "not readable", "message": .string("the app's tree was not read: \(code ?? "unknown"); it may not be running")]
        }
        var out: [String: JSON] = ["pid": .number(Double(bg.holdApp(bundle))), "elements": .array(elements.compactMap(json))]
        if let before, before == digest(of: elements), op != "set" {
            out["needsFront"] = true
            out["failure"] = "the step was taken but nothing in the app changed; it likely needs a touch. Check the app before doing it again"
            out.removeValue(forKey: "elements")
        }
        return .object(out)
    }

    private static func json(_ e: PKBackgroundElement) -> JSON? {
        // Empty containers say nothing the model can act on.
        if e.label.isEmpty, e.value.isEmpty, e.identifier.isEmpty, e.actions.isEmpty, e.type != 9 /* button */ { return nil }
        var o: [String: JSON] = ["ref": .number(Double(e.index)), "type": .string(typeName(e.type)), "label": .string(e.label.isEmpty ? e.identifier : e.label),
                                 "frame": .array([e.frame.origin.x, e.frame.origin.y, e.frame.size.width, e.frame.size.height].map { .number(Double($0.rounded())) })]
        if !e.value.isEmpty { o["value"] = .string(e.value) }
        if e.selected { o["selected"] = true }
        if !e.actions.isEmpty { o["actions"] = .array(e.actions.map(JSON.string)) }
        return .object(o)
    }

    private static func digest(_ bundle: String) -> String? {
        var code: NSString?
        return PKBackground.shared().elements(of: bundle, code: &code).map(digest(of:))
    }

    private static func digest(of elements: [PKBackgroundElement]) -> String {
        elements.map { "\($0.type)|\($0.label)|\($0.value)|\($0.selected)|\(Int($0.frame.origin.y))" }.joined(separator: "\n")
    }

    /// XCUIElementType's numbers, for the common ones.
    static func typeName(_ type: UInt) -> String {
        let names: [UInt: String] = [1: "Other", 2: "Application", 4: "Window", 5: "Sheet", 7: "Alert", 9: "Button", 12: "CheckBox", 14: "PopUpButton",
                                     19: "Keyboard", 21: "NavigationBar", 22: "TabBar", 24: "Toolbar", 25: "StatusBar", 26: "Table", 32: "CollectionView",
                                     33: "Slider", 34: "PageIndicator", 36: "ActivityIndicator", 37: "SegmentedControl", 38: "Picker", 39: "PickerWheel",
                                     40: "Switch", 41: "Toggle", 42: "Link", 43: "Image", 45: "SearchField", 46: "ScrollView", 47: "ScrollBar",
                                     48: "StaticText", 49: "TextField", 50: "SecureTextField", 51: "DatePicker", 52: "TextView", 53: "Menu",
                                     54: "MenuItem", 58: "WebView", 75: "Cell", 79: "Stepper", 80: "Tab"]
        return names[type] ?? "Type\(type)"
    }
}
#endif
