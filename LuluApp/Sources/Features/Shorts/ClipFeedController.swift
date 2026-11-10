import UIKit
import AVFoundation
import Combine
import SafariServices

private final class FilmSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

class ClipFeedController: UIViewController, UIScrollViewDelegate, UIAdaptivePresentationControllerDelegate, SFSafariViewControllerDelegate {
    private let store: TravelStore
    private var clips: [Record]
    private var initialIndex: Int
    private let discovery: Bool
    private var emptyState: UIView?
    private let paging = UIScrollView()
    private let pages = UIStackView()
    private var films: [FilmPage] = []
    private let player = AVPlayer()
    private var loading: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var loopObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var progressObserver: Any?
    private var storeObservation: AnyCancellable?
    private var activeIndex = -1
    private var isActive = false
    private var covered = false
    private var readFailed = false
    private var fitEntireScene = false
    private var didPosition = false
    private var manuallyPaused = false
    private var busy = false
    private var requestID = UUID()
    private let feedRefresh = UIRefreshControl()
    private var refreshingFeed = false
    private var discoveryOrder: [String] = []
    init(store: TravelStore, clips: [Record] = [], initialIndex: Int = 0, discovery: Bool = false) {
        let selectedID = clips.indices.contains(initialIndex) ? clips[initialIndex].id : clips.first?.id
        let visibleClips = discovery ? Self.discoveryClips(store: store) : clips.compactMap { Self.visibleClip($0, store: store) }
        self.store = store
        self.clips = visibleClips
        self.discovery = discovery
        self.initialIndex = visibleClips.firstIndex(where: { $0.id == selectedID }) ?? 0
        super.init(nibName: nil, bundle: nil)
    }

    private static func discoveryClips(store: TravelStore) -> [Record] {
        let blocked = Set(store.rows("blocks").map { $0.string("blocked_id") })
        let reported = Set(store.rows("reports").filter { $0.string("target_kind") == "clip" }.map { $0.string("target_id") })
        return store.rows("clips").filter {
            !blocked.contains($0.string("publisher_id")) && !reported.contains($0.id)
        }.sorted {
            let leftRank = $0.int("feed_rank")
            let rightRank = $1.int("feed_rank")
            let left = leftRank > 0 ? leftRank : Int.max
            let right = rightRank > 0 ? rightRank : Int.max
            return left == right ? $0.id < $1.id : left < right
        }
    }
    private static func visibleClip(_ clip: Record, store: TravelStore) -> Record? {
        if clip.bool("is_private") {
            guard let submission = store.rows("submissions").first(where: { $0.id == clip.id && $0.string("owner_id") == store.userID }) else { return nil }
            var privateClip = submission
            privateClip["is_private"] = .bool(true); privateClip["publisher_id"] = .string(store.userID)
            return privateClip
        }
        guard let current = store.rows("clips").first(where: { $0.id == clip.id }),
              !store.rows("blocks").contains(where: { $0.string("blocked_id") == current.string("publisher_id") }),
              !store.rows("reports").contains(where: { $0.string("target_kind") == "clip" && $0.string("target_id") == current.id }) else { return nil }
        return current
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        paging.isPagingEnabled = true; paging.showsVerticalScrollIndicator = false; paging.delegate = self; paging.contentInsetAdjustmentBehavior = .never
        paging.alwaysBounceVertical = true
        if discovery {
            feedRefresh.tintColor = .white
            feedRefresh.addAction(UIAction { [weak self] _ in self?.refreshFeed() }, for: .valueChanged)
            paging.refreshControl = feedRefresh
        }
        pages.axis = .vertical; pages.spacing = 0
        paging.translatesAutoresizingMaskIntoConstraints = false; pages.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paging); paging.addSubview(pages)
        NSLayoutConstraint.activate([
            paging.leadingAnchor.constraint(equalTo: view.leadingAnchor), paging.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paging.topAnchor.constraint(equalTo: view.topAnchor), paging.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pages.leadingAnchor.constraint(equalTo: paging.contentLayoutGuide.leadingAnchor), pages.trailingAnchor.constraint(equalTo: paging.contentLayoutGuide.trailingAnchor),
            pages.topAnchor.constraint(equalTo: paging.contentLayoutGuide.topAnchor), pages.bottomAnchor.constraint(equalTo: paging.contentLayoutGuide.bottomAnchor),
            pages.widthAnchor.constraint(equalTo: paging.frameLayoutGuide.widthAnchor)
        ])
        buildPages()
        if discovery { installDiscoveryToolbar() }
        let back: (() -> Void)? = discovery ? nil : { [weak self] in self?.navigationController?.popViewController(animated: true) }
        let failure = ServerReadFailureOverlay(store: store, back: back)
        failure.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(failure)
        NSLayoutConstraint.activate([failure.leadingAnchor.constraint(equalTo: view.leadingAnchor), failure.trailingAnchor.constraint(equalTo: view.trailingAnchor), failure.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), failure.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        failure.onVisibilityChange = { [weak self] failed in self?.readFailed = failed; if failed { self?.player.pause() } else { self?.resumeIfAllowed() } }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.player.pause() } }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.resumeIfAllowed() } }
        storeObservation = store.$revision.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshInteractions() }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, self.films.indices.contains(self.activeIndex), let duration = self.player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
            let progress = self.films[self.activeIndex].progress
            guard !progress.isTracking else { return }
            progress.value = Float(time.seconds / duration)
        }
    }
    private func installDiscoveryToolbar() {
        let title = text("Shorts", 24, color: .white, display: true)
        title.layer.shadowColor = UIColor.black.cgColor
        title.layer.shadowOpacity = 0.9
        title.layer.shadowRadius = 4
        let search = iconButton("icon-search", label: "Search travel videos") { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(ShortsSearchController(store: self.store), animated: true)
        }
        let create = iconButton("icon-camera", label: "Create a travel video") { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(CreationController(store: self.store), animated: true)
        }
        let toolbar = line([appLogoView(), title, UIView(), search, create], spacing: 8)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
    }

    private func buildPages() {
        if clips.isEmpty {
            let message = discovery ? "No travel videos available." : "This film is no longer available."
            let empty = column([text(message, 25, color: .white, display: true)])
            if !discovery {
                empty.addArrangedSubview(action("Go back", icon: "icon-back", filled: false) { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                })
            }
            empty.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(empty, aboveSubview: paging)
            emptyState = empty
            NSLayoutConstraint.activate([empty.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24), empty.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24), empty.centerYAnchor.constraint(equalTo: paging.centerYAnchor)])
        }
        for (index, clip) in clips.enumerated() {
            let film = FilmPage(clip: clip, store: store, discovery: discovery)
            film.translatesAutoresizingMaskIntoConstraints = false
            pages.addArrangedSubview(film)
            film.heightAnchor.constraint(equalTo: paging.frameLayoutGuide.heightAnchor).isActive = true
            film.updateControlsBottomInset(view.safeAreaInsets.bottom)
            film.onTap = { [weak self] in self?.togglePlayback() }
            film.onBack = { [weak self] in self?.navigationController?.popViewController(animated: true) }
            film.onLike = { [weak self] in self?.toggle("clip.like", clip: clip, table: "likes") }
            film.onSave = { [weak self] in self?.toggle("clip.save", clip: clip, table: "saved_clips") }
            film.onComments = { [weak self] in self?.showComments(clip) }
            film.onShare = { [weak self] in self?.shareClip(clip) }
            film.onMore = { [weak self] in self?.showMore(clip) }
            film.onProfile = { [weak self] in guard let self else { return }; self.navigationController?.pushViewController(PublicProfileController(store: self.store, profileID: clip.string("publisher_id", fallback: clip.string("owner_id"))), animated: true) }
            film.onPlace = { [weak self] in guard let self, !clip.string("place_id").isEmpty else { return }; self.openPlaceGuide(clip.string("place_id"), store: self.store) }
            film.onSeek = { [weak self] fraction in
                guard let self, self.activeIndex == index, let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite else { return }
                self.player.seek(to: CMTime(seconds: seconds * Double(fraction), preferredTimescale: 600))
            }
            films.append(film)
        }
        films.forEach { $0.updateCounts(store: store) }
    }

    private func refreshFeed() {
        guard !refreshingFeed else { return }
        refreshingFeed = true
        player.pause()
        let previous = clips.indices.contains(activeIndex) ? clips[activeIndex].id : clips.first?.id
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.refreshingFeed = false
                self.feedRefresh.endRefreshing()
                self.resumeIfAllowed()
            }
            do {
                try await self.store.refresh()
                self.discoveryOrder = nextDiscoveryOrder(Self.discoveryClips(store: self.store), after: previous)
                self.manuallyPaused = false
                self.reloadDiscovery(startAtFirst: true)
            } catch is CancellationError { }
            catch { self.showNotice(error.localizedDescription) }
        }
    }

    private func reloadDiscovery(startAtFirst: Bool = false) {
        let updated = orderedDiscovery(Self.discoveryClips(store: store), order: discoveryOrder)
        guard startAtFirst || updated != clips else { return }
        let previousIndex = max(activeIndex, initialIndex)
        let selectedID = clips.indices.contains(activeIndex) ? clips[activeIndex].id : nil
        stopCurrentItem()
        pages.arrangedSubviews.forEach { $0.removeFromSuperview() }
        films.removeAll()
        emptyState?.removeFromSuperview()
        emptyState = nil
        clips = updated
        initialIndex = startAtFirst ? 0 : (updated.firstIndex { $0.id == selectedID } ?? min(previousIndex, max(0, updated.count - 1)))
        activeIndex = -1
        didPosition = false
        buildPages()
        view.setNeedsLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // The tab dock reserves safe-area space for controls while the video fills the view.
        for film in films {
            film.updateControlsBottomInset(view.safeAreaInsets.bottom)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didPosition, paging.bounds.height > 0 else { return }
        didPosition = true
        paging.setContentOffset(CGPoint(x: 0, y: CGFloat(initialIndex) * paging.bounds.height), animated: false)
        activate(initialIndex)
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isActive = true; covered = false
        guard !closeHiddenClip() else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        resumeIfAllowed()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isActive = false
        player.pause()
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { selectVisiblePage() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { selectVisiblePage() }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { player.pause() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { selectVisiblePage() } }
    private func selectVisiblePage() {
        guard !refreshingFeed, !clips.isEmpty, paging.bounds.height > 0 else { return }
        let index = min(max(0, Int((paging.contentOffset.y / paging.bounds.height).rounded())), clips.count - 1)
        if index == activeIndex { resumeIfAllowed() } else { activate(index) }
    }
    private func activate(_ index: Int) {
        guard clips.indices.contains(index) else { return }
        guard let current = Self.visibleClip(clips[index], store: store) else {
            if discovery { reloadDiscovery() }
            else { player.pause(); navigationController?.popViewController(animated: true) }
            return
        }
        clips[index] = current
        stopCurrentItem()
        activeIndex = index; manuallyPaused = false
        let identity = UUID(); requestID = identity
        films[index].setLoadingMessage("Opening this little escape…")
        films[index].retry.isHidden = true
        films[index].poster.isHidden = false
        films[index].onRetry = { [weak self] in self?.activate(index) }
        films[index].surface.playerLayer.player = player
        films[index].surface.playerLayer.videoGravity = fitEntireScene ? .resizeAspect : .resizeAspectFill
        loading = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.store.mediaURL(self.clips[index].string("video_path"))
                guard !Task.isCancelled, self.requestID == identity, self.activeIndex == index else { return }
                let item = AVPlayerItem(url: url)
                self.player.replaceCurrentItem(with: item)
                self.statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.requestID == identity else { return }
                        switch item.status {
                        case .readyToPlay:
                            self.films[index].setLoadingMessage("")
                            self.films[index].poster.isHidden = true
                            self.resumeIfAllowed()
                        case .failed:
                            self.films[index].setLoadingMessage("This film could not load. Tap Retry below.")
                            self.films[index].retry.isHidden = false
                        default: break
                        }
                    }
                }
                self.loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in guard let self, self.requestID == identity else { return }; self.player.seek(to: .zero); self.resumeIfAllowed() }
                }
                self.resumeIfAllowed()
            } catch {
                guard self.requestID == identity else { return }
                self.films[index].setLoadingMessage("This film is unavailable. Please try again.")
                self.films[index].retry.isHidden = false
            }
        }
    }
    private func stopCurrentItem() {
        requestID = UUID()
        loading?.cancel()
        player.pause()
        statusObservation = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        for film in films { film.surface.playerLayer.player = nil }
        player.replaceCurrentItem(with: nil)
    }

    private func resumeIfAllowed() {
        guard isActive, !covered, !readFailed, !manuallyPaused, !refreshingFeed, UIApplication.shared.applicationState == .active, player.currentItem?.status == .readyToPlay else { return }
        player.playImmediately(atRate: 1)
        if films.indices.contains(activeIndex) { films[activeIndex].pauseLabel.isHidden = true }
    }
    private func togglePlayback() {
        manuallyPaused.toggle()
        if manuallyPaused { player.pause() } else { resumeIfAllowed() }
        if films.indices.contains(activeIndex) { films[activeIndex].pauseLabel.isHidden = !manuallyPaused }
    }
    private func toggle(_ action: String, clip: Record, table: String) {
        guard !busy else { return }; busy = true
        let enabled = !store.rows(table).contains { $0.string("clip_id") == clip.id }
        Task { [weak self] in
            guard let self else { return }; defer { self.busy = false }
            do { try await self.store.perform(action, ["clip_id": .string(clip.id), "enabled": .bool(enabled)]) }
            catch { self.showNotice(error.localizedDescription) }
        }
    }
    private func refreshInteractions() {
        guard !refreshingFeed else { return }
        if discovery { reloadDiscovery() }
        for film in films { film.updateCounts(store: store) }
        _ = closeHiddenClip()
    }

    private func closeHiddenClip() -> Bool {
        guard !discovery, clips.indices.contains(activeIndex),
              Self.visibleClip(clips[activeIndex], store: store) == nil else { return false }
        player.pause()
        if isActive, navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
        }
        return true
    }

    private func showComments(_ clip: Record) {
        covered = true; player.pause()
        let controller = CommentsController(store: store, clipID: clip.id)
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
        nav.presentationController?.delegate = self
        if let sheet = nav.sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
        controller.onClose = { [weak self, weak nav] in nav?.dismiss(animated: true) { self?.covered = false; self?.resumeIfAllowed() } }
    }
    private func shareClip(_ clip: Record) {
        covered = true; player.pause()
        var values: [Any] = [clip.string("title") + " — " + clip.string("caption")]
        if let url = URL(string: clip.string("source_url")), url.scheme == "https" { values.append(url) }
        let sheet = UIActivityViewController(activityItems: values, applicationActivities: nil)
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.covered = false; self?.resumeIfAllowed() }
        present(sheet, animated: true)
        sheet.presentationController?.delegate = self
    }
    private func showMore(_ clip: Record) {
        covered = true; player.pause()
        var choices: [(String, Bool, () -> Void)] = []
        let publisherID = clip.string("publisher_id")
        if !clip.bool("is_private"), publisherID != store.userID {
            choices.append(("Report video", false, { [weak self] in
                guard let self else { return }
                self.covered = false
                self.navigationController?.pushViewController(ReportController(store: self.store, kind: "clip", targetID: clip.id), animated: true)
            }))
            if !publisherID.isEmpty {
                choices.append(("Block publisher", true, { [weak self] in self?.block(clip) }))
            }
        }
        choices += [
            (self.player.isMuted ? "Unmute film" : "Mute film", false, { [weak self] in self?.player.isMuted.toggle(); self?.covered = false; self?.resumeIfAllowed() }),
            (self.fitEntireScene ? "Fill the screen" : "Fit the entire scene", false, { [weak self] in
                guard let self else { return }; self.fitEntireScene.toggle()
                if self.films.indices.contains(self.activeIndex) { self.films[self.activeIndex].surface.playerLayer.videoGravity = self.fitEntireScene ? .resizeAspect : .resizeAspectFill }
                self.covered = false; self.resumeIfAllowed()
            })
        ]
        if let url = URL(string: clip.string("source_url")), url.scheme == "https" {
            choices.append(("Source & license", false, { [weak self] in self?.openSource(clip) }))
        }
        choices.append(("Close", false, { [weak self] in self?.covered = false; self?.resumeIfAllowed() }))
        let dialog = TravelDialogController(title: "About this film", choices: choices)
        present(dialog, animated: true); dialog.presentationController?.delegate = self
    }
    private func block(_ clip: Record) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.perform("safety.block", ["profile_id": .string(clip.string("publisher_id")), "enabled": .bool(true)])
                self.covered = false
                if self.discovery {
                    self.reloadDiscovery()
                    self.resumeIfAllowed()
                } else if self.navigationController?.topViewController === self {
                    self.navigationController?.popViewController(animated: true)
                }
            } catch { self.showNotice(error.localizedDescription) }
        }
    }
    private func openSource(_ clip: Record) {
        guard let url = URL(string: clip.string("source_url")), url.scheme == "https" else { covered = false; resumeIfAllowed(); return }
        let safari = SFSafariViewController(url: url)
        safari.delegate = self
        present(safari, animated: true); safari.presentationController?.delegate = self
    }
    private func showNotice(_ message: String) {
        covered = true; player.pause()
        let dialog = TravelDialogController(title: "Travel notes", message: message, choices: [("OK", false, { [weak self] in self?.covered = false; self?.resumeIfAllowed() })])
        present(dialog, animated: true); dialog.presentationController?.delegate = self
    }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) { covered = false; resumeIfAllowed() }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { covered = false; resumeIfAllowed() }
    deinit {
        loading?.cancel(); player.pause()
        statusObservation = nil
        if let progressObserver { player.removeTimeObserver(progressObserver) }
        for observer in [loopObserver, backgroundObserver, foregroundObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
    }
}

private final class FilmProgressSlider: UISlider {
    private static let invisibleThumb = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }
    private let trackLine = CALayer()
    private let playedLine = CALayer()

    override var value: Float {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumTrackTintColor = .clear
        maximumTrackTintColor = .clear
        setThumbImage(Self.invisibleThumb, for: .normal)
        setThumbImage(Self.invisibleThumb, for: .highlighted)
        trackLine.backgroundColor = UIColor.white.withAlphaComponent(0.55).cgColor
        playedLine.backgroundColor = Palette.ochre.cgColor
        layer.addSublayer(trackLine)
        layer.addSublayer(playedLine)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let track = trackRect(forBounds: bounds)
        let start = thumbRect(forBounds: bounds, trackRect: track, value: minimumValue).midX
        let end = thumbRect(forBounds: bounds, trackRect: track, value: maximumValue).midX
        let position = thumbRect(forBounds: bounds, trackRect: track, value: value).midX

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLine.frame = CGRect(x: min(start, end), y: track.midY - 0.5, width: abs(end - start), height: 1)
        playedLine.frame = CGRect(x: min(start, position), y: track.midY - 1.5, width: abs(position - start), height: 3)
        CATransaction.commit()
    }
}

private final class FilmPage: UIView {
    let surface = FilmSurface()
    let poster: RemoteImageView
    let progress: UISlider = FilmProgressSlider(frame: .zero)
    private lazy var progressBottom = progress.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
    private let loading = text("", 15, color: .white)
    let pauseLabel = text("Paused · Tap to play", 18, color: .white)
    let retry = TravelApp.action("Retry film", icon: "icon-refresh", filled: false) {}
    private let clip: Record
    private let likeCount = text("", 12, color: .white)
    private let saveCount = text("", 12, color: .white)
    private let commentCount = text("", 12, color: .white)
    var onRetry: (() -> Void)?
    var onTap: (() -> Void)?
    var onBack: (() -> Void)?
    var onLike: (() -> Void)?
    var onSave: (() -> Void)?
    var onComments: (() -> Void)?
    var onShare: (() -> Void)?
    var onMore: (() -> Void)?
    var onProfile: (() -> Void)?
    var onPlace: (() -> Void)?
    var onSeek: ((Float) -> Void)?
    init(clip: Record, store: TravelStore, discovery: Bool) {
        self.clip = clip
        poster = remoteImage(clip.string("cover_path"), store: store, height: 1, radius: 0)
        super.init(frame: .zero)
        poster.constraints.filter { $0.firstAttribute == .height }.forEach { $0.isActive = false }
        backgroundColor = .black
        for item in [surface, poster] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item); NSLayoutConstraint.activate([item.leadingAnchor.constraint(equalTo: leadingAnchor), item.trailingAnchor.constraint(equalTo: trailingAnchor), item.topAnchor.constraint(equalTo: topAnchor), item.bottomAnchor.constraint(equalTo: bottomAnchor)]) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        surface.addGestureRecognizer(tap)
        poster.isUserInteractionEnabled = false
        surface.isAccessibilityElement = true; surface.accessibilityLabel = "Travel video. Double tap to pause or play."; surface.accessibilityTraits = .button
        let back = iconButton("icon-back", label: "Back") { [weak self] in self?.onBack?() }
        let publisher = clip.string("publisher_id") == store.userID ? store.profile : store.rows("profiles").first { $0.id == clip.string("publisher_id") }
        let retainedCommunity = clip.bool("retained_community")
        let author = TravelApp.action(retainedCommunity ? "Community film" : (publisher?.string("display_name") ?? "Travel films"), icon: "icon-profile", filled: false) { [weak self] in self?.onProfile?() }
        author.isEnabled = !retainedCommunity
        let header: UIView
        if discovery {
            header = UIView()
            header.isUserInteractionEnabled = false
            header.heightAnchor.constraint(equalToConstant: 44).isActive = true
        } else {
            header = line([back, UIView(), author])
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16), header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8)])
        let rail = column(spacing: 13)
        func railItem(_ icon: String, _ name: String, _ count: UILabel? = nil, _ work: @escaping () -> Void) {
            let button = iconButton(icon, label: name, work)
            let container = column([button], spacing: 3); container.alignment = .center
            if let count { container.addArrangedSubview(count) }
            rail.addArrangedSubview(container)
        }
        if !retainedCommunity {
            let avatar = publisherAvatar(clip.string("publisher_id", fallback: clip.string("owner_id")), store: store) { [weak self] in self?.onProfile?() }
            let avatarContainer = column([avatar], spacing: 0)
            avatarContainer.alignment = .center
            rail.addArrangedSubview(avatarContainer)
        }
        railItem("icon-heart", "Like video", likeCount) { [weak self] in self?.onLike?() }
        railItem("icon-comment", "Open comments", commentCount) { [weak self] in self?.onComments?() }
        railItem("icon-save", "Save video", saveCount) { [weak self] in self?.onSave?() }
        railItem("icon-share", "Share video") { [weak self] in self?.onShare?() }
        railItem("icon-more", "More options") { [weak self] in self?.onMore?() }
        let railScroll = UIScrollView()
        railScroll.showsVerticalScrollIndicator = false
        let railContainer = UIView()
        for item in [railScroll, railContainer, rail] { item.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(railScroll); railScroll.addSubview(railContainer); railContainer.addSubview(rail)
        let railPreferred = railContainer.heightAnchor.constraint(equalTo: rail.heightAnchor)
        railPreferred.priority = .defaultLow
        NSLayoutConstraint.activate([
            railContainer.leadingAnchor.constraint(equalTo: railScroll.contentLayoutGuide.leadingAnchor), railContainer.trailingAnchor.constraint(equalTo: railScroll.contentLayoutGuide.trailingAnchor),
            railContainer.topAnchor.constraint(equalTo: railScroll.contentLayoutGuide.topAnchor), railContainer.bottomAnchor.constraint(equalTo: railScroll.contentLayoutGuide.bottomAnchor),
            railContainer.widthAnchor.constraint(equalTo: railScroll.frameLayoutGuide.widthAnchor), railContainer.heightAnchor.constraint(greaterThanOrEqualTo: railScroll.frameLayoutGuide.heightAnchor), railPreferred,
            rail.leadingAnchor.constraint(equalTo: railContainer.leadingAnchor), rail.trailingAnchor.constraint(equalTo: railContainer.trailingAnchor), rail.bottomAnchor.constraint(equalTo: railContainer.bottomAnchor), rail.topAnchor.constraint(greaterThanOrEqualTo: railContainer.topAnchor)
        ])
        let title = text(clip.string("title"), discovery ? 23 : 29, color: .white, display: true)
        let caption = text(clip.string("caption"), discovery ? 14 : 15, color: .white)
        let location = TravelApp.action(discovery ? "Explore" : "Explore this destination", icon: "icon-location", filled: false) { [weak self] in self?.onPlace?() }
        location.accessibilityLabel = "Explore this destination"
        location.isHidden = clip.string("place_id").isEmpty
        let privacy = text("Private submission · " + clip.string("status", fallback: "Pending review"), 14, color: .white)
        privacy.isHidden = !clip.bool("is_private")
        railScroll.isHidden = clip.bool("is_private")
        loading.isHidden = true
        let info = column([privacy, title, caption], spacing: discovery ? 3 : 8)
        if discovery {
            title.numberOfLines = 2
            caption.numberOfLines = 2
            for button in [author, location] {
                var configuration = button.configuration ?? .plain()
                configuration.background.backgroundColor = .clear
                configuration.baseForegroundColor = .white
                configuration.image = nil
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                configuration.titleLineBreakMode = .byTruncatingTail
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                    var attributes = incoming
                    attributes.font = FontBook.font(14)
                    return attributes
                }
                button.configuration = configuration
                button.titleLabel?.numberOfLines = 1
                button.contentHorizontalAlignment = .leading
                let minimumWidth = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
                minimumWidth.priority = UILayoutPriority(999)
                minimumWidth.isActive = true
            }
            author.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let links = line([author, location], spacing: 12)
            info.addArrangedSubview(links)
        } else {
            info.addArrangedSubview(location)
        }
        info.addArrangedSubview(loading)
        info.addArrangedSubview(retry)
        let cornerRadius: CGFloat = discovery ? 12 : 18
        let inset: CGFloat = discovery ? 8 : 12
        info.backgroundColor = UIColor.black.withAlphaComponent(discovery ? 0.38 : 0.48)
        info.layer.cornerRadius = cornerRadius
        info.isLayoutMarginsRelativeArrangement = true
        info.directionalLayoutMargins = NSDirectionalEdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        let infoScroll = UIScrollView()
        infoScroll.showsVerticalScrollIndicator = false; infoScroll.layer.cornerRadius = cornerRadius; infoScroll.clipsToBounds = true
        infoScroll.translatesAutoresizingMaskIntoConstraints = false
        info.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoScroll); infoScroll.addSubview(info)
        let preferredInfoHeight = infoScroll.heightAnchor.constraint(equalTo: info.heightAnchor)
        preferredInfoHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            info.leadingAnchor.constraint(equalTo: infoScroll.contentLayoutGuide.leadingAnchor), info.trailingAnchor.constraint(equalTo: infoScroll.contentLayoutGuide.trailingAnchor),
            info.topAnchor.constraint(equalTo: infoScroll.contentLayoutGuide.topAnchor), info.bottomAnchor.constraint(equalTo: infoScroll.contentLayoutGuide.bottomAnchor),
            info.widthAnchor.constraint(equalTo: infoScroll.frameLayoutGuide.widthAnchor), preferredInfoHeight,
            infoScroll.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.46), infoScroll.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 12)
        ])
        retry.isHidden = true
        retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        progress.accessibilityLabel = "Video position"
        progress.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.progress.setNeedsLayout()
            self.onSeek?(self.progress.value)
        }, for: .valueChanged)
        progress.translatesAutoresizingMaskIntoConstraints = false; addSubview(progress)
        pauseLabel.isHidden = true; pauseLabel.translatesAutoresizingMaskIntoConstraints = false; addSubview(pauseLabel)
        NSLayoutConstraint.activate([
            railScroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14), railScroll.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -24), railScroll.widthAnchor.constraint(equalToConstant: 52), railScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            infoScroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16), clip.bool("is_private") ? infoScroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16) : infoScroll.trailingAnchor.constraint(equalTo: railScroll.leadingAnchor, constant: -12), infoScroll.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -12),
            progress.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20), progress.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20), progressBottom,
            pauseLabel.centerXAnchor.constraint(equalTo: centerXAnchor), pauseLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { onTap?() }
    func updateControlsBottomInset(_ inset: CGFloat) {
        progressBottom.constant = -inset - 8
    }

    func setLoadingMessage(_ message: String) {
        loading.text = message
        loading.isHidden = message.isEmpty
    }
    func updateCounts(store: TravelStore) {
        let liked = store.rows("likes").contains { $0.string("clip_id") == clip.id }
        let saved = store.rows("saved_clips").contains { $0.string("clip_id") == clip.id }
        likeCount.text = store.contentLikeCount(kind: "clips", id: clip.id).map { $0.formatted() } ?? "—"
        likeCount.accessibilityLabel = liked ? "Liked" : "Like"
        saveCount.text = saved ? "Saved" : "Save"
        commentCount.text = "\(store.rows("comments").filter { $0.string("clip_id") == clip.id }.count)"
    }
}
