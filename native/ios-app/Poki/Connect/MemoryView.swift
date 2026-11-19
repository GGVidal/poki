import PokiCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Memory: the routines agents saved on this iPhone (each repeats a task in one call) and
/// the owner's notes, both shared by Poki's own chat and every connected agent. Export and Import move
/// them between iPhones as one file; Poki Setup on the computer keeps the same file as a backup.
/// The maintainers' run log is on Settings › Advanced; the archived conversations have their own row on
/// the settings home.
struct MemoryView: View {
    var back: () -> Void
    @State private var routines: [Routine] = []
    @State private var notes: [MemoryNote] = []
    @State private var newNote = ""
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var confirmClear = false
    private let store = RoutineStore.shared

    var body: some View {
        Form {
            Section {
                if routines.isEmpty { Text("None yet").foregroundStyle(Color(.secondaryLabel)) }
                ForEach(routines, id: \.name) { r in
                    RoutineRow(routine: r)
                        .swipeActions { Button("Forget", role: .destructive) { _ = store.forget(r.name); reload() } }
                }
            } header: {
                SettingsHeader("Skills")
            } footer: {
                Text("When a task succeeds, an agent saves a skill to repeat it in one step next time, and stops if the screen changes. Swipe to forget.")
            }

            Section {
                ForEach(notes, id: \.id) { n in
                    LabeledContent(n.text, value: n.by)
                        .swipeActions { Button("Forget", role: .destructive) { _ = store.forgetNote(n.id); reload() } }
                }
                HStack {
                    TextField("e.g., Mom is “Mama” in Contacts", text: $newNote).submitLabel(.done).onSubmit(addNote)
                    Button("Add", action: addNote).disabled(!canAdd)
                }
            } header: {
                SettingsHeader("Notes")
            } footer: {
                Text("Every agent sees these notes before a task. They stay on this iPhone.")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { SettingsRow(title: "Export Memory", symbol: "square.and.arrow.up") }
                }
                Button { importing = true } label: { SettingsRow(title: "Import Memory", symbol: "square.and.arrow.down") }
            } header: {
                SettingsHeader("Move or Back Up")
            } footer: {
                Text(message ?? AppLocalization.text(LocalizedStringResource("Exports all skills and notes into a single file. Importing merges entries and keeps newer versions. You can also back up and restore data using Poki Setup on your computer.")))
            }

            Section {
                Button(role: .destructive) { confirmClear = true } label: {
                    Text("Clear Memory").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .accessibilityIdentifier("memory.clear")
            }
        }
        .navigationTitle(AppLocalization.text("Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    message = try store.importData(data, by: "import")
                } catch {
                    message = AppLocalization.text(LocalizedStringResource("That file could not be imported: \(String(describing: error))"))
                }
                reload()
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Clear all skills and notes on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Memory", role: .destructive) { store.clearAll(); reload() }
        }
    }

    private var canAdd: Bool { !newNote.trimmingCharacters(in: .whitespaces).isEmpty }

    private func addNote() {
        guard canAdd else { return }
        _ = store.remember(newNote.trimmingCharacters(in: .whitespaces), by: "owner")
        newNote = ""
        reload()
    }

    /// Reads the store again and writes the export to tmp for the share sheet.
    private func reload() {
        routines = store.routines.sorted { $0.updated > $1.updated }
        notes = store.notes
        let tmp = FileManager.default.temporaryDirectory
        let export = tmp.appendingPathComponent(RoutineStore.backupName)
        if let data = try? store.exportData(), (try? data.write(to: export, options: .atomic)) != nil { exportURL = export }
    }
}

/// A routine: its name, how many steps, how often it worked, and a flag when it stopped twice in a row.
private struct RoutineRow: View {
    var routine: Routine
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: routine.name).fontWeight(.semibold)
                Text(detail).font(.footnote).foregroundStyle(routine.stale ? Color.red : Color.secondary)
            }
            Spacer()
            if let ms = routine.lastMs {
                Text(verbatim: String(format: "%.1f s", Double(ms) / 1000)).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private var appName: String {
        guard let app = routine.app, !app.isEmpty else {
            return AppLocalization.text(LocalizedStringResource("Other"))
        }
        return AppIconStore.name(app) ?? app
    }

    private var detail: String {
        let sep = AppLocalization.locale.language.languageCode?.identifier == "zh" ? "，" : ", "
        let steps = AppLocalization.text(LocalizedStringResource("\(routine.steps.count) steps"))
        let runs = routine.runs == 0 ? AppLocalization.text(LocalizedStringResource("not run yet")) : AppLocalization.text(LocalizedStringResource("worked \(routine.ok) of \(routine.runs)"))
        let base = [appName, steps, runs, routine.savedBy].joined(separator: sep)
        return routine.stale ? AppLocalization.text(LocalizedStringResource("Needs redoing: stopped twice in a row")) + sep + base : base
    }
}
