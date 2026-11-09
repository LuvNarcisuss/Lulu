import UIKit
import Combine
import SafariServices

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { LaunchServices.shared.registered(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { LaunchServices.shared.registrationFailed() }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .portrait }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: TravelCoordinator?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = Palette.cream
        let coordinator = TravelCoordinator(window: window)
        self.window = window
        self.coordinator = coordinator
        coordinator.start()
        for context in connectionOptions.urlContexts { coordinator.open(context.url) }
        window.makeKeyAndVisible()
    }
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for context in contexts { coordinator?.open(context.url) }
    }
}

@MainActor final class TravelCoordinator {
    private let window: UIWindow
    private let store = TravelStore()
    private var observation: AnyCancellable?
    private var pendingFriendID: String?
    init(window: UIWindow) { self.window = window }
    func start() {
        LaunchServices.shared.start()
        configureAppearance()
        showEntry()
        observation = store.$isAuthenticated.removeDuplicates().dropFirst().sink { [weak self] authenticated in
            if !authenticated { self?.showEntry() }
        }
    }
    private func showEntry() {
        let welcome = EntryController(store: store)
        welcome.onEntry = { [weak self] in
            guard let self else { return }
            let tabs = TravelTabController(store: self.store)
            self.window.rootViewController = tabs
            if let friendID = self.pendingFriendID { self.pendingFriendID = nil; tabs.loadViewIfNeeded(); tabs.openFriend(friendID) }
        }
        window.rootViewController = UINavigationController(rootViewController: welcome)
    }
    func open(_ url: URL) {
        guard let memberID = TravelFriendCode.memberID(from: url.absoluteString) else { return }
        if let tabs = window.rootViewController as? TravelTabController { tabs.openFriend(memberID) }
        else { pendingFriendID = memberID }
    }
    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.font: FontBook.font(23, display: true), .foregroundColor: Palette.ink]
        appearance.largeTitleTextAttributes = [.font: FontBook.font(34, display: true), .foregroundColor: Palette.ink]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: FontBook.font(16), .foregroundColor: Palette.teal]
        appearance.buttonAppearance = button
        appearance.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = Palette.teal
        UITextView.appearance().font = FontBook.font(16)
        UISearchBar.appearance().tintColor = Palette.teal
    }
}

final class EntryController: TravelScreen {
    var onEntry: (() -> Void)?
    private var accepted = false
    private var started = false
    private var loginBusy = false
    override func viewDidLoad() { automaticRefresh = false; showsReadFailureOverlay = false; super.viewDidLoad() }
    override func render() {
        super.render()
        navigationController?.setNavigationBarHidden(true, animated: false)
        let artwork = UIImageView(image: UIImage(named: "background-welcome"))
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 30
        artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 1.08).isActive = true
        content.addArrangedSubview(artwork)
        content.addArrangedSubview(text(started ? "Your next chapter." : "A little further.", 40, display: true))
        content.addArrangedSubview(text(started ? "Save places, make a plan, and meet along the way." : "Real places. Small discoveries. Stories worth taking home.", 19, color: Palette.muted))
        if !started {
            content.addArrangedSubview(action("Start exploring", icon: "icon-route") { [weak self] in self?.started = true; self?.render() })
            content.addArrangedSubview(text("Travel inspiration across Europe & North America", 13, color: Palette.muted))
            return
        }
        content.addArrangedSubview(text("A guest account keeps your journeys and conversations together. Keep this installation to retain access; an unlinked guest account cannot be recovered after access is lost.", 14, color: Palette.muted))
        let consent = action(accepted ? "Agreed to Terms & Privacy" : "I agree to Terms & Privacy", icon: accepted ? "icon-check" : "icon-save", filled: false) { [weak self] in
            self?.accepted.toggle(); self?.render()
        }
        consent.accessibilityTraits.insert(.button)
        consent.accessibilityValue = accepted ? "Checked" : "Unchecked"
        content.addArrangedSubview(consent)
        content.addArrangedSubview(line([
            action("Terms of Service", filled: false) { [weak self] in self?.openAgreement("termsURL") },
            action("Privacy Policy", filled: false) { [weak self] in self?.openAgreement("privacyURL") }
        ]))
        let login = action(loginBusy ? "Opening your travel book…" : "Log in", icon: "icon-globe") { [weak self] in
            guard let self, !self.loginBusy else { return }
            guard self.accepted else {
                self.confirm("Before you explore", message: "Please read and agree to the Terms of Service and Privacy Policy to continue.", actionTitle: "Agree and continue") {
                    self.accepted = true
                    self.logIn()
                }
                return
            }
            self.logIn()
        }
        login.isEnabled = !loginBusy
        if loginBusy { login.configuration?.showsActivityIndicator = true }
        content.addArrangedSubview(login)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    private func logIn() {
        guard !loginBusy else { return }
        loginBusy = true; render()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.login()
                try await self.store.perform("profile.update", ["consent_version": .string(BackendConfiguration.consentVersion)])
                self.loginBusy = false
                self.onEntry?()
            } catch {
                self.loginBusy = false
                self.render()
                self.notice(error.localizedDescription)
            }
        }
    }
    private func openAgreement(_ key: String) {
        push(AgreementController(store: store, title: key == "termsURL" ? "Terms of Service" : "Privacy Policy", configurationKey: key, resource: key == "termsURL" ? "TermsOfService" : "PrivacyPolicy"))
    }

}

final class TravelTabController: UIViewController, UINavigationControllerDelegate {
    private let store: TravelStore
    private var controllers: [UINavigationController] = []
    private let dock = UIStackView()
    private var buttons: [UIButton] = []
    private var current = -1
    init(store: TravelStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.cream
        controllers = [ShortsController(store: store), ExploreController(store: store), JourneysController(store: store), ChatsController(store: store), MeController(store: store)].map { root in
            let nav = UINavigationController(rootViewController: root)
            nav.delegate = self
            root.additionalSafeAreaInsets.bottom = 84
            return nav
        }
        dock.axis = .horizontal
        dock.distribution = .fillEqually
        dock.spacing = 2
        dock.backgroundColor = Palette.paper
        dock.layer.cornerRadius = 30
        dock.layer.borderWidth = 1
        dock.layer.borderColor = Palette.line.cgColor
        dock.isLayoutMarginsRelativeArrangement = true
        dock.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6)
        let names = ["Shorts", "Explore", "Journeys", "Chats", "Me"]
        let icons = ["icon-shorts", "icon-explore", "icon-journeys", "icon-chats", "icon-profile"]
        for index in names.indices {
            let button = UIButton(type: .custom)
            var config = UIButton.Configuration.plain()
            config.title = names[index]
            config.image = UIImage(named: icons[index])?.preparingThumbnail(of: CGSize(width: 29, height: 29))
            config.imagePlacement = .top
            config.imagePadding = 3
            config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
            config.baseForegroundColor = Palette.ink
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var result = incoming; result.font = FontBook.font(11); return result
            }
            button.configuration = config
            button.accessibilityLabel = names[index]
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            buttons.append(button); dock.addArrangedSubview(button)
        }
        dock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dock)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6), dock.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
        select(0)
    }
    private func select(_ index: Int) {
        guard index != current else { return }
        if current >= 0 {
            let old = controllers[current]
            old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent()
        }
        current = index
        let selected = controllers[index]
        addChild(selected)
        selected.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(selected.view, belowSubview: dock)
        NSLayoutConstraint.activate([
            selected.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), selected.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selected.view.topAnchor.constraint(equalTo: view.topAnchor), selected.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        selected.didMove(toParent: self)
        for (position, button) in buttons.enumerated() {
            button.backgroundColor = position == index ? Palette.ochre.withAlphaComponent(0.36) : .clear
            button.layer.cornerRadius = 24
            button.accessibilityTraits = position == index ? [.button, .selected] : [.button]
        }
        dock.isHidden = selected.viewControllers.count != 1
    }
    func openFriend(_ id: String) {
        loadViewIfNeeded()
        guard store.isAuthenticated, id != store.userID,
              let profile = store.rows("profiles").first(where: { $0.id.lowercased() == id.lowercased() }), !profile.bool("is_editorial") else { return }
        select(3)
        controllers[3].pushViewController(PublicProfileController(store: store, profileID: profile.id), animated: true)
    }
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.setNavigationBarHidden(false, animated: animated)
        dock.isHidden = navigationController.viewControllers.first !== viewController
    }
}
