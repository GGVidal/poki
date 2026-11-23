import SwiftUI


/// The two speed-ups being tried (General › Testing Options), both on unless turned off there.
enum SpeedOptions {
    static let appNamesKey = "testing.appNames"
    static let quickReadKey = "testing.quickRead"
    static var appNames: Bool { UserDefaults.standard.object(forKey: appNamesKey) as? Bool ?? true }
    static var quickRead: Bool { UserDefaults.standard.object(forKey: quickReadKey) as? Bool ?? true }
}

/// General › Testing Options: the switches for the two speed-ups.
struct SpeedTestingSection: View {
    @AppStorage(SpeedOptions.appNamesKey) private var appNames = true
    @AppStorage(SpeedOptions.quickReadKey) private var quickRead = true
    var body: some View {
        Section {
            Toggle("Apps by Name", isOn: $appNames)
            Toggle("Read When the Screen Settles", isOn: $quickRead)
        } header: {
            Text("Speed")
        } footer: {
            Text("On by default. Apps by Name lets an agent open an app by its name and keep it as the app it works in. Read When the Screen Settles reads the screen as soon as it has changed and holds still after an app opens, a swipe or a button, in place of a fixed pause. Changes count from the next step.")
        }
        #if POKI_EXPERIMENTS
        BackgroundTestingSection()
        #endif
    }
}

#if POKI_EXPERIMENTS
/// Poki Lab only (issue #656): the switch for steps in an app that stays in the background.
struct BackgroundTestingSection: View {
    @AppStorage(BackgroundRoute.key) private var on = false
    var body: some View {
        Section {
            Toggle("Work in the Background", isOn: $on)
                .accessibilityIdentifier("testing.background")
        } header: {
            Text("Experiments")
        } footer: {
            Text("Off by default. Lets an agent read an app and press some of its controls while the app stays behind the one you are using. Steps that need the app in front still bring it forward. Changes count from the next task.")
        }
    }
}
#endif
