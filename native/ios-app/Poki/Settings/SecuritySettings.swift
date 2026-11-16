import SwiftUI

// Security (the owner, 2026-11-16): what Poki may do by itself and what Backtape may read, on one
// page. Approvals come first, as they were on their own page; then Backtape's apps, access times,
// lock and what Poki may ask it; then the two records, the Activity Log and the Observing Record.

struct SecuritySettingsView: View {
    @ObservedObject private var capture = HistoryCapture.shared

    private var apps: String {
        let count = (capture.listMode == .exclude ? capture.excluded : capture.included).filter { !HistoryCapture.isPoki($0) }.count
        return "\(count)"
    }

    var body: some View {
        List {
            SecurityApprovalSections()

            Section {
                NavigationLink { HistoryGate { HistoryPermissionsPage().settingsPage() } } label: {
                    SettingsRow(title: capture.listMode == .exclude ? "Apps Backtape Leaves Out" : "Apps Backtape Reads", symbol: "square.grid.2x2", value: apps)
                }
                NavigationLink { BacktapeAccessTimesPage().settingsPage() } label: {
                    SettingsRow(title: "Access Times", symbol: "clock",
                                value: AppLocalization.text(capture.scheduleOn ? LocalizedStringResource("On") : LocalizedStringResource("Off")))
                }
                NavigationLink { HistoryGate { HistoryLockSettings().settingsPage() } } label: {
                    SettingsRow(title: "Backtape Lock", symbol: "lock")
                }
                Toggle(isOn: $capture.agentAsks) {
                    SettingsRow(title: "Poki Can Ask Backtape", symbol: "questionmark.bubble")
                }
            } header: {
                SettingsHeader("Backtape")
            } footer: {
                Text("During a task, Poki can ask what you recently did. A model on this iPhone writes a short answer and decides whether you must approve it before it goes to the model Poki runs on. Your screen text never leaves this iPhone. Each answer is listed in Observing Record.")
            }

            Section {
                NavigationLink(value: DetailsRoute.history) {
                    SettingsRow(title: "Activity Log", symbol: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("details.activity")
                NavigationLink { HistoryGate { HistoryRecordPage().settingsPage() } } label: {
                    SettingsRow(title: "Observing Record", symbol: "eye")
                }
            } header: {
                SettingsHeader("Records")
            } footer: {
                Text("The Activity Log lists every step Poki took and every approval. The Observing Record lists when Backtape was on, paused or left an app out.")
            }
        }
        .navigationTitle(AppLocalization.text("Security"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// When Backtape may read: always, or only on the chosen days between two times.
struct BacktapeAccessTimesPage: View {
    @ObservedObject private var capture = HistoryCapture.shared

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    var body: some View {
        List {
            Section {
                Toggle("Read Only at Set Times", isOn: $capture.scheduleOn)
                if capture.scheduleOn {
                    let symbols = Calendar.current.veryShortWeekdaySymbols
                    HStack(spacing: 0) {
                        ForEach(1...7, id: \.self) { day in
                            let on = capture.weekdays.contains(day)
                            Button {
                                if on { capture.weekdays.removeAll { $0 == day } } else { capture.weekdays = (capture.weekdays + [day]).sorted() }
                            } label: {
                                Text(verbatim: symbols.indices.contains(day - 1) ? symbols[day - 1] : "\(day)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(on ? Color.white : Color.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    DatePicker("From", selection: time($capture.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: time($capture.endMinute), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Outside these times nothing is read.")
            }
        }
        .navigationTitle(AppLocalization.text("Access Times"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
