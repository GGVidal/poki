import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// Skills and notes: the agent's memory library, kept on the phone and shared by every agent that
// drives it (Poki's own chat and any MCP client over the relay).
//
// A task's `do` actions are recorded as they are sent, each target as what it is (role, label,
// identifier, and where it was) rather than its number, which changes from read to read. A recorded
// task saved under a name is a skill; `do {run: "name"}` replays it in one call. Each step waits for
// its target to be on screen, acts only on a single match, and stops at the first screen that differs,
// so a skill never taps the wrong thing: the agent goes on from the read the stop answers with.
// A skill keeps its runs, so one that keeps stopping is marked stale and no longer offered.
//
// Notes are short facts the agent or the owner saves ("Mom is the contact Mama"). Both live in one
// JSON file in the app's own storage; a copy in Documents/AgentBackup is what Poki Setup backs up.
// Typed text is a parameter of the skill; text typed into a password field is never stored.

/// What a step acts on, as it was found when the step was recorded.
public struct SkillTarget: Codable, Equatable, Sendable {
    public var type: String
    public var label: String?
    public var identifier: String?
    /// The element's centre when recorded: picks one of several matches that are otherwise alike.
    public var x: Double
    public var y: Double

    init(_ e: Element) {
        type = e.type
        label = e.label.flatMap { $0.isEmpty ? nil : $0 }
        identifier = e.identifier.flatMap { $0.isEmpty ? nil : $0 }
        let c = e.frame.centre
        x = (c.x * 10).rounded() / 10
        y = (c.y * 10).rounded() / 10
    }

    public init(type: String, label: String? = nil, identifier: String? = nil, x: Double, y: Double) {
        self.type = type
        self.label = label
        self.identifier = identifier
        self.x = x
        self.y = y
    }

    public var describe: String { "\(type) \"\(label ?? identifier ?? "")\"" }

    func matches(_ e: Element) -> Bool {
        guard !e.fromPicture, e.type == type else { return false }
        if let identifier, e.identifier == identifier { return label == nil || e.label == label }
        return (e.label.flatMap { $0.isEmpty ? nil : $0 }) == label && (identifier == nil || e.identifier == nil || e.identifier == identifier)
    }
}

public typealias RoutineTarget = SkillTarget

/// One recorded action. `action` is the `do` action with its element number taken out; `target` is
/// what the number pointed at. A type's text is `{{name}}` of a parameter.
public struct SkillStep: Codable, Equatable, Sendable {
    public var action: JSON
    public var target: SkillTarget?
    /// The app in front when the step was sent.
    public var app: String?
    /// A type into a password field: the text was not kept, so a run stops here for the agent.
    public var secret: Bool?

    public init(action: JSON, target: SkillTarget? = nil, app: String? = nil, secret: Bool? = nil) {
        self.action = action
        self.target = target
        self.app = app
        self.secret = secret
    }
}

public typealias RoutineStep = SkillStep

public struct SkillStop: Codable, Equatable, Sendable {
    public var step: Int
    public var why: String
    public var at: Date

    public init(step: Int, why: String, at: Date) {
        self.step = step
        self.why = why
        self.at = at
    }
}

public typealias RoutineStop = SkillStop

public struct Skill: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    /// The app the skill works in (it is launched first when another app is in front).
    public var app: String?
    public var steps: [SkillStep]
    /// Parameters and the values they were recorded with: `{{text_1}}` in a type.
    public var params: [String: String]
    /// Texts that must be on screen when the skill has run (its end check).
    public var expect: [String]
    /// Labels whose values the run reads off the last screen (a learned readout).
    public var read: [String]
    public var runs: Int
    public var ok: Int
    /// Runs that stopped in a row; two or more mark the skill stale.
    public var failuresInARow: Int
    public var lastStop: SkillStop?
    public var lastMs: Int?
    public var savedBy: String
    public var created: Date
    public var updated: Date

    public init(
        name: String,
        description: String,
        app: String?,
        steps: [SkillStep],
        params: [String: String],
        expect: [String],
        read: [String],
        runs: Int,
        ok: Int,
        failuresInARow: Int,
        lastStop: SkillStop?,
        lastMs: Int?,
        savedBy: String,
        created: Date,
        updated: Date
    ) {
        self.name = name
        self.description = description
        self.app = app
        self.steps = steps
        self.params = params
        self.expect = expect
        self.read = read
        self.runs = runs
        self.ok = ok
        self.failuresInARow = failuresInARow
        self.lastStop = lastStop
        self.lastMs = lastMs
        self.savedBy = savedBy
        self.created = created
        self.updated = updated
    }

    public var stale: Bool { failuresInARow >= 2 }

    public var summary: String {
        "\(name): \(description.isEmpty ? "" : description + "; ")\(app.map { "in \($0), " } ?? "")\(steps.count) steps, \(runs) runs, \(ok) ok\(stale ? ", STALE (stopped \(failuresInARow) times in a row\(lastStop.map { " at step \($0.step): \($0.why)" } ?? ""))" : "")\(params.isEmpty ? "" : ", with: " + params.keys.sorted().map { "\($0) (recorded \"\(params[$0]!.prefix(30))\")" }.joined(separator: ", "))"
    }

    var briefLine: String {
        let detail = description.isEmpty ? "" : ": \(description)"
        let inApp = app.map { description.isEmpty ? ": in \($0)" : " (in \($0))" } ?? ""
        let withParams = params.isEmpty ? "" : ", with: " + params.keys.sorted().map { "\($0) (recorded \"\(params[$0]!.prefix(30))\")" }.joined(separator: ", ")
        return "\(name)\(detail)\(inApp)\(withParams)"
    }

    func migrated() -> Skill {
        var copy = self
        copy.app = Self.normalizedApp(app) ?? Self.inferredApp(from: steps)
        return copy
    }

    private static func normalizedApp(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare("com.apple.springboard") != .orderedSame else {
            return nil
        }
        return trimmed
    }

    static func inferredApp(from steps: [SkillStep]) -> String? {
        if let hit = steps.lazy.compactMap({ $0.target != nil ? normalizedApp($0.app) : nil }).first {
            return hit
        }
        for step in steps {
            let launched = step.action["launch"]?.string ?? step.action["launch"]?["bundle"]?.string
            if let hit = normalizedApp(launched) { return hit }
        }
        return steps.lazy.compactMap { normalizedApp($0.app) }.first
    }
}

public typealias Routine = Skill

/// The conversation turn where a memory was stated or inferred, so the Memory page can open it.
public struct MemoryConversation: Codable, Equatable, Sendable {
    public var sessionID: String
    public var entryID: String?
    public var app: String?
    public var at: Date

    public init(sessionID: String, entryID: String? = nil, app: String? = nil, at: Date) {
        self.sessionID = sessionID
        self.entryID = entryID
        self.app = app
        self.at = at
    }
}

public struct MemoryNote: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var by: String
    public var at: Date
    public var conversation: MemoryConversation?

    public init(id: String, text: String, by: String, at: Date, conversation: MemoryConversation? = nil) {
        self.id = id
        self.text = text
        self.by = by
        self.at = at
        self.conversation = conversation
    }
}

/// One skill run, for the maintainers' log bundle.
public struct SkillRunLog: Codable, Equatable, Sendable {
    public var skill: String
    public var at: Date
    public var ms: Int
    public var outcome: String
    public var steps: [String]

    public var routine: String {
        get { skill }
        set { skill = newValue }
    }

    public init(skill: String, at: Date, ms: Int, outcome: String, steps: [String]) {
        self.skill = skill
        self.at = at
        self.ms = ms
        self.outcome = outcome
        self.steps = steps
    }

    public init(routine: String, at: Date, ms: Int, outcome: String, steps: [String]) {
        self.init(skill: routine, at: at, ms: ms, outcome: outcome, steps: steps)
    }

    private enum CodingKeys: String, CodingKey {
        case skill, routine, at, ms, outcome, steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skill = try c.decodeIfPresent(String.self, forKey: .skill) ?? c.decode(String.self, forKey: .routine)
        at = try c.decode(Date.self, forKey: .at)
        ms = try c.decode(Int.self, forKey: .ms)
        outcome = try c.decode(String.self, forKey: .outcome)
        steps = try c.decode([String].self, forKey: .steps)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(skill, forKey: .skill)
        try c.encode(at, forKey: .at)
        try c.encode(ms, forKey: .ms)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(steps, forKey: .steps)
    }
}

public typealias RoutineRunLog = SkillRunLog

/// The file: skills, notes and the latest runs. Reads both v1 (`routines`) and v2 (`skills`).
struct MemoryFile: Codable {
    var schema = SkillStore.schema
    var exported: Date?
    var skills: [Skill] = []
    var notes: [MemoryNote] = []
    var runs: [SkillRunLog] = []
    /// What the app adds to a backup (its saved sessions), opaque here.
    var extras: [String: JSON]?

    init(
        schema: String = SkillStore.schema,
        exported: Date? = nil,
        skills: [Skill] = [],
        notes: [MemoryNote] = [],
        runs: [SkillRunLog] = [],
        extras: [String: JSON]? = nil
    ) {
        self.schema = schema
        self.exported = exported
        self.skills = skills
        self.notes = notes
        self.runs = runs
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case schema, exported, skills, routines, notes, runs, extras
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema) ?? SkillStore.schema
        exported = try c.decodeIfPresent(Date.self, forKey: .exported)
        let loaded = try c.decodeIfPresent([Skill].self, forKey: .skills)
            ?? c.decodeIfPresent([Skill].self, forKey: .routines)
            ?? []
        skills = loaded.map { $0.migrated() }
        notes = try c.decodeIfPresent([MemoryNote].self, forKey: .notes) ?? []
        runs = try c.decodeIfPresent([SkillRunLog].self, forKey: .runs) ?? []
        extras = try c.decodeIfPresent([String: JSON].self, forKey: .extras)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encodeIfPresent(exported, forKey: .exported)
        try c.encode(skills, forKey: .skills)
        try c.encode(notes, forKey: .notes)
        try c.encode(runs, forKey: .runs)
        try c.encodeIfPresent(extras, forKey: .extras)
    }
}

/// The agent's memory library: thread-safe, saved to one file after every change.
public final class SkillStore: @unchecked Sendable {
    public static let schema = "poki.agent-backup/2"
    static let supportedSchemas: Set<String> = ["poki.agent-backup/1", "poki.agent-backup/2"]
    public static let backupName = "poki-agent-backup.json"
    static let maxNotes = 50, maxSkills = 200, maxRuns = 50, maxNoteLength = 300

    private let lock = NSLock()
    private var file = MemoryFile()
    /// Where the memory is kept (nil: in memory only, as in tests).
    public let url: URL?
    /// Where a copy goes after every change, for Poki Setup's backup (Documents/AgentBackup).
    public let backupDirectory: URL?
    private var lastBackupHash: String?

    public init(url: URL?, backupDirectory: URL? = nil) {
        self.url = url
        self.backupDirectory = backupDirectory
        if let url, let data = try? Data(contentsOf: url), let saved = try? Self.decoder.decode(MemoryFile.self, from: data) {
            file = saved
        }
        if let backupDirectory { lastBackupHash = try? String(contentsOf: backupDirectory.appendingPathComponent(".last-written"), encoding: .utf8) }
    }

    /// The shared memory of the app (Application Support/Poki/agent-memory.json, and its backup copy
    /// in Documents/AgentBackup). The app may replace it before PokiCore starts.
    public static var shared: SkillStore = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Poki", isDirectory: true)
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("AgentBackup", isDirectory: true)
        #if os(iOS)
        return SkillStore(url: support?.appendingPathComponent("agent-memory.json"), backupDirectory: documents)
        #else
        return SkillStore(url: nil)
        #endif
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func withFile<T>(_ change: Bool = false, _ body: (inout MemoryFile) throws -> T) rethrows -> T {
        lock.lock()
        let result = try body(&file)
        let snapshot = change ? file : nil
        lock.unlock()
        if let snapshot { persist(snapshot) }
        return result
    }

    /// Notified after every change (the app's Memory page).
    public var onChange: (@Sendable () -> Void)?

    private func persist(_ snapshot: MemoryFile) {
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var diskSnapshot = snapshot
            diskSnapshot.schema = Self.schema
            if let data = try? Self.encoder.encode(diskSnapshot) { try? data.write(to: url, options: .atomic) }
        }
        if let backupDirectory, let data = try? exportData(includeExtras: false) {
            try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let target = backupDirectory.appendingPathComponent(Self.backupName)
            try? data.write(to: target, options: .atomic)
            let hash = Self.hash(data)
            lastBackupHash = hash
            try? hash.write(to: backupDirectory.appendingPathComponent(".last-written"), atomically: true, encoding: .utf8)
        }
        onChange?()
    }

    static func hash(_ data: Data) -> String {
        // FNV-1a: only to tell our own copy from one put there by Poki Setup.
        var h: UInt64 = 0xcbf29ce484222325
        for b in data { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// A backup file Poki Setup put in Documents/AgentBackup since the app last wrote it is merged in.
    /// Returns what was imported, or nil when there was nothing new.
    @discardableResult
    public func importRestoredBackup() -> String? {
        guard let backupDirectory else { return nil }
        let target = backupDirectory.appendingPathComponent(Self.backupName)
        guard let data = try? Data(contentsOf: target), Self.hash(data) != lastBackupHash else { return nil }
        return try? importData(data, by: "restore")
    }

    // MARK: Reading

    public var skills: [Skill] { withFile { $0.skills } }
    public var routines: [Skill] { skills }
    public var notes: [MemoryNote] { withFile { $0.notes } }
    public var runLog: [SkillRunLog] { withFile { $0.runs } }

    public func skill(named name: String) -> Skill? {
        withFile { f in f.skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
    }

    public func routine(named name: String) -> Skill? { skill(named: name) }

    // MARK: Changing

    public func save(_ skill: Skill) {
        withFile(true) { f in
            var s = skill.migrated()
            if let i = f.skills.firstIndex(where: { $0.name.caseInsensitiveCompare(s.name) == .orderedSame }) {
                let old = f.skills[i]
                s.created = old.created
                if s.app == nil { s.app = old.app }
                // A skill saved again after it stopped is the path that worked: its record starts over.
                if old.steps == s.steps { s.runs = old.runs; s.ok = old.ok; s.failuresInARow = old.failuresInARow; s.lastStop = old.lastStop }
                f.skills[i] = s
            } else {
                f.skills.append(s)
                if f.skills.count > Self.maxSkills { f.skills.removeFirst(f.skills.count - Self.maxSkills) }
            }
        }
    }

    @discardableResult
    public func forget(_ name: String) -> Bool {
        withFile(true) { f in
            let before = f.skills.count
            f.skills.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            return f.skills.count != before
        }
    }

    @discardableResult
    public func rename(_ name: String, to new: String) -> Bool {
        withFile(true) { f in
            guard let i = f.skills.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
            f.skills[i].name = new
            f.skills[i].updated = Date()
            return true
        }
    }

    public func update(_ name: String, _ change: (inout Skill) -> Void) {
        withFile(true) { f in
            guard let i = f.skills.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            change(&f.skills[i])
        }
    }

    @discardableResult
    public func remember(_ text: String, by: String, conversation: MemoryConversation? = nil) -> MemoryNote? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return withFile(true) { f in
            if let same = f.notes.first(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) { return same }
            let note = MemoryNote(id: String(UUID().uuidString.prefix(8)).lowercased(), text: String(clean.prefix(Self.maxNoteLength)), by: by, at: Date(), conversation: conversation)
            f.notes.append(note)
            if f.notes.count > Self.maxNotes { f.notes.removeFirst(f.notes.count - Self.maxNotes) }
            return note
        }
    }

    @discardableResult
    public func forgetNote(_ idOrText: String) -> Bool {
        withFile(true) { f in
            let before = f.notes.count
            f.notes.removeAll { $0.id == idOrText || $0.text.caseInsensitiveCompare(idOrText) == .orderedSame }
            return f.notes.count != before
        }
    }

    public func editNote(_ id: String, text: String) {
        withFile(true) { f in
            guard let i = f.notes.firstIndex(where: { $0.id == id }) else { return }
            f.notes[i].text = String(text.prefix(Self.maxNoteLength))
        }
    }

    func logRun(_ log: SkillRunLog) {
        withFile(true) { f in
            f.runs.append(log)
            if f.runs.count > Self.maxRuns { f.runs.removeFirst(f.runs.count - Self.maxRuns) }
        }
    }

    public func clearAll() { withFile(true) { $0 = MemoryFile() } }

    // MARK: Export and import

    /// What the app adds to a backup and takes back from one (its saved chat sessions). Off unless set.
    public var extrasProvider: (@Sendable () -> [String: JSON])?
    public var extrasRestorer: (@Sendable ([String: JSON]) -> Void)?

    /// The backup file: skills, notes and the run log; with `includeExtras`, what the app adds.
    public func exportData(includeExtras: Bool = false) throws -> Data {
        var snapshot = withFile { $0 }
        snapshot.schema = Self.schema
        snapshot.exported = Date()
        snapshot.extras = includeExtras ? extrasProvider?() : nil
        return try Self.encoder.encode(snapshot)
    }

    /// Merges a backup in: a skill with the same name is replaced when the incoming one is newer;
    /// notes are added unless the same text is there. Accepts both v1 and v2 backups.
    @discardableResult
    public func importData(_ data: Data, by: String) throws -> String {
        let incoming: MemoryFile
        do { incoming = try Self.decoder.decode(MemoryFile.self, from: data) }
        catch { throw ImportError("not a Poki agent backup: \(error)") }
        guard incoming.schema.hasPrefix("poki.agent-backup/") else { throw ImportError("not a Poki agent backup (schema \(incoming.schema))") }
        guard Self.supportedSchemas.contains(incoming.schema) else { throw ImportError("a backup of a newer Poki (\(incoming.schema)); update Poki to import it") }
        var added = 0, replaced = 0, kept = 0, notes = 0
        withFile(true) { f in
            for r in incoming.skills where !r.name.isEmpty {
                let migrated = r.migrated()
                if let i = f.skills.firstIndex(where: { $0.name.caseInsensitiveCompare(migrated.name) == .orderedSame }) {
                    if migrated.updated > f.skills[i].updated { f.skills[i] = migrated; replaced += 1 } else { kept += 1 }
                } else { f.skills.append(migrated); added += 1 }
            }
            for n in incoming.notes where !f.notes.contains(where: { $0.text.caseInsensitiveCompare(n.text) == .orderedSame }) {
                f.notes.append(n); notes += 1
            }
            if f.notes.count > Self.maxNotes { f.notes.removeFirst(f.notes.count - Self.maxNotes) }
        }
        if let extras = incoming.extras, !extras.isEmpty { extrasRestorer?(extras) }
        return "imported: \(added) skills added, \(replaced) replaced by newer ones, \(kept) kept (ours were newer), \(notes) notes added\(incoming.extras?.isEmpty == false ? ", and the app's saved sessions" : "")"
    }

    public struct ImportError: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    /// The maintainers' bundle: every skill with its record, the latest runs and the notes' count.
    /// No screenshots and no typed text beyond what the skills keep as parameters.
    public func debugBundle(extra: [String: JSON] = [:]) -> Data {
        let snapshot = withFile { $0 }
        var bundle: [String: JSON] = extra
        bundle["schema"] = "poki.agent-debug/2"
        bundle["made"] = .string(ISO8601DateFormatter().string(from: Date()))
        bundle["skills"] = .array(snapshot.skills.map { r in
            ["name": .string(r.name), "app": r.app.map(JSON.string) ?? .null, "steps": .array(r.steps.map { s in
                ["action": s.action, "target": s.target.map { .string($0.describe) } ?? .null, "app": s.app.map(JSON.string) ?? .null] }),
             "runs": .number(Double(r.runs)), "ok": .number(Double(r.ok)), "stale": .bool(r.stale),
             "last_stop": r.lastStop.map { ["step": .number(Double($0.step)), "why": .string($0.why), "at": .string(ISO8601DateFormatter().string(from: $0.at))] } ?? .null,
             "last_ms": r.lastMs.map { .number(Double($0)) } ?? .null]
        })
        bundle["runs"] = .array(snapshot.runs.map { l in
            ["skill": .string(l.skill), "at": .string(ISO8601DateFormatter().string(from: l.at)), "ms": .number(Double(l.ms)), "outcome": .string(l.outcome), "steps": .array(l.steps.map(JSON.string))]
        })
        bundle["notes"] = .number(Double(snapshot.notes.count))
        return JSON.object(bundle).data()
    }

    // MARK: For the agent

    /// The brief goes into every task's prompt, so it stays this short (in characters); the skills
    /// tool lists the rest.
    static let maxBriefLength = 4000

    /// Non-stale skills ranked by current app and task terms. Unrelated skills (score 0) are omitted.
    public func matchingSkills(for task: String, apps: [String] = [], limit: Int = 12) -> [Skill] {
        matchingSkills(in: withFile { $0.skills }, for: task, apps: apps, limit: limit)
    }

    private func matchingSkills(in skills: [Skill], for task: String, apps: [String], limit: Int) -> [Skill] {
        let targetApps = Set(apps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let taskTokens = Self.tokens(task)
        return skills.filter { !$0.stale }.compactMap { skill -> (Skill, Int)? in
            let skillTokens = Self.tokens(skill.name + " " + skill.description)
            let termScore = skillTokens.intersection(taskTokens).count * 3
            let appScore = (skill.app.map { targetApps.contains($0.lowercased()) } ?? false) ? 4 : 0
            let score = termScore + appScore
            return score > 0 ? (skill, score) : nil
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.updated > $1.0.updated }.prefix(limit).map(\.0)
    }

    /// What a model should know at the start of a task: the skills that fit its app or wording best
    /// (stale ones left out) in up to half of `maxBriefLength`, and the newest notes in the rest.
    public func brief(for task: String, app: String? = nil, apps: [String] = [], limit: Int = 12) -> String {
        let (skills, notes) = withFile { ($0.skills, $0.notes) }
        let allApps = apps + (app.map { [$0] } ?? [])
        let fit = matchingSkills(in: skills, for: task, apps: allApps, limit: limit)
        var room = Self.maxBriefLength
        func section(_ header: String, _ items: [String], within limit: Int) -> [String] {
            var left = min(room, limit) - header.count - 1
            var taken: [String] = []
            for item in items where item.count + 1 <= left {
                taken.append(item)
                left -= item.count + 1
            }
            guard !taken.isEmpty else { return [] }
            room -= ([header] + taken).reduce(0) { $0 + $1.count + 1 }
            return [header] + taken
        }
        let skillLines = section(
            "Saved skills: do {run: \"name\"} replays one in a single call and stops cleanly at a screen that differs, so try a skill that fits before stepping by hand (with: {text_1: \"…\"} changes what it types). The skills tool lists, shows, edits and saves them:",
            fit.map { "- \($0.briefLine)" },
            within: Self.maxBriefLength / 2
        )
        let noteLines = section(
            "Notes saved about the owner and their phone, newest first (use them; the skills tool's remember adds one, forget_note drops one):",
            notes.suffix(20).reversed().map { "- \($0.text)" },
            within: room
        )
        return (noteLines + skillLines).joined(separator: "\n")
    }

    private static let englishStopwords: Set<String> = [
        "an", "and", "are", "as", "at", "be", "by", "can", "do", "for", "from", "get", "go",
        "he", "how", "if", "in", "into", "is", "it", "its", "let", "me", "my", "no", "of",
        "on", "open", "or", "our", "out", "please", "read", "run", "see", "show", "so",
        "the", "their", "them", "then", "this", "that", "to", "up", "use", "view", "we",
        "what", "when", "where", "which", "who", "with", "you", "your",
    ]

    private static let chineseStopwords: Set<String> = [
        "一下", "一个", "一些", "帮我", "给我", "替我", "看看", "看下", "查看", "查下", "查询",
        "打开", "开启", "进入", "使用", "点击", "怎么", "可以", "能否", "能不能", "现在", "今天",
        "手机", "里面", "请问", "想要", "我要", "去看看", "帮我看", "看一看",
    ]

    static func tokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var out: Set<String> = []

        var latin = ""
        var cjk: [Character] = []

        func flushLatin() {
            guard !latin.isEmpty else { return }
            if latin.count >= 2, !englishStopwords.contains(latin) {
                out.insert(latin)
            }
            latin.removeAll(keepingCapacity: true)
        }

        func flushCJK() {
            guard !cjk.isEmpty else { return }
            if cjk.count >= 2 {
                for i in 0..<(cjk.count - 1) {
                    let bigram = String(cjk[i...i + 1])
                    if !chineseStopwords.contains(bigram) {
                        out.insert(bigram)
                    }
                }
            }
            cjk.removeAll(keepingCapacity: true)
        }

        for ch in lower {
            let isIdeograph = ch.unicodeScalars.contains { $0.properties.isIdeographic }
            if isIdeograph {
                flushLatin()
                cjk.append(ch)
            } else if ch.isLetter || ch.isNumber {
                flushCJK()
                latin.append(ch)
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()

        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lower
        tokenizer.enumerateTokens(in: lower.startIndex..<lower.endIndex) { range, _ in
            let word = String(lower[range])
            guard word.count >= 2 else { return true }
            let hasIdeograph = word.unicodeScalars.contains { $0.properties.isIdeographic }
            if hasIdeograph {
                if !chineseStopwords.contains(word) { out.insert(word) }
            } else if !englishStopwords.contains(word) {
                out.insert(word)
            }
            return true
        }
        #endif

        return out
    }
}

public typealias RoutineStore = SkillStore

// MARK: Recording and replay in `do`

/// A step as recorded while the task ran, with what the screen held before it (for the end check).
struct RecordedStep {
    var step: SkillStep
    var typed: String?
    var keysBefore: Set<String>
}

extension Computer {
    /// The `do` action as a skill step: element numbers become targets. nil for what is not kept
    /// (a handoff, a run, which records its own steps).
    func recordable(_ action: JSON) -> RecordedStep? {
        guard case .object(var o) = action, o["handoff"] == nil, o["run"] == nil else { return nil }
        var target: SkillTarget?
        var typed: String?
        var secret: Bool?
        func element(_ spec: JSON?) -> Element? {
            guard let spec else { return nil }
            if let n = spec.int, spec.array == nil, case .number = spec { return refs[n] }
            if case .string = spec, let n = spec.int { return refs[n] }
            if let n = spec["ref"]?.int { return refs[n] }
            return nil
        }
        func point(_ e: Element) -> JSON { let c = e.frame.centre; return [.number(c.x.rounded()), .number(c.y.rounded())] }
        for key in ["tap", "long_press"] {
            if let spec = o[key], let e = element(spec) {
                target = SkillTarget(e)
                if case .object(var inner) = spec { inner["ref"] = "@"; o[key] = .object(inner) } else { o[key] = "@" }
            }
        }
        if let text = o["type"]?.text {
            if let e = element(o["ref"]) { target = SkillTarget(e); o["ref"] = "@" }
            let hidden = describe(action).hasSuffix("(hidden)")
            if hidden { secret = true; o["type"] = "" } else { typed = text }
        }
        if case .object(var s) = o["scroll_to"], let e = element(s["ref"]) {
            s["ref"] = nil
            s["text"] = .string(e.label ?? e.text)
            o["scroll_to"] = .object(s)
        }
        if case .object(var s) = o["scroll_to"], s["in"] != nil { s["in"] = nil; o["scroll_to"] = .object(s) }
        if case .object(var s) = o["swipe"], s["in"] != nil { s["in"] = nil; o["swipe"] = .object(s) }
        if case .object(var d) = o["drag"] {
            for k in ["from", "to"] { if let e = element(d[k]) { d[k] = point(e) } }
            o["drag"] = .object(d)
        }
        if case .object(var p) = o["pinch"], let e = element(.object(p)) { p["ref"] = nil; let c = e.frame.centre; p["x"] = .number(c.x.rounded()); p["y"] = .number(c.y.rounded()); o["pinch"] = .object(p) }
        let keys = Set(listed.map(\.element.key))
        return RecordedStep(step: SkillStep(action: .object(o), target: target, app: lastForeground?.bundleID, secret: secret), typed: typed, keysBefore: keys)
    }

    /// The task's recorded steps as a skill (nil and why, when they cannot make one).
    func skill(named name: String, description: String, read: [String], expect: [String]?, by: String) -> (Skill?, String) {
        let recorded = trace
        guard !recorded.isEmpty else { return (nil, "nothing was recorded in this task yet: a skill is made of the do actions sent since the task began (the first look or do after a finish)") }
        var params: [String: String] = [:]
        var steps: [SkillStep] = []
        for r in recorded {
            var s = r.step
            if let text = r.typed, case .object(var o) = s.action {
                let id = params.first(where: { $0.value == text })?.key ?? "text_\(params.count + 1)"
                params[id] = text
                o["type"] = .string("{{\(id)}}")
                s.action = .object(o)
            }
            steps.append(s)
        }
        steps = Self.withoutRefocusTaps(steps)
        var checks = expect ?? []
        if expect == nil, let last = recorded.last {
            let fresh = listed.map(\.element).filter { e in
                !e.fromPicture && !e.text.isEmpty && !Self.containers.contains(e.type) && !last.keysBefore.contains(e.key) && e.text.count <= 60
                    && listed.filter({ $0.element.key == e.key }).count == 1
            }
            let preferred = fresh.filter { ["NavigationBar", "StaticText", "Heading"].contains($0.type) } + fresh.filter { !["NavigationBar", "StaticText", "Heading"].contains($0.type) }
            checks = Array(preferred.prefix(3).map { $0.label ?? $0.text })
        }
        let app = Skill.inferredApp(from: steps)
        let now = Date()
        let skill = Skill(name: name, description: description, app: app, steps: steps, params: params, expect: checks.filter { !$0.isEmpty }, read: read,
                          runs: 0, ok: 0, failuresInARow: 0, lastStop: nil, lastMs: nil, savedBy: by, created: now, updated: now)
        var notes: [String] = []
        let points = steps.filter { s in s.target == nil && (s.action["tap"]?.array != nil || s.action["long_press"]?.array != nil) }.count
        if points > 0 { notes.append("\(points) step\(points == 1 ? "" : "s") tap a point, not an element: they replay at the same point whatever is there") }
        if steps.contains(where: { $0.secret == true }) { notes.append("a password typed in it was not kept: a run stops there for you to type it") }
        if skill.expect.isEmpty { notes.append("no end check could be chosen from the last screen; give expect: [\"text\"] to add one") }
        return (skill, notes.joined(separator: "; "))
    }

    func routine(named name: String, description: String, read: [String], expect: [String]?, by: String) -> (Skill?, String) {
        skill(named: name, description: description, read: read, expect: expect, by: by)
    }

    /// Drops a redundant tap on an already-focused text field right between typing and Return.
    static func withoutRefocusTaps(_ steps: [SkillStep]) -> [SkillStep] {
        steps.indices.compactMap { i in
            let step = steps[i]
            guard step.action["tap"] != nil, let target = step.target, fieldTypes.contains(target.type),
                  i > 0, steps[i - 1].action["type"] != nil, i + 1 < steps.count, isReturn(steps[i + 1].action) else { return step }
            let typedInto = steps[i - 1].target ?? (i > 1 && steps[i - 2].action["tap"] != nil ? steps[i - 2].target : nil)
            if let typedInto, typedInto.type != target.type || typedInto.label != target.label || typedInto.identifier != target.identifier { return step }
            return nil
        }
    }

    /// `{run: "name"}` or `{run: {name, with: {text_1: "…"}}}`: replays a saved skill's steps in order,
    /// waiting for each target on screen and stopping cleanly at the first screen that differs.
    func runSkill(_ spec: JSON, until: Double) async throws -> String {
        let name = spec.string ?? spec["name"]?.string ?? spec["skill"]?.string ?? ""
        guard let store = memory, let skill = store.skill(named: name) else {
            let known = memory?.skills.prefix(12).map { "\"\($0.name)\"" }.joined(separator: ", ") ?? ""
            throw ActionFailure(message: "no skill named \"\(name)\"\(known.isEmpty ? " (none are saved)" : "; saved: \(known)")", delivery: .notSent)
        }
        var params = skill.params
        if case .object(let given) = spec["with"] { for (k, v) in given { if let t = v.text { params[k] = t } } }
        let started = now()
        var log: [String] = []
        var done = 0
        let screen = size ?? ScreenSize(width: 10_000, height: 10_000)
        func finish(_ outcome: String, stop: SkillStop?) {
            let ms = Int(((now() - started) * 1000).rounded())
            store.update(skill.name) { r in
                r.runs += 1
                r.lastMs = ms
                if let stop { r.failuresInARow += 1; r.lastStop = stop } else { r.ok += 1; r.failuresInARow = 0 }
            }
            store.logRun(SkillRunLog(skill: skill.name, at: Date(), ms: ms, outcome: outcome, steps: log))
        }
        func stop(_ index: Int, _ why: String, _ delivery: Delivery = .notSent) -> ActionFailure {
            finish("stopped at step \(index + 1): \(why)", stop: SkillStop(step: index + 1, why: why, at: Date()))
            let sent = done == 0 ? "no step was sent" : "steps 1 to \(done) were sent"
            return ActionFailure(message: "run \"\(skill.name)\" stopped at step \(index + 1) of \(skill.steps.count): \(why); \(sent). Go on by hand from the screen below; when the task is done, skills {action: \"save\", name: \"\(skill.name)\"} saves the path that worked over this one", delivery: delivery)
        }

        var front = lastForeground
        if let app = skill.app, lastForeground?.bundleID != app, skill.steps.first?.action["launch"] == nil, !config.isPoki(Foreground(bundleID: app, name: nil)) {
            do {
                _ = try await perform(["launch": .string(app)], until: until)
                log.append("launched \(app)")
                front = Foreground(bundleID: app, name: nil)
            } catch { throw stop(0, "\(app) could not be launched (\(error))") }
        }

        var previous: String?
        for (index, step) in skill.steps.enumerated() {
            if step.secret == true { throw stop(index, "it types into a password field, which a skill never keeps: type it yourself") }
            var action = step.action
            if let text = action["type"]?.string, case .object(var o) = action {
                o["type"] = .string(text.replacingParams(params))
                action = .object(o)
            }
            var scan: SensitiveScan?
            if let target = step.target {
                let stepEnds = min(until, now() + config.actionCap)
                var found: Element?
                var why = "\(target.describe) is not on screen"
                var reads = 0
                var candidate: String?
                let readStart = now()
                while now() < stepEnds - 0.2 {
                    guard let tree = try? await runner.tree(timeout: min(config.readTimeout, max(0.3, stepEnds - now() - 0.1)), format: config.treeFormat) else { break }
                    reads += 1
                    let elements = listable(tree.elements, screen)
                    let signature = elements.map { "\($0.key)@\($0.frame.described)" }.joined(separator: ";")
                    let moved = previous == nil || signature != previous || now() - readStart > 0.8
                    lastAll = tree.elements
                    lastForeground = tree.foreground
                    let matches = elements.filter(target.matches)
                    if moved, !matches.isEmpty {
                        let layout = Layout(all: tree.elements, screen: screen)
                        let reachable = matches.filter { layout.touchPoint($0) != nil }
                        let near = reachable.sorted { hypot($0.frame.centre.x - target.x, $0.frame.centre.y - target.y) < hypot($1.frame.centre.x - target.x, $1.frame.centre.y - target.y) }
                        var pick: Element?
                        if near.count == 1 { pick = near[0] }
                        if near.count > 1 {
                            let d0 = hypot(near[0].frame.centre.x - target.x, near[0].frame.centre.y - target.y)
                            let d1 = hypot(near[1].frame.centre.x - target.x, near[1].frame.centre.y - target.y)
                            if d0 < 40, d1 > 2 * d0 + 20 { pick = near[0] }
                            why = "\(near.count) elements match \(target.describe) and none is clearly the recorded one"
                        } else { why = "\(target.describe) is listed but not where a tap reaches it" }
                        if let pick {
                            let here = "\(pick.key)@\(pick.frame.described)"
                            if here == candidate || now() - readStart > 1.5 { found = pick; break }
                            candidate = here
                            why = "\(target.describe) was still moving"
                            continue
                        }
                    }
                    candidate = nil
                    await sleep(seconds: 0.12)
                }
                guard let element = found else { throw stop(index, why + " (\(reads) reads in \(Int(((now() - readStart) * 1000).rounded())) ms)") }
                refs[Self.runRef] = element
                action = Self.replacingTarget(action, with: Self.runRef)
                front = lastForeground
                scan = SensitiveScan(front: lastForeground, secureOnScreen: lastAll.contains(where: \.isSecure))
            } else if config.sensitive.enabled, ActionKind(action)?.movesScreen == true {
                scan = SensitiveScan(front: front, read: false, secureOnScreen: false)
                if let tree = try? await runner.tree(timeout: min(config.readTimeout, max(0.3, until - now() - 0.1)), format: config.treeFormat) {
                    lastAll = tree.elements
                    lastForeground = tree.foreground
                    front = tree.foreground
                    let elements = listable(tree.elements, screen)
                    scan = SensitiveScan(front: front, secureOnScreen: elements.contains(where: \.isSecure), elements: elements)
                }
            }
            if var scan, let reason = sensitive(action, &scan) {
                refs[Self.runRef] = nil
                throw stop(index, "it needs the owner's approval (\(reason)); send it as an ordinary do so the owner is asked")
            }
            let began = now()
            let kind: String, text: String
            do { (kind, text) = try await perform(action, until: min(until, now() + config.actionCap)) }
            catch let failure as ActionFailure {
                refs[Self.runRef] = nil
                throw stop(index, failure.message, failure.delivery)
            } catch {
                refs[Self.runRef] = nil
                throw stop(index, "\(error)", .unknown)
            }
            refs[Self.runRef] = nil
            if let spec = action["launch"] { front = Foreground(bundleID: spec.string ?? spec["bundle"]?.string, name: nil) }
            done = index + 1
            log.append("\(index + 1) \(text.prefix(80)) (\(Int(((now() - began) * 1000).rounded())) ms)")
            var recorded = step
            recorded.app = lastForeground?.bundleID ?? step.app
            trace.append(RecordedStep(step: recorded, typed: kind == "type" ? action["type"]?.string : nil, keysBefore: []))
            previous = listable(lastAll, screen).map { "\($0.key)@\($0.frame.described)" }.joined(separator: ";")
            if kind == "type" || kind == "key" { previous = nil }
        }

        var outcome = "\(skill.steps.count) steps in \(Self.seconds(now() - started)) s"
        if !skill.expect.isEmpty || !skill.read.isEmpty {
            let checkEnds = min(until, now() + 3)
            var missing = skill.expect
            var values: [String] = []
            while now() < checkEnds {
                guard let tree = try? await runner.tree(timeout: min(config.readTimeout, max(0.3, checkEnds - now())), format: config.treeFormat) else { break }
                let texts = listable(tree.elements, screen)
                missing = skill.expect.filter { want in !texts.contains { $0.text.localizedCaseInsensitiveContains(want) } }
                values = skill.read.compactMap { label in
                    guard let e = texts.first(where: { $0.label?.caseInsensitiveCompare(label) == .orderedSame && !($0.value ?? "").isEmpty })
                        ?? texts.first(where: { ($0.label ?? "").localizedCaseInsensitiveContains(label) && ($0.label ?? "").count > label.count }) else { return nil }
                    if let v = e.value, !v.isEmpty { return "\(label) = \(v)" }
                    let rest = (e.label ?? "").replacingOccurrences(of: label, with: "", options: .caseInsensitive).trimmingCharacters(in: CharacterSet(charactersIn: " :,"))
                    return rest.isEmpty ? nil : "\(label) = \(rest)"
                }
                if missing.isEmpty && values.count == skill.read.count { break }
                await sleep(seconds: 0.15)
            }
            if !missing.isEmpty {
                let why = "the end check did not pass: \(missing.map { "\"\($0)\"" }.joined(separator: ", ")) not on screen"
                finish("ran, end check failed", stop: SkillStop(step: skill.steps.count, why: why, at: Date()))
                return "run \"\(skill.name)\": \(outcome), but \(why); look at the screen below before going on"
            }
            if !skill.expect.isEmpty { outcome += ", end check passed (\(skill.expect.map { "\"\($0)\"" }.joined(separator: ", ")) on screen)" }
            if !values.isEmpty { outcome += "; read: " + values.joined(separator: "; ") }
            else if !skill.read.isEmpty { outcome += "; the values to read (\(skill.read.joined(separator: ", "))) were not found: read them from the screen below" }
        }
        finish("ok", stop: nil)
        skillRanWhole = true
        return "run \"\(skill.name)\": \(outcome)"
    }

    func runRoutine(_ spec: JSON, until: Double) async throws -> String {
        try await runSkill(spec, until: until)
    }

    /// The number a run gives the element it found, for the one action it sends.
    static let runRef = 900_001

    static func replacingTarget(_ action: JSON, with ref: Int) -> JSON {
        guard case .object(var o) = action else { return action }
        for key in ["tap", "long_press"] {
            if o[key]?.string == "@" { o[key] = .number(Double(ref)) }
            else if case .object(var inner) = o[key], inner["ref"]?.string == "@" { inner["ref"] = .number(Double(ref)); o[key] = .object(inner) }
        }
        if o["ref"]?.string == "@" { o["ref"] = .number(Double(ref)) }
        return .object(o)
    }

    /// A new task: its recording starts empty.
    func beginRecording() {
        trace = []
        skillRanWhole = false
    }

    /// The skills saved for the app in front, for the first look of a task (nil when none).
    func skillsLine() -> String? {
        guard let memory else { return nil }
        let app = lastForeground?.bundleID
        let all = memory.skills.filter { !$0.stale }
        guard !all.isEmpty else { return nil }
        let here = all.filter { $0.app == app }
        let onHome = app == nil || app == "com.apple.springboard"
        guard !here.isEmpty || onHome else { return nil }
        let pool = here.isEmpty ? all : here
        let shown = pool.sorted { $0.updated > $1.updated }.prefix(6)
        let names = shown.map { "\"\($0.name)\"\($0.description.isEmpty ? "" : " (\($0.description.prefix(60)))")" }.joined(separator: ", ")
        return "skills\(here.isEmpty ? "" : " for this app"): \(names)\(pool.count > shown.count ? ", and \(pool.count - shown.count) more (skills {action: \"list\"})" : ""); do {run: \"name\"} repeats one in a single call"
    }
}

extension String {
    /// `{{name}}` replaced by the parameter's value.
    func replacingParams(_ params: [String: String]) -> String {
        var out = self
        for (k, v) in params { out = out.replacingOccurrences(of: "{{\(k)}}", with: v) }
        return out
    }
}

// MARK: The skills tool

extension PokiCore {
    /// What a model should know at the start of a task about this phone's owner and saved skills:
    /// the notes, and the skills that fit `task` and `apps` best. "" when nothing is saved.
    public static func memoryBrief(for task: String, app: String? = nil, apps: [String] = []) -> String {
        SkillStore.shared.brief(for: task, app: app, apps: apps)
    }

    static let skillsTool: JSON = [
        "name": "skills",
        "description": "The agent's memory library on this phone, shared by every agent that drives it. Skills are saved procedures in apps: the do actions of a task, each target kept as what it is (role and label), so do {run: \"name\"} replays it in one call, waits for each target, and stops cleanly at a screen that differs. Notes are short facts about the owner. action: list (skills and notes) | show (one skill's steps, name) | save (the do actions sent since this task began, as name, with description; expect: texts that must be on screen at the end, chosen from the last screen when left out; read: labels whose values a run reports) | edit (name; rename, description, expect, read, steps as JSON to replace them) | forget (name) | remember (text: a fact worth keeping, never a password) | forget_note (id or text) | export (the whole memory as JSON, to review or move) | import (data: such JSON; newer skills win). Save a skill after an app task that worked and that someone may ask for again; save it again under the same name to fix one that stopped.",
        "inputSchema": ["type": "object", "properties": [
            "action": ["type": "string", "enum": ["list", "show", "save", "edit", "forget", "remember", "forget_note", "export", "import"]],
            "name": ["type": "string"], "description": ["type": "string"], "rename": ["type": "string"],
            "text": ["type": "string"], "data": ["type": "string"],
            "expect": ["type": "array", "items": ["type": "string"]], "read": ["type": "array", "items": ["type": "string"]],
            "steps": ["type": "string"],
        ], "required": ["action"], "additionalProperties": false],
    ]

    func skillsCall(_ args: JSON, session: String?) -> ToolResult {
        guard let store = computer.memory else { return ToolResult(text: "skills: no memory on this phone", jpeg: nil, isError: true) }
        let action = args["action"]?.string ?? "list"
        let name = args["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let by = session == nil ? "Poki" : (clientNames.value[session!].flatMap { $0.isEmpty ? nil : $0 } ?? "an MCP client")
        func fail(_ text: String) -> ToolResult { ToolResult(text: "skills \(action): \(text)", jpeg: nil, isError: true) }
        switch action {
        case "list":
            let skills = store.skills, notes = store.notes
            var lines = ["skills (\(skills.count)):"] + skills.map { "- \($0.summary)" }
            if skills.isEmpty { lines = ["skills: none saved yet. After a task that worked, skills {action: \"save\", name, description} keeps its steps so do {run: name} repeats them in one call."] }
            lines.append(notes.isEmpty ? "notes: none" : "notes (\(notes.count)):")
            lines += notes.map { "- [\($0.id)] \($0.text) (by \($0.by))" }
            if !computer.trace.isEmpty { lines.append("this task has \(computer.trace.count) recorded steps so far (save keeps them)") }
            return ToolResult(text: lines.joined(separator: "\n"), jpeg: nil)
        case "show":
            guard let r = store.skill(named: name) else { return fail("no skill named \"\(name)\"") }
            var lines = [r.summary]
            for (i, s) in r.steps.enumerated() {
                lines.append("\(i + 1). \(s.action.serialized())\(s.target.map { " on \($0.describe) at [\(Int($0.x)), \(Int($0.y))]" } ?? "")\(s.app.map { " in \($0)" } ?? "")")
            }
            if !r.expect.isEmpty { lines.append("end check: " + r.expect.map { "\"\($0)\"" }.joined(separator: ", ")) }
            if !r.read.isEmpty { lines.append("reads: " + r.read.joined(separator: ", ")) }
            let compact = JSONEncoder(); compact.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; compact.dateEncodingStrategy = .iso8601
            let steps = (try? String(decoding: compact.encode(r.steps), as: UTF8.self)) ?? "[]"
            lines.append("steps as JSON (edit takes this shape): \(steps)")
            return ToolResult(text: lines.joined(separator: "\n"), jpeg: nil)
        case "save":
            guard !name.isEmpty else { return fail("give the skill a name") }
            let expect = args["expect"]?.array?.compactMap(\.string)
            let read = args["read"]?.array?.compactMap(\.string) ?? store.skill(named: name)?.read ?? []
            let (skill, note) = computer.skill(named: name, description: args["description"]?.string ?? store.skill(named: name)?.description ?? "", read: read, expect: expect, by: by)
            guard let skill else { return fail(note) }
            let replacing = store.skill(named: name) != nil
            store.save(skill)
            return ToolResult(text: "skills: \(replacing ? "saved over" : "saved") \"\(skill.name)\" (\(skill.steps.count) steps\(skill.app.map { " in \($0)" } ?? "")\(skill.params.isEmpty ? "" : "; it types " + skill.params.keys.sorted().joined(separator: ", ") + ", which with: changes")\(skill.expect.isEmpty ? "" : "; end check: " + skill.expect.map { "\"\($0)\"" }.joined(separator: ", "))). do {run: \"\(skill.name)\"} repeats it.\(note.isEmpty ? "" : " Note: \(note).")", jpeg: nil)
        case "edit":
            guard store.skill(named: name) != nil else { return fail("no skill named \"\(name)\"") }
            var newSteps: [SkillStep]?
            if let text = args["steps"]?.string {
                guard let steps = try? SkillStore.decoder.decode([SkillStep].self, from: Data(text.utf8)), !steps.isEmpty else { return fail("steps must be the JSON array show gives") }
                newSteps = steps
            }
            store.update(name) { r in
                if let d = args["description"]?.string { r.description = d }
                if let e = args["expect"]?.array { r.expect = e.compactMap(\.string) }
                if let e = args["read"]?.array { r.read = e.compactMap(\.string) }
                if let steps = newSteps {
                    r.steps = steps
                    if r.app == nil { r.app = Skill.inferredApp(from: steps) }
                    r.failuresInARow = 0
                    r.lastStop = nil
                }
                r.updated = Date()
            }
            if let rename = args["rename"]?.string, !rename.isEmpty { store.rename(name, to: rename) }
            return ToolResult(text: "skills: edited \"\(args["rename"]?.string ?? name)\"", jpeg: nil)
        case "forget":
            guard store.forget(name) else { return fail("no skill named \"\(name)\"") }
            return ToolResult(text: "skills: forgot \"\(name)\"", jpeg: nil)
        case "remember":
            let text = args["text"]?.string ?? ""
            guard let note = store.remember(text, by: by) else { return fail("give the text to remember") }
            return ToolResult(text: "skills: remembered [\(note.id)] \(note.text)", jpeg: nil)
        case "forget_note":
            guard store.forgetNote(args["text"]?.string ?? name) else { return fail("no such note") }
            return ToolResult(text: "skills: note forgotten", jpeg: nil)
        case "export":
            guard let data = try? store.exportData() else { return fail("could not be made") }
            return ToolResult(text: String(decoding: data, as: UTF8.self), jpeg: nil)
        case "import":
            guard let text = args["data"]?.string else { return fail("give data: the JSON export gives") }
            do {
                let summary = try store.importData(Data(text.utf8), by: by)
                return ToolResult(text: "skills: \(summary)", jpeg: nil)
            } catch { return fail("\(error)") }
        default:
            return fail("unknown action; the actions are list, show, save, edit, forget, remember, forget_note, export, import")
        }
    }
}
