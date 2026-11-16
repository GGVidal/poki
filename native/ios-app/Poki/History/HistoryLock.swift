import CryptoKit
import LocalAuthentication
import SQLite3
import Security
import SwiftUI
import UIKit
import notify

/// The lock in front of iPhone History (the owner, 2026-11-14): its pages open only after Face ID or
/// Touch ID, with no fall back to the iPhone's passcode, or after a PIN that belongs to Poki alone.
/// Either one can be turned off, but never both.
@MainActor
final class HistoryLock: ObservableObject {
    static let shared = HistoryLock()

    enum AuthMethods: Equatable {
        case biometricsOnly
        case pinOnly
        case biometricsAndPIN

        init?(biometrics: Bool, pin: Bool) {
            switch (biometrics, pin) {
            case (true, true): self = .biometricsAndPIN
            case (true, false): self = .biometricsOnly
            case (false, true): self = .pinOnly
            case (false, false): return nil
            }
        }

        var usesBiometrics: Bool { self != .pinOnly }
        var hasPIN: Bool { self != .biometricsOnly }
    }

    struct PINCooldown: Equatable {
        var failures = 0
        var blockedUntil: Date?
    }

    enum State: Equatable {
        case unconfigured
        case locked(methods: AuthMethods, evaluatingBiometrics: UUID?, cooldown: PINCooldown)
        case biometricsUnavailable
        case deviceLocked
        case unlocked(methods: AuthMethods)
    }

    private enum StoredPIN {
        case present(Data)
        case absent
        case inaccessibleWhileDeviceLocked
    }

    private struct BiometricsSnapshot {
        let ready: Bool
        let name: String
        let blockedOrDeniedOnHardware: Bool
    }

    private struct Environment {
        let biometricsOn: Bool
        let biometrics: BiometricsSnapshot
        let storedPIN: StoredPIN
        let armed: Bool
    }

    private enum Event {
        case refresh
        case enteredBackground
        case beginBiometrics(UUID)
        case finishBiometrics(attempt: UUID, passed: Bool)
        case setPIN(String)
        case unlockWithPIN(String)
        case removePIN
        case setBiometrics(Bool)
    }

    @Published private(set) var state: State = .unconfigured
    /// The owner's choice. Whether it can be used also depends on the iPhone (`biometricsReady`).
    @Published private(set) var biometricsOn: Bool

    private static let service = "nz.zheha.poki.history-lock"
    private static let pinAccount = "pin"
    private static let armedAccount = "armed"
    private static let biometricsKey = "history.lock.biometrics"
    private static let armedKey = "history.lock.armed"
    private var enrollmentToken: Int32 = NOTIFY_TOKEN_INVALID

    private init() {
        biometricsOn = UserDefaults.standard.object(forKey: Self.biometricsKey) as? Bool ?? true
        _ = transition(.refresh)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in _ = self?.transition(.refresh) }
        }
        center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in _ = self?.transition(.refresh) }
        }
        notify_register_dispatch("com.apple.BiometricKit.enrollmentChanged", &enrollmentToken, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in _ = self?.transition(.refresh) }
        }
    }

    private var effectiveState: State {
        Self.reconcile(state, env: currentEnvironment(), now: Date())
    }

    var unlocked: Bool {
        if case .unlocked = effectiveState { return true }
        return false
    }

    var hasPIN: Bool {
        switch effectiveState {
        case .locked(let methods, _, _), .unlocked(let methods): return methods.hasPIN
        case .unconfigured, .biometricsUnavailable, .deviceLocked: return false
        }
    }

    // MARK: Biometrics

    /// Face ID or Touch ID is set up on this iPhone and allowed for Poki.
    var biometricsReady: Bool { Self.biometricsSnapshot().ready }

    var usesBiometrics: Bool {
        switch effectiveState {
        case .locked(let methods, _, _), .unlocked(let methods): return methods.usesBiometrics
        case .unconfigured, .biometricsUnavailable, .deviceLocked: return false
        }
    }

    /// "Face ID", "Touch ID" or "Optic ID", as this iPhone has it.
    var biometricsName: String { Self.biometricsSnapshot().name }

    /// The same name in Poki's language.
    var biometricsLabel: String { AppLocalization.bundle.localizedString(forKey: biometricsName, value: nil, table: nil) }

    /// Nothing can unlock history yet: a PIN has to be made first.
    var needsSetup: Bool { effectiveState == .unconfigured }

    var biometricsUnavailable: Bool { effectiveState == .biometricsUnavailable }

    var failures: Int {
        if case .locked(_, _, let cooldown) = effectiveState { return cooldown.failures }
        return 0
    }

    var blockedUntil: Date? {
        if case .locked(_, _, let cooldown) = effectiveState { return cooldown.blockedUntil }
        return nil
    }

    func unlockWithBiometrics() async {
        let attempt = UUID()
        guard transition(.beginBiometrics(attempt)) else { return }
        let context = LAContext()
        // No "Enter Passcode" button: the iPhone's passcode does not open history.
        context.localizedFallbackTitle = ""
        let reason = AppLocalization.text("Unlock Screen History")
        let passed = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
        _ = transition(.finishBiometrics(attempt: attempt, passed: passed))
    }

    /// Asks for Face ID or Touch ID again, for something that cannot be undone. The page stays as it is.
    func confirm(_ reason: String) async -> Bool {
        guard usesBiometrics else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }

    // MARK: PIN

    static func valid(_ pin: String) -> Bool { (4...8).contains(pin.count) && pin.allSatisfy(\.isNumber) }

    /// Keeps a new PIN. Allowed while history is unlocked, or when nothing can unlock it yet.
    @discardableResult
    func setPIN(_ pin: String) -> Bool { transition(.setPIN(pin)) }

    func unlock(pin: String) -> Bool { transition(.unlockWithPIN(pin)) }

    /// Removes the PIN. Refused unless Face ID or Touch ID stays as the way in.
    @discardableResult
    func removePIN() -> Bool { transition(.removePIN) }

    /// Turns Face ID or Touch ID on or off for history. Turning it off is refused without a PIN.
    @discardableResult
    func setBiometrics(_ on: Bool) -> Bool { transition(.setBiometrics(on)) }

    func lock() { _ = transition(.enteredBackground) }

    // MARK: State machine

    @discardableResult
    private func transition(_ event: Event, now: Date = Date()) -> Bool {
        var env = currentEnvironment()
        if biometricsOn != env.biometricsOn { biometricsOn = env.biometricsOn }
        let current = Self.reconcile(state, env: env, now: now)
        if env.armed { Self.persistArmed() }

        let next: State
        let accepted: Bool

        switch event {
        case .refresh:
            next = current
            accepted = true

        case .enteredBackground:
            let base: State = switch current {
            case .unlocked(let methods):
                .locked(methods: methods, evaluatingBiometrics: nil, cooldown: PINCooldown())
            case .locked(let methods, _, let cooldown):
                .locked(methods: methods, evaluatingBiometrics: nil, cooldown: cooldown)
            case .unconfigured, .biometricsUnavailable, .deviceLocked:
                current
            }
            next = Self.reconcile(base, env: env, now: now)
            accepted = true

        case .beginBiometrics(let attempt):
            guard case .locked(let methods, nil, let cooldown) = current, methods.usesBiometrics else {
                if state != current { state = current }
                return false
            }
            next = .locked(methods: methods, evaluatingBiometrics: attempt, cooldown: cooldown)
            accepted = true

        case .finishBiometrics(let attempt, let passed):
            guard case .locked(let methods, let active?, let cooldown) = current, active == attempt else {
                if state != current { state = current }
                return false
            }
            if passed, methods.usesBiometrics {
                Self.persistArmed()
                next = .unlocked(methods: methods)
                accepted = true
            } else {
                next = .locked(methods: methods, evaluatingBiometrics: nil, cooldown: cooldown)
                accepted = false
            }

        case .setPIN(let pin):
            let allowed = switch current {
            case .unconfigured, .unlocked: true
            case .locked, .biometricsUnavailable, .deviceLocked: false
            }
            guard Self.valid(pin), allowed, Self.writeStoredPIN(pin) else {
                if state != current { state = current }
                return false
            }
            Self.persistArmed()
            env = currentEnvironment()
            guard let methods = AuthMethods(biometrics: env.biometricsOn && env.biometrics.ready, pin: true) else {
                return false
            }
            next = .unlocked(methods: methods)
            accepted = true

        case .unlockWithPIN(let pin):
            switch current {
            case .locked(let methods, let attempt, var cooldown) where methods.hasPIN:
                if let until = cooldown.blockedUntil, until > now {
                    if state != current { state = current }
                    return false
                }
                guard case .present(let value) = env.storedPIN else {
                    if state != current { state = current }
                    return false
                }
                if Self.matchesPIN(pin, stored: value) {
                    Self.persistArmed()
                    next = .unlocked(methods: methods)
                    accepted = true
                } else {
                    cooldown.failures += 1
                    // Five wrong tries in a row, then a wait that doubles: 30 s, 1 min, 2 min, up to an hour.
                    if cooldown.failures >= 5 {
                        cooldown.blockedUntil = now.addingTimeInterval(min(3600, 30 * pow(2, Double(cooldown.failures - 5))))
                    }
                    next = .locked(methods: methods, evaluatingBiometrics: attempt, cooldown: cooldown)
                    accepted = false
                }
            case .unlocked(let methods) where methods.hasPIN:
                guard case .present(let value) = env.storedPIN else { return false }
                next = current
                accepted = Self.matchesPIN(pin, stored: value)
            default:
                if state != current { state = current }
                return false
            }

        case .removePIN:
            guard case .unlocked(.biometricsAndPIN) = current else {
                if state != current { state = current }
                return false
            }
            Self.deleteStoredPIN()
            next = .unlocked(methods: .biometricsOnly)
            accepted = true

        case .setBiometrics(let on):
            guard case .unlocked(let methods) = current, on || methods.hasPIN,
                  let updated = AuthMethods(biometrics: on && env.biometrics.ready, pin: methods.hasPIN) else {
                if state != current { state = current }
                return false
            }
            biometricsOn = on
            UserDefaults.standard.set(on, forKey: Self.biometricsKey)
            if on, env.biometrics.ready { Self.persistArmed() }
            next = .unlocked(methods: updated)
            accepted = true
        }

        if state != next { state = next }
        return accepted
    }

    private func currentEnvironment() -> Environment {
        let on = UserDefaults.standard.object(forKey: Self.biometricsKey) as? Bool ?? true
        let bio = Self.biometricsSnapshot()
        let pin = Self.storedPIN()
        let pinExists: Bool = switch pin {
        case .present, .inaccessibleWhileDeviceLocked: true
        case .absent: false
        }
        let armed = Self.isArmedPersisted()
            || pinExists
            || (on && bio.ready)
            || (on && bio.blockedOrDeniedOnHardware && Self.storeHasProtectedEntries())
        return Environment(biometricsOn: on, biometrics: bio, storedPIN: pin, armed: armed)
    }

    private static func reconcile(_ state: State, env: Environment, now: Date) -> State {
        let knownHasPIN: Bool = switch state {
        case .locked(let methods, _, _), .unlocked(let methods): methods.hasPIN
        case .unconfigured, .biometricsUnavailable, .deviceLocked: false
        }
        let hasPIN: Bool = switch env.storedPIN {
        case .present: true
        case .absent: false
        case .inaccessibleWhileDeviceLocked: knownHasPIN
        }
        let usesBiometrics = env.biometricsOn && env.biometrics.ready
        if case .inaccessibleWhileDeviceLocked = env.storedPIN, !usesBiometrics, !hasPIN {
            if case .unlocked(let methods) = state { return .unlocked(methods: methods) }
            return .deviceLocked
        }
        guard let methods = AuthMethods(biometrics: usesBiometrics, pin: hasPIN) else {
            return env.armed ? .biometricsUnavailable : .unconfigured
        }
        switch state {
        case .unlocked:
            return .unlocked(methods: methods)
        case .locked(_, let activeAttempt, var cooldown):
            if let until = cooldown.blockedUntil, until <= now { cooldown.blockedUntil = nil }
            return .locked(methods: methods, evaluatingBiometrics: methods.usesBiometrics ? activeAttempt : nil, cooldown: cooldown)
        case .unconfigured, .biometricsUnavailable, .deviceLocked:
            return .locked(methods: methods, evaluatingBiometrics: nil, cooldown: PINCooldown())
        }
    }

    // MARK: Boundaries

    private static func biometricsSnapshot() -> BiometricsSnapshot {
        let context = LAContext()
        var error: NSError?
        let ready = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name: String = switch context.biometryType {
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Face ID"
        }
        let code = error?.code
        let blockedOrDenied = code == LAError.biometryLockout.rawValue
            || (context.biometryType != .none && code == LAError.biometryNotAvailable.rawValue)
        return BiometricsSnapshot(ready: ready, name: name, blockedOrDeniedOnHardware: blockedOrDenied)
    }

    private static func storedPIN() -> StoredPIN {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: pinAccount,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count > 16 else { return .absent }
            return .present(data)
        case errSecInteractionNotAllowed:
            return .inaccessibleWhileDeviceLocked
        default:
            return .absent
        }
    }

    private static func digest(_ pin: String, salt: Data) -> Data {
        var hash = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        // Stretched, so the short PIN is slow to try from a copy of the stored value.
        for _ in 0..<20_000 { hash = Data(SHA256.hash(data: salt + hash)) }
        return hash
    }

    private static func matchesPIN(_ pin: String, stored value: Data) -> Bool {
        guard value.count > 16 else { return false }
        let salt = Data(value.prefix(16))
        return digest(pin, salt: salt) == value.dropFirst(16)
    }

    private static func writeStoredPIN(_ pin: String) -> Bool {
        var salt = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else { return false }
        let value = salt + digest(pin, salt: salt)
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: pinAccount]
        SecItemDelete(match as CFDictionary)
        var add = match
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteStoredPIN() {
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: pinAccount]
        SecItemDelete(match as CFDictionary)
    }

    private static func isArmedPersisted() -> Bool {
        if UserDefaults.standard.bool(forKey: armedKey) { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: armedAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private static func persistArmed() {
        UserDefaults.standard.set(true, forKey: armedKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: armedAccount,
        ]
        guard SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound else { return }
        var add = query
        add[kSecValueData as String] = Data([1])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func storeHasProtectedEntries() -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = base.appendingPathComponent("History/history.sqlite")
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return false
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM entries LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}

/// Shows its content only while iPhone History is unlocked.
struct HistoryGate<Content: View>: View {
    @ObservedObject var lock = HistoryLock.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        if lock.unlocked { content() } else { HistoryLockedPage() }
    }
}

/// The lock on a page of its own.
private struct HistoryLockedPage: View {
    var body: some View {
        BacktapeLockScreen()
            .navigationTitle(AppLocalization.text("Screen History"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Backtape shows before it is unlocked (the owner, 2026-11-15: a screen that says an unlock is
/// needed to view, with the Face ID prompt or a password pad). Face ID or Touch ID is asked for as the
/// page opens and again from its button; with a PIN, the pad is on the page. Nothing of the tape is
/// drawn behind it. An iPhone with neither yet gets the list that makes a PIN.
struct BacktapeLockScreen: View {
    @ObservedObject private var lock = HistoryLock.shared
    @State private var pin = ""
    @State private var wrong = 0
    @State private var now = Date()

    private var waiting: Bool { lock.blockedUntil.map { $0 > now } ?? false }

    var body: some View {
        if lock.needsSetup {
            List { HistoryUnlockSections() }.settingsPage()
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: lock.usesBiometrics ? (lock.biometricsName == "Touch ID" ? "touchid" : "faceid") : "lock.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Tint.blue)
                        .padding(.top, 36)
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("Screen History Is Locked").font(.title2.weight(.semibold))
                        Text("Unlock to view what Screen History kept on this iPhone.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    if lock.usesBiometrics {
                        Button { Task { await lock.unlockWithBiometrics() } } label: {
                            Text(verbatim: String(format: AppLocalization.text("Unlock with %@"), lock.biometricsLabel))
                                .padding(.horizontal, 6)
                        }
                        .glassButton(prominent: true)
                        .controlSize(.large)
                    } else if lock.biometricsUnavailable, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button { UIApplication.shared.open(url) } label: {
                            Text("Open Settings").padding(.horizontal, 6)
                        }
                        .glassButton(prominent: true)
                        .controlSize(.large)
                    }
                    if lock.hasPIN { pad }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .task { await lock.unlockWithBiometrics() }
            .task(id: lock.blockedUntil) {
                // The wait's end shows by itself.
                while let until = lock.blockedUntil, until > Date() {
                    try? await Task.sleep(for: .seconds(1))
                    now = Date()
                }
                now = Date()
            }
            .sensoryFeedback(.error, trigger: wrong)
        }
    }

    /// Poki's own PIN, 4 to 8 digits: the dots, then the keys.
    private var pad: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(0..<max(4, pin.count), id: \.self) { index in
                    Circle().fill(index < pin.count ? Color(.label) : Color(.tertiaryLabel).opacity(0.5)).frame(width: 11, height: 11)
                }
            }
            .frame(height: 20)
            .accessibilityLabel(Text("PIN"))
            .accessibilityValue(Text(verbatim: "\(pin.count)"))
            Group {
                if waiting, let until = lock.blockedUntil {
                    Text(verbatim: String(format: AppLocalization.text("Too many wrong tries. Try again at %@."), until.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLocalization.locale))))
                } else if wrong > 0, pin.isEmpty {
                    Text("That PIN is not right.")
                } else {
                    Text(verbatim: " ")
                }
            }
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Grid(horizontalSpacing: 22, verticalSpacing: 14) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(1..<4, id: \.self) { column in key("\(row * 3 + column)") }
                    }
                }
                GridRow {
                    symbolKey("delete.left", label: "Delete") { if !pin.isEmpty { pin.removeLast() } }
                    key("0")
                    symbolKey("arrow.right", label: "Unlock") { enter() }
                        .disabled(!HistoryLock.valid(pin))
                }
            }
            .disabled(waiting)
            .glassGroup(spacing: 8)
        }
        .padding(.top, 6)
    }

    private func key(_ digit: String) -> some View {
        Button {
            guard pin.count < 8 else { return }
            pin += digit
        } label: {
            Text(verbatim: digit).font(.title.weight(.regular)).frame(width: 72, height: 72).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassSurface(in: Circle(), interactive: true)
        .sensoryFeedback(.selection, trigger: pin)
    }

    private func symbolKey(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).frame(width: 72, height: 72).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func enter() {
        if !lock.unlock(pin: pin) { wrong += 1 }
        pin = ""
        now = Date()
    }
}

/// The way in, as sections of a list: Face ID or Touch ID, the PIN, or making a PIN when the iPhone
/// has neither set up.
struct HistoryUnlockSections: View {
    @ObservedObject private var lock = HistoryLock.shared
    @State private var pin = ""
    @State private var again = ""
    @State private var wrong = false
    @State private var now = Date()

    private var waiting: Bool { lock.blockedUntil.map { $0 > now } ?? false }

    var body: some View {
        Group {
            if lock.needsSetup {
                Section {
                    SecureField("New PIN", text: $pin).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    SecureField("Repeat PIN", text: $again).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button("Set PIN") {
                        wrong = !(pin == again && lock.setPIN(pin))
                        if wrong { again = "" }
                    }
                    .disabled(!HistoryLock.valid(pin) || again.isEmpty)
                } header: {
                    Text("Make a PIN for Screen History")
                } footer: {
                    Text(LocalizedStringKey(wrong ? "The two PINs did not match. Try again." : "Screen History is locked with a PIN of 4 to 8 digits that belongs to Poki alone. The iPhone's passcode does not open it."))
                }
            } else {
                if lock.usesBiometrics {
                    Section {
                        Button { Task { await lock.unlockWithBiometrics() } } label: {
                            Text(verbatim: String(format: AppLocalization.text("Unlock with %@"), lock.biometricsLabel))
                        }
                    } header: {
                        Text("Screen History Is Locked")
                    }
                } else if lock.biometricsUnavailable, let url = URL(string: UIApplication.openSettingsURLString) {
                    Section {
                        Button("Open Settings") { UIApplication.shared.open(url) }
                    } header: {
                        Text("Screen History Is Locked")
                    }
                }
                if lock.hasPIN {
                    Section {
                        SecureField("PIN", text: $pin).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("Unlock") {
                            wrong = !lock.unlock(pin: pin)
                            pin = ""
                            now = Date()
                        }
                        .disabled(pin.isEmpty || waiting)
                    } footer: {
                        if waiting, let until = lock.blockedUntil {
                            Text(verbatim: String(format: AppLocalization.text("Too many wrong tries. Try again at %@."), until.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(AppLocalization.locale))))
                        } else if wrong {
                            Text("That PIN is not right.")
                        }
                    }
                }
            }
        }
        .task { await lock.unlockWithBiometrics() }
        .task(id: lock.blockedUntil) {
            while let until = lock.blockedUntil, until > Date() {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
            now = Date()
        }
    }
}

/// History's lock settings: Face ID or Touch ID, and Poki's own PIN. One of the two always stays on.
struct HistoryLockSettings: View {
    @ObservedObject private var lock = HistoryLock.shared
    @State private var pin = ""
    @State private var again = ""
    @State private var mismatch = false

    var body: some View {
        List {
            if lock.biometricsReady {
                Section {
                    Toggle(isOn: Binding(get: { lock.biometricsOn }, set: { lock.setBiometrics($0) })) {
                        Text(verbatim: lock.biometricsLabel)
                    }
                    .disabled(lock.biometricsOn && !lock.hasPIN)
                } footer: {
                    Text("The iPhone's passcode never opens history. To turn this off, set a PIN first.")
                }
            }
            Section {
                SecureField(LocalizedStringKey(lock.hasPIN ? "New PIN" : "PIN"), text: $pin).keyboardType(.numberPad).textContentType(.oneTimeCode)
                SecureField("Repeat PIN", text: $again).keyboardType(.numberPad).textContentType(.oneTimeCode)
                Button(LocalizedStringKey(lock.hasPIN ? "Change PIN" : "Set PIN")) {
                    mismatch = !(pin == again && lock.setPIN(pin))
                    pin = ""
                    again = ""
                }
                .disabled(!HistoryLock.valid(pin) || again.isEmpty)
                if lock.hasPIN {
                    Button("Remove PIN", role: .destructive) { lock.removePIN() }.disabled(!lock.usesBiometrics)
                }
            } header: {
                Text("Poki PIN")
            } footer: {
                Text(LocalizedStringKey(mismatch ? "The two PINs did not match. Try again." : "A PIN of 4 to 8 digits that belongs to Poki alone. One of the two ways in always stays on."))
            }
        }
        .navigationTitle(AppLocalization.text("Screen History Lock"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
