import UIKit
import Combine

@MainActor enum Palette {
    static let ink = UIColor(red: 0.07, green: 0.20, blue: 0.22, alpha: 1)
    static let muted = UIColor(red: 0.29, green: 0.39, blue: 0.40, alpha: 1)
    static let teal = UIColor(red: 0.04, green: 0.34, blue: 0.35, alpha: 1)
    static let cream = UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1)
    static let paper = UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 0.96)
    static let ochre = UIColor(red: 0.96, green: 0.77, blue: 0.39, alpha: 1)
    static let coral = UIColor(red: 0.77, green: 0.28, blue: 0.19, alpha: 1)
    static let line = UIColor(red: 0.81, green: 0.84, blue: 0.79, alpha: 1)
}

@MainActor enum FontBook {
    static var bodyName = "Kalam-Regular"
    static var displayName = "FrauncesTravelDisplay-Semibold"
    static func font(_ size: CGFloat, display: Bool = false) -> UIFont {
        guard let font = UIFont(name: display ? displayName : bodyName, size: size) else {
            preconditionFailure("A required packaged font is missing.")
        }
        return UIFontMetrics(forTextStyle: display ? .title2 : .body).scaledFont(for: font)
    }
}

@MainActor func text(_ value: String, _ size: CGFloat = 16, color: UIColor = Palette.ink, display: Bool = false) -> UILabel {
    let label = UILabel()
    label.text = value
    label.font = FontBook.font(size, display: display)
    label.textColor = color
    label.numberOfLines = 0
    label.adjustsFontForContentSizeCategory = true
    label.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
    return label
}

@MainActor func column(_ views: [UIView] = [], spacing: CGFloat = 16) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    stack.spacing = spacing
    stack.alignment = .fill
    return stack
}

@MainActor func line(_ views: [UIView] = [], spacing: CGFloat = 12) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .horizontal
    stack.spacing = spacing
    stack.alignment = .center
    return stack
}

@MainActor func card(_ views: [UIView], color: UIColor = Palette.paper) -> UIView {
    let stack = column(views, spacing: 12)
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    stack.backgroundColor = color
    stack.layer.cornerRadius = 24
    stack.layer.borderColor = Palette.line.cgColor
    stack.layer.borderWidth = 0.7
    return stack
}

@MainActor func action(_ title: String, icon: String? = nil, filled: Bool = true, _ handler: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .custom)
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.baseForegroundColor = filled ? Palette.cream : Palette.teal
    configuration.background.backgroundColor = filled ? Palette.teal : Palette.cream
    configuration.background.cornerRadius = 17
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var result = incoming
        result.font = FontBook.font(16)
        return result
    }
    if let icon, let image = UIImage(named: icon) {
        configuration.image = image.preparingThumbnail(of: CGSize(width: 25, height: 25))
        configuration.imagePadding = 9
    }
    button.configuration = configuration
    button.titleLabel?.numberOfLines = 0
    let minimumHeight = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
    minimumHeight.priority = UILayoutPriority(999)
    minimumHeight.isActive = true
    button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
    button.accessibilityLabel = title
    return button
}

@MainActor func appLogoView() -> UIImageView {
    let logo = UIImageView(image: UIImage(named: "logo-lulu"))
    logo.translatesAutoresizingMaskIntoConstraints = false
    logo.contentMode = .scaleAspectFit
    logo.layer.cornerRadius = 8
    logo.clipsToBounds = true
    logo.isAccessibilityElement = true
    logo.accessibilityLabel = "Lulu logo"
    logo.accessibilityTraits = .image
    NSLayoutConstraint.activate([
        logo.widthAnchor.constraint(equalToConstant: 32),
        logo.heightAnchor.constraint(equalToConstant: 32)
    ])
    return logo
}

@MainActor func iconButton(_ name: String, label: String, _ handler: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(named: name)?.preparingThumbnail(of: CGSize(width: 27, height: 27)), for: .normal)
    button.backgroundColor = Palette.paper.withAlphaComponent(0.96)
    button.layer.cornerRadius = 22
    let width = button.widthAnchor.constraint(equalToConstant: 44)
    let height = button.heightAnchor.constraint(equalToConstant: 44)
    width.priority = UILayoutPriority(999); height.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([width, height])
    button.accessibilityLabel = label
    button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
    return button
}

@MainActor func input(_ placeholder: String, value: String = "") -> UITextField {
    let field = UITextField()
    field.placeholder = placeholder
    field.text = value
    field.font = FontBook.font(16)
    field.textColor = Palette.ink
    field.backgroundColor = Palette.paper
    field.layer.cornerRadius = 14
    field.layer.borderColor = Palette.line.cgColor
    field.layer.borderWidth = 1
    field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
    field.leftViewMode = .always
    field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
    field.rightViewMode = .always
    field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    field.accessibilityLabel = placeholder
    return field
}

@MainActor func spacer(_ height: CGFloat = 8) -> UIView {
    let view = UIView()
    view.heightAnchor.constraint(equalToConstant: height).isActive = true
    return view
}

@MainActor final class RemoteImageView: UIImageView {
    private var request: Task<Void, Never>?
    private var requestID = UUID()
    init(path: String, store: TravelStore, height: CGFloat, radius: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = Palette.cream
        layer.cornerRadius = radius
        clipsToBounds = true
        contentMode = .scaleAspectFill
        heightAnchor.constraint(equalToConstant: height).isActive = true
        load(path, store: store)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func load(_ path: String, store: TravelStore) {
        request?.cancel()
        let identity = UUID()
        requestID = identity
        image = UIImage(named: "icon-globe")
        guard !path.isEmpty else { return }
        request = Task { [weak self] in
            do {
                let url = try await store.mediaURL(path)
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: data), self?.requestID == identity else { return }
                self?.image = image
            } catch { /* Keep the generated travel placeholder when loading fails. */ }
        }
    }
    deinit { request?.cancel() }
}

@MainActor func remoteImage(_ path: String, store: TravelStore, height: CGFloat, radius: CGFloat = 20) -> RemoteImageView {
    RemoteImageView(path: path, store: store, height: height, radius: radius)
}

@MainActor class TravelScreen: UIViewController {
    let store: TravelStore
    let scroll = UIScrollView()
    let content = column(spacing: 20)
    private var observation: AnyCancellable?
    private var running = false
    private var visible = false
    var usesScrolling: Bool { true }
    var automaticRefresh = true
    var refreshWhileEditing = false
    var showsReadFailureOverlay = true

    init(store: TravelStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.cream
        let background = UIImageView(image: UIImage(named: "background-paper"))
        background.contentMode = .scaleAspectFill
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor), background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor), background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        content.translatesAutoresizingMaskIntoConstraints = false
        let keyboardTop = view.keyboardLayoutGuide.topAnchor
        let safeTop = view.safeAreaLayoutGuide.topAnchor
        if usesScrolling {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.keyboardDismissMode = .interactive
            scroll.alwaysBounceVertical = true
            view.addSubview(scroll)
            scroll.addSubview(content)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: safeTop), scroll.bottomAnchor.constraint(equalTo: keyboardTop),
                content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
                content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -36),
                content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
            ])
        } else {
            view.addSubview(content)
            let safeArea = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: safeTop, constant: 12),
                content.bottomAnchor.constraint(lessThanOrEqualTo: keyboardTop, constant: -12)
            ])
        }
        observation = store.$revision.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, self.visible, self.automaticRefresh, (self.refreshWhileEditing || self.view.findFirstResponder() == nil) else { return }
            self.render()
        }
        navigationItem.backButtonDisplayMode = .minimal
        if showsReadFailureOverlay {
            let failure = ServerReadFailureOverlay(store: store)
            failure.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(failure)
            NSLayoutConstraint.activate([failure.leadingAnchor.constraint(equalTo: view.leadingAnchor), failure.trailingAnchor.constraint(equalTo: view.trailingAnchor), failure.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), failure.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
        }
        render()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visible = true
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if automaticRefresh, isViewLoaded { render() }
        if navigationController?.viewControllers.first !== self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: iconButton("icon-back", label: "Back") { [weak self] in self?.navigationController?.popViewController(animated: true) })
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false }
    func render() { content.arrangedSubviews.forEach { $0.removeFromSuperview() } }
    func push(_ controller: UIViewController) { navigationController?.pushViewController(controller, animated: true) }
    func run(_ work: @escaping () async throws -> Void) {
        guard !running else { return }
        running = true
        Task { [weak self] in
            defer { self?.running = false }
            do { try await work() }
            catch is CancellationError { }
            catch { self?.notice(error.localizedDescription) }
        }
    }
    func notice(_ message: String) {
        guard viewIfLoaded?.window != nil else { return }
        let dialog = TravelDialogController(title: "Travel notes", message: message, choices: [("OK", false, {})])
        present(dialog, animated: true)
    }
    func confirm(_ title: String, message: String, destructive: Bool = false, actionTitle: String? = nil, action work: @escaping () -> Void) {
        let dialog = TravelDialogController(title: title, message: message, choices: [
            ("Cancel", false, {}), (actionTitle ?? (destructive ? "Confirm" : "Continue"), destructive, work)
        ])
        present(dialog, animated: true)
    }
    func share(_ values: [Any], source: UIView? = nil) {
        let sheet = UIActivityViewController(activityItems: values, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = source ?? view
        present(sheet, animated: true)
    }
}

private extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        return subviews.lazy.compactMap { $0.findFirstResponder() }.first
    }
}

@MainActor final class TravelDialogController: UIViewController {
    private let heading: String
    private let message: String
    private let choices: [(String, Bool, () -> Void)]
    init(title: String, message: String, choices: [(String, Bool, () -> Void)]) {
        heading = title; self.message = message; self.choices = choices
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.cream
        let scroll = UIScrollView()
        let body = column([text(heading, 29, display: true), text(message, 17)], spacing: 20)
        for choice in choices {
            let button = action(choice.0, filled: choice.0 != "Cancel") { [weak self] in
                self?.dismiss(animated: true) { choice.2() }
            }
            if choice.1 { button.configuration?.background.backgroundColor = Palette.coral }
            body.addArrangedSubview(button)
        }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(body)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 30), body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        if let sheet = sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
    }
}

@MainActor final class ServerReadFailureOverlay: UIView {
    var onVisibilityChange: ((Bool) -> Void)?
    private var observation: AnyCancellable?
    private let store: TravelStore
    init(store: TravelStore, back: (() -> Void)? = nil) {
        self.store = store
        super.init(frame: .zero)
        isHidden = true
        backgroundColor = Palette.cream
        let background = UIImageView(image: UIImage(named: "background-paper"))
        background.contentMode = .scaleAspectFill; background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        let message = column([text("A small pause in the journey", 30, display: true), text("This page could not be refreshed. Check your connection and try again. Your unfinished input is kept.", 17, color: Palette.muted)])
        let retry = TravelApp.action("Try again", icon: "icon-refresh") { [weak self] in
            guard let self else { return }
            Task { do { try await self.store.refresh() } catch { } }
        }
        message.addArrangedSubview(retry)
        if let back { message.addArrangedSubview(TravelApp.action("Go back", icon: "icon-back", filled: false, back)) }
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor), background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24), message.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        observation = store.$lastRefreshError.combineLatest(store.$isAuthenticated).receive(on: RunLoop.main).sink { [weak self] error, authenticated in
            let failed = error != nil && authenticated
            self?.isHidden = !failed
            self?.onVisibilityChange?(failed)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
