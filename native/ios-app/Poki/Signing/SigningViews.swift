import SwiftUI

/// The Apple Account, optional and out of the way (ESP-222): Poki Setup on a Mac signs Poki, and
/// signed in here Poki can also renew itself with no computer. Sections of the Apple Account page's Form.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    @State private var appleID = ""
    @State private var password = ""
    @State private var keepPassword = true
    @State private var code = ""

    private var signer: SelfSigner { model.signer }

    var body: some View {
        if signer.needsCode {
            Section {
                TextField("Verification Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button("Verify") { Task { await signer.finishSignIn(code: code); code = "" } }
                    .disabled(code.count != 6 || signer.working != nil)
            } footer: {
                Text("Apple sent a six-digit code to your trusted devices or phone number.")
            }
        } else if signer.signedIn {
            Section {
                LabeledContent("Apple Account", value: signer.status?.apple_id ?? "")
                if let name = signer.status?.name, name != signer.status?.apple_id { LabeledContent("Name", value: name) }
                if signer.teams.count > 1 {
                    Picker("Team", selection: Binding(get: { signer.status?.team_id ?? "" }, set: { id in
                        if let team = signer.teams.first(where: { $0.team_id == id }) { Task { await signer.choose(team: team) } }
                    })) {
                        ForEach(signer.teams) { team in
                            Text(verbatim: team.is_free ? AppLocalization.text(LocalizedStringResource("\(team.name) (Free)")) : team.name).tag(team.team_id)
                        }
                    }
                } else if let team = signer.teams.first {
                    LabeledContent("Team", value: team.is_free ? AppLocalization.text(LocalizedStringResource("\(team.name) (Free, 7-day signing)")) : team.name)
                }
            } footer: {
                Text(signer.status?.keeps_password == true
                     ? "Poki keeps the password in this iPhone’s Keychain to sign itself again every week."
                     : "Poki signs in again when its signing is due, and asks you for the password then.")
            }
            .task { if signer.teams.isEmpty { await signer.loadTeams() } }
            Section { Button("Sign Out", role: .destructive) { Task { await signer.signOut() } } }
        } else {
            Section {
                TextField("Apple ID", text: $appleID)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Toggle("Keep Me Signed In", isOn: $keepPassword)
            } footer: {
                Text("A free Apple Account can be used. Poki signs itself for 7 days at a time and prepares to refresh before expiration. Your Apple Account and password are sent only to Apple.")
            }
            Section {
                Button("Sign In") { Task { await signer.signIn(appleID: appleID, password: password, keepPassword: keepPassword); password = "" } }
                    .disabled(appleID.isEmpty || password.isEmpty || signer.working != nil)
            }
        }
        SignerActivityRows(signer: signer)
    }
}

/// The Apple Account as a page of its own under Signing & Updates.
struct AppleAccountPage: View {
    var body: some View {
        Form { AccountPage() }
            .navigationTitle(AppLocalization.text("Apple Account"))
            .navigationBarTitleDisplayMode(.inline)
            .settingsPage()
    }
}

/// What the signer is doing, or why it stopped.
struct SignerActivityRows: View {
    let signer: SelfSigner
    var body: some View {
        if let working = signer.working {
            Section {
                if let f = signer.fraction { ProgressView(value: f) { Text(verbatim: local(working)) } } else { LabeledContent { ProgressView() } label: { Text(verbatim: local(working)) } }
            }
        }
        if let error = signer.lastError {
            Section { problem(Text(verbatim: local(error))) }
        }
        // The core's own sentences name its servers. They are in the log; the page says what to do.
        if signer.updateCheckError != nil {
            Section { problem(Text("Poki couldn’t check for updates. Check your internet connection and try again.")) }
        } else if signer.latest?.source_notice != nil {
            Section {
                Label { Text("The primary download server is unavailable. Poki is using a backup server for this update.") } icon: { Image(systemName: "info.circle") }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    /// The signer's words are English; those the strings table knows are shown in Poki's language.
    private func local(_ text: String) -> String {
        AppLocalization.bundle.localizedString(forKey: text, value: text, table: nil)
    }

    private func problem(_ text: Text) -> some View {
        Label { text } icon: { Image(systemName: "exclamationmark.triangle") }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Tint.red)
    }
}

/// Settings › Signing & Updates: the installed Poki and the newest one, when its signing ends, the
/// update or the refresh to install, and the way to the Apple Account and to Advanced.
struct SigningUpdatesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List { SigningSection() }
            .navigationTitle(AppLocalization.text("Signing & Updates"))
            .navigationBarTitleDisplayMode(.inline)
            // The page says what the newest Poki is, so it looks when it opens (not on every return
            // from a page under it).
            .task {
                let signer = model.signer
                if signer.latest != nil, let last = signer.lastCheck, Date().timeIntervalSince(last) < 60 { return }
                await signer.checkLatest()
            }
    }
}

/// The rows of Signing & Updates. Setup's checklist shows them too.
struct SigningSection: View {
    @Environment(AppModel.self) private var model
    private var signer: SelfSigner { model.signer }

    var body: some View {
        Section {
            SettingsRow(title: "Version", symbol: "info.circle", value: "\(signer.installedVersion) (\(signer.installedBuild))")
            if let latest = signer.latest {
                let newer = signer.isNewer(latest)
                SettingsRow(title: "Latest Version", symbol: "sparkles",
                            value: newer ? "\(latest.version) (\(latest.build))" : AppLocalization.text(LocalizedStringResource("Up to Date")), warns: newer)
            } else if signer.lookingUp {
                SettingsRow(title: "Latest Version", symbol: "sparkles", value: AppLocalization.text(LocalizedStringResource("Checking…")))
            } else if signer.updateCheckError != nil {
                SettingsRow(title: "Latest Version", symbol: "sparkles", value: AppLocalization.text(LocalizedStringResource("Unable to Check")))
            }
            SignedUntilRow(expiry: signer.expiry, countdownColor: countdownColor)
            if !signer.updateNotReady, let next = signer.next {
                SettingsRow(title: next.kind == "update" ? "Update Ready" : "Refresh Ready", symbol: "checkmark.seal",
                            value: next.kind == "update" ? "\(next.version) (\(next.build))"
                                : AppLocalization.text(LocalizedStringResource("Until \(next.expires.formatted(.dateTime.month(.abbreviated).day().year().locale(AppLocalization.locale)))")))
            }
        }

        // The actions under what they act on. A newer build not yet downloaded comes first: one tap
        // downloads and installs it (or, without an Apple Account, opens the sign-in).
        Section {
            switch signer.updateStep {
            case .download:
                SignerAction(signer: signer, title: "Download and Install Update", systemImage: "arrow.down.circle") { await signer.downloadAndInstallUpdate() }
            case .signIn:
                NavigationLink { AppleAccountPage() } label: {
                    SettingsLabel("Sign In to Download the Update", systemImage: "person.crop.circle.badge.plus")
                }
            case .install, nil:
                if let next = signer.next {
                    // Idle is partly time (a minute since the last agent step), which nothing observes, so
                    // the row looks again every few seconds instead of staying as it was first drawn.
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        SignerAction(signer: signer, title: next.kind == "update" ? "Install Update" : "Install Refresh", systemImage: "arrow.down.app") { await signer.install() }
                    }
                }
            }
            if signer.needsCode {
                Button {
                    signer.presentCodeSheet()
                } label: {
                    SettingsLabel("Enter Verification Code…", systemImage: "lock.shield")
                }
            }
            if signer.signedIn {
                SignerAction(signer: signer, title: "Prepare Refresh Now", systemImage: "arrow.clockwise") { await signer.prepare(kind: "refresh") }
            }
        } footer: {
            Text(footer)
        }

        Section {
            NavigationLink { AppleAccountPage() } label: {
                SettingsRow(title: "Apple Account", symbol: "person.crop.circle",
                            value: signer.signedIn ? signer.status?.apple_id : AppLocalization.text(LocalizedStringResource("Not Signed In")))
            }
            NavigationLink { SigningOptionsPage() } label: {
                SettingsRow(title: "Advanced", symbol: "slider.horizontal.3")
            }
        } footer: {
            Text("Optional. To renew Poki without a Mac, sign in to your Apple Account here.")
        }
        SignerActivityRows(signer: signer)
    }

    /// Amber when the next build is due, red on the last day.
    private var countdownColor: Color {
        guard let days = signer.daysLeft else { return Color(.secondaryLabel) }
        return days <= 1 ? Tint.red : days <= SelfSigner.refreshWithDaysLeft ? Tint.amberInk : Color(.secondaryLabel)
    }

    private var footer: String {
        if let blocker = signer.updateBlocker { return blocker }
        if !signer.signedIn { return AppLocalization.text(LocalizedStringResource("Poki Setup on your Mac renews Poki when this iPhone is connected.")) }
        if signer.next != nil {
            return model.signingIdle
                ? AppLocalization.text(LocalizedStringResource("Installing closes Poki for a moment. Your chats and setup stay."))
                : (model.signingBusyReason ?? "") + " " + AppLocalization.text(LocalizedStringResource("Install is available when Poki isn’t running a task."))
        }
        return AppLocalization.text(LocalizedStringResource("Poki automatically prepares the next build \(Int(SelfSigner.refreshWithDaysLeft)) days before signing expires, or when an update is available. Nothing is installed until you tap Install."))
    }
}

/// When the installed Poki stops opening, as a row with what is left under its name: the date and its
/// countdown take the row's width in every language, where a value on the right would not fit.
private struct SignedUntilRow: View {
    var expiry: Date?
    var countdownColor: Color
    @ScaledMetric(relativeTo: .body) private var iconSpacing = SettingsRowMetrics.iconSpacing

    var body: some View {
        HStack(spacing: min(18, iconSpacing)) {
            SettingsIcon(symbol: "signature")
                .padding(.vertical, SettingsRowMetrics.iconLineInset)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signed Until").font(.body).foregroundStyle(Color(.label))
                Group {
                    if let expiry {
                        Text(expiry, format: .dateTime.month(.abbreviated).day().year()) + Text(verbatim: " · ") + Text(expiry, style: .relative).foregroundStyle(countdownColor)
                    } else {
                        Text("Unknown")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the Signing & Updates page offers when there is a newer Poki (ESP-387).
enum UpdateStep: Equatable {
    /// One tap downloads it, signs it and installs it.
    case download
    /// A signed copy of it is ready.
    case install
    /// No Apple Account: sign in here, or install it with Poki Setup on a Mac.
    case signIn

    init?(updateAvailable: Bool, copyReady: Bool, signedIn: Bool) {
        guard updateAvailable else { return nil }
        self = copyReady ? .install : signedIn ? .download : .signIn
    }
}

/// One signer action row, disabled while the signer works.
struct SignerAction: View {
    let signer: SelfSigner
    let title: LocalizedStringKey
    let systemImage: String
    let work: () async -> Void

    var body: some View {
        Button { Task { await work() } } label: { SettingsLabel(title, systemImage: systemImage) }
            .disabled(signer.working != nil)
    }
}

/// Home's warning that the installed Poki stops opening soon (ESP-222). Renewing happens on the Mac:
/// it installs a build with a new profile, so a renewed Poki has a later expiry and no warning.
struct ExpiryWarning {
    let expiry: Date

    init?(expiry: Date?, now: Date = .now) {
        guard let expiry, expiry.timeIntervalSince(now) <= SelfSigner.warnWithDaysLeft * 86_400 else { return nil }
        self.expiry = expiry
    }

    var message: String {
        let when = expiry.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.locale))
        return AppLocalization.text(LocalizedStringResource("Poki stops opening after \(when). Connect this iPhone to your Mac and ask your agent to renew it."))
    }
}

/// Signing & Updates › Advanced: the server that helps Poki sign in to the Apple Account (the core's
/// anisette server). Poki's own is used until the person names another.
struct SigningOptionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    private var signer: SelfSigner { model.signer }

    var body: some View {
        List {
            Section {
                TextField("Default Server", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await signer.setAnisette(server) } }
                Button("Use Default Server") { server = ""; Task { await signer.setAnisette("") } }
                    .disabled(server.isEmpty && signer.customSignInServer == nil)
            } header: {
                SettingsHeader("Sign-In Server")
            } footer: {
                Text("Signing in to your Apple Account in Poki requires a sign-in server to verify this iPhone. The server never sees your Apple Account or password. Change this only if signing in continues to fail.")
            }
            SignerActivityRows(signer: signer)
        }
        .navigationTitle(AppLocalization.text("Advanced"))
        .navigationBarTitleDisplayMode(.inline)
        .settingsPage()
        .onAppear { server = signer.customSignInServer ?? "" }
    }
}

extension EnvironmentValues {
    @Entry var pokiDetailsOpen = false
}

/// Six-digit 2FA verification sheet shown when renewing a saved-password Apple session requires a code.
struct VerificationCodeSheet: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""

    private var signer: SelfSigner { model.signer }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("6-Digit Code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: code) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(6))
                            if digits != new { code = digits }
                            if digits.count == 6, signer.working == nil {
                                submit()
                            }
                        }
                } header: {
                    Text("Two-Factor Authentication")
                } footer: {
                    Text("Enter the 6-digit verification code sent to your trusted devices or phone number.")
                }
                SignerActivityRows(signer: signer)
            }
            .navigationTitle(AppLocalization.text("Verification Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { signer.dismissCodeSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify") { submit() }
                        .disabled(code.count != 6 || signer.working != nil)
                }
            }
        }
    }

    private func submit() {
        let entered = code
        code = ""
        Task { await signer.finishSignIn(code: entered) }
    }
}
