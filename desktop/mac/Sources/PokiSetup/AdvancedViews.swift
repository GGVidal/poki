import AppKit
import SwiftUI

// MARK: Relay

struct RelayView: View {
    @EnvironmentObject var model: AppModel
    @State private var token = ""
    @State private var accounts: [CloudflareAccount] = []
    @State private var accountID = ""
    @State private var working = false
    @State private var error: String?
    @State private var relayUp: Bool?
    @State private var worker: WorkerStatus?
    @State private var tokenSaved = false

    var body: some View {
        Form {
            HeroSection {
                PageHero(symbol: "point.3.connected.trianglepath.dotted", title: "Relay", subtitle: "Lets AI apps reach your iPhone from anywhere. A small Cloudflare Worker in your own account that passes messages along and stores nothing. The free plan is enough.")
            }
            if let d = model.relay {
                Section(L10n.tr("Your Relay")) {
                    LabeledContent(L10n.tr("Address")) { Text(d.address).foregroundStyle(.secondary).textSelection(.enabled) }
                    LabeledContent(L10n.tr("Cloudflare Account")) { Text(d.accountName).foregroundStyle(.secondary) }
                    LabeledContent(L10n.tr("Status")) {
                        HStack(spacing: 8) {
                            switch relayUp {
                            case .some(true): Label(L10n.tr("Answering"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .some(false): Label(L10n.tr("Not answering"), systemImage: "xmark.circle.fill").foregroundStyle(.red)
                            case .none: EmptyView()
                            }
                            Button(L10n.tr("Check")) { Task { await check(d.address) } }
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        QRCode(text: d.phoneLink, size: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Give the address to Poki")).font(.headline)
                            Text(L10n.tr("Scan this with the iPhone's Camera. Poki opens and starts using this relay."))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(L10n.tr("Copy Link")) { copyToPasteboard(d.phoneLink) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let w = worker {
                Section {
                    LabeledContent(L10n.tr("Relay Code")) {
                        Text(w.source == "built in" ? L10n.tr("Built into Poki Setup") : L10n.fmt("From release %@", w.source)).foregroundStyle(.secondary)
                    }
                    if w.updateAvailable {
                        Label(L10n.tr("Relay update available. Update Relay below to match your Poki."), systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.pokiBlue)
                    }
                    HStack {
                        if let u = URL(string: w.downloadUrl) { Link(L10n.tr("Download worker.js"), destination: u) }
                        Spacer()
                        if let u = URL(string: w.guideUrl) { Link(L10n.tr("Deploy It Yourself…"), destination: u) }
                    }
                } footer: {
                    Text(L10n.tr("Poki Setup deploys the relay from the same release as the Poki on your iPhone, checked against that release's SHA256SUMS."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if tokenSaved {
                    LabeledContent(L10n.tr("Cloudflare API Token")) {
                        HStack {
                            Text(L10n.tr("Saved in Keychain")).foregroundStyle(.secondary)
                            Button(L10n.tr("Forget")) { Task { _ = try? await model.bridge.call("relay_forget_token", as: Bool?.self); tokenSaved = false; accounts = [] } }
                        }
                    }
                } else {
                    SecureField(L10n.tr("Cloudflare API Token"), text: $token, prompt: Text(L10n.tr("Paste the token")))
                }
                if !accounts.isEmpty {
                    Picker(L10n.tr("Account"), selection: $accountID) {
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                }
                if let s = model.steps["relay"], !s.isEmpty { StepsView(steps: s) }
                HStack {
                    Link(L10n.tr("Create a token…"), destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if accounts.isEmpty {
                        Button(L10n.tr("Continue")) { Task { await loadAccounts() } }.disabled((token.isEmpty && !tokenSaved) || working)
                    } else {
                        Button(L10n.tr(model.relay == nil ? "Deploy Relay" : "Update Relay")) { Task { await deploy() } }
                            .pokiProminentButton()
                            .disabled(accountID.isEmpty || working)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            } header: {
                Text(L10n.tr(model.relay == nil ? "Deploy" : "Redeploy"))
            } footer: {
                Text(L10n.tr("Use the “Edit Cloudflare Workers” template. Poki Setup keeps the token in your Keychain, so you can update the relay later without pasting it again."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .pokiPage()
        .task {
            if let d = model.relay, !model.demo { await check(d.address) } else if model.demo { relayUp = true }
            if !model.demo {
                tokenSaved = (try? await model.bridge.call("relay_token_saved")) ?? false
                worker = try? await model.bridge.call("relay_worker")
            }
        }
    }

    private func loadAccounts() async {
        working = true
        error = nil
        defer { working = false }
        do {
            var args: [String: Any?] = [:]
            if !token.isEmpty { args["token"] = token }
            accounts = try await model.bridge.call("relay_accounts", args)
            accountID = accounts.first?.id ?? ""
            if accounts.isEmpty { error = "This token can't see any Cloudflare account." }
        } catch { self.error = error.localizedDescription }
    }

    private var deployArgs: [String: Any?] {
        var args: [String: Any?] = ["account_id": accountID]
        if !token.isEmpty { args["token"] = token }
        return args
    }

    private func deploy() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let d: Deployed = try await model.job("relay") { try await model.bridge.call("relay_deploy", deployArgs) }
            model.relay = d
            worker = try? await model.bridge.call("relay_worker")
            tokenSaved = (try? await model.bridge.call("relay_token_saved")) ?? false
            token = ""
            accounts = []
            await check(d.address)
        } catch { self.error = error.localizedDescription }
    }

    private func check(_ address: String) async {
        relayUp = try? await model.bridge.call("relay_check", ["address": address])
    }
}

// MARK: Connectors

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var streaming = false
    @State private var showHelperLog = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.tr("iPhone Log")) {
                    HStack {
                        TextField(L10n.tr("Filter"), text: $filter, prompt: Text("Poki"))
                            .frame(maxWidth: 220)
                        Spacer()
                        Button(L10n.tr(streaming ? "Stop" : "Start")) { Task { await toggle() } }
                            .disabled(model.selectedPhone == nil && !streaming)
                        Button(L10n.tr("Clear")) { model.logLines.removeAll() }
                        Button(L10n.tr("Copy")) { copyToPasteboard(model.logLines.joined(separator: "\n")) }
                    }
                }
                Section(L10n.tr("Tools")) {
                    LabeledContent(L10n.tr("Developer Disk Image")) {
                        Button(L10n.tr("Mount")) { Task { await mount() } }.disabled(model.selectedPhone == nil || model.busyJobs.contains("ddi"))
                    }
                    LabeledContent(L10n.tr("Support Bundle")) {
                        Button(L10n.tr("Save…")) { Task { await saveBundle() } }
                    }
                    LabeledContent(L10n.tr("Helper Log")) {
                        Button(L10n.tr(showHelperLog ? "Hide" : "Show")) { showHelperLog.toggle() }
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            .pokiPage()
            .scrollDisabled(true)
            .frame(height: message == nil ? 318 : 350)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    let lines = showHelperLog ? model.bridge.helperLog : model.logLines
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.suffix(2000).enumerated()), id: \.offset) { i, l in
                            Text(l).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    if (showHelperLog ? model.bridge.helperLog : model.logLines).isEmpty {
                        Text(L10n.tr(showHelperLog ? "The helper has not logged anything yet." : (model.selectedPhone == nil ? "Connect an iPhone to see its log here." : "Press Start to see the iPhone's log here.")))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: model.logLines.count) { _, _ in proxy.scrollTo(min(model.logLines.count, 2000) - 1, anchor: .bottom) }
            }
        }
    }

    private func toggle() async {
        do {
            if streaming {
                try await model.bridge.run("logs_stop")
                streaming = false
            } else if let p = model.selectedPhone {
                try await model.bridge.run("logs_start", ["udid": p.id, "filter": filter.isEmpty ? nil : filter])
                streaming = true
            }
        } catch { model.report(error) }
    }

    private func mount() async {
        guard let p = model.selectedPhone else { return }
        do {
            try await model.mountDDI(udid: p.id)
            message = L10n.tr("The Developer Disk Image is mounted.")
        } catch { model.report(error) }
    }

    private func saveBundle() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L10n.tr("Save Here")
        panel.message = L10n.tr("Support bundles can contain device identifiers, local paths and raw logs. Review the archive before sharing.")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let path: String = try await model.bridge.call("support_bundle", ["udid": model.selectedPhone?.id, "out_dir": dir.path])
            message = L10n.fmt("Saved %@. Review the archive before sharing.", path)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } catch { model.report(error) }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var choice = ""
    @State private var custom = ""
    @State private var message: String?

    private let customTag = "custom"
    private let systemTag = "system"

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("Identity Server"), selection: $choice) {
                    ForEach(model.info?.anisetteServers ?? [], id: \.self) { u in
                        Text(URL(string: u)?.host ?? u).tag(u)
                    }
                    if model.info?.canUseSystemAnisette == true { Text(L10n.tr("This Mac (macOS 26 and earlier)")).tag(systemTag) }
                    Text(L10n.tr("Other…")).tag(customTag)
                }
                if choice == customTag {
                    TextField(L10n.tr("Server Address"), text: $custom, prompt: Text("https://"))
                }
                HStack {
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button(L10n.tr("Apply")) { Task { await apply() } }
                }
            } header: {
                Text(L10n.tr("Sign-In"))
            } footer: {
                Text(L10n.tr("Apple's sign-in wants proof that it talks to a Mac or PC (“anisette”). A server provides it; it never sees your Apple Account or password. If sign-in fails, try another one."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(L10n.tr("About")) {
                LabeledContent(L10n.tr("Version")) { Text(displayVersion(model.info?.version ?? "")).foregroundStyle(.secondary) }
            }
            Section(L10n.tr("Data")) {
                LabeledContent(L10n.tr("Folder")) {
                    Button(L10n.tr("Show in Finder")) {
                        if let d = model.info?.dataDir { NSWorkspace.shared.open(URL(fileURLWithPath: d)) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear(perform: load)
    }

    private func load() {
        guard let src = model.account?.anisette else { choice = model.info?.defaultAnisette ?? ""; return }
        if src.kind == "system" {
            choice = systemTag
        } else if let u = src.url, (model.info?.anisetteServers ?? []).contains(u) {
            choice = u
        } else {
            choice = customTag
            custom = src.url ?? ""
        }
    }

    private func apply() async {
        let src: AnisetteSource = choice == systemTag ? .system : .remote(choice == customTag ? custom : choice)
        do {
            try await model.setAnisette(src)
            message = L10n.tr("Saved.")
        } catch { message = error.localizedDescription }
    }
}
