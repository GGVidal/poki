import Foundation
import PokiCore

/// Habits Poki learns from Screen History: today only the music app the owner uses most.
///
/// Nothing is stored. The habit is worked out on this iPhone each time it is needed, from which app
/// was in front and when (`MusicHabitEvaluator`), so deleting history deletes its evidence with it
/// and no copy outlives the switches. It is not a note: it stays out of Memory's export, the
/// computer's backup and what connected agents read. The model sees it only for a request about
/// music, as one line in that task's instructions.
@MainActor
enum ScreenHabits {
    private static let forgottenKey = "history.habitsForgottenAt"

    /// Both switches are on: Screen History, and Learn Habits from Screen History.
    static var isOn: Bool {
        let capture = HistoryCapture.shared
        return capture.enabled && capture.learnHabits
    }

    /// Reads kept before this never count again (turning a switch off, or Forget on the Memory page).
    static var forgottenAt: Date? {
        UserDefaults.standard.object(forKey: forgottenKey) as? Date
    }

    /// The owner's usual music app, or nil while learning is off or the evidence falls short.
    static func musicApp(now: Date = Date()) -> InferredMusicAppHabit? {
        guard isOn else { return nil }
        let capture = HistoryCapture.shared
        let since = now.addingTimeInterval(-MusicHabitEvaluator.windowSeconds - 3600)
        let inputs = HistoryStore.shared.habitInputs(since: since)
        return MusicHabitEvaluator.evaluate(observations: inputs.observations, agentSpans: inputs.spans,
                                            watermarkAt: forgottenAt, keepsApp: { capture.keeps($0) }, now: now)
    }

    /// Forgets what was learned. Uses kept so far are never counted again, after a restart too.
    static func forget(at now: Date = Date()) {
        let at = max(now, forgottenAt ?? now)
        UserDefaults.standard.set(at, forKey: forgottenKey)
    }

    // MARK: Agents' own launches

    /// A use of a music app that starts within this long after an agent opened or used it is the
    /// agent's, not the owner's.
    nonisolated static let agentShadow: TimeInterval = 30 * 60

    /// From the phone core: an agent launched, used or left `bundleID`. Only music apps are noted.
    nonisolated static func agentActivity(_ bundleID: String, _ phase: AgentAppActivityPhase, _ at: Date) {
        guard HistoryCapture.isEnabled, let app = MusicAppCatalog.canonicalBundleID(for: bundleID) else { return }
        HistoryStore.shared.markAgent(app: app, from: at.addingTimeInterval(-5), to: at.addingTimeInterval(agentShadow))
    }

    // MARK: The chat

    /// Words that make a request about music, in the languages Poki speaks.
    private static let musicWords = ["歌", "音乐", "音樂", "曲", "专辑", "專輯", "听", "聽", "music", "song", "track", "album", "playlist", "tune"]

    static func isAboutMusic(_ task: String) -> Bool {
        let lower = task.lowercased()
        return musicWords.contains { lower.contains($0) }
    }

    /// Names that mean one music app. Plain "Music" and 音乐 are left out: they ask for music, not for
    /// Apple's app.
    private static let musicAppNames: [String] = {
        let generic: Set<String> = ["music", "音乐", "音樂"]
        let known = MusicAppCatalog.allCanonicalIDs.flatMap { KnownApps.find($0)?.names ?? [] }
        let more = ["Apple Music", "Apple 音乐", "Apple 音樂", "网易云", "網易雲", "QQ Music", "酷狗", "Kugou", "酷我", "Kuwo",
                    "汽水音乐", "汽水音樂", "Spotify", "YouTube Music", "Apple Music Classical"]
        return Array(Set((known + more).map { $0.lowercased() }).subtracting(generic))
    }()

    /// The owner's saved notes, as the app's own copy of PokiCore holds them.
    static var memory: RoutineStore { RoutineStore.shared }

    /// Whether `text` names a music app.
    static func namesMusicApp(_ text: String) -> Bool {
        let lower = text.lowercased()
        return musicAppNames.contains { lower.contains($0) }
    }

    /// The line a music request's instructions carry, or nil. The owner's own choice comes first: a
    /// music app named in the request, then a saved note naming one. Either way the guess is left out,
    /// so it cannot win over them, and a "from now on" request can be saved.
    static func instructions(for task: String) -> String? {
        guard isAboutMusic(task), !namesMusicApp(task),
              !memory.notes.contains(where: { namesMusicApp($0.text) }),
              let habit = musicApp() else { return nil }
        let id = habit.bundleID
        let known = KnownApps.find(id)
        let names = known.map { $0.names.joined(separator: " / ") } ?? id
        return """
        The owner's usual music app, worked out on this iPhone from Screen History because the owner turned on Learn Habits: \(names), bundle id \(id) (\(habit.activeSessionCount) uses on \(habit.distinctDayCount) days in the last two weeks). \
        When the owner asks to play music, a song, a singer or a playlist and names no app, play it in this app: start with do {launch: "\(id)"}. \
        A music app the owner names in this message comes first, and that choice is for this time only. A saved note naming the owner's music app also comes before this guess. \
        If this app is not installed, needs sign-in or cannot play, say so and ask which app to use; do not switch on your own. \
        This is a guess from Screen History, not a saved preference: do not save it, or a routine for this task, with routines.
        """
    }
}
