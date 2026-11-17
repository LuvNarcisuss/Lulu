import UIKit
import Combine

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    fileprivate let store = TravelStore()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        store.payments.startObservingPayments()
        return true
    }

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
        guard let scene = scene as? UIWindowScene, let application = UIApplication.shared.delegate as? AppDelegate else { return }
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = Palette.cream
        let coordinator = TravelCoordinator(window: window, store: application.store)
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
    private let store: TravelStore
    private var observation: AnyCancellable?
    private var pendingFriendID: String?
    init(window: UIWindow, store: TravelStore) {
        self.window = window
        self.store = store
    }
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

final class EntryController: TravelScreen, UITextViewDelegate {
    override var usesScrolling: Bool { false }
    var onEntry: (() -> Void)?
    private let artwork = UIImageView(image: UIImage(named: "background-welcome"))
    private var accepted = false
    private var signingIn = false
    private var feedback: String?

    override func viewDidLoad() {
        automaticRefresh = false
        showsReadFailureOverlay = false
        content.spacing = 10
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 24
        artwork.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        artwork.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        let artworkHeight = artwork.heightAnchor.constraint(equalToConstant: 280)
        artworkHeight.priority = .defaultLow
        artworkHeight.isActive = true
        super.viewDidLoad()
        content.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -24).isActive = true
    }

    override func render() {
        super.render()
        navigationController?.setNavigationBarHidden(true, animated: false)
        content.addArrangedSubview(artwork)
        let flexibleSpace = UIView()
        flexibleSpace.heightAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        content.addArrangedSubview(flexibleSpace)
        content.addArrangedSubview(text("Lulu", 40, display: true))
        content.addArrangedSubview(text("Real places. Small discoveries. Stories worth taking home.", 17, color: Palette.muted))
        content.addArrangedSubview(agreementConsentRow())
        if let feedback { content.addArrangedSubview(text(feedback, 15, color: Palette.coral)) }
        let start = action("Start exploring", icon: "icon-route") { [weak self] in
            guard let self, !self.signingIn else { return }
            guard self.accepted else {
                self.askForConsent()
                return
            }
            self.continueEntry()
        }
        start.isEnabled = !signingIn
        start.configuration?.showsActivityIndicator = signingIn
        start.accessibilityValue = signingIn ? "Signing in" : nil
        content.addArrangedSubview(start)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func askForConsent() {
        guard !signingIn, presentedViewController == nil else { return }
        let reminder = agreementText("To log in, please agree to the Terms of Service and Privacy Policy.")
        let dialog = AgreementConsentDialog(reminder: reminder) { [weak self] in
            guard let self else { return }
            self.accepted = true
            self.continueEntry()
        }
        present(dialog, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func continueEntry() {
        guard accepted, !signingIn else { return }
        signingIn = true
        feedback = nil
        render()
        Task {
            do {
                try await store.signInWithOneTap()
            } catch is CancellationError {
            } catch {
                feedback = "Unable to sign in. Tap Start exploring to try again."
            }
            signingIn = false
            if store.isAuthenticated {
                onEntry?()
            } else {
                render()
            }
        }
    }

    private func agreementConsentRow() -> UIStackView {
        var configuration = UIButton.Configuration.plain()
        configuration.background.backgroundColor = accepted ? Palette.paper : .clear
        configuration.background.strokeColor = Palette.teal
        configuration.background.strokeWidth = 1.5
        configuration.background.cornerRadius = 5
        configuration.background.backgroundInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.contentInsets = .zero
        if accepted {
            configuration.image = UIImage(named: "icon-check")?.preparingThumbnail(of: CGSize(width: 22, height: 22))
        }

        let checkbox = UIButton(configuration: configuration)
        checkbox.widthAnchor.constraint(equalToConstant: 44).isActive = true
        checkbox.heightAnchor.constraint(equalToConstant: 44).isActive = true
        checkbox.isEnabled = !signingIn
        checkbox.accessibilityLabel = "Agree to the Terms of Service and Privacy Policy"
        checkbox.accessibilityValue = accepted ? "Checked" : "Unchecked"
        checkbox.accessibilityTraits = accepted ? [.button, .selected] : .button
        checkbox.addAction(UIAction { [weak self] _ in
            guard let self, !self.signingIn else { return }
            self.accepted.toggle()
            self.render()
        }, for: .touchUpInside)

        let sentence = agreementText("I agree to the Terms of Service and Privacy Policy.")
        sentence.textContainerInset = .init(top: 8, left: 0, bottom: 8, right: 0)
        let row = line([checkbox, sentence], spacing: 4)
        row.alignment = .top
        return row
    }

    private func agreementText(_ sentence: String) -> UITextView {
        let agreementText = UITextView()
        agreementText.backgroundColor = .clear
        agreementText.isEditable = false
        agreementText.isSelectable = true
        agreementText.isScrollEnabled = false
        agreementText.adjustsFontForContentSizeCategory = true
        agreementText.textContainerInset = .zero
        agreementText.textContainer.lineFragmentPadding = 0
        agreementText.setContentCompressionResistancePriority(.required, for: .vertical)
        agreementText.delegate = self
        agreementText.linkTextAttributes = [
            .foregroundColor: Palette.teal,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let body = NSMutableAttributedString(string: sentence, attributes: [
            .font: FontBook.font(16),
            .foregroundColor: Palette.ink
        ])
        for document in TravelAgreement.allCases {
            body.addAttribute(.link, value: document.consentLink, range: (sentence as NSString).range(of: document.title))
        }
        agreementText.attributedText = body

        return agreementText
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in range: NSRange,
                  interaction: UITextItemInteraction) -> Bool {
        if #available(iOS 17.0, *) { return true }
        openAgreement(for: url)
        return false
    }

    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return UIAction { [weak self] _ in self?.openAgreement(for: url) }
    }

    private func openAgreement(for url: URL) {
        guard !signingIn, let document = TravelAgreement.allCases.first(where: { $0.consentLink == url }) else { return }
        let reader = AgreementController(store: store, document: document)
        guard let dialog = presentedViewController as? AgreementConsentDialog else {
            push(reader)
            return
        }
        guard dialog.presentedViewController == nil else { return }
        let navigation = UINavigationController(rootViewController: reader)
        reader.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: iconButton("icon-close", label: "Close agreement") { [weak navigation] in
            navigation?.dismiss(animated: true)
        })
        dialog.present(navigation, animated: true)
    }
}

private final class AgreementConsentDialog: UIViewController {
    private let reminder: UITextView
    private let onAgree: () -> Void

    init(reminder: UITextView, onAgree: @escaping () -> Void) {
        self.reminder = reminder
        self.onAgree = onAgree
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.accessibilityViewIsModal = true
        let heading = text("Before you log in", 23, display: true)
        heading.accessibilityTraits = .header
        let agree = action("Agree and log in") { [weak self] in
            guard let self else { return }
            self.close(then: self.onAgree)
        }
        let decline = action("Disagree", filled: false) { [weak self] in self?.close() }
        let panel = card([heading, reminder, agree, decline], color: Palette.cream)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        let safeArea = view.safeAreaLayoutGuide
        let width = panel.widthAnchor.constraint(equalToConstant: 320)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            width,
            panel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -16)
        ])
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    private func close(then work: (() -> Void)? = nil) {
        guard view.isUserInteractionEnabled else { return }
        view.isUserInteractionEnabled = false
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: work)
    }
}

final class TravelTabController: UIViewController, UINavigationControllerDelegate {
    private let store: TravelStore
    private var controllers: [UINavigationController] = []
    private let dock = UIStackView()
    private var buttons: [UIButton] = []
    private var current = -1
    private var hasAppeared = false
    init(store: TravelStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.cream
        controllers = [ShortsController(store: store), ExploreController(store: store), JourneysController(store: store), ChatsController(store: store), MeController(store: store)].map { root in
            let nav = UINavigationController(rootViewController: root)
            nav.delegate = self
            if !(root is ShortsController) {
                root.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: appLogoView())
            }
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
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hasAppeared = false
    }

    private func select(_ index: Int) {
        guard index != current else { return }
        if current >= 0 {
            let old = controllers[current]
            old.willMove(toParent: nil)
            if hasAppeared { old.beginAppearanceTransition(false, animated: false) }
            old.view.removeFromSuperview()
            if hasAppeared { old.endAppearanceTransition() }
            old.removeFromParent()
        }
        current = index
        let selected = controllers[index]
        addChild(selected)
        if hasAppeared { selected.beginAppearanceTransition(true, animated: false) }
        selected.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(selected.view, belowSubview: dock)
        NSLayoutConstraint.activate([
            selected.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), selected.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selected.view.topAnchor.constraint(equalTo: view.topAnchor), selected.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        selected.didMove(toParent: self)
        if hasAppeared { selected.endAppearanceTransition() }
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
        navigationController.setNavigationBarHidden(viewController is ClipFeedController, animated: animated)
        dock.isHidden = navigationController.viewControllers.first !== viewController
    }
}
