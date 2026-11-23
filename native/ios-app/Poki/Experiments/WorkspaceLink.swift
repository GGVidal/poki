#if POKI_EXPERIMENTS
import Foundation
import PokiCore
import SwiftUI

/// Experimental (issue #689, Poki Lab builds only): this Poki calls Poki on the owner's iPad, which
/// drives apps on its workspace display. The link is that iPad's own connector address, so the relay,
/// the secret and the iPad's approval rules are exactly those of any other agent of that iPad.
enum WorkspaceLinkStore {
    private static let account = "experiments.workspaceLink"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (text: String, link: WorkspaceLink)?

    /// The saved address, kept in the keychain since it holds the connector secret.
    static var address: WorkspaceLinkAddress? {
        guard let data = try? Keychain.read(account) else { return nil }
        return WorkspaceLinkAddress(String(decoding: data, as: UTF8.self))
    }

    /// Saves a valid address and answers true, or answers false and keeps what was there.
    @discardableResult
    static func save(_ text: String) -> Bool {
        guard let address = WorkspaceLinkAddress(text) else { return false }
        do { try Keychain.write(Data(address.url.absoluteString.utf8), account: account) } catch { return false }
        lock.withLock { cached = nil }
        return true
    }

    static func remove() {
        Keychain.delete(account)
        lock.withLock { cached = nil }
    }

    /// One link per address, so its MCP session is kept between calls.
    static var link: WorkspaceLink? {
        guard let address else { return nil }
        return lock.withLock {
            if let cached, cached.text == address.url.absoluteString { return cached.link }
            let link = WorkspaceLink(address: address)
            cached = (address.url.absoluteString, link)
            return link
        }
    }
}

/// The chat's tools for the linked iPad: the iPad's own look and do, renamed, with the same arguments.
enum WorkspaceTools {
    static let names: Set<String> = ["ipad_look", "ipad_do"]

    /// Declared only while a link is saved.
    static var specs: [ToolSpec] {
        guard WorkspaceLinkStore.address != nil else { return [] }
        return Harness.phoneTools.filter { $0.name == "look" || $0.name == "do" }.map {
            ToolSpec(name: "ipad_" + $0.name,
                     description: "On the owner's iPad, through Poki on the iPad: the same as \($0.name), but for apps on the iPad's workspace display, which the owner is not using. This iPhone's screen is left alone. " + $0.description,
                     schema: $0.schema)
        }
    }

    static var instructions: String {
        guard WorkspaceLinkStore.address != nil else { return "" }
        return """
        The owner linked Poki on their iPad. ipad_look and ipad_do read and operate apps on the iPad's workspace display, \
        a separate screen Poki owns there, so neither the iPad's own screen nor this iPhone's is disturbed. Use them when \
        the owner asks for something on the iPad, or when the task should run without taking over this iPhone. Launch \
        apps there with ipad_do and the iPad's bundle ids. They follow the same rules as look and do, and an action the \
        iPad holds for approval waits for the owner there.
        """
    }

    static func perform(_ name: String, arguments: String) async -> PokiCore.ToolAnswer {
        guard let link = WorkspaceLinkStore.link else {
            return PokiCore.ToolAnswer(text: "No iPad is linked. The owner adds the iPad's agent address in Settings, iPad Workspace.", jpeg: nil, isError: true)
        }
        return await link.call(String(name.dropFirst("ipad_".count)), arguments: arguments)
    }
}

/// Settings, iPad Workspace: paste the address of an agent made in Poki on the iPad, check it, remove it.
struct WorkspaceLinkView: View {
    var back: () -> Void
    @State private var text = ""
    @State private var rejected = false
    @State private var saved = WorkspaceLinkStore.address
    @State private var checking = false
    @State private var check: (ok: Bool, text: String)?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("https://poki-relay.you.workers.dev/v1/…/mcp", text: $text)
                    .font(.body.monospaced())
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done).onSubmit(save)
                Button("Paste Address") {
                    if let pasted = UIPasteboard.general.string { text = pasted; save() }
                }
            } header: {
                Text("iPad Agent Address")
            } footer: {
                if rejected {
                    Text("That is not an agent address from Poki on an iPad.").foregroundStyle(.red)
                } else {
                    Text("On the iPad, open Poki Lab, add an agent in Settings and copy its address. Poki on this iPhone can then use apps on the iPad workspace display while both screens stay free.")
                }
            }
            if let saved {
                Section("Status") {
                    LabeledContent("Linked iPad", value: saved.host)
                    Button(action: runCheck) {
                        if checking { ProgressView() } else { Text("Check Link") }
                    }
                    .disabled(checking)
                    if let check {
                        Label(check.ok ? AppLocalization.text(LocalizedStringResource("The iPad answered")) : check.text,
                              systemImage: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle")
                            .foregroundStyle(check.ok ? Color.green : Color.red)
                    }
                    Button("Remove Link", role: .destructive) {
                        WorkspaceLinkStore.remove()
                        self.saved = nil
                        text = ""
                        check = nil
                    }
                }
            }
        }
        .navigationTitle(AppLocalization.text("iPad Workspace"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        .onAppear { if saved == nil { focused = true } }
    }

    private func save() {
        rejected = !WorkspaceLinkStore.save(text)
        if !rejected {
            saved = WorkspaceLinkStore.address
            text = ""
            focused = false
            check = nil
        }
    }

    private func runCheck() {
        guard let link = WorkspaceLinkStore.link else { return }
        checking = true
        Task {
            let answer = await link.call("status", arguments: "{}", timeout: 20)
            check = (!answer.isError, answer.text)
            checking = false
        }
    }
}
#endif
