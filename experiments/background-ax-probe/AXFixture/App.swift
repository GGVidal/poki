import SwiftUI
import UIKit

// Fixture for the background accessibility probe. Every handler logs "FIXLOG <event>" (NSLog,
// read with `simctl spawn <sim> log show`) and writes the event into an on-screen label whose
// accessibility identifier is "lastEvent", so a background read can see it too.

enum Fix {
    static var count = 0
    static weak var label: UILabel?
    static let t0 = Date()
    static func log(_ event: String) {
        count += 1
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        NSLog("FIXLOG %d %d %@ state=%d", count, ms, event, UIApplication.shared.applicationState.rawValue)
        label?.text = "\(count) \(event)"
        label?.accessibilityValue = "\(count) \(event)"
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: session.role); c.delegateClass = SceneDelegate.self; return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: scene)
        let tabs = UITabBarController()
        tabs.delegate = self
        let nav = UINavigationController(rootViewController: ControlsController())
        nav.delegate = NavLogger.shared
        nav.tabBarItem = UITabBarItem(title: "Controls", image: UIImage(systemName: "slider.horizontal.3"), tag: 0)
        let second = SecondController(); second.tabBarItem = UITabBarItem(title: "Second", image: UIImage(systemName: "2.circle"), tag: 1)
        let swiftUI = UIHostingController(rootView: SwiftUIScreens()); swiftUI.tabBarItem = UITabBarItem(title: "SwiftUI", image: UIImage(systemName: "swift"), tag: 2)
        tabs.viewControllers = [nav, second, swiftUI]
        w.rootViewController = tabs
        w.makeKeyAndVisible()
        window = w
    }
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) { Fix.log("tab.didSelect \(viewController.tabBarItem.title ?? "")") }
    func sceneDidEnterBackground(_ scene: UIScene) { Fix.log("scene.didEnterBackground"); logWindow("didEnterBackground") }
    func sceneDidBecomeActive(_ scene: UIScene) { logWindow("didBecomeActive") }
    func sceneWillResignActive(_ scene: UIScene) { logWindow("willResignActive") }
    var windowTimer: Timer?
    func logWindow(_ tag: String) {
        guard let w = window else { return }
        let ctx = (w.value(forKey: "_contextId") as? NSNumber)?.uint32Value ?? 0
        let layerContext = (w.layer.value(forKey: "context") as AnyObject?).map { "\($0)" } ?? "nil"
        NSLog("FIXLOG window %@ contextId=%u layer.context=%@ activation=%d hidden=%d", tag, ctx, layerContext, w.windowScene?.activationState.rawValue ?? -9, w.isHidden ? 1 : 0)
        if windowTimer == nil { windowTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.logWindow("tick") } }
    }
    func sceneWillEnterForeground(_ scene: UIScene) { Fix.log("scene.willEnterForeground") }
}

final class NavLogger: NSObject, UINavigationControllerDelegate {
    static let shared = NavLogger()
    func navigationController(_ n: UINavigationController, willShow vc: UIViewController, animated: Bool) { Fix.log("nav.willShow \(vc.title ?? "") animated=\(animated)") }
    func navigationController(_ n: UINavigationController, didShow vc: UIViewController, animated: Bool) { Fix.log("nav.didShow \(vc.title ?? "")") }
}

/// An element that logs every UIKit accessibility entry point, used to map action numbers to names.
final class ProbeTarget: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        text = "Probe target"; isAccessibilityElement = true; accessibilityLabel = "Probe target"; accessibilityIdentifier = "probeTarget"
        accessibilityTraits = [.button, .adjustable]
        isUserInteractionEnabled = true
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Custom one") { _ in Fix.log("ax.customAction one"); return true }]
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityActivate() -> Bool { Fix.log("ax.activate"); return true }
    override func accessibilityPerformEscape() -> Bool { Fix.log("ax.escape"); return true }
    override func accessibilityIncrement() { Fix.log("ax.increment") }
    override func accessibilityDecrement() { Fix.log("ax.decrement") }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool { Fix.log("ax.scroll \(direction.rawValue)"); return true }
    override func accessibilityPerformMagicTap() -> Bool { Fix.log("ax.magicTap"); return true }
    override func accessibilityZoomIn(at point: CGPoint) -> Bool { Fix.log("ax.zoomIn"); return true }
    override func accessibilityZoomOut(at point: CGPoint) -> Bool { Fix.log("ax.zoomOut"); return true }
    override func accessibilityElementDidBecomeFocused() { Fix.log("ax.didBecomeFocused") }
}

class LoggingController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); Fix.log("vc.didAppear \(title ?? "")")
        transitionCoordinator?.animate(alongsideTransition: nil) { _ in Fix.log("vc.transitionComplete \(self.title ?? "")") }
    }
    override func accessibilityPerformEscape() -> Bool { Fix.log("vc.escape \(title ?? "")"); return super.accessibilityPerformEscape() }
}

final class ControlsController: LoggingController, UITableViewDataSource, UITableViewDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Controls"; view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Bar", style: .plain, target: self, action: #selector(bar))
        let label = UILabel(); label.accessibilityIdentifier = "lastEvent"; label.text = "0 start"; Fix.label = label
        let button = UIButton(type: .system); button.setTitle("Plain button", for: .normal); button.addTarget(self, action: #selector(plain), for: .primaryActionTriggered)
        let push = UIButton(type: .system); push.setTitle("Push level 2", for: .normal); push.addTarget(self, action: #selector(pushNext), for: .primaryActionTriggered)
        let sw = UISwitch(); sw.accessibilityLabel = "Switch"; sw.addTarget(self, action: #selector(switched(_:)), for: .valueChanged)
        let seg = UISegmentedControl(items: ["One", "Two", "Three"]); seg.selectedSegmentIndex = 0; seg.addTarget(self, action: #selector(segmented(_:)), for: .valueChanged)
        let slider = UISlider(); slider.accessibilityLabel = "Slider"; slider.addTarget(self, action: #selector(slid(_:)), for: .valueChanged)
        let field = UITextField(); field.borderStyle = .roundedRect; field.placeholder = "Field"; field.accessibilityIdentifier = "field"; field.addTarget(self, action: #selector(edited(_:)), for: .editingChanged)
        let alert = UIButton(type: .system); alert.setTitle("Show alert", for: .normal); alert.addTarget(self, action: #selector(showAlert), for: .primaryActionTriggered)
        let sheet = UIButton(type: .system); sheet.setTitle("Show sheet", for: .normal); sheet.addTarget(self, action: #selector(showSheet), for: .primaryActionTriggered)
        let probe = ProbeTarget()
        let table = UITableView(); table.dataSource = self; table.delegate = self; table.accessibilityIdentifier = "bigTable"; table.delegate = self
        let stack = UIStackView(arrangedSubviews: [label, probe, button, push, sw, seg, slider, field, alert, sheet])
        stack.axis = .vertical; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false; table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack); view.addSubview(table)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            table.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6), table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
    }
    @objc func bar() { Fix.log("barButton -> push level 2"); navigationController?.pushViewController(LevelTwoController(), animated: true) }
    @objc func plain() { Fix.log("button") }
    @objc func pushNext() { Fix.log("push.requested"); navigationController?.pushViewController(LevelTwoController(), animated: true) }
    @objc func switched(_ s: UISwitch) { Fix.log("switch \(s.isOn)") }
    @objc func segmented(_ s: UISegmentedControl) { Fix.log("segment \(s.selectedSegmentIndex)") }
    @objc func slid(_ s: UISlider) { Fix.log(String(format: "slider %.2f", s.value)) }
    @objc func edited(_ f: UITextField) { Fix.log("field \(f.text ?? "")") }
    @objc func showAlert() {
        let a = UIAlertController(title: "Alert", message: "Pick", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in Fix.log("alert.cancel") })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in Fix.log("alert.ok") })
        present(a, animated: true) { Fix.log("alert.presented") }
    }
    @objc func showSheet() {
        let s = SheetController(); s.title = "Sheet"
        present(UINavigationController(rootViewController: s), animated: true) { Fix.log("sheet.presented") }
    }
    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { 500 }
    func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = t.dequeueReusableCell(withIdentifier: "c") ?? UITableViewCell(style: .default, reuseIdentifier: "c")
        c.textLabel?.text = "Row \(i.row)"; return c
    }
    func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) { Fix.log("row.select \(i.row)") }
    func scrollViewDidScroll(_ s: UIScrollView) { if Int(s.contentOffset.y) % 200 < 20 { Fix.log("table.scroll \(Int(s.contentOffset.y))") } }
}

final class LevelTwoController: LoggingController {
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Level 2"; view.backgroundColor = .systemBackground
        let b = UIButton(type: .system); b.setTitle("Push level 3", for: .normal)
        b.addTarget(self, action: #selector(pushThree), for: .primaryActionTriggered)
        b.frame = CGRect(x: 40, y: 200, width: 200, height: 44); view.addSubview(b)
        let a = ActivatePush(frame: CGRect(x: 40, y: 260, width: 240, height: 44)); a.onActivate = { [weak self] in self?.pushThree() }; view.addSubview(a)
    }
    @objc func pushThree() { Fix.log("push3.requested"); navigationController?.pushViewController({ let v = LoggingController(); v.title = "Level 3"; v.view.backgroundColor = .systemBackground; return v }(), animated: true) }
}

final class ActivatePush: UILabel {
    var onActivate: (() -> Void)?
    override init(frame: CGRect) { super.init(frame: frame); text = "Activate push"; isAccessibilityElement = true; accessibilityLabel = "Activate push"; accessibilityTraits = .button }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityActivate() -> Bool { Fix.log("activatePush"); onActivate?(); return true }
}

final class SheetController: LoggingController {
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
    }
    @objc func close() { Fix.log("sheet.close"); dismiss(animated: true) { Fix.log("sheet.dismissed") } }
}

final class SecondController: LoggingController {
    override func viewDidLoad() { super.viewDidLoad(); title = "Second"; view.backgroundColor = .systemBackground }
}

struct SwiftUIScreens: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                List {
                    NavigationLink("SwiftUI detail") { Text("Detail").onAppear { Fix.log("swiftui.detail.appear") } }
                    Button("SwiftUI button") { Fix.log("swiftui.button") }
                }.navigationTitle("SwiftUI")
            }.tabItem { Label("Inner A", systemImage: "a.circle") }.tag(0)
            Text("Inner B").onAppear { Fix.log("swiftui.innerB.appear") }.tabItem { Label("Inner B", systemImage: "b.circle") }.tag(1)
        }.onChange(of: tab) { _, v in Fix.log("swiftui.tab \(v)") }
    }
}
