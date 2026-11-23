import Foundation
import XCTest
@testable import PokiCore

/// Experimental (issue #656): the background tool is listed only while the host turns it on, and
/// its answers tell the model whether the step ran in the background or needs the app in front.
final class BackgroundToolTests: XCTestCase {
    func names(_ core: PokiCore) -> [String] { core.listedTools.compactMap { $0["name"]?.string } }

    func testHiddenUnlessTurnedOn() async {
        let (off, _, _) = makeCore()
        XCTAssertFalse(names(off).contains("background"))
        let answer = await off.call("background", ["op": "look", "app": "x"])
        XCTAssertTrue(answer.isError)
        let flag = LockedBox(false)
        let (core, _, _) = makeCore { $0.background = { flag.value } }
        XCTAssertFalse(names(core).contains("background"))
        flag.value = true
        XCTAssertTrue(names(core).contains("background"))
        XCTAssertFalse(PokiCore.toolCatalogJSON(includeScreenHistory: false).contains("\"background\""))
        XCTAssertTrue(PokiCore.toolCatalogJSON(includeScreenHistory: false, includeBackground: true).contains("\"background\""))
    }

    func testLookAndActionAnswers() async throws {
        let wda = FakeWDA()
        let sent = LockedBox<[JSON]>([])
        wda.set("POST /poki/background") { body in
            sent.update { $0.append(body ?? .null) }
            let op = body?["op"]?.string
            if op == "activate" { return (200, ["value": ["needsFront": true, "failure": "the control did not answer"]]) }
            return (200, ["value": ["pid": 42, "elements": [["ref": 3, "type": "Button", "label": "Save", "frame": [10, 20, 100, 44], "actions": ["Delete"]]]]])
        }
        let (core, _, _) = makeCore(wda) { $0.background = { true } }
        let look = await core.call("background", ["op": "look", "app": "com.example.fixture"])
        XCTAssertFalse(look.isError, look.text)
        XCTAssertTrue(look.text.contains("[3] Button \"Save\" [10,20,100,44] actions: Delete"), look.text)
        let custom = await core.call("background", ["op": "custom", "app": "com.example.fixture", "ref": 3, "name": "Delete"])
        XCTAssertTrue(custom.text.hasPrefix("done_in_background"), custom.text)
        let press = await core.call("background", ["op": "activate", "app": "com.example.fixture", "ref": 3])
        XCTAssertTrue(press.text.hasPrefix("needs_front"), press.text)
        let missing = await core.call("background", ["op": "activate", "app": "com.example.fixture"])
        XCTAssertTrue(missing.isError)
        XCTAssertEqual(sent.value.count, 3, "an action without ref is not sent")
        XCTAssertEqual(sent.value[1]["name"]?.string, "Delete")
        XCTAssertEqual(sent.value[1]["bundle"]?.string, "com.example.fixture")
    }
}
