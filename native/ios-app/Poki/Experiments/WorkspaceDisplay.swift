#if POKI_EXPERIMENTS
import SwiftUI

/// Experimental (issue #689, Poki Lab builds only, unverified on hardware): on iPad, choose a second
/// display as Poki's workspace. While one is chosen, Poki's reads and touches go there and nowhere
/// else. Off at every launch, and a display is used only once the owner picks it here, so a display
/// the owner connects for themselves is left alone.
struct WorkspaceDisplayView: View {
    var back: () -> Void
    @State private var displays: [[String: Any]] = []
    @State private var chosen: Int64?
    @State private var report: String?
    @State private var checking = false
    private static let queue = DispatchQueue(label: "poki.lab.display")

    private var others: [(id: Int64, width: Int, height: Int)] {
        displays.compactMap { row in
            guard (row["main"] as? Bool) == false, let id = (row["id"] as? NSNumber)?.int64Value else { return nil }
            return (id, (row["width"] as? NSNumber)?.intValue ?? 0, (row["height"] as? NSNumber)?.intValue ?? 0)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Workspace Display", selection: Binding(get: { chosen }, set: choose)) {
                    Text("Off").tag(Int64?.none)
                    ForEach(others, id: \.id) { display in
                        Text("Display \(display.id) \(display.width) × \(display.height)").tag(Int64?.some(display.id))
                    }
                }
            } footer: {
                Text("Experimental. Poki works only on the display you choose here and never on this iPad’s own screen. A display you connect is left alone until you choose it.")
            }
            Section {
                Button(action: check) {
                    if checking { ProgressView() } else { Text("Check Displays") }
                }
                .disabled(checking)
                if let report {
                    Text(verbatim: report).font(.footnote.monospaced()).textSelection(.enabled)
                }
            } footer: {
                Text("Shows each display Poki can see and whether it shows a picture. Share the result with the Poki team.")
            }
        }
        .navigationTitle(AppLocalization.text("Workspace Display"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let (rows, current) = await withCheckedContinuation { (c: CheckedContinuation<([[String: Any]], Int64?), Never>) in
            Self.queue.async { c.resume(returning: (PKInProcess.shared().labDisplays(), PKInProcess.shared().labDisplayID?.int64Value)) }
        }
        displays = rows
        chosen = current
    }

    private func choose(_ id: Int64?) {
        chosen = id
        Self.queue.async { PKInProcess.shared().labDisplayID = id.map { NSNumber(value: $0) } }
    }

    private func check() {
        checking = true
        Task {
            let result = await withCheckedContinuation { (c: CheckedContinuation<[String: Any], Never>) in
                Self.queue.async { c.resume(returning: PKInProcess.shared().labDisplayCheck()) }
            }
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            report = data.map { String(decoding: $0, as: UTF8.self) } ?? "\(result)"
            checking = false
            await load()
        }
    }
}
#endif
