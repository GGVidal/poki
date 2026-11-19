import Foundation
import PiSwiftAgent
import PiSwiftAI

/// What the model is sent of the conversation so far. Everything the owner asked, everything the model
/// said, planned and called, and what each call did stay as they were, for every provider. Only the
/// bulk of old screen reads goes: an old read keeps its header (the app, what each action did, whether
/// the screen changed) and loses its element list and its screenshot, which describe a screen that is
/// no longer there. Without this every read went back to the model on every later step of every later
/// task in the chat, so a chat's cost grew with the square of its steps.
///
/// The conversation the loop keeps is not changed, only the copy that is sent.
enum HistoryTrim {
    /// The newest reads of the task under way that always stay whole.
    static let keep = 3
    /// Older reads are cut this many at a time, so the sent history stays the same from step to step
    /// in between and the provider's prompt cache keeps matching it.
    static let step = 4
    /// A long answer without an element list (a web page read) keeps this much when it is old.
    static let plainLimit = 1500

    /// `taskStart` is the index of the first message of the task under way: reads before it belong to
    /// finished tasks and are all cut.
    static func trimmed(_ messages: [AgentMessage], taskStart: Int) -> [AgentMessage] {
        let reads = messages.indices.filter { index in
            if case .toolResult(let result) = messages[index] { return isBulky(result) }
            return false
        }
        guard !reads.isEmpty else { return messages }
        let current = reads.filter { $0 >= taskStart }
        let cutInTask = cutCount(current.count)
        let cut = Set(reads.filter { $0 < taskStart } + current.prefix(cutInTask))
        guard !cut.isEmpty else { return messages }
        var out = messages
        for index in cut {
            if case .toolResult(var result) = out[index] {
                result.content = shortened(result.content)
                out[index] = .toolResult(result)
            }
        }
        return out
    }

    /// How many of a task's `count` reads are cut: none until there are `keep + step`, then `step` more
    /// each time, so between `keep` and `keep + step - 1` whole reads are always in view.
    static func cutCount(_ count: Int) -> Int {
        max(0, (count - keep) / step * step)
    }

    private static func isBulky(_ result: ToolResultMessage) -> Bool {
        result.content.contains { block in
            switch block {
            case .image: return true
            case .text(let content): return elementsRange(content.text) != nil || content.text.count > plainLimit
            default: return false
            }
        }
    }

    private static func shortened(_ content: [ContentBlock]) -> [ContentBlock] {
        content.compactMap { block in
            switch block {
            case .image: return nil
            case .text(var content):
                content.text = shortened(content.text)
                return .text(content)
            default: return block
            }
        }
    }

    /// An old read's text: its header lines up to the element list, then one line in the list's place.
    static func shortened(_ text: String) -> String {
        if let range = elementsRange(text) {
            let lines = text[range.lowerBound...].split(separator: "\n", omittingEmptySubsequences: false).count - 1
            return text[..<range.lowerBound] + "[older read: its \(max(lines, 0)) element lines and its screenshot are left out. The screen has moved on since; element numbers still on screen are unchanged. Call look for the screen as it is now.]"
        }
        guard text.count > plainLimit else { return text }
        return text.prefix(plainLimit) + "… [older answer: the remaining \(text.count - plainLimit) characters are left out. Read it again if you need them.]"
    }

    /// Where a read's element list begins: the heading line PokiCore writes ("elements (42):",
    /// "elements, changed (3 of 42):"), which follows the header lines.
    private static func elementsRange(_ text: String) -> Range<String.Index>? {
        if text.hasPrefix("elements") { return text.startIndex..<text.startIndex }
        guard let found = text.range(of: "\nelements") else { return nil }
        let start = text.index(after: found.lowerBound)
        return start..<start
    }
}
