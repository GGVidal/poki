import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var ipa: URL?
    @State private var choosingIPA = false
    @State private var handOff = false
    @State private var result: InstallAnswer?
    @State private var failed: String?
    /// Set when the Apple Account is at its certificate limit: the question to put to the person.
    @State private var certificateQuestion: String?
    @State private var checking = false
    @State private var channelError: String?
    @State private var modelKey = ""
    @State private var sendingModelKey = false
    @State private var modelKeyStatus: String?

    private var installing: Bool { model.busyJobs.contains("install") }

    var body: some View {
        Form {
            HeroSection {
                PageHero(symbol: nil, title: "Set Up Poki", subtitle: "Plug in your iPhone with a USB cable and follow the next step below. No command line, VPN or AI agent is needed.")
            }
            if let snap = model.wizard {
                wizardSection(snap)
            }
            phoneSection
            accountSection
            appSection
            modelKeySection
            if let steps = model.steps["install"], !steps.isEmpty {
                Section(L10n.tr("Progress")) { StepsView(steps: steps) }
            }
            if let result { resultSection(result) }
        }
        .pokiPage()
        .task {
            await model.refreshChannels()
            await model.refreshWizard()
        }
        .alert(L10n.tr("Replace the Certificate?"), isPresented: Binding(get: { certificateQuestion != nil }, set: { if !$0 { certificateQuestion = nil } })) {
            Button(L10n.tr("Replace Certificate"), role: .destructive) {
                Task {
                    do {
                        try await model.approveCertificateReplacement()
                        await install()
                    } catch { model.report(error) }
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(certificateQuestion ?? "")
        }
        .fileImporter(isPresented: $choosingIPA, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { r in
            if case .success(let url) = r { ipa = url }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await install() }
                } label: {
                    Label(L10n.tr("Install Poki"), systemImage: "arrow.down.app")
                }
                .disabled(!canInstall)
                .help(L10n.tr("Sign Poki with your Apple Account and install it on the iPhone"))
            }
        }
    }

    // MARK: Next Step Wizard

    @ViewBuilder private func wizardSection(_ snap: WizardSnapshot) -> some View {
        Section(L10n.tr("Next Step")) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: wizardSymbol(snap.state))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(wizardColor(snap.state))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(wizardTitle(snap)).font(.headline)
                    Text(wizardInstruction(snap))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure = snap.failure, snap.state == .signingFailed || snap.state == .installFailed {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    wizardActions(snap)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            if let s = model.steps["ddi"], !s.isEmpty, model.busyJobs.contains("ddi") {
                StepsView(steps: s)
            }
        }
    }

    private func wizardSymbol(_ state: WizardStateId) -> String {
        switch state {
        case .deviceDisconnected: "cable.connector"
        case .deviceUntrusted: "hand.tap.fill"
        case .developerModeOff: "hammer.fill"
        case .accountSignedOut: "person.crop.circle.badge.exclamationmark"
        case .readyToInstall: "arrow.down.app.fill"
        case .signingFailed, .installFailed: "exclamationmark.triangle.fill"
        case .ddiUnmounted: "externaldrive.badge.plus"
        case .appUntrusted: "checkmark.shield"
        case .pokiNotStarted: "iphone.and.arrow.forward"
        case .completed: "checkmark.seal.fill"
        }
    }

    private func wizardColor(_ state: WizardStateId) -> Color {
        switch state {
        case .completed: .green
        case .signingFailed, .installFailed: .red
        case .deviceUntrusted, .developerModeOff, .ddiUnmounted, .appUntrusted: .orange
        default: .pokiBlue
        }
    }

    private func wizardTitle(_ snap: WizardSnapshot) -> String {
        switch snap.state {
        case .deviceDisconnected: L10n.tr("1. Connect your iPhone over USB")
        case .deviceUntrusted: L10n.tr("2. Trust this Mac on your iPhone")
        case .developerModeOff: L10n.tr("3. Turn on Developer Mode on your iPhone")
        case .accountSignedOut: L10n.tr("4. Sign in with your Apple Account")
        case .readyToInstall: L10n.tr("4. Ready to install Poki")
        case .signingFailed: L10n.tr("Signing Poki did not finish")
        case .installFailed: L10n.tr("Installing Poki did not finish")
        case .ddiUnmounted: L10n.tr("Restore the Developer Disk Image")
        case .appUntrusted: L10n.tr("5. Trust your Developer App certificate on iPhone")
        case .pokiNotStarted: L10n.tr("5. Open Poki on your iPhone")
        case .completed: L10n.tr("Poki is ready on your iPhone")
        }
    }

    private func wizardInstruction(_ snap: WizardSnapshot) -> String {
        switch snap.state {
        case .deviceDisconnected:
            return L10n.tr("Plug your iPhone into this Mac with a USB cable and unlock the screen. This page advances automatically.")
        case .deviceUntrusted:
            return L10n.tr("Unlock your iPhone, tap Trust in the “Trust This Computer?” alert, and enter your iPhone passcode. This page advances automatically.")
        case .developerModeOff:
            return L10n.tr("On your iPhone, open Settings > Privacy & Security > Developer Mode, turn it on, restart the iPhone, and tap Turn On after it restarts.")
        case .accountSignedOut:
            return L10n.tr("Sign in with any Apple Account (a free account works). Poki Setup signs Poki, installs it, and mounts the Developer Disk Image automatically.")
        case .readyToInstall:
            return L10n.tr("Click Install Poki. Poki Setup signs the app, installs it over USB, and mounts the Developer Disk Image in one step.")
        case .signingFailed:
            return L10n.tr("Check the message below, then retry signing and installing.")
        case .installFailed:
            return L10n.tr("Keep the iPhone unlocked and connected over USB, then retry installing.")
        case .ddiUnmounted:
            return L10n.tr("Your iPhone restarted or has not mounted the Developer Disk Image yet. Click Restore Developer Disk Image while connected over USB.")
        case .appUntrusted:
            let account = snap.accountAppleId ?? L10n.tr("your Apple Account")
            return L10n.fmt("On your iPhone, open Settings > General > VPN & Device Management, tap %@, and tap Trust. Then open Poki.", account)
        case .pokiNotStarted:
            return L10n.tr("Tap Poki on your iPhone Home Screen while still connected over USB. If you have not trusted your developer certificate yet, open Settings > General > VPN & Device Management first.")
        case .completed:
            return L10n.tr("Poki is installed, the Developer Disk Image is mounted, and Poki has started on your iPhone.")
        }
    }

    @ViewBuilder private func wizardActions(_ snap: WizardSnapshot) -> some View {
        switch snap.state {
        case .deviceUntrusted:
            if let udid = snap.selectedUdid {
                Button(L10n.tr("Ask iPhone to Trust Again")) {
                    Task { await run { try await model.pair(udid: udid) } }
                }
                .disabled(model.busyJobs.contains("pair"))
                .padding(.top, 4)
            }
        case .developerModeOff:
            if let udid = snap.selectedUdid {
                Button(L10n.tr("Reveal Developer Mode in Settings")) {
                    Task { await run { try await model.enableDeveloperMode(udid: udid) } }
                }
                .disabled(model.busyJobs.contains("devmode"))
                .padding(.top, 4)
            }
        case .accountSignedOut:
            Button(L10n.tr("Sign In…")) { model.page = .account }
                .pokiProminentButton()
                .padding(.top, 4)
        case .readyToInstall:
            Button(L10n.tr(installing ? "Installing…" : "Install Poki")) {
                Task { await install() }
            }
            .pokiProminentButton()
            .disabled(!canInstall)
            .padding(.top, 4)
        case .signingFailed, .installFailed:
            HStack(spacing: 8) {
                Button(L10n.tr("Retry Install")) {
                    Task {
                        await model.clearWizardFailure()
                        await install()
                    }
                }
                .pokiProminentButton()
                .disabled(!canInstall)
                if snap.failure?.kind == "auth" || snap.failure?.kind == "needs_code" {
                    Button(L10n.tr("Open Apple Account")) { model.page = .account }
                }
                Button(L10n.tr("Dismiss")) {
                    Task { await model.clearWizardFailure() }
                }
            }
            .padding(.top, 4)
        case .ddiUnmounted:
            if let udid = snap.selectedUdid {
                Button(L10n.tr("Restore Developer Disk Image")) {
                    Task { await run { try await model.mountDDI(udid: udid) } }
                }
                .pokiProminentButton()
                .disabled(model.busyJobs.contains("ddi"))
                .padding(.top, 4)
            }
        default:
            EmptyView()
        }
    }

    // MARK: iPhone

    @ViewBuilder private var phoneSection: some View {
        Section {
            if let err = model.phonesError {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("Poki Setup can't see iPhones right now"))
                        Text(err.message).font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cable.connector.slash").foregroundStyle(.orange)
                }
            } else if model.phones.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.pokiBlue)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("Connect your iPhone")).font(.headline)
                        Text(L10n.tr("Use a cable, unlock the iPhone and tap Trust when it asks."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView().controlSize(.small)
                }
                .padding(.vertical, 4)
            } else {
                if model.phones.count > 1 {
                    Picker("iPhone", selection: Binding(get: { model.selectedPhone?.id ?? "" }, set: { id in
                        model.selectedUDID = id
                        Task { await model.refreshWizard() }
                    })) {
                        ForEach(model.phones) { Text($0.title).tag($0.id) }
                    }
                }
                if let row = model.selectedPhone { phoneRows(row) }
            }
        } header: {
            Text("iPhone")
        }
    }

    @ViewBuilder private func phoneRows(_ row: PhoneRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.pokiBlue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                if let f = row.facts {
                    Text("iOS \(f.ios), \(f.productType)").font(.callout).foregroundStyle(.secondary)
                } else if let e = row.error {
                    Text(e).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        if let f = row.facts {
            LabeledContent(L10n.tr("Trusts This Mac")) {
                if f.pairedWithThisComputer {
                    statusText(L10n.tr("Yes"), .green)
                } else {
                    Button(L10n.tr("Pair")) { Task { await run { try await model.pair(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("pair"))
                }
            }
            LabeledContent(L10n.tr("Developer Mode")) {
                switch f.developerMode {
                case .some(true): statusText(L10n.tr("On"), .green)
                case .some(false):
                    Button(L10n.tr("Turn On…")) { Task { await run { try await model.enableDeveloperMode(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("devmode"))
                case .none: Text(L10n.tr("Checked during setup")).foregroundStyle(.secondary)
                }
            }
            if let snap = model.wizard, snap.installed != nil {
                LabeledContent(L10n.tr("Developer Disk Image")) {
                    if snap.ddiMounted {
                        statusText(L10n.tr("Mounted"), .green)
                    } else {
                        Button(L10n.tr("Restore Developer Disk Image")) {
                            Task { await run { try await model.mountDDI(udid: f.udid) } }
                        }
                        .disabled(model.busyJobs.contains("ddi"))
                    }
                }
            }
            if let s = model.steps["devmode"], !s.isEmpty, model.busyJobs.contains("devmode") { StepsView(steps: s) }
            if let s = model.steps["pair"], !s.isEmpty, model.busyJobs.contains("pair") { StepsView(steps: s) }
            if let r = row.record {
                LabeledContent("Poki") {
                    statusText("\(r.version), \(relativeDays(r))", r.daysLeft <= 2 ? .orange : .green)
                }
            }
        }
    }

    private func statusText(_ s: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(s).foregroundStyle(.secondary)
        }
    }

    // MARK: Account

    @ViewBuilder private var accountSection: some View {
        Section(L10n.tr("Apple Account")) {
            if let a = model.account, a.signedIn {
                LabeledContent(L10n.tr("Signed In As")) { Text(a.name ?? a.appleId ?? "").foregroundStyle(.secondary) }
                if model.teams.count > 1 {
                    Picker(L10n.tr("Team"), selection: Binding(get: { a.teamId ?? model.teams.first?.teamId ?? "" }, set: { id in
                        if let t = model.teams.first(where: { $0.teamId == id }) { Task { await model.chooseTeam(t) } }
                    })) {
                        ForEach(model.teams) { t in Text(t.isFree ? L10n.fmt("%@ (free)", t.name) : t.name).tag(t.teamId) }
                    }
                } else if let t = model.teams.first {
                    LabeledContent(L10n.tr("Team")) { Text(t.isFree ? L10n.fmt("%@, free (7-day apps)", t.name) : t.name).foregroundStyle(.secondary) }
                }
                if model.account?.pendingFactor != nil {
                    Button(L10n.tr("Enter 6-Digit Verification Code…")) { model.needsCode = true }
                }
            } else if let err = model.accountError {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Could not read your saved Apple Account"))
                            Text(L10n.tr("When macOS asks for keychain access, enter your Mac login password and choose “Always Allow”, then retry."))
                                .font(.callout).foregroundStyle(.secondary)
                            Text(err.message)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "key.slash").foregroundStyle(.orange)
                    }
                    HStack {
                        Spacer()
                        Button(L10n.tr("Retry")) { Task { await model.refreshAccount() } }
                    }
                }
            } else {
                LabeledContent(L10n.tr("Sign in with the Apple Account Poki is signed for")) {
                    Button(L10n.tr("Sign In…")) { model.page = .account }
                }
            }
        }
    }

    // MARK: Optional Model API Key

    @ViewBuilder private var modelKeySection: some View {
        Section {
            HStack(spacing: 8) {
                SecureField(L10n.tr("API Key"), text: $modelKey, prompt: Text(L10n.tr("Optional: paste your OpenAI, Anthropic or Gemini API key")))
                if sendingModelKey { ProgressView().controlSize(.small) }
                Button(L10n.tr("Send to Poki")) {
                    Task { await submitModelKey() }
                }
                .disabled(sendingModelKey || modelKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let provider = model.wizard?.modelKeyImportedProvider {
                Label(L10n.fmt("Imported on iPhone (%@)", provider), systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else if model.wizard?.modelKeyQueued == true {
                Label(L10n.tr("Queued in memory. Open Poki on your iPhone while connected over USB to import it."), systemImage: "clock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let modelKeyStatus {
                Text(modelKeyStatus).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.tr("Model Key (Optional)"))
        } footer: {
            Text(L10n.tr("Saves typing on the iPhone keyboard. Poki Setup encrypts the key to Poki's public key and never stores it on this Mac."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func submitModelKey() async {
        let trimmed = modelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendingModelKey = true
        modelKeyStatus = nil
        defer { sendingModelKey = false }
        do {
            let delivery = try await model.sendModelKey(udid: model.selectedPhone?.id, apiKey: trimmed)
            modelKey = ""
            modelKeyStatus = delivery.sent
                ? L10n.tr("Sent encrypted key to Poki on your iPhone.")
                : L10n.tr("Queued in memory. Open Poki on your iPhone while connected over USB to import it.")
        } catch {
            model.report(error)
        }
    }

    // MARK: Channel and updates

    private var channelChoice: Binding<String> {
        Binding(
            get: { model.channel?.id ?? "stable" },
            set: { id in
                Task {
                    do {
                        try await model.setChannel(id)
                        model.update = nil
                        channelError = nil
                    } catch { channelError = error.localizedDescription }
                }
            }
        )
    }

    private func installUpdate() async {
        do { try await model.installUpdate() } catch { channelError = error.localizedDescription }
    }

    private func checkForUpdates() async {
        checking = true
        defer { checking = false }
        await model.refreshChannels()
        await model.refreshLatest()
        do {
            model.update = try await model.bridge.call("check_update")
            channelError = nil
        } catch { channelError = error.localizedDescription }
    }

    // MARK: App

    @ViewBuilder private var appSection: some View {
        Section {
            Picker(selection: channelChoice) {
                ForEach(model.channels) { c in Text(L10n.tr(c.title)).tag(c.id) }
            } label: {
                Text("Poki")
                Text(installLine)
            }
            .disabled(ipa != nil)
            LabeledContent {
                if let u = model.update, u.newer {
                    Button(L10n.tr(model.installingUpdate ? "Updating…" : "Restart to Update")) { Task { await installUpdate() } }
                        .disabled(model.installingUpdate)
                } else {
                    Button(L10n.tr(checking ? "Checking…" : "Check for Updates")) { Task { await checkForUpdates() } }
                        .disabled(checking)
                }
            } label: {
                Text("Poki Setup")
                Text(setupLine)
            }
            HStack {
                Menu {
                    Button(L10n.tr(ipa == nil ? "Install from an IPA File…" : "Choose Another IPA File…")) { choosingIPA = true }
                    if ipa != nil { Button(L10n.tr("Use the Release Instead")) { ipa = nil } }
                    Divider()
                    Toggle(L10n.tr("Also Show a QR Code for Wi-Fi Pairing"), isOn: $handOff)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.tr("More install options"))
                Spacer()
                Button {
                    Task { await install() }
                } label: {
                    Text(L10n.tr(installing ? "Installing…" : "Install Poki")).frame(minWidth: 140)
                }
                .pokiProminentButton()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInstall)
            }
            if let message = failed ?? channelError {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        } header: {
            Text("Poki")
        } footer: {
            if let f = footer { Text(f).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private var installLine: String {
        if let ipa { return L10n.fmt("From %@", ipa.lastPathComponent) }
        if let latest = model.latest { return buildLine(latest) }
        return L10n.tr("No release published yet")
    }

    private var setupLine: String {
        let version = displayVersion(model.info?.version ?? "")
        guard let update = model.update else { return version }
        return update.newer
            ? L10n.fmt("%@, %@ is available", version, displayVersion(update.latest ?? ""))
            : L10n.fmt("%@, up to date", version)
    }

    private func buildLine(_ r: Release) -> String {
        let id = r.channel ?? model.channel?.id ?? ""
        let title = L10n.tr(model.channels.first(where: { $0.id == id })?.title ?? id.capitalized)
        if let chosen = model.channel, !id.isEmpty, chosen.id != id {
            return L10n.fmt("%@ %@ (%@), no %@ release yet", title, r.version, r.build, L10n.tr(chosen.title))
        }
        return "\(r.version) (\(r.build))"
    }

    private var footer: String? {
        if model.accountError != nil { return L10n.tr("Unlock your keychain and choose “Always Allow”, then tap Retry above.") }
        if model.account?.signedIn != true { return L10n.tr("Sign in first. Your Apple Account password goes to Apple only.") }
        if ipa == nil && model.latest == nil { return L10n.tr("No Poki release is published yet. Use ⋯ to install from the Poki IPA you downloaded (the “external” one).") }
        return nil
    }

    private var canInstall: Bool {
        !installing && model.selectedPhone?.facts != nil && model.account?.signedIn == true && (ipa != nil || model.latest != nil)
    }

    @ViewBuilder private func resultSection(_ r: InstallAnswer) -> some View {
        Section(L10n.tr("Done")) {
            Label(L10n.fmt("Poki %@ is on %@. It stays signed until %@.", r.record.version, r.record.phoneName, r.record.expires.formatted(date: .abbreviated, time: .shortened)), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.primary)
            ForEach(Array(r.notes.enumerated()), id: \.offset) { _, n in
                Text(n).font(.callout).foregroundStyle(.secondary)
            }
            Text(L10n.tr("On the iPhone: open Settings › General › VPN & Device Management, trust your Apple Account, then open Poki."))
                .font(.callout)
            if let h = r.handoff {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: h.link, size: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Scan with the iPhone's Camera")).font(.headline)
                        Text(L10n.tr("Keep the iPhone on the same Wi-Fi as this Mac. Poki opens and saves its pairing file."))
                            .font(.callout).foregroundStyle(.secondary)
                        Button(L10n.tr("Copy Link")) { copyToPasteboard(h.link) }
                    }
                }
            }
        }
    }

    private func install() async {
        guard let phone = model.selectedPhone else { return }
        failed = nil
        result = nil
        do {
            result = try await model.install(udid: phone.id, ipa: ipa, handOff: handOff)
        } catch let e as CoreError where e.kind == "certificate_limit" {
            failed = e.message
            certificateQuestion = e.message
        } catch {
            failed = error.localizedDescription
        }
    }

    private func run(_ body: () async throws -> Void) async {
        do { try await body() } catch { model.report(error) }
    }
}
