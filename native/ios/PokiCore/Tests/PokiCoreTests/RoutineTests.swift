import XCTest
@testable import PokiCore

/// Routines: a task's do actions are recorded, saved by name, replayed in one call that waits for each
/// target and stops at a screen that differs; notes; export and import.
final class RoutineTests: XCTestCase {
    /// Settings → General → About, a screen per tap.
    final class Pages: @unchecked Sendable {
        let wda: FakeWDA
        let page = LockedBox(0)
        var screens: [[Node]]
        init(_ wda: FakeWDA, _ screens: [[Node]]) {
            self.wda = wda
            self.screens = screens
            show(0)
            wda.set("POST /wda/tap") { [self] _ in
                let next = min(self.page.value + 1, self.screens.count - 1)
                self.show(next)
                return (200, ["value": .null])
            }
        }
        func show(_ i: Int) { page.value = i; wda.tree(screens[i], app: "Settings") }
    }

    static let home = [Node("Button", "General", [16, 100, 358, 44]), Node("Button", "Privacy", [16, 144, 358, 44])]
    static let general = [Node("NavigationBar", "General", [0, 50, 390, 44]), Node("Button", "About", [16, 100, 358, 44]), Node("Button", "Software Update", [16, 144, 358, 44])]
    static let about = [Node("NavigationBar", "About", [0, 50, 390, 44]), Node("StaticText", "iOS Version", [16, 100, 358, 44], value: "27.3"), Node("StaticText", "Model Name", [16, 144, 358, 44], value: "iPhone")]

    func core(_ store: RoutineStore = RoutineStore(url: nil)) -> (PokiCore, FakeWDA, Pages) {
        let wda = FakeWDA()
        let pages = Pages(wda, [Self.home, Self.general, Self.about])
        let (core, _, _) = makeCore(wda) { $0.memory = store }
        return (core, wda, pages)
    }

    func number(of label: String, in text: String) -> Int? {
        for line in text.split(separator: "\n") where line.contains("\"\(label)") {
            let digits = line.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
            if let n = Int(digits) { return n }
        }
        return nil
    }

    /// Records Settings → General → About by hand and saves it.
    func recordAbout(_ core: PokiCore) async -> ToolResult {
        let first = await core.call("look", [:])
        let general = number(of: "General", in: first.text)!
        let second = await core.call("do", ["actions": [["tap": .number(Double(general))]]])
        guard let about = number(of: "About", in: second.text) else { XCTFail(second.text); return second }
        _ = await core.call("do", ["actions": [["tap": .number(Double(about))]]])
        return await core.call("routines", ["action": "save", "name": "iOS version", "description": "read the iOS version in Settings", "read": ["iOS Version"]])
    }

    func testATaskIsSavedAsARoutineByWhatItTapped() async {
        let store = RoutineStore(url: nil)
        let (core, _, _) = core(store)
        let saved = await recordAbout(core)
        XCTAssertTrue(saved.text.contains("saved \"iOS version\" (2 steps"), saved.text)
        let routine = store.routine(named: "iOS version")!
        XCTAssertEqual(routine.steps.map { $0.target?.label }, ["General", "About"])
        XCTAssertEqual(routine.steps.map { $0.target?.type }, ["Button", "Button"])
        XCTAssertEqual(routine.app, "com.apple.Preferences")
        XCTAssertTrue(routine.expect.contains("About") || routine.expect.contains("iOS Version"), "\(routine.expect)")
    }

    func testARunRepeatsTheRoutineInOneCallAndReadsTheValue() async {
        let (core, wda, pages) = core()
        _ = await recordAbout(core)
        pages.show(0)
        let taps = wda.bodies("POST /wda/tap").count
        _ = await core.call("look", [:])
        let run = await core.call("do", ["actions": [["run": "iOS version"]]])
        XCTAssertTrue(run.text.contains("run \"iOS version\": 2 steps"), run.text)
        XCTAssertTrue(run.text.contains("end check passed"), run.text)
        XCTAssertTrue(run.text.contains("read: iOS Version = 27.3"), run.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, taps + 2)
        XCTAssertEqual(pages.page.value, 2)
        XCTAssertFalse(run.isError)
    }

    func testARunStopsWhereTheScreenDiffersAndSendsNothingMore() async {
        let store = RoutineStore(url: nil)
        let (core, wda, pages) = core(store)
        _ = await recordAbout(core)
        pages.screens[0] = [Node("Button", "Privacy", [16, 100, 358, 44])]
        pages.show(0)
        let taps = wda.bodies("POST /wda/tap").count
        _ = await core.call("look", [:])
        let run = await core.call("do", ["actions": [["run": "iOS version"]]])
        XCTAssertTrue(run.text.contains("stopped at step 1 of 2"), run.text)
        XCTAssertTrue(run.text.contains("Button \"General\" is not on screen"), run.text)
        XCTAssertTrue(run.text.contains("app: Settings"), "the stop answers with the screen: \(run.text)")
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, taps)
        XCTAssertEqual(store.routine(named: "iOS version")?.failuresInARow, 1)
        XCTAssertEqual(store.routine(named: "iOS version")?.lastStop?.step, 1)
    }

    func testTwoLikeTargetsFarFromTheRecordedOneAreNotGuessedBetween() async {
        let (core, wda, pages) = core()
        _ = await recordAbout(core)
        pages.screens[0] = [Node("Button", "General", [16, 400, 358, 44]), Node("Button", "General", [16, 600, 358, 44])]
        pages.show(0)
        let taps = wda.bodies("POST /wda/tap").count
        _ = await core.call("look", [:])
        let run = await core.call("do", ["actions": [["run": "iOS version"]]])
        XCTAssertTrue(run.text.contains("2 elements match Button \"General\""), run.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, taps)
    }

    /// The brief goes into every task's prompt: a full memory stays within 4000 characters, and keeps
    /// the routine that fits the task and the newest note.
    func testTheBriefStaysShortWhenTheMemoryIsFull() async throws {
        let store = RoutineStore(url: nil)
        let (core, _, _) = core(store)
        _ = await recordAbout(core)
        var other = try XCTUnwrap(store.routine(named: "iOS version"))
        for i in 0..<30 {
            other.name = "errand \(i)"
            other.description = String(repeating: "an errand the owner runs every week, ", count: 8)
            store.save(other)
        }
        for i in 0..<50 { _ = store.remember("note \(i): " + String(repeating: "a long fact about the owner. ", count: 10), by: "test") }

        let brief = store.brief(for: "what iOS version is this")

        XCTAssertLessThanOrEqual(brief.count, 4000)
        XCTAssertTrue(brief.contains("- iOS version: read the iOS version in Settings"), brief)
        XCTAssertTrue(brief.contains("note 49: "), brief)
    }

    func testAStaleRoutineIsNotOfferedAndASaveOverItStartsItsRecordAgain() async {
        let store = RoutineStore(url: nil)
        let (core, _, pages) = core(store)
        _ = await recordAbout(core)
        XCTAssertTrue(store.brief(for: "what iOS version is this").contains("iOS version"))
        pages.screens[0] = [Node("Button", "Privacy", [16, 100, 358, 44])]
        for _ in 0..<2 { pages.show(0); _ = await core.call("look", [:]); _ = await core.call("do", ["actions": [["run": "iOS version"]]]) }
        XCTAssertTrue(store.routine(named: "iOS version")!.stale)
        XCTAssertFalse(store.brief(for: "what iOS version is this").contains("iOS version:"))
    }

    func testTheFirstLookOfATaskNamesTheRoutinesAndFinishOffersToSave() async {
        let (core, _, pages) = core()
        let first = await core.call("look", [:])
        XCTAssertFalse(first.text.contains("skills"), first.text)
        _ = await recordAbout(core)
        pages.show(0)
        let finished = await core.call("do", ["actions": [["tap": 1]], "finish": true])
        XCTAssertTrue(finished.text.contains("learn: this task took"), finished.text)
        let next = await core.call("look", [:])
        XCTAssertTrue(next.text.contains("skills for this app: \"iOS version\""), next.text)
    }

    func testTypedTextBecomesAParameterAndAPasswordIsNeverKept() async {
        let store = RoutineStore(url: nil)
        let (core, _, _) = core(store)
        _ = await core.call("look", [:])
        // Record by hand: the type actions as the recorder sees them.
        let c = core.computer
        c.refs = [1: Element(type: "SearchField", label: "Search", value: nil, identifier: nil, frame: Rect(x: 16, y: 60, width: 358, height: 36), depth: 1)]
        c.trace = [c.recordable(["type": "hello", "ref": 1])!]
        let (routine, _) = c.routine(named: "search", description: "", read: [], expect: [], by: "test")
        XCTAssertEqual(routine?.steps.first?.action["type"]?.string, "{{text_1}}")
        XCTAssertEqual(routine?.params["text_1"], "hello")
        XCTAssertEqual(routine?.steps.first?.target?.label, "Search")
        c.refs = [1: Element(type: "SecureTextField", label: "Password", value: nil, identifier: nil, frame: Rect(x: 16, y: 60, width: 358, height: 36), depth: 1)]
        let secret = c.recordable(["type": "hunter2", "ref": 1])!
        XCTAssertEqual(secret.step.secret, true)
        XCTAssertNil(secret.typed)
        XCTAssertFalse(secret.step.action.serialized().contains("hunter2"))
    }

    func testNotesExportAndImportMoveTheMemoryBetweenPhones() async throws {
        let a = RoutineStore(url: nil)
        let (core, _, _) = core(a)
        _ = await recordAbout(core)
        let remembered = await core.call("routines", ["action": "remember", "text": "Mom is the contact Mama"])
        XCTAssertTrue(remembered.text.contains("remembered"), remembered.text)
        let exported = await core.call("routines", ["action": "export"])
        XCTAssertTrue(exported.text.contains("\"schema\" : \"poki.agent-backup/2\""), String(exported.text.prefix(200)))

        let b = RoutineStore(url: nil)
        let summary = try b.importData(Data(exported.text.utf8), by: "test")
        XCTAssertTrue(summary.contains("1 skills added"), summary)
        XCTAssertEqual(b.notes.map(\.text), ["Mom is the contact Mama"])
        XCTAssertEqual(b.routine(named: "iOS version")?.steps.count, 2)
        // Importing the same file again changes nothing; an older copy does not replace a newer one.
        let again = try b.importData(Data(exported.text.utf8), by: "test")
        XCTAssertTrue(again.contains("0 skills added, 0 replaced"), again)
        XCTAssertThrowsError(try b.importData(Data(#"{"schema":"other/1"}"#.utf8), by: "test"))
        XCTAssertTrue(b.brief(for: "anything").contains("Mom is the contact Mama"))
    }

    func testTheBackupCopyIsWrittenAndARestoredOneIsMergedIn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poki-routines-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RoutineStore(url: dir.appendingPathComponent("memory.json"), backupDirectory: dir.appendingPathComponent("AgentBackup"))
        store.remember("Use the work email", by: "owner")
        let backup = dir.appendingPathComponent("AgentBackup/poki-agent-backup.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertNil(store.importRestoredBackup(), "our own copy is not imported again")
        // Poki Setup puts another phone's backup there.
        let other = RoutineStore(url: nil)
        other.remember("Mom is the contact Mama", by: "owner")
        try other.exportData().write(to: backup)
        let reopened = RoutineStore(url: dir.appendingPathComponent("memory.json"), backupDirectory: dir.appendingPathComponent("AgentBackup"))
        XCTAssertNotNil(reopened.importRestoredBackup())
        XCTAssertEqual(Set(reopened.notes.map(\.text)), ["Use the work email", "Mom is the contact Mama"])
    }

    func testTheToolIsListedAndAnswersWithoutTheRunner() async {
        let (core, _, _) = core()
        let list = await core.rpc(["jsonrpc": "2.0", "id": 1, "method": "tools/list"], session: nil)
        XCTAssertTrue(list.reply?.serialized().contains("\"name\":\"skills\"") == true)
        let empty = await core.call("routines", ["action": "list"])
        XCTAssertTrue(empty.text.contains("none saved yet"), empty.text)
        let bad = await core.call("routines", ["action": "show", "name": "nope"])
        XCTAssertTrue(bad.isError)
    }

    func testChineseRequestSelectsTheMatchingSkillAndLeavesUnrelatedSkillsOut() async throws {
        let store = RoutineStore(url: nil)
        let (core, _, _) = core(store)
        _ = await recordAbout(core)
        var battery = try XCTUnwrap(store.routine(named: "iOS version"))
        battery.name = "查电池健康"
        battery.description = "在设置里查看电池最大容量"
        battery.app = "com.apple.Preferences"
        battery.updated = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(battery)

        for i in 0..<15 {
            var filler = battery
            filler.name = "日常事务\(i)"
            filler.description = "每周查看一次快递进度\(i)"
            filler.app = "com.Cainiao.cnwireless"
            filler.updated = Date(timeIntervalSince1970: 1_700_001_000 + Double(i))
            store.save(filler)
        }

        let matched = store.brief(for: "帮我看看电池健康度")
        XCTAssertTrue(matched.contains("查电池健康"), matched)
        XCTAssertFalse(matched.contains("日常事务"), matched)

        let unrelated = store.brief(for: "帮我算一下 25 乘 36", app: "com.apple.calculator")
        XCTAssertFalse(unrelated.contains("查电池健康"), unrelated)
        XCTAssertFalse(unrelated.contains("日常事务"), unrelated)
    }

    func testLegacyBackupMigratesRoutinesToSkillsWithAppFromStepsOrNil() throws {
        let legacyJSON = """
        {
          "schema": "poki.agent-backup/1",
          "routines": [
            {
              "name": "查电池健康",
              "description": "查看最大容量",
              "app": "com.apple.Preferences",
              "steps": [{"action": {"tap": "@"}, "app": "com.apple.Preferences"}],
              "params": {},
              "expect": [],
              "read": [],
              "runs": 2,
              "ok": 2,
              "failuresInARow": 0,
              "savedBy": "Poki",
              "created": "2026-11-01T00:00:00Z",
              "updated": "2026-11-01T00:00:00Z"
            },
            {
              "name": "步骤里带设置",
              "description": "顶层没有记录 App",
              "steps": [
                {"action": {"tap": "@"}, "app": "com.apple.springboard"},
                {"action": {"tap": "@"}, "target": {"type": "Button", "label": "通用", "x": 100, "y": 120}, "app": "com.apple.Preferences"}
              ],
              "params": {},
              "expect": [],
              "read": [],
              "runs": 1,
              "ok": 1,
              "failuresInARow": 0,
              "savedBy": "Poki",
              "created": "2026-11-01T00:00:00Z",
              "updated": "2026-11-01T00:00:00Z"
            },
            {
              "name": "返回主屏幕",
              "description": "没有任何 App 记录",
              "steps": [{"action": {"button": "home"}}],
              "params": {},
              "expect": [],
              "read": [],
              "runs": 1,
              "ok": 1,
              "failuresInARow": 0,
              "savedBy": "Poki",
              "created": "2026-11-01T00:00:00Z",
              "updated": "2026-11-01T00:00:00Z"
            }
          ],
          "notes": [{"id": "n1", "text": "常点少冰", "by": "owner", "at": "2026-11-01T00:00:00Z"}],
          "runs": [{"routine": "查电池健康", "at": "2026-11-01T00:00:00Z", "ms": 420, "outcome": "ok", "steps": ["1 tap"]}]
        }
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("poki-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("agent-memory.json")
        try Data(legacyJSON.utf8).write(to: file)

        let loaded = RoutineStore(url: file)
        XCTAssertEqual(loaded.routine(named: "查电池健康")?.app, "com.apple.Preferences")
        XCTAssertEqual(loaded.routine(named: "步骤里带设置")?.app, "com.apple.Preferences")
        XCTAssertNil(loaded.routine(named: "返回主屏幕")?.app)
        XCTAssertEqual(loaded.notes.map(\.text), ["常点少冰"])

        let imported = RoutineStore(url: nil)
        let summary = try imported.importData(Data(legacyJSON.utf8), by: "test")
        XCTAssertTrue(summary.contains("3 skills added"), summary)
        XCTAssertEqual(imported.routine(named: "步骤里带设置")?.app, "com.apple.Preferences")
        XCTAssertNil(imported.routine(named: "返回主屏幕")?.app)
        let ref = MemoryConversation(sessionID: "session-42", entryID: "entry-7", app: "com.meituan.itakeaway", at: Date(timeIntervalSince1970: 1_700_000_120))
        _ = imported.remember("外卖放前台", by: "Poki", conversation: ref)

        let exportedData = try imported.exportData()
        let exported = String(decoding: exportedData, as: UTF8.self)
        XCTAssertTrue(exported.contains("\"schema\" : \"poki.agent-backup/2\""), exported)
        XCTAssertTrue(exported.contains("\"skills\""), exported)
        let roundTripped = RoutineStore(url: nil)
        _ = try roundTripped.importData(exportedData, by: "test")
        XCTAssertEqual(roundTripped.notes.first(where: { $0.text == "外卖放前台" })?.conversation, ref)
    }

    func testSkillsToolIsPrimaryAndRoutinesAliasReturnsTheSameResult() async {
        let (core, _, pages) = core()
        let listRPC = await core.rpc(["jsonrpc": "2.0", "id": 1, "method": "tools/list"], session: nil)
        let catalog = listRPC.reply?.serialized() ?? ""
        XCTAssertTrue(catalog.contains("\"name\":\"skills\""), catalog)
        XCTAssertFalse(catalog.contains("\"name\":\"routines\""), catalog)

        _ = await core.call("look", [:])
        let general = number(of: "General", in: (await core.call("look", [:])).text)!
        let second = await core.call("do", ["actions": [["tap": .number(Double(general))]]])
        let about = number(of: "About", in: second.text)!
        _ = await core.call("do", ["actions": [["tap": .number(Double(about))]]])
        let saved = await core.call("skills", ["action": "save", "name": "查系统版本", "description": "在设置里读取 iOS 版本", "read": ["iOS Version"]])
        XCTAssertFalse(saved.isError, saved.text)
        XCTAssertTrue(saved.text.contains("skills: saved \"查系统版本\""), saved.text)

        let listedViaNew = await core.call("skills", ["action": "list"])
        let listedViaAlias = await core.call("routines", ["action": "list"])
        XCTAssertFalse(listedViaAlias.isError, listedViaAlias.text)
        XCTAssertEqual(listedViaAlias.text, listedViaNew.text)

        pages.show(0)
        _ = await core.call("look", [:])
        let replayed = await core.call("do", ["actions": [["run": "查系统版本"]]])
        XCTAssertFalse(replayed.isError, replayed.text)
        XCTAssertTrue(replayed.text.contains("run \"查系统版本\": 2 steps"), replayed.text)
        XCTAssertTrue(replayed.text.contains("read: iOS Version = 27.3"), replayed.text)
    }
}
