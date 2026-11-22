import SwiftUI

/// Localized release-note text held inside the single What's New catalog so every release edits one file.
struct WhatsNewText: Equatable {
    let en: String
    let zhHans: String
    let zhHant: String

    func resolved(for language: String = AppLocalization.language) -> String {
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh-HK") || language.hasPrefix("zh-TW") {
            return zhHant
        }
        if language.hasPrefix("zh") {
            return zhHans
        }
        return en
    }
}

/// One highlighted change shown in the What's New card.
struct WhatsNewItem: Equatable, Identifiable {
    let id: String
    let symbol: String
    let title: WhatsNewText
    let summary: WhatsNewText
}

/// The release notes for one Poki version, shared between the post-update popup and Settings > About.
struct WhatsNewRelease: Equatable, Identifiable {
    var id: String { version }
    let version: String
    let items: [WhatsNewItem]
}

/// Single source of truth for What's New content. Update `current` on each release.
enum WhatsNewCatalog {
    static let current = WhatsNewRelease(
        version: "0.5.0",
        items: [
            WhatsNewItem(
                id: "result-cards",
                symbol: "rectangle.grid.1x2",
                title: WhatsNewText(
                    en: "Rich Result Cards",
                    zhHans: "结果卡片上线",
                    zhHant: "結果卡片上線"
                ),
                summary: WhatsNewText(
                    en: "Shows visual cards with photos for travel, shopping, food, and transit.",
                    zhHans: "查机酒、商品、美食和换乘直接出带图卡片。",
                    zhHant: "查機酒、商品、美食與轉乘直接出帶圖卡片。"
                )
            ),
            WhatsNewItem(
                id: "task-memory",
                symbol: "bookmark",
                title: WhatsNewText(
                    en: "Task Memory",
                    zhHans: "任务记忆与复用",
                    zhHant: "任務記憶與重用"
                ),
                summary: WhatsNewText(
                    en: "Remembers your preferences and steps to finish repeat tasks faster.",
                    zhHans: "记住常用偏好与步骤，同类任务更快更准。",
                    zhHant: "記住常用偏好與步驟，同類任務更快更準。"
                )
            ),
            WhatsNewItem(
                id: "voice-speed",
                symbol: "waveform",
                title: WhatsNewText(
                    en: "Smoother Voice & Speed",
                    zhHans: "实时语音与提速",
                    zhHant: "即時語音與提速"
                ),
                summary: WhatsNewText(
                    en: "More natural voice updates, cleaner interrupts, and quicker app launches.",
                    zhHans: "语音播报与打断更自然，应用操作更利落。",
                    zhHant: "語音播報與打斷更自然，App 操作更俐落。"
                )
            ),
            WhatsNewItem(
                id: "native-wardrobe",
                symbol: "hanger",
                title: WhatsNewText(
                    en: "Native iOS Wardrobe",
                    zhHans: "原生风格换装页",
                    zhHant: "原生風格換裝頁"
                ),
                summary: WhatsNewText(
                    en: "Redesigned with native iOS interactions, all outfits and headwear on one page.",
                    zhHans: "升级原生交互体验，装扮与配饰一页搞定。",
                    zhHant: "升級原生互動體驗，裝扮與配飾一頁搞定。"
                )
            ),
            WhatsNewItem(
                id: "stability-fixes",
                symbol: "checkmark.shield",
                title: WhatsNewText(
                    en: "Launch & Approval Fixes",
                    zhHans: "启动与确认更稳定",
                    zhHant: "啟動與確認更穩定"
                ),
                summary: WhatsNewText(
                    en: "Fixed launch crashes on newer iPhones, false Photos prompts, and island approvals.",
                    zhHans: "修好冷启动闪退、相册误判和灵动岛确认。",
                    zhHant: "修好冷啟動閃退、相簿誤判與動態島確認。"
                )
            ),
        ]
    )
}

/// Decides whether What's New should appear once after an update, and never on a fresh install.
enum WhatsNew {
    static let seenVersionKey = "pokiWhatsNewSeenVersion"

    /// Call at launch right after `FirstRun.decide(...)`.
    /// Fresh installs record the current version as seen so they never get What's New on install.
    nonisolated static func decide(
        currentVersion: String = WhatsNewCatalog.current.version,
        defaults: UserDefaults = .standard,
        sessionsFolder: URL = SessionStore.defaultFolder
    ) {
        guard !currentVersion.isEmpty else { return }
        let firstRun = defaults.string(forKey: FirstRun.key)
        let isFreshInstall: Bool
        if let firstRun {
            isFreshInstall = firstRun == FirstRun.Record.due.rawValue
        } else {
            isFreshInstall = !EarlierVersion.leftTraces(defaults: defaults, sessionsFolder: sessionsFolder)
        }
        if isFreshInstall {
            defaults.set(currentVersion, forKey: seenVersionKey)
        }
    }

    /// Pure decision based on persisted state (used by `isDueAtLaunch` and unit tests).
    nonisolated static func shouldPresent(
        currentVersion: String = WhatsNewCatalog.current.version,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !currentVersion.isEmpty else { return false }
        if defaults.string(forKey: FirstRun.key) == FirstRun.Record.due.rawValue { return false }
        return defaults.string(forKey: seenVersionKey) != currentVersion
    }

    /// Launch-time gate that respects scripted `-poki…` launches and XCTest runs.
    static func isDueAtLaunch(
        currentVersion: String = WhatsNewCatalog.current.version,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        if arguments["pokiScreen"] as? String == "whatsNew" { return true }
        if ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil { return false }
        if arguments.keys.contains(where: { $0.hasPrefix("poki") }) { return false }
        return shouldPresent(currentVersion: currentVersion, defaults: defaults)
    }

    nonisolated static func markSeen(
        version: String = WhatsNewCatalog.current.version,
        defaults: UserDefaults = .standard
    ) {
        guard !version.isEmpty else { return }
        defaults.set(version, forKey: seenVersionKey)
    }
}

/// Motion-equivalent SwiftUI spring timings for the What's New sheet.
private enum WhatsNewMotion {
    static let headerSpring = Animation.interpolatingSpring(mass: 1, stiffness: 260, damping: 22)
    static let cardSpring = Animation.interpolatingSpring(mass: 1, stiffness: 240, damping: 24).delay(0.06)
    static let buttonSpring = Animation.interpolatingSpring(mass: 1, stiffness: 240, damping: 24).delay(0.16)
    static func rowSpring(index: Int) -> Animation {
        Animation.interpolatingSpring(mass: 1, stiffness: 250, damping: 24).delay(0.10 + Double(index) * 0.04)
    }
    static let pressSpring = Animation.spring(duration: 0.22, bounce: 0.2)
}

/// Full-screen post-update highlights card featuring Poki, the release badge, and a grouped list of changes.
struct WhatsNewView: View {
    var release: WhatsNewRelease = WhatsNewCatalog.current
    var onContinue: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var iconCircleSize: CGFloat = 38
    @State private var appeared = false

    private var dark: Bool { scheme == .dark }
    private var isChinese: Bool { AppLocalization.language.hasPrefix("zh") }

    private static let primaryInk = Color(light: 0x11191C, dark: 0xF2F4F7)
    private static let secondaryInk = Color(light: 0x5F676C, dark: 0x9BA5B4)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 24)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                        .offset(y: appeared || reduceMotion ? 0 : 10)
                        .animation(reduceMotion ? nil : WhatsNewMotion.headerSpring, value: appeared)

                    card
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 16)
                        .animation(reduceMotion ? nil : WhatsNewMotion.cardSpring, value: appeared)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            continueBar
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 12)
                .animation(reduceMotion ? nil : WhatsNewMotion.buttonSpring, value: appeared)
        }
        .background { backdrop }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsNew.screen")
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                appeared = true
            }
        }
    }

    private var backdrop: some View {
        LinearGradient(
            stops: dark
                ? [
                    .init(color: Color(hex: 0x0D2C68), location: 0.0),
                    .init(color: Color(hex: 0x081736), location: 0.28),
                    .init(color: Tint.page, location: 0.56),
                    .init(color: Tint.page, location: 1.0),
                ]
                : [
                    .init(color: Color(hex: 0xDCEBFF), location: 0.0),
                    .init(color: Color(hex: 0xEDF4FE), location: 0.26),
                    .init(color: Tint.page, location: 0.54),
                    .init(color: Tint.page, location: 1.0),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                if dark {
                    RadialGradient(
                        stops: [
                            .init(color: Color(hex: 0x4C9DFF).opacity(0.34), location: 0.0),
                            .init(color: Tint.blue.opacity(0.14), location: 0.36),
                            .init(color: Tint.blue.opacity(0.0), location: 0.68),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 56
                    )
                    .frame(width: 112, height: 112)
                } else {
                    RadialGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.92), location: 0.0),
                            .init(color: Color(hex: 0xE3EEFF).opacity(0.42), location: 0.38),
                            .init(color: Color(hex: 0xE3EEFF).opacity(0.0), location: 0.70),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 54
                    )
                    .frame(width: 108, height: 108)
                }

                if let image = PokiMood.cutout(.ready, small: true) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: 0.78),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                let effectiveTitleSize = min(titleSize, 40)
                Text(verbatim: AppLocalization.text(LocalizedStringResource("What’s New")))
                    .font(.system(size: effectiveTitleSize, weight: isChinese ? .semibold : .bold))
                    .tracking(-0.02 * effectiveTitleSize)
                    .foregroundStyle(Self.primaryInk)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("whatsNew.title")

                Text(verbatim: "Poki \(release.version)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tint.blueText)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule().fill(dark ? Color.white.opacity(0.10) : Color.white.opacity(0.76))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            dark ? Color.white.opacity(0.16) : Color.white.opacity(0.92),
                            lineWidth: 1
                        )
                    )
                    .shadow(
                        color: dark ? .clear : Color(hex: 0x183878).opacity(0.07),
                        radius: 5,
                        y: 2
                    )
                    .accessibilityIdentifier("whatsNew.version")
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let circle = min(48, max(36, iconCircleSize))
        let dividerLeading = 16 + circle + 13
        let language = AppLocalization.language

        return VStack(spacing: 0) {
            ForEach(Array(release.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(dark ? Color.white.opacity(0.09) : Color(hex: 0xEEF2F7))
                        .frame(height: 1)
                        .padding(.leading, dividerLeading)
                        .padding(.trailing, 16)
                }

                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: item.symbol)
                        .font(.system(size: circle * 0.41, weight: .medium))
                        .foregroundStyle(Tint.blueText)
                        .frame(width: circle, height: circle)
                        .background(Tint.blueSoft, in: .circle)
                        .padding(.top, 1)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.title.resolved(for: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Self.primaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: item.summary.resolved(for: language))
                            .font(.footnote)
                            .foregroundStyle(Self.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("whatsNew.item.\(item.id)")
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 8)
                .animation(reduceMotion ? nil : WhatsNewMotion.rowSpring(index: index), value: appeared)
            }
        }
        .padding(.vertical, 8)
        .background(
            shape.fill(dark ? Color(hex: 0x141B29).opacity(0.90) : Color.white.opacity(0.94))
        )
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(dark ? Color.white.opacity(0.12) : Color.white, lineWidth: 1)
        )
        .shadow(
            color: dark ? Color.black.opacity(0.34) : Color(hex: 0x11191C).opacity(0.08),
            radius: dark ? 14 : 16,
            y: dark ? 8 : 5
        )
    }

    private var continueBar: some View {
        Button(action: onContinue) {
            Text(verbatim: AppLocalization.text(LocalizedStringResource("Continue")))
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(hex: 0x1E88FF), Tint.blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        Color.white.opacity(dark ? 0.22 : 0.32),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: dark ? .clear : Tint.blue.opacity(0.32),
                    radius: 14,
                    y: 8
                )
                .contentShape(.capsule)
        }
        .buttonStyle(WhatsNewContinueButtonStyle(reduceMotion: reduceMotion))
        .accessibilityIdentifier("whatsNew.continue")
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

private struct WhatsNewContinueButtonStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : WhatsNewMotion.pressSpring, value: configuration.isPressed)
    }
}
